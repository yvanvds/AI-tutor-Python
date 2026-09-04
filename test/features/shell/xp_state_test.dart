// Issue #116 — the level curve. XP is derived from `Progress.progress`
// summed over the non-optional subgoals × 100, and every level is a constant
// 500 XP wide (it used to be `1500 * level`, so level 2 cost 15 subgoals and
// each level after that was wider than the last).
//
// `_xpBreakdown` / the curve constants are private, so the curve is exercised
// where the app reads it: `xpStateProvider` over the real `GoalsService` /
// `ProgressService` on an in-memory Cosmos. The user-visible end of the same
// change — the top bar's XP pill — is asserted in
// `integration_test/flows/options_panel.dart`.

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const String _uid = 'u1';

class _SignedInAccount extends AccountService {
  @override
  Account? build() => const Account(
    uid: _uid,
    email: 'sam@school.example',
    firstName: 'Sam',
    lastName: 'Peeters',
    targetGoal: 'Python basics',
  );
}

Map<String, dynamic> _goalDoc({
  required String id,
  String? parentId,
  bool optional = false,
}) => {
  'id': id,
  'type': 'goal',
  'title': id,
  'parentId': parentId,
  'order': 1000,
  'optional': optional,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'moduleId': 'python-basics',
};

Map<String, dynamic> _progressDoc(String goalId, double progress) => {
  'id': '${_uid}_$goalId',
  'uid': _uid,
  'goalId': goalId,
  'progress': progress,
  'updatedAt': '2026-05-01T10:00:00Z',
  'lastSessionAt': '2026-05-01T10:00:00Z',
};

void main() {
  /// [completed] fully-finished non-optional subgoals out of [subgoals], each
  /// worth 100 XP.
  Future<XpState> xpFor({
    required int subgoals,
    required int completed,
    double partial = 0.0,
  }) async {
    final goals = InMemoryCosmos([
      _goalDoc(id: 'r1'),
      for (var i = 0; i < subgoals; i++) _goalDoc(id: 's$i', parentId: 'r1'),
    ]);
    final progress = InMemoryCosmos([
      for (var i = 0; i < completed; i++) _progressDoc('s$i', 1.0),
      if (partial > 0) _progressDoc('s$completed', partial),
    ]);

    final container = ProviderContainer(
      overrides: [
        accountServiceProvider.overrideWith(_SignedInAccount.new),
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
        progressServiceProvider.overrideWithValue(
          ProgressService(
            container: progress.container,
            historyContainer: InMemoryCosmos([]).container,
            getUid: () => _uid,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(xpStateProvider.future);
  }

  group('xp level curve', () {
    test('every level is the same 500 XP wide', () async {
      // 5 subgoals = 500 XP = exactly the first threshold.
      final atThreshold = await xpFor(subgoals: 8, completed: 5);
      expect(atThreshold.level, 2);
      expect(atThreshold.xp, 0);
      expect(atThreshold.xpNext, 500);

      // …and the second level is not wider than the first: 10 subgoals, not
      // the 45 the old `1500 * level` ramp would have demanded for level 3.
      final second = await xpFor(subgoals: 12, completed: 10);
      expect(second.level, 3);
      expect(second.xp, 0);
      expect(second.xpNext, 500);

      final third = await xpFor(subgoals: 20, completed: 15);
      expect(third.level, 4);
      expect(third.xpNext, 500);
    });

    test('XP inside a level is the remainder', () async {
      final s = await xpFor(subgoals: 8, completed: 7);
      expect(s.level, 2);
      expect(s.xp, 200);
      expect(s.xpNext, 500);
    });

    test('one completed subgoal is 100 XP, still level 1', () async {
      final s = await xpFor(subgoals: 5, completed: 1);
      expect(s.level, 1);
      expect(s.xp, 100);
      expect(s.xpNext, 500);
    });

    test('partial progress counts pro rata', () async {
      final s = await xpFor(subgoals: 5, completed: 2, partial: 0.5);
      expect(s.level, 1);
      expect(s.xp, 250);
    });

    test('no progress at all is the default state', () async {
      final s = await xpFor(subgoals: 5, completed: 0);
      expect(s.level, 1);
      expect(s.xp, 0);
      expect(s.xpNext, 500);
    });

    test('optional subgoals are worth nothing', () async {
      final goals = InMemoryCosmos([
        _goalDoc(id: 'r1'),
        _goalDoc(id: 's0', parentId: 'r1'),
        _goalDoc(id: 's1', parentId: 'r1', optional: true),
      ]);
      final progress = InMemoryCosmos([
        _progressDoc('s0', 1.0),
        _progressDoc('s1', 1.0),
      ]);
      final container = ProviderContainer(
        overrides: [
          accountServiceProvider.overrideWith(_SignedInAccount.new),
          goalsServiceProvider.overrideWithValue(
            GoalsService(container: goals.container),
          ),
          progressServiceProvider.overrideWithValue(
            ProgressService(
              container: progress.container,
              historyContainer: InMemoryCosmos([]).container,
              getUid: () => _uid,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final s = await container.read(xpStateProvider.future);
      expect(s.xp, 100);
    });
  });
}
