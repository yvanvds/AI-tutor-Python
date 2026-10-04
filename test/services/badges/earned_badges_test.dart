// Issue #220 — the earned badges on the account doc: read tolerantly, merged
// so that nothing earned is ever taken away, and shaped so #221 can add the
// teacher's badges and the podium's medals (`awardedBy`) next to them.

import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 9, 30);
  final earlier = DateTime.utc(2026, 10, 1, 10);

  group('reading the doc', () {
    test('no `badges` field: never looked at — null, not "none earned"', () {
      expect(EarnedBadges.fromDoc({'id': 'u1'}), isNull);
      expect(EarnedBadges.fromDoc({'badges': {}}), EarnedBadges.none);
    });

    test('entries that are not a badge are left out', () {
      final earned = EarnedBadges.fromDoc({
        'badges': {
          'effort': {'tier': 2, 'earnedAt': '2026-10-01T10:00:00.000Z'},
          'helloWorld': {'tier': 1},
          'broken': 'yes',
          'zero': {'tier': 0},
          'nan': {'tier': 'two'},
        },
      })!;
      expect(earned.byId.keys, unorderedEquals(['effort', 'helloWorld']));
      expect(earned.tierOf('effort'), 2);
      expect(earned.byId['effort']!.earnedAt, earlier);
      expect(earned.tierOf('zero'), 0);
      expect(earned.tierOf('missing'), 0);
    });

    test('compares by value, so the 5 s poll only passes on a change', () {
      Map<String, dynamic> doc() => {
        'badges': {
          'effort': {'tier': 2, 'earnedAt': '2026-10-01T10:00:00.000Z'},
        },
      };
      expect(EarnedBadges.fromDoc(doc()), EarnedBadges.fromDoc(doc()));
      expect(
        EarnedBadges.fromDoc(doc()).hashCode,
        EarnedBadges.fromDoc(doc()).hashCode,
      );
    });
  });

  group('merging', () {
    test(
      'the first look: every badge reached is raised, and it says first',
      () {
        final award = mergeBadgeTiers(null, {
          'effort': 2,
          'helloWorld': 1,
          'streak': 0,
        }, now: now);
        expect(award.first, isTrue);
        expect(award.changed, isTrue);
        expect(award.raised, {'effort': 2, 'helloWorld': 1});
        expect(award.badges['effort'], {
          'tier': 2,
          'earnedAt': '2026-10-05T09:30:00.000Z',
        });
        expect(award.badges.containsKey('streak'), isFalse);
      },
    );

    test('a first look with nothing earned still writes the empty map, so '
        'the next badge is announced on its own', () {
      final award = mergeBadgeTiers(null, const {}, now: now);
      expect(award.first, isTrue);
      expect(award.changed, isTrue);
      expect(award.badges, isEmpty);
      expect(award.raised, isEmpty);
    });

    test('only a higher tier goes up, with a new earnedAt; a lower one — a '
        'threshold raised later, a history reset — never takes one away', () {
      final stored = {
        'effort': {'tier': 2, 'earnedAt': '2026-10-01T10:00:00.000Z'},
        'streak': {'tier': 3, 'earnedAt': '2026-10-01T10:00:00.000Z'},
      };
      final award = mergeBadgeTiers(stored, {
        'effort': 3,
        'streak': 1,
      }, now: now);
      expect(award.first, isFalse);
      expect(award.raised, {'effort': 3});
      expect(award.badges['effort'], {
        'tier': 3,
        'earnedAt': '2026-10-05T09:30:00.000Z',
      });
      expect(award.badges['streak'], stored['streak']);
    });

    test('nothing higher: nothing to write', () {
      final award = mergeBadgeTiers(
        {
          'effort': {'tier': 2},
        },
        {'effort': 2},
        now: now,
      );
      expect(award.changed, isFalse);
      expect(award.raised, isEmpty);
    });

    test('entries the rules do not name — another build\'s, a teacher\'s '
        '(#221) — and fields this build does not know are kept', () {
      final stored = {
        'teacher:helper': {
          'tier': 1,
          'awardedBy': 'teacher',
          'note': 'hielp de buren',
        },
        'effort': {
          'tier': 1,
          'earnedAt': '2026-10-01T10:00:00.000Z',
          'seenAt': '2026-10-01T10:01:00.000Z',
        },
        'future': 'something else entirely',
      };
      final award = mergeBadgeTiers(stored, {'effort': 2}, now: now);
      expect(award.badges['teacher:helper'], stored['teacher:helper']);
      expect(award.badges['future'], 'something else entirely');
      expect(award.badges['effort'], {
        'seenAt': '2026-10-01T10:01:00.000Z',
        'tier': 2,
        'earnedAt': '2026-10-05T09:30:00.000Z',
      });
    });

    test('an awardedBy survives a raise, so #221\'s badges keep their '
        'origin', () {
      final award = mergeBadgeTiers(
        {
          'podium:2026-10': {'tier': 1, 'awardedBy': 'podium'},
        },
        {'podium:2026-10': 2},
        now: now,
      );
      expect(
        EarnedBadge.fromJson(award.badges['podium:2026-10'])!.awardedBy,
        'podium',
      );
    });
  });
}
