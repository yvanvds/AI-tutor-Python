// Issue #183 — the token usage card on the Students page adds the turn
// records' usage up per class, over the last 7 and 30 days.

import 'package:ai_tutor_python/core/token_usage.dart';
import 'package:ai_tutor_python/features/account/token_usage_card.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

Account _account(String uid, [String className = '']) => Account(
  uid: uid,
  email: '$uid@example.com',
  firstName: uid,
  lastName: 'Student',
  targetGoal: 'Python',
  className: className,
);

TokenUsage _t(int prompt, int cached, int completion) => TokenUsage(
  promptTokens: prompt,
  cachedTokens: cached,
  completionTokens: completion,
);

void main() {
  final now = DateTime.utc(2026, 9, 24, 12);

  group('tokenUsageByClass', () {
    test('adds each student up under their class, 7 days inside 30', () {
      final rows = tokenUsageByClass(
        accounts: [
          _account('anna', '5A'),
          _account('ben', '5A'),
          _account('cara', '5b'),
          _account('dave', '6C'),
        ],
        entries: [
          (
            uid: 'anna',
            at: now.subtract(const Duration(days: 2)),
            tokens: _t(5000, 3000, 700),
          ),
          (
            uid: 'ben',
            at: now.subtract(const Duration(days: 10)),
            tokens: _t(4000, 0, 500),
          ),
          (
            uid: 'cara',
            at: now.subtract(const Duration(days: 3)),
            tokens: _t(2100, 1000, 250),
          ),
          // Outside the window.
          (
            uid: 'anna',
            at: now.subtract(const Duration(days: 31)),
            tokens: _t(99999, 0, 9999),
          ),
        ],
        now: now,
      );

      expect(rows.map((r) => r.className), [
        '5A',
        '5b',
        '6C',
      ], reason: 'sorted case-insensitively; a class without usage too');
      expect(rows[0].last7Days, _t(5000, 3000, 700));
      expect(rows[0].last30Days, _t(9000, 3000, 1200));
      expect(rows[1].last7Days, _t(2100, 1000, 250));
      expect(rows[1].last30Days, _t(2100, 1000, 250));
      expect(rows[2].last30Days, TokenUsage.zero);
    });

    test('students without a class, and accounts that are gone, share a '
        'last row — only when they used anything', () {
      final accounts = [_account('anna', '5A'), _account('teacher')];
      final rows = tokenUsageByClass(
        accounts: accounts,
        entries: [
          (
            uid: 'teacher',
            at: now.subtract(const Duration(days: 1)),
            tokens: _t(2700, 2048, 450),
          ),
          (
            uid: 'deleted',
            at: now.subtract(const Duration(days: 20)),
            tokens: _t(100, 0, 10),
          ),
        ],
        now: now,
      );
      expect(rows.map((r) => r.className), ['5A', '']);
      expect(rows[1].last7Days, _t(2700, 2048, 450));
      expect(rows[1].last30Days, _t(2800, 2048, 460));

      expect(
        tokenUsageByClass(
          accounts: accounts,
          entries: const [],
          now: now,
        ).map((r) => r.className),
        ['5A'],
      );
    });
  });

  test('listUsageSince reads every student\'s records that carry usage, '
      'since the given moment', () async {
    final store = InMemoryCosmos([
      {
        'id': 'a1',
        'uid': 'anna',
        'turnAt': now.subtract(const Duration(days: 2)).toIso8601String(),
        'usage': {
          'model': 'gpt-5-mini',
          'promptTokens': 5000,
          'cachedTokens': 3000,
          'completionTokens': 700,
          'byCall': <String, Object>{},
        },
      },
      {
        // Written before #183: no usage block.
        'id': 'b1',
        'uid': 'ben',
        'turnAt': now.subtract(const Duration(days: 1)).toIso8601String(),
      },
      {
        'id': 'a0',
        'uid': 'anna',
        'turnAt': now.subtract(const Duration(days: 40)).toIso8601String(),
        'usage': {'promptTokens': 1, 'completionTokens': 1},
      },
    ]);
    final service = TurnHistoryService(
      container: store.container,
      getUid: () => 'teacher',
    );

    final entries = await service.listUsageSince(
      now.subtract(const Duration(days: 30)),
    );
    expect(entries, hasLength(1));
    expect(entries.single.uid, 'anna');
    expect(entries.single.tokens, _t(5000, 3000, 700));
  });
}
