// Supervision from the timetable (#219): an answer is `supervised` when it
// falls in a lesson of the student's class, 10 minutes before and after
// included, in local time; `home` for everything else — outside the lesson,
// no class, a class without lessons, a schedule that cannot be read.
//
// Moments are built as local wall-clock times (`DateTime(...)`) and handed
// over in UTC, the way the tutor stamps a graded turn, so the tests hold in
// whatever time zone they run.

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _supervised = EvidenceProvenance.supervised;
const _home = EvidenceProvenance.home;

/// Tuesday 10:50–11:40 and Wednesday 08:25–09:15, local time.
const _tuesday = LessonSlot(
  weekday: DateTime.tuesday,
  startMinute: 10 * 60 + 50,
  endMinute: 11 * 60 + 40,
);
const _wednesday = LessonSlot(
  weekday: DateTime.wednesday,
  startMinute: 8 * 60 + 25,
  endMinute: 9 * 60 + 15,
);

final ClassList _classes = ClassList.sorted([
  const SchoolClass(name: '6EWI', lessons: [_tuesday, _wednesday]),
  const SchoolClass(name: '6WEWI'),
]);

/// The UTC instant of a local wall-clock time.
DateTime _at(int month, int day, int hour, int minute, [int second = 0]) =>
    DateTime(2026, month, day, hour, minute, second).toUtc();

/// The timetable source over fixed lookups, counting the reads it makes.
class _Lookups {
  _Lookups({
    this.classOf = const {'u1': '6EWI'},
    this.classes,
    this.failClassName = false,
    this.failClasses = false,
    this.cached,
  });

  final Map<String, String> classOf;
  final ClassList? classes;
  final bool failClassName;
  final bool failClasses;
  final ClassList? cached;
  int classNameReads = 0;
  int classesReads = 0;

  late final ScheduleSupervisionSource source = ScheduleSupervisionSource(
    classNameOf: (uid) async {
      classNameReads += 1;
      if (failClassName) throw StateError('accounts unreachable');
      return classOf[uid] ?? '';
    },
    readClasses: () async {
      classesReads += 1;
      if (failClasses) throw StateError('config unreachable');
      return classes ?? _classes;
    },
    cachedClasses: () => cached,
  );

  Future<EvidenceProvenance> at(DateTime at, {String uid = 'u1'}) =>
      source.provenanceFor(uid: uid, at: at);
}

