// Issue #25 — the Options panel gathers language, progress reset (all or one
// goal), the user's own OpenAI key, GitHub bug reports and — behind the
// developer gate — the former debug dialog.
//
// This mounts the real OptionsPage over the real services (AccountService,
// GoalsService, ProgressService, LoBeliefsService, TurnHistoryService,
// LocalApiKeyStorage, GitHubTokenStorage, LocaleService), each backed by an
// in-memory Cosmos fake / mock SharedPreferences / a scripted http client, so
// every flow is exercised from the button through the dialogs to the writes.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo (#28).

import 'dart:convert';

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/github/github_issue_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';

const _uid = 'u1';

const _identity = AccountIdentity(
  oid: _uid,
  displayName: 'Sam Student',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  isTeacher: false,
);

class _SignedInAuth extends AuthService {
  @override
  AccountIdentity? build() => _identity;
}

Map<String, dynamic> _goal({
  required String id,
  required String title,
  String? parentId,
  int order = 1000,
}) => {
  'id': id,
  'type': 'goal',
  'title': title,
  'parentId': parentId,
  'order': order,
  'optional': false,
  'teachingTips': const <String>[],
  'allowChains': false,
  'objectives': const <Map<String, dynamic>>[],
  'contentId': null,
  'moduleId': 'python-basics',
};

Map<String, dynamic> _progress(String goalId, double value) => {
  'id': '${_uid}_$goalId',
  'uid': _uid,
  'goalId': goalId,
  'progress': value,
};

Map<String, dynamic> _sample(String id, String goalId) => {
  'id': id,
  'uid': _uid,
  'goalId': goalId,
  'progress': 0.5,
  'at': '2026-05-01T10:00:00Z',
};

Map<String, dynamic> _belief(String id, String subgoalId) => {
  'id': id,
  'type': 'lo_belief',
  'uid': _uid,
  'subgoalId': subgoalId,
  'loId': 'lo-1',
  'alpha': 3.0,
  'beta': 1.0,
  'lastUpdatedAt': '2026-05-01T10:00:00Z',
};

Map<String, dynamic> _turn(String id, String subgoalId) => {
  'id': id,
  'uid': _uid,
  'subgoalId': subgoalId,
  'turnAt': '2026-05-01T10:00:00Z',
};

Map<String, dynamic> _account({required bool mayUseGlobalKey}) => {
  'id': _uid,
  'uid': _uid,
  'email': 'sam@example.com',
  'firstName': 'Sam',
  'lastName': 'Student',
  'targetGoal': 'Python',
  'mayUseGlobalKey': mayUseGlobalKey,
  'calibration': {
    'difficulty': 'hard',
    'recentAnswers': const [],
    'recentQuestionTypes': const [],
  },
};

