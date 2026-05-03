// 5.3 — Inline columns and row-tap drawer behaviour on the teacher accounts
// page. The accounts page now joins three streams (accounts, all-progress
// cross-partition, all-goals) and derives per-row "Huidig doel", "Voortgang",
// "Status" columns from them. Tapping a row opens the right-hand
// `StudentDetailDrawer`. The detail drawer's own contents are tested via
// the helper-function tests in `teacher_signals_test.dart` and the service
// tests; here we only assert the wiring.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/features/account/accounts_page.dart';
import 'package:ai_tutor_python/features/account/detail/student_detail_drawer.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/status_report/report_service.dart';
import 'package:ai_tutor_python/services/status_report/status_report.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

/// Minimal AccountService subclass that returns a fixed accounts stream
/// without touching auth or Cosmos.
class _FakeAccountService extends AccountService {
  _FakeAccountService(this._accounts);
  final List<Account> _accounts;

  @override
  Account? build() => null;

  @override
  Stream<List<Account>> streamAllAccounts() => Stream.value(_accounts);
}

void main() {
  late MockProgressService progressSvc;
  late MockGoalsService goalsSvc;
  late MockReportService reportSvc;

  final accounts = [
    const Account(
      uid: 'u1',
      email: 'alice@example.com',
      firstName: 'Alice',
      lastName: 'A',
      targetGoal: '',
    ),
    const Account(
      uid: 'u2',
      email: 'bob@example.com',
      firstName: 'Bob',
      lastName: 'B',
      targetGoal: '',
    ),
  ];

  final goals = [
    Goal(id: 'r1', title: 'Variabelen', order: 1000),
    Goal(id: 'c1', title: 'Toekenning', parentId: 'r1', order: 1000),
    Goal(id: 'r2', title: 'Lussen', order: 2000),
    Goal(id: 'c2', title: 'For-lus', parentId: 'r2', order: 1000),
  ];

  final now = DateTime.now().toUtc();
  final progressByUid = <String, List<Progress>>{
    // Alice: recent activity, all wrong → struggling
    'u1': [
      Progress(
        goalID: 'c1',
        progress: 0.5,
        lastSessionAt: now.subtract(const Duration(hours: 2)),
        recentAnswers: const [
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.wrong,
        ],
      ),
    ],
    // Bob: recent activity, all correct → active
    'u2': [
      Progress(
        goalID: 'c2',
        progress: 0.8,
        lastSessionAt: now.subtract(const Duration(hours: 1)),
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
        ],
      ),
    ],
  };

  setUp(() {
    progressSvc = MockProgressService();
    goalsSvc = MockGoalsService();
    reportSvc = MockReportService();

    when(() => progressSvc.watchAllProgress()).thenAnswer(
      (_) => Stream<Map<String, List<Progress>>>.value(progressByUid),
    );
    when(() => progressSvc.watchProgressForUser(any<String>())).thenAnswer(
      (inv) => Stream<List<Progress>>.value(
        progressByUid[inv.positionalArguments.first as String] ??
            const <Progress>[],
      ),
    );
    when(
      () => progressSvc.watchHistoryForUser(
        any<String>(),
        since: any<DateTime?>(named: 'since'),
        limit: any<int?>(named: 'limit'),
      ),
    ).thenAnswer((_) => const Stream.empty());
    when(() => goalsSvc.streamAllGoals())
        .thenAnswer((_) => Stream<List<Goal>>.value(goals));
    when(() => reportSvc.watchStatusReportsForUser(any<String>()))
        .thenAnswer((_) => Stream<List<StatusReport>>.value(const []));
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountServiceProvider.overrideWith(
            () => _FakeAccountService(accounts),
          ),
          progressServiceProvider.overrideWithValue(progressSvc),
          goalsServiceProvider.overrideWithValue(goalsSvc),
          reportServiceProvider.overrideWithValue(reportSvc),
        ],
        child: const MaterialApp(home: AccountsPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders the new inline columns', (tester) async {
    await pump(tester);
    expect(find.text('Huidig doel'), findsOneWidget);
    expect(find.text('Voortgang'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets('shows the most-recently-active root goal title in '
      '"Huidig doel"', (tester) async {
    await pump(tester);
    expect(find.text('Variabelen'), findsOneWidget); // Alice's root
    expect(find.text('Lussen'), findsOneWidget); // Bob's root
  });

  testWidgets('tapping a row opens the student detail drawer',
      (tester) async {
    await pump(tester);
    expect(find.byType(StudentDetailDrawer), findsNothing);

    // Tap a plain Text cell — SelectableText would swallow the tap before
    // DataRow.onSelectChanged sees it.
    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(StudentDetailDrawer), findsOneWidget);
  });
}