void main() {
  group('ScheduleSupervisionSource', () {
    test(
      'an answer in a lesson of the student\'s class is supervised',
      () async {
        final lookups = _Lookups();
        // Tuesday 6 October, in the lesson; Wednesday 7 October, in the other.
        expect(await lookups.at(_at(10, 6, 11, 0)), _supervised);
        expect(await lookups.at(_at(10, 7, 8, 30)), _supervised);
      },
    );

    test('ten minutes before the start and after the end still count, a '
        'second more does not', () async {
      final lookups = _Lookups();
      expect(await lookups.at(_at(10, 6, 10, 40)), _supervised);
      expect(await lookups.at(_at(10, 6, 10, 39, 59)), _home);
      expect(await lookups.at(_at(10, 6, 11, 50)), _supervised);
      expect(await lookups.at(_at(10, 6, 11, 50, 1)), _home);
      expect(ScheduleSupervisionSource.margin, const Duration(minutes: 10));
    });

    test('outside the lessons is home: the evening, the weekend, another '
        'day at the same hour', () async {
      final lookups = _Lookups();
      expect(await lookups.at(_at(10, 6, 20, 15)), _home);
      expect(await lookups.at(_at(10, 10, 11, 0)), _home); // Saturday
      expect(await lookups.at(_at(10, 8, 11, 0)), _home); // Thursday
    });

    test('lessons are local wall-clock times: the same lesson hour counts in '
        'summer time and in winter time', () async {
      final lookups = _Lookups();
      // Belgian clocks go back on Sunday 25 October 2026. The lesson stays
      // at 10:50 local, so in UTC it moves an hour; a stored UTC timestamp
      // is read in local time either way.
      final summer = _at(10, 20, 11, 0);
      final winter = _at(11, 3, 11, 0);
      expect(await lookups.at(summer), _supervised);
      expect(await lookups.at(winter), _supervised);
      expect(summer.isUtc && winter.isUtc, isTrue);
      // And the hour after the lesson is home in winter as in summer.
      expect(await lookups.at(_at(11, 3, 12, 0)), _home);
    });

    test('a student without a class is home, and costs no read of the '
        'class list', () async {
      final lookups = _Lookups(classOf: const {'u1': '  '});
      expect(await lookups.at(_at(10, 6, 11, 0)), _home);
      expect(await lookups.at(_at(10, 6, 11, 0), uid: 'nobody'), _home);
      expect(lookups.classesReads, 0);
    });

    test('a class without lessons, or one that is not in the list, is '
        'home', () async {
      final lookups = _Lookups(classOf: const {'u1': '6WEWI', 'u2': '5C'});
      expect(await lookups.at(_at(10, 6, 11, 0)), _home);
      expect(await lookups.at(_at(10, 6, 11, 0), uid: 'u2'), _home);
      // No classes doc at all.
      final empty = _Lookups(classes: ClassList.empty);
      expect(await empty.at(_at(10, 6, 11, 0)), _home);
    });

    test('a read that fails is home, never supervised', () async {
      expect(await _Lookups(failClassName: true).at(_at(10, 6, 11, 0)), _home);
      expect(await _Lookups(failClasses: true).at(_at(10, 6, 11, 0)), _home);
      expect(
        await _Lookups(failClasses: true).source.provenancesFor(
          uid: 'u1',
          ats: [_at(10, 6, 11, 0), _at(10, 7, 8, 30)],
        ),
        [_home, _home],
      );
    });

    test('provenancesFor answers every moment in order with one lookup of '
        'the class', () async {
      final lookups = _Lookups();
      final answers = await lookups.source.provenancesFor(
        uid: 'u1',
        ats: [_at(10, 6, 11, 0), _at(10, 6, 20, 0), _at(10, 7, 9, 20)],
      );
      expect(answers, [_supervised, _home, _supervised]);
      expect(lookups.classNameReads, 1);
      expect(lookups.classesReads, 1);
      expect(
        await lookups.source.provenancesFor(uid: 'u1', ats: const []),
        isEmpty,
      );
    });

    test('wired for a class with lessons only, and not before the list is '
        'known (#160)', () {
      expect(_Lookups(cached: _classes).source.isWiredFor('6EWI'), isTrue);
      expect(_Lookups(cached: _classes).source.isWiredFor('6WEWI'), isFalse);
      expect(_Lookups(cached: _classes).source.isWiredFor('5C'), isFalse);
      expect(_Lookups(cached: _classes).source.isWiredFor(''), isFalse);
      expect(_Lookups().source.isWiredFor('6EWI'), isFalse);
    });
  });

  group('NoSupervisionSource', () {
    test('answers home for anyone at any time', () async {
      const source = NoSupervisionSource();
      expect(
        await source.provenanceFor(uid: 'u1', at: _at(10, 6, 11, 0)),
        _home,
      );
      expect(await source.provenancesFor(uid: 'u2', ats: [_at(10, 6, 21, 0)]), [
        _home,
      ]);
    });

    test('is not wired: its "all home" is a default, not a finding about '
        'anyone (#160)', () {
      expect(const NoSupervisionSource().isWiredFor('6EWI'), isFalse);
    });
  });

  group('the app binding', () {
    Map<String, dynamic> account(String uid, String className) => {
      'id': uid,
      'uid': uid,
      'email': '$uid@example.com',
      'firstName': uid,
      'lastName': 'Test',
      'className': className,
    };

    late ProviderContainer container;

    void boot({AccountIdentity? signedIn, bool withClasses = true}) {
      InMemoryCosmosClient({
        'accounts': InMemoryCosmos([
          account('stu', '6EWI'),
          account('other', '6WEWI'),
        ]),
        'config': InMemoryCosmos([
          {'id': 'global', 'type': 'config', 'Model': 'gpt-4o'},
          if (withClasses)
            {'id': 'classes', 'type': 'config', 'classes': _classes.toMaps()},
        ]),
      }).install();
      container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWith(() => _SignedIn(signedIn)),
        ],
      );
      addTearDown(container.dispose);
    }

    test('is the timetable', () {
      boot();
      expect(
        container.read(supervisionSourceProvider),
        isA<ScheduleSupervisionSource>(),
      );
    });

    test('reads the student\'s class from the account and the lessons from '
        'config/classes', () async {
      boot(
        signedIn: const AccountIdentity(
          oid: 'stu',
          displayName: 'Stu Test',
          email: 'stu@example.com',
          firstName: 'Stu',
          lastName: 'Test',
          isTeacher: false,
        ),
      );
      final source = container.read(supervisionSourceProvider);
      expect(
        await source.provenanceFor(uid: 'stu', at: _at(10, 6, 11, 0)),
        _supervised,
      );
      expect(
        await source.provenanceFor(uid: 'stu', at: _at(10, 6, 21, 0)),
        _home,
      );
      // Another account, read on demand: its class has no lessons.
      expect(
        await source.provenanceFor(uid: 'other', at: _at(10, 6, 11, 0)),
        _home,
      );
    });

    test('without a classes doc every answer is home', () async {
      boot(withClasses: false);
      final source = container.read(supervisionSourceProvider);
      expect(
        await source.provenanceFor(uid: 'stu', at: _at(10, 6, 11, 0)),
        _home,
      );
    });

    test(
      'is wired for a class once the polled list says it has lessons',
      () async {
        boot();
        final source = container.read(supervisionSourceProvider);
        // Not known yet: not wired.
        expect(source.isWiredFor('6EWI'), isFalse);
        await pumpEventQueue();
        expect(source.isWiredFor('6EWI'), isTrue);
        expect(source.isWiredFor('6WEWI'), isFalse);
      },
    );
  });
}

class _SignedIn extends AuthService {
  _SignedIn(this._identity);

  final AccountIdentity? _identity;

  @override
  AccountIdentity? build() => _identity;
}