void main() {
  late InMemoryCosmos goals;
  late InMemoryCosmos progress;
  late InMemoryCosmos history;
  late InMemoryCosmos beliefs;
  late InMemoryCosmos turns;
  late InMemoryCosmos accounts;
  late DebugSessionRecorder recorder;
  late List<http.Request> githubRequests;

  setUp(() {
    SharedPreferences.setMockInitialValues({'local_api_key': 'sk-old'});
    goals = InMemoryCosmos([
      _goal(id: 'r1', title: 'Loops'),
      _goal(id: 's1', title: 'For loops', parentId: 'r1', order: 1000),
      _goal(id: 's2', title: 'While loops', parentId: 'r1', order: 2000),
    ]);
    progress = InMemoryCosmos([
      _progress('r1', 0.75),
      _progress('s1', 1.0),
      _progress('s2', 0.5),
    ]);
    history = InMemoryCosmos([_sample('h1', 's1'), _sample('h2', 's2')]);
    beliefs = InMemoryCosmos([_belief('b1', 's1'), _belief('b2', 's2')]);
    turns = InMemoryCosmos([_turn('t1', 's1'), _turn('t2', 's2')]);
    accounts = InMemoryCosmos([_account(mayUseGlobalKey: false)]);

    recorder = DebugSessionRecorder()
      ..beginTurn(
        requestType: 'submitCode',
        currentExerciseTypeAtStart: '',
        tutorStateAtStart: 'working',
        selectedRootGoalId: 'r1',
        selectedChildGoalId: 's1',
        preferredRootGoalId: null,
        preferredChildGoalId: null,
        streamable: true,
        previousInputsMode: 'includeSession',
      )
      ..recordRequestPayload(
        userInput: 'print(1)',
        instructions: 'SYSTEM PROMPT — must not be posted',
        instructionsDocId: 'submitCode',
      )
      ..endTurn();

    githubRequests = [];
  });

  http.Client githubClient() => MockClient((req) async {
    githubRequests.add(req);
    if (req.method == 'GET' && req.url.path == '/user') {
      if (req.headers['Authorization'] != 'Bearer ghp_valid') {
        return http.Response('{"message":"Bad credentials"}', 401);
      }
      return http.Response('{"login":"yvan"}', 200);
    }
    if (req.method == 'POST' &&
        req.url.path == '/repos/$kBugReportRepo/issues') {
      return http.Response(
        '{"html_url":"https://github.com/$kBugReportRepo/issues/42"}',
        201,
      );
    }
    return http.Response('{"message":"Not Found"}', 404);
  });

  Widget buildApp({bool devTools = false}) => ProviderScope(
    overrides: [
      authServiceProvider.overrideWith(_SignedInAuth.new),
      accountServiceProvider.overrideWith(
        () => AccountService(container: accounts.container),
      ),
      goalsServiceProvider.overrideWithValue(
        GoalsService(container: goals.container),
      ),
      progressServiceProvider.overrideWithValue(
        ProgressService(
          container: progress.container,
          historyContainer: history.container,
          getUid: () => _uid,
        ),
      ),
      loBeliefsServiceProvider.overrideWithValue(
        LoBeliefsService(container: beliefs.container, getUid: () => _uid),
      ),
      turnHistoryServiceProvider.overrideWithValue(
        TurnHistoryService(container: turns.container, getUid: () => _uid),
      ),
      githubIssueServiceProvider.overrideWithValue(
        GitHubIssueService(client: githubClient()),
      ),
      debugServiceProvider.overrideWithValue(recorder),
      developerToolsProvider.overrideWithValue(devTools),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: OptionsPage()),
    ),
  );

  Future<void> mount(WidgetTester tester, {bool devTools = false}) async {
    // Tall viewport so every card is laid out without scrolling.
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp(devTools: devTools));
    // Account poll + SharedPreferences hydration.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(OptionsPage)));

  group('progress', () {
    testWidgets('reset all wipes every per-user doc and resets calibration', (
      tester,
    ) async {
      await mount(tester);

      await tester.tap(find.text('Reset all progress'));
      await tester.pumpAndSettle();
      expect(find.text('Reset all progress?'), findsOneWidget);

      // Cancel changes nothing.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(progress.docs, hasLength(3));

      await tester.tap(find.text('Reset all progress'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset everything'));
      await tester.pumpAndSettle();

      expect(progress.docs, isEmpty);
      expect(history.docs, isEmpty);
      expect(beliefs.docs, isEmpty);
      expect(turns.docs, isEmpty);
      expect(accounts[_uid]!['calibration']['difficulty'], 'medium');
      expect(find.text('All progress has been reset.'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('reset one subgoal clears only that subgoal and recomputes '
        'the root', (tester) async {
      await mount(tester);

      await tester.tap(find.text('Reset one goal…'));
      await tester.pumpAndSettle();
      expect(find.text('Reset progress for a goal'), findsOneWidget);
      expect(find.text('Loops'), findsOneWidget);
      expect(find.text('While loops'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'For loops'));
      await tester.pumpAndSettle();
      expect(find.text('Reset "For loops"?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(progress['${_uid}_s1'], isNull);
      expect(progress['${_uid}_s2']!['progress'], 0.5);
      expect(history['h1'], isNull);
      expect(history['h2'], isNotNull);
      expect(beliefs['b1'], isNull);
      expect(beliefs['b2'], isNotNull);
      expect(turns['t1'], isNull);
      expect(turns['t2'], isNotNull);
      // Root cache = mean over children (s1 now missing = 0, s2 = 0.5).
      expect(progress['${_uid}_r1']!['progress'], 0.25);
      expect(
        find.text('Progress for "For loops" has been reset.'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('reset a root goal clears all of its subgoals', (tester) async {
      await mount(tester);

      await tester.tap(find.text('Reset one goal…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Loops'));
      await tester.pumpAndSettle();
      expect(find.text('Reset "Loops"?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();

      expect(progress.docs, isEmpty);
      expect(history.docs, isEmpty);
      expect(beliefs.docs, isEmpty);
      expect(turns.docs, isEmpty);
      // Calibration is untouched by a granular reset.
      expect(accounts[_uid]!['calibration']['difficulty'], 'hard');

      await unmount(tester);
    });
  });

  group('OpenAI key', () {
    testWidgets('card is shown for own-key accounts; remove clears the key', (
      tester,
    ) async {
      await mount(tester);

      expect(find.text('OpenAI API key'), findsOneWidget);
      expect(find.text('A key is stored on this device.'), findsOneWidget);

      await tester.tap(find.text('Remove key'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('local_api_key'), isFalse);
      expect(find.text('No key stored on this device.'), findsOneWidget);
      expect(find.text('API key removed.'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('change key stores the new value', (tester) async {
      await mount(tester);

      await tester.tap(find.text('Change key'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sk-new');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_api_key'), 'sk-new');
      expect(find.text('API key updated.'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('card is hidden for accounts on the bundled key', (
      tester,
    ) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester);

      expect(find.text('OpenAI API key'), findsNothing);
      expect(find.text('Progress'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('bug reports', () {
    testWidgets('connect with a token, then post an issue with the latest '
        'turn attached', (tester) async {
      await mount(tester);
      expect(find.text('Not connected to GitHub.'), findsOneWidget);
      expect(find.text('Report a bug…'), findsNothing);

      await tester.tap(find.text('Connect GitHub'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ghp_valid');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      // Status line plus the confirmation snackbar.
      expect(find.text('Connected to GitHub as yvan.'), findsNWidgets(2));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('github_token'), 'ghp_valid');

      // Let the confirmation snackbar expire so the next one is not queued
      // behind it.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Connected to GitHub as yvan.'), findsOneWidget);

      await tester.tap(find.text('Report a bug…'));
      await tester.pumpAndSettle();
      expect(find.text('Report a bug'), findsOneWidget);
      // Latest turn is preselected.
      expect(find.text('#1 submitCode'), findsOneWidget);

      // Title is required.
      await tester.tap(find.widgetWithText(FilledButton, 'Post issue'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a title.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Tutor crashed',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'What went wrong?'),
        'It stopped after my answer.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Post issue'));
      await tester.pumpAndSettle();

      final post = githubRequests.singleWhere((r) => r.method == 'POST');
      expect(post.headers['Authorization'], 'Bearer ghp_valid');
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['title'], 'Tutor crashed');
      final text = body['body'] as String;
      expect(text, contains('It stopped after my answer.'));
      expect(text, contains('App version: `$kAppVersion`'));
      expect(text, contains('"turnId": 1'));
      expect(text, contains('"userInput": "print(1)"'));
      expect(text, isNot(contains('SYSTEM PROMPT')));
      expect(
        find.text('Issue posted: https://github.com/$kBugReportRepo/issues/42'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('a rejected token is not stored', (tester) async {
      await mount(tester);

      await tester.tap(find.text('Connect GitHub'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ghp_bad');
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not connect'), findsOneWidget);
      expect(find.text('Not connected to GitHub.'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('github_token'), isFalse);

      await unmount(tester);
    });

    testWidgets('a stored token is picked up on open and can be '
        'disconnected', (tester) async {
      SharedPreferences.setMockInitialValues({'github_token': 'ghp_valid'});
      await mount(tester);
      await tester.pump();

      expect(find.text('Connected to GitHub as yvan.'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(find.text('Not connected to GitHub.'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('github_token'), isFalse);

      await unmount(tester);
    });
  });

  group('developer tools', () {
    testWidgets('hidden without the developer gate', (tester) async {
      await mount(tester);
      expect(find.text('Developer tools'), findsNothing);
      expect(find.text('Recent turns'), findsNothing);
      await unmount(tester);
    });

    testWidgets('shown with the developer gate, listing recorded turns', (
      tester,
    ) async {
      await mount(tester, devTools: true);
      expect(find.text('Developer tools'), findsOneWidget);
      expect(find.text('Show level-up overlay'), findsOneWidget);
      expect(find.text('Trigger question'), findsOneWidget);
      expect(find.text('Recent turns'), findsOneWidget);
      expect(find.textContaining('#1  submitCode'), findsOneWidget);

      await tester.tap(find.textContaining('#1  submitCode'));
      await tester.pumpAndSettle();
      expect(find.text('Turn #1'), findsOneWidget);
      expect(find.textContaining('"userInput": "print(1)"'), findsOneWidget);

      await unmount(tester);
    });
  });

  testWidgets('language rows switch the locale', (tester) async {
    await mount(tester);
    final container = containerOf(tester);
    expect(container.read(localeServiceProvider), isNull);

    await tester.tap(find.text('Nederlands'));
    await tester.pumpAndSettle();
    expect(container.read(localeServiceProvider), const Locale('nl'));

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(container.read(localeServiceProvider), isNull);

    await unmount(tester);
  });

  testWidgets('about card shows the app version', (tester) async {
    await mount(tester);
    expect(find.text('Version $kAppVersion'), findsOneWidget);
    await unmount(tester);
  });
}
