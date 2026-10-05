// #228 — the content of an oefening is kept until a day of the year at
// midnight, Belgian time (default 1 July), and every write turns that day
// into the seconds Cosmos counts down from the write.

import 'package:ai_tutor_python/core/keep_until.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeepUntil.tryParse', () {
    test('reads MM-DD, with or without leading zeros and around spaces', () {
      expect(KeepUntil.tryParse('07-01'), const KeepUntil(7, 1));
      expect(KeepUntil.tryParse('7-1'), const KeepUntil(7, 1));
      expect(KeepUntil.tryParse(' 12-20 '), const KeepUntil(12, 20));
      expect(KeepUntil.tryParse('02-29'), const KeepUntil(2, 29));
    });

    test('is null for anything that is not a day of the year', () {
      for (final raw in <Object?>[
        null,
        '',
        '13-01',
        '00-10',
        '02-30',
        '04-31',
        '07-00',
        '07/01',
        '2027-07-01',
        701,
      ]) {
        expect(KeepUntil.tryParse(raw), isNull, reason: '$raw');
      }
    });

    test('writes back as MM-DD', () {
      expect(const KeepUntil(7, 1).toString(), '07-01');
      expect(const KeepUntil(12, 20).toString(), '12-20');
    });
  });

  group('KeepUntil.after', () {
    const july = KeepUntil.schoolYearEnd;

    test('1 July after an oefening in October is next summer, at midnight '
        'summer time (UTC+2)', () {
      expect(
        july.after(DateTime.utc(2026, 10, 4, 10)),
        DateTime.utc(2027, 6, 30, 22),
      );
    });

    test('the moment itself is not after it: an oefening at midnight '
        'Brussels time on 1 July is kept until the next 1 July', () {
      expect(
        july.after(DateTime.utc(2027, 6, 30, 21, 59)),
        DateTime.utc(2027, 6, 30, 22),
      );
      expect(
        july.after(DateTime.utc(2027, 6, 30, 22)),
        DateTime.utc(2028, 6, 30, 22),
      );
      expect(
        july.after(DateTime.utc(2027, 7, 1, 8)),
        DateTime.utc(2028, 6, 30, 22),
      );
    });

    test('a day in winter is midnight at UTC+1', () {
      expect(
        const KeepUntil(12, 20).after(DateTime.utc(2026, 10, 4)),
        DateTime.utc(2026, 12, 19, 23),
      );
    });

    test('around the clock changes: midnight on the last Sunday of March is '
        'still winter time, on the last Sunday of October still summer '
        'time', () {
      final at = DateTime.utc(2027, 1, 10);
      // 2027: summer time from Sunday 28 March to Sunday 31 October.
      expect(const KeepUntil(3, 28).after(at), DateTime.utc(2027, 3, 27, 23));
      expect(const KeepUntil(3, 29).after(at), DateTime.utc(2027, 3, 28, 22));
      expect(const KeepUntil(10, 31).after(at), DateTime.utc(2027, 10, 30, 22));
      expect(const KeepUntil(11, 1).after(at), DateTime.utc(2027, 10, 31, 23));
    });

    test('a turn that is already on the next day in Brussels counts from '
        'there', () {
      // 23:30 UTC on 31 December is 00:30 on 1 January in Brussels: the
      // 1 January just past does not count.
      expect(
        const KeepUntil(1, 1).after(DateTime.utc(2026, 12, 31, 23, 30)),
        DateTime.utc(2027, 12, 31, 23),
      );
    });

    test('29 February is 1 March in a year without one', () {
      expect(
        const KeepUntil(2, 29).after(DateTime.utc(2026, 10, 4)),
        DateTime.utc(2027, 2, 28, 23),
      );
      expect(
        const KeepUntil(2, 29).after(DateTime.utc(2027, 10, 4)),
        DateTime.utc(2028, 2, 28, 23),
      );
    });

    test('a local time is read as the instant it is', () {
      final local = DateTime.utc(2026, 10, 4, 10).toLocal();
      expect(july.after(local), DateTime.utc(2027, 6, 30, 22));
    });
  });

  group('KeepUntil.ttlSeconds', () {
    test('the seconds from the write to the day after the turn', () {
      final at = DateTime.utc(2026, 10, 4, 10);
      final now = at.add(const Duration(seconds: 5));
      expect(
        KeepUntil.schoolYearEnd.ttlSeconds(at: at, now: now),
        DateTime.utc(2027, 6, 30, 22).difference(now).inSeconds,
      );
    });

    test('rounds a part second up', () {
      final at = DateTime.utc(2027, 6, 30, 21, 59, 58);
      final now = DateTime.utc(2027, 6, 30, 21, 59, 58, 500);
      expect(KeepUntil.schoolYearEnd.ttlSeconds(at: at, now: now), 2);
    });

    test('is at least one second when the write comes after the day', () {
      final at = DateTime.utc(2027, 6, 30, 21, 59, 59);
      final now = DateTime.utc(2027, 6, 30, 22, 0, 30);
      expect(KeepUntil.schoolYearEnd.ttlSeconds(at: at, now: now), 1);
    });
  });
}
