// #218 — `ClassesService` keeps the school's class list in one doc,
// `classes`, in the `config` container next to `global`.
//
// Under test: every write is a read-modify-write of that one doc (so
// `global` and fields this build does not know are left alone), names are
// unique up to case, and a rename moves the class's students along before
// it renames the list, so a failure halfway can be finished by renaming
// again.

import 'package:ai_tutor_python/services/classes/classes_service.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _global = {
  'id': 'global',
  'type': 'config',
  'Model': 'gpt-4o',
  'ApiKey': 'sk-school',
};

const _tuesday = LessonSlot(
  weekday: DateTime.tuesday,
  startMinute: 10 * 60 + 50,
  endMinute: 11 * 60 + 40,
);

Map<String, dynamic> _classesDoc(List<Map<String, dynamic>> classes) => {
  'id': 'classes',
  'type': 'config',
  'classes': classes,
};

void main() {
  late InMemoryCosmos config;
  late ProviderContainer container;

  /// The real service over an in-memory `config` container, kept alive the
  /// way the app's provider container keeps it.
  ClassesService service() => container.read(classesServiceProvider.notifier);

  void setUpWith(List<Map<String, dynamic>> docs) {
    config = InMemoryCosmos(docs);
    container = ProviderContainer(
      overrides: [
        classesServiceProvider.overrideWith(
          () => ClassesService(container: config.container),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  List<String> storedNames() => [
    for (final c in config['classes']!['classes'] as List)
      (c as Map)['name'] as String,
  ];

  test('no doc yet reads as no classes, not as "unknown"', () async {
    setUpWith([_global]);
    final classes = await service().getClasses();
    expect(classes.isEmpty, isTrue);
  });

  test('the provider publishes the list once it is read', () async {
    setUpWith([
      _global,
      _classesDoc([
        {
          'name': '6EWI',
          'lessons': [_tuesday.toMap()],
        },
      ]),
    ]);
    expect(container.read(classesServiceProvider), isNull);
    await pumpEventQueue();
    expect(container.read(classesServiceProvider)!.names, ['6EWI']);
    expect(container.read(classLessonsProvider('6EWI')), [_tuesday]);
    expect(container.read(classLessonsProvider('6WEWI')), isEmpty);
  });

  test('a poll that brings back the same list is no news', () {
    final service = ClassesService(container: InMemoryCosmos().container);
    final list = ClassList.fromDoc(
      _classesDoc([
        {
          'name': '6EWI',
          'lessons': [_tuesday.toMap()],
        },
      ]),
    );
    final same = ClassList.fromDoc({'classes': list.toMaps()});
    expect(service.updateShouldNotify(list, same), isFalse);
    expect(service.updateShouldNotify(null, same), isTrue);
    expect(service.updateShouldNotify(list, ClassList.empty), isTrue);
  });

  test('addClass creates the doc next to global and leaves global '
      'alone', () async {
    setUpWith([_global]);

    await service().addClass(' 6EWI ');

    expect(config['classes']!['type'], 'config');
    expect(storedNames(), ['6EWI']);
    expect(config['global'], _global);
    // Published at once, without waiting for the poll.
    expect(container.read(classesServiceProvider)!.names, ['6EWI']);
  });

  test('addClass keeps the list sorted and refuses a name that is there up '
      'to case, or empty', () async {
    setUpWith([_global]);
    await service().addClass('6WEWI');
    await service().addClass('6EWI');
    expect(storedNames(), ['6EWI', '6WEWI']);

    await expectLater(
      service().addClass('6ewi'),
      throwsA(
        isA<ClassNameException>().having((e) => e.taken, 'taken', isTrue),
      ),
    );
    await expectLater(
      service().addClass('   '),
      throwsA(
        isA<ClassNameException>().having((e) => e.taken, 'taken', isFalse),
      ),
    );
    expect(storedNames(), ['6EWI', '6WEWI']);
  });

  test('a write keeps fields it does not model, and drops Cosmos system '
      'fields', () async {
    setUpWith([
      _global,
      {
        ..._classesDoc([
          {'name': '6EWI', 'lessons': [], 'colour': 'green'},
        ]),
        'Note': 'keep me',
        '_etag': '"0x1"',
      },
    ]);

    await service().addClass('6WEWI');

    final doc = config['classes']!;
    expect(doc['Note'], 'keep me');
    expect(doc.keys, isNot(contains('_etag')));
    expect((doc['classes'] as List).first, {
      'colour': 'green',
      'name': '6EWI',
      'lessons': <Object>[],
    });
    expect(doc['updatedAt'], isA<String>());
  });

  test('a write starts from what is stored, not from the last poll', () async {
    setUpWith([_global]);
    await service().addClass('6EWI');
    // Another laptop adds a class behind this one's back.
    config.upsert(
      _classesDoc([
        {'name': '6EWI', 'lessons': []},
        {'name': '5A', 'lessons': []},
      ]),
    );

    await service().addClass('6WEWI');

    expect(storedNames(), ['5A', '6EWI', '6WEWI']);
  });

  test('removeClass removes the class and its lessons', () async {
    setUpWith([
      _global,
      _classesDoc([
        {
          'name': '6EWI',
          'lessons': [_tuesday.toMap()],
        },
        {'name': '5A', 'lessons': []},
      ]),
    ]);

    await service().removeClass('6EWI');
    await service().removeClass('not there');

    expect(storedNames(), ['5A']);
  });

  test('setLessons stores the lessons in week order', () async {
    setUpWith([
      _global,
      _classesDoc([
        {'name': '6EWI', 'lessons': []},
      ]),
    ]);

    await service().setLessons('6EWI', [
      _tuesday.copyWith(weekday: DateTime.wednesday, startMinute: 10 * 60),
      _tuesday,
    ]);

    expect((config['classes']!['classes'] as List).single, {
      'name': '6EWI',
      'lessons': [
        {'weekday': 2, 'start': '10:50', 'end': '11:40'},
        {'weekday': 3, 'start': '10:00', 'end': '11:40'},
      ],
    });
    await expectLater(
      service().setLessons('7A', const []),
      throwsA(isA<UnknownClassException>()),
    );
  });

  group('renameClass', () {
    late List<(String, String)> moved;

    Future<void> recordMove({
      required String uid,
      required String className,
    }) async {
      moved.add((uid, className));
    }

    setUp(() => moved = []);

    test('moves every member with one setClassName each, then renames the '
        'class and keeps its lessons', () async {
      setUpWith([
        _global,
        _classesDoc([
          {
            'name': '6EWI',
            'lessons': [_tuesday.toMap()],
          },
          {'name': '6WEWI', 'lessons': []},
        ]),
      ]);

      await service().renameClass(
        from: '6EWI',
        to: ' 6EWI-A ',
        memberUids: ['u1', 'u2'],
        setClassName: recordMove,
      );

      expect(moved, [('u1', '6EWI-A'), ('u2', '6EWI-A')]);
      expect(storedNames(), ['6EWI-A', '6WEWI']);
      final list = await service().getClasses();
      expect(list.lessonsOf('6EWI-A'), [_tuesday]);
      expect(list.contains('6EWI'), isFalse);
    });

    test('may change only the case of the name', () async {
      setUpWith([
        _global,
        _classesDoc([
          {'name': '6ewi', 'lessons': []},
        ]),
      ]);

      await service().renameClass(
        from: '6ewi',
        to: '6EWI',
        memberUids: ['u1'],
        setClassName: recordMove,
      );

      expect(storedNames(), ['6EWI']);
      expect(moved, [('u1', '6EWI')]);
    });

    test('refuses a name another class has, or an unknown class, before any '
        'account is touched', () async {
      setUpWith([
        _global,
        _classesDoc([
          {'name': '6EWI', 'lessons': []},
          {'name': '6WEWI', 'lessons': []},
        ]),
      ]);

      await expectLater(
        service().renameClass(
          from: '6EWI',
          to: '6wewi',
          memberUids: ['u1'],
          setClassName: recordMove,
        ),
        throwsA(isA<ClassNameException>()),
      );
      await expectLater(
        service().renameClass(
          from: '7A',
          to: '7B',
          memberUids: ['u1'],
          setClassName: recordMove,
        ),
        throwsA(isA<UnknownClassException>()),
      );
      expect(moved, isEmpty);
      expect(storedNames(), ['6EWI', '6WEWI']);
    });

    test('a failure halfway leaves the list on the old name, and renaming '
        'again finishes the job', () async {
      setUpWith([
        _global,
        _classesDoc([
          {'name': '6EWI', 'lessons': []},
        ]),
      ]);
      var calls = 0;
      Future<void> failSecond({
        required String uid,
        required String className,
      }) async {
        calls += 1;
        if (calls == 2) throw StateError('network');
        moved.add((uid, className));
      }

      await expectLater(
        service().renameClass(
          from: '6EWI',
          to: '6EWI-A',
          memberUids: ['u1', 'u2'],
          setClassName: failSecond,
        ),
        throwsStateError,
      );
      expect(moved, [('u1', '6EWI-A')]);
      expect(storedNames(), ['6EWI'], reason: 'the list goes last');

      // The retry only has u2 left on the old name.
      await service().renameClass(
        from: '6EWI',
        to: '6EWI-A',
        memberUids: ['u2'],
        setClassName: recordMove,
      );
      expect(moved, [('u1', '6EWI-A'), ('u2', '6EWI-A')]);
      expect(storedNames(), ['6EWI-A']);
    });
  });
}
