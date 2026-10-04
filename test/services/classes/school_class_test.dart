// #218 — the class list and its lessons, as stored in `config/classes`.
//
// What matters downstream (#219 decides from this whether an oefening was
// done in class, #220 counts lesson weeks with it): a lesson is a weekday and
// a local clock time, so it must match the moment a student was in class on
// both sides of the switch to winter time, and an entry that cannot be a
// lesson must never match anything.

import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tuesday 10:50–11:40, the shape of a 6EWI lesson.
const _tuesday = LessonSlot(
  weekday: DateTime.tuesday,
  startMinute: 10 * 60 + 50,
  endMinute: 11 * 60 + 40,
);

void main() {
  group('clock times', () {
    test('format and parse HH:MM', () {
      expect(formatClockMinute(0), '00:00');
      expect(formatClockMinute(8 * 60 + 5), '08:05');
      expect(formatClockMinute(23 * 60 + 59), '23:59');
      expect(parseClockMinute('08:05'), 8 * 60 + 5);
      expect(parseClockMinute('8:05'), 8 * 60 + 5);
      expect(parseClockMinute(' 13:30 '), 13 * 60 + 30);
    });

    test('reject what is not a time of day', () {
      for (final bad in ['24:00', '12:60', '1230', '12:3', 'noon', '', null]) {
        expect(parseClockMinute(bad), isNull, reason: '$bad');
      }
      expect(parseClockMinute(1230), isNull);
    });
  });

  group('LessonSlot', () {
    test('round-trips through the stored shape', () {
      expect(_tuesday.toMap(), {
        'weekday': 2,
        'start': '10:50',
        'end': '11:40',
      });
      expect(LessonSlot.fromMap(_tuesday.toMap()), _tuesday);
    });

    test('an entry that cannot be a lesson is left out', () {
      for (final bad in <Object?>[
        null,
        'Tuesday',
        {'weekday': 0, 'start': '10:50', 'end': '11:40'},
        {'weekday': 8, 'start': '10:50', 'end': '11:40'},
        {'weekday': 2.5, 'start': '10:50', 'end': '11:40'},
        {'weekday': '2', 'start': '10:50', 'end': '11:40'},
        {'weekday': 2, 'start': '10.50', 'end': '11:40'},
        {'weekday': 2, 'start': '11:40', 'end': '11:40'},
        {'weekday': 2, 'start': '11:40', 'end': '10:50'},
        {'weekday': 2, 'start': '10:50'},
      ]) {
        expect(LessonSlot.fromMap(bad), isNull, reason: '$bad');
      }
      // A whole number stored as a double (a hand edit) still counts.
      expect(
        LessonSlot.fromMap({'weekday': 2.0, 'start': '10:50', 'end': '11:40'}),
        _tuesday,
      );
    });

    test('contains a moment in the lesson, both ends included', () {
      expect(_tuesday.contains(DateTime(2026, 10, 6, 10, 50)), isTrue);
      expect(_tuesday.contains(DateTime(2026, 10, 6, 11, 15, 30)), isTrue);
      expect(_tuesday.contains(DateTime(2026, 10, 6, 11, 40)), isTrue);
      expect(_tuesday.contains(DateTime(2026, 10, 6, 10, 49, 59)), isFalse);
      expect(_tuesday.contains(DateTime(2026, 10, 6, 11, 40, 1)), isFalse);
    });

    test('only on its own weekday', () {
      // Wednesday 7 October, same clock time.
      expect(_tuesday.contains(DateTime(2026, 10, 7, 11, 0)), isFalse);
    });

    test('a margin widens the lesson on both sides', () {
      const margin = Duration(minutes: 10);
      expect(
        _tuesday.contains(DateTime(2026, 10, 6, 10, 40), margin: margin),
        isTrue,
      );
      expect(
        _tuesday.contains(DateTime(2026, 10, 6, 11, 50), margin: margin),
        isTrue,
      );
      expect(
        _tuesday.contains(DateTime(2026, 10, 6, 10, 39, 59), margin: margin),
        isFalse,
      );
      expect(
        _tuesday.contains(DateTime(2026, 10, 6, 11, 50, 1), margin: margin),
        isFalse,
      );
    });

    test('is a local clock time: the same lesson before and after the clock '
        'goes to winter time', () {
      // 25 October 2026 the clock goes back an hour. A lesson stored in UTC
      // would move by an hour; a local clock time does not.
      expect(_tuesday.contains(DateTime(2026, 10, 20, 11, 0)), isTrue);
      expect(_tuesday.contains(DateTime(2026, 10, 27, 11, 0)), isTrue);
    });

    test('compares a UTC timestamp as the local time it was', () {
      final local = DateTime(2026, 10, 27, 11, 0);
      expect(_tuesday.contains(local.toUtc()), isTrue);
      final outside = DateTime(2026, 10, 27, 12, 30);
      expect(_tuesday.contains(outside.toUtc()), isFalse);
    });
  });

  group('SchoolClass', () {
    test('reads its lessons in week order and keeps fields it does not '
        'know', () {
      final c = SchoolClass.fromMap({
        'name': ' 6EWI ',
        'lessons': [
          {'weekday': 3, 'start': '10:00', 'end': '10:50'},
          {'weekday': 2, 'start': '10:50', 'end': '11:40'},
          {'weekday': 2, 'start': 'bad', 'end': '11:40'},
        ],
        'colour': 'green',
      })!;
      expect(c.name, '6EWI');
      expect(c.lessons.map((l) => l.weekday), [2, 3]);
      expect(c.extra, {'colour': 'green'});
      expect(c.toMap()['colour'], 'green');
      expect(c.toMap()['lessons'], [
        {'weekday': 2, 'start': '10:50', 'end': '11:40'},
        {'weekday': 3, 'start': '10:00', 'end': '10:50'},
      ]);
    });

    test('an entry without a name is no class', () {
      expect(SchoolClass.fromMap({'name': '  '}), isNull);
      expect(SchoolClass.fromMap({'lessons': []}), isNull);
      expect(SchoolClass.fromMap('6EWI'), isNull);
    });

    test('copyWith keeps the lessons in week order', () {
      const c = SchoolClass(name: '6EWI');
      final next = c.copyWith(
        lessons: [
          _tuesday.copyWith(weekday: DateTime.friday),
          _tuesday,
        ],
      );
      expect(next.lessons.map((l) => l.weekday), [2, 5]);
    });
  });

  group('ClassList', () {
    final list = ClassList.fromDoc({
      'id': 'classes',
      'type': 'config',
      'classes': [
        {
          'name': '6WEWI',
          'lessons': [
            {'weekday': 5, 'start': '10:00', 'end': '11:40'},
          ],
        },
        {
          'name': '6EWI',
          'lessons': [_tuesday.toMap()],
        },
        {'name': '6EWI', 'lessons': []},
        {'name': '5A'},
        'garbage',
      ],
    });

    test('reads the doc: sorted by name, a name only once', () {
      expect(list.names, ['5A', '6EWI', '6WEWI']);
      // The first entry of a name wins.
      expect(list.lessonsOf('6EWI'), [_tuesday]);
    });

    test('a doc without classes is no classes', () {
      expect(ClassList.fromDoc(const {}).isEmpty, isTrue);
      expect(ClassList.fromDoc({'classes': 'nope'}).isEmpty, isTrue);
    });

    test('lessonsOf an unknown class, or one without lessons, is empty', () {
      expect(list.lessonsOf('5A'), isEmpty);
      expect(list.lessonsOf('6 WEWI'), isEmpty);
      expect(list.lessonsOf(''), isEmpty);
    });

    test('contains and byName go by the exact name', () {
      expect(list.contains('6EWI'), isTrue);
      expect(list.contains(' 6EWI '), isTrue);
      expect(list.contains('6ewi'), isFalse);
      expect(list.byName('6WEWI')!.lessons, hasLength(1));
    });

    test('clashWith goes by the name up to case, except the one named', () {
      expect(list.clashWith('6ewi')?.name, '6EWI');
      expect(list.clashWith('6EWI', except: '6EWI'), isNull);
      expect(list.clashWith('7A'), isNull);
    });

    test('isDuringLesson: in a lesson of the class, with the margin', () {
      const margin = Duration(minutes: 10);
      final tuesdayEleven = DateTime(2026, 10, 6, 11, 0);
      final fridayTen = DateTime(2026, 10, 9, 10, 30);
      expect(list.isDuringLesson('6EWI', tuesdayEleven), isTrue);
      expect(list.isDuringLesson('6WEWI', tuesdayEleven), isFalse);
      expect(list.isDuringLesson('6WEWI', fridayTen), isTrue);
      expect(
        list.isDuringLesson(
          '6EWI',
          DateTime(2026, 10, 6, 10, 41),
          margin: margin,
        ),
        isTrue,
      );
      // No class, an unknown class, a class without lessons: never.
      expect(list.isDuringLesson('', tuesdayEleven), isFalse);
      expect(list.isDuringLesson('7A', tuesdayEleven), isFalse);
      expect(list.isDuringLesson('5A', tuesdayEleven), isFalse);
    });

    test('compares by value: two reads of the same doc are equal', () {
      final again = ClassList.fromDoc({'classes': list.toMaps()});
      expect(again, list);
      expect(again.hashCode, list.hashCode);
      final changed = ClassList.sorted([
        for (final c in again.classes)
          c.name == '5A' ? c.copyWith(lessons: [_tuesday]) : c,
      ]);
      expect(changed, isNot(list));
    });

    test('toMaps is the stored classes field', () {
      expect(ClassList.fromDoc({'classes': list.toMaps()}).names, list.names);
    });
  });
}
