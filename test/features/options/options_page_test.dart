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
// Extended for #32: appearance (light / dark), the per-device AI model, and
// export / import of progress.
//
// The end-to-end half of the panel — the theme switch repainting the whole
// shell, and the progress round trip through a real file — lives in
// `integration_test/flows/options_panel.dart`, which boots the real app.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:ai_tutor_python/services/config/model_preference.dart';
import 'package:ai_tutor_python/services/config/theme_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/progress/progress_archive.dart';
import 'package:ai_tutor_python/services/progress/progress_archive_io.dart';
import 'package:ai_tutor_python/services/github/github_device_flow.dart';
import 'package:ai_tutor_python/services/github/github_issue_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// The school-wide config doc, without a Cosmos round trip.
class _FixedGlobalConfig extends GlobalConfigService {
  _FixedGlobalConfig(this._config);
  final GlobalConfig? _config;

  @override
  GlobalConfig? build() => _config;
}

/// Stands in for the OS file dialogs behind progress export / import (#32).
class _FakeArchiveIo implements ProgressArchiveIo {
  String? savedName;
  String? savedContents;
  bool cancelSave = false;
  ArchiveFile? toOpen;
  Object? openError;

  @override
  Future<String?> save({
    required String suggestedName,
    required String contents,
  }) async {
    savedName = suggestedName;
    savedContents = contents;
    return cancelSave ? null : 'C:\\Users\\sam\\$suggestedName';
  }

  @override
  Future<ArchiveFile?> open() async {
    if (openError != null) throw openError!;
    return toOpen;
  }
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
  late _FakeArchiveIo archiveIo;

  // #57 — the device flow's two moving parts, as a test can steer them:
  // whether the student has approved the code yet, and whether GitHub is
  // answering with an outright refusal instead.
  late bool githubApproved;
  late String? githubPollError;
  late List<Uri> browserLaunches;
  late bool browserOpens;

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
    archiveIo = _FakeArchiveIo();
    githubApproved = false;
    githubPollError = null;
    browserLaunches = [];
    browserOpens = true;
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

  /// GitHub's OAuth host (#57): hands out a fixed code pair and then answers
  /// `authorization_pending` until the test says the student approved it.
  http.Client githubOAuthClient() => MockClient((req) async {
    githubRequests.add(req);
    if (req.url.path == '/login/device/code') {
      return http.Response(
        jsonEncode({
          'device_code': 'dev-code',
          'user_code': 'WDJB-MJHT',
          'verification_uri': 'https://github.com/login/device',
          'interval': 5,
          'expires_in': 900,
        }),
        200,
      );
    }
    if (req.url.path == '/login/oauth/access_token') {
      if (githubPollError != null) {
        return http.Response('{"error":"$githubPollError"}', 200);
      }
      if (!githubApproved) {
        return http.Response('{"error":"authorization_pending"}', 200);
      }
      return http.Response('{"access_token":"ghp_valid"}', 200);
    }
    return http.Response('{"message":"Not Found"}', 404);
  });

  Widget buildApp({
    bool devTools = false,
    UpdateServices? update,
    String globalModel = 'gpt-4o',
    String oauthClientId = 'Ov23liTESTCLIENTID',
  }) => ProviderScope(
    overrides: [
      gitHubDeviceFlowProvider.overrideWithValue(
        GitHubDeviceFlow(
          clientId: oauthClientId,
          client: githubOAuthClient(),
          authBase: Uri.parse('https://github.com/'),
        ),
      ),
      browserLauncherProvider.overrideWithValue((url) async {
        browserLaunches.add(url);
        return browserOpens;
      }),
      if (update != null) updateServicesProvider.overrideWithValue(update),
      globalConfigServiceProvider.overrideWith(
        () => _FixedGlobalConfig(GlobalConfig(model: globalModel, apiKey: '')),
      ),
      progressArchiveIoProvider.overrideWithValue(archiveIo),
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

  Future<void> mount(
    WidgetTester tester, {
    bool devTools = false,
    UpdateServices? update,
    String globalModel = 'gpt-4o',
    String oauthClientId = 'Ov23liTESTCLIENTID',
  }) async {
    // Tall viewport so every card is laid out without scrolling.
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildApp(
        devTools: devTools,
        update: update,
        globalModel: globalModel,
        oauthClientId: oauthClientId,
      ),
    );
    // Account poll + SharedPreferences hydration.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  /// Drops any confirmation still on screen, so the next one asserted on is
  /// not queued behind it.
  Future<void> clearSnacks(WidgetTester tester) async {
    ScaffoldMessenger.of(tester.element(find.byType(OptionsPage)))
        .clearSnackBars();
    await tester.pumpAndSettle();
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
    /// Settles the frames that are not the dialog's spinner.
    ///
    /// `pumpAndSettle` cannot be used while the device dialog is up: it holds
    /// a `CircularProgressIndicator`, which never stops animating, so
    /// "settled" never arrives.
    Future<void> pumpFrames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// Drives the device flow to the point where the code is on screen and
    /// the app is polling.
    Future<void> startDeviceFlow(WidgetTester tester) async {
      await tester.tap(find.text('Connect GitHub'));
      // The device-code request, then the dialog route animating in.
      await tester.pump();
      await pumpFrames(tester);
    }

    /// One poll interval: the app is parked in the 5 s wait GitHub asked for.
    Future<void> pollOnce(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    }

    /// Ends a flow a test left running, so no poll timer outlives the widget
    /// tree (which `flutter_test` fails the test over, rightly).
    Future<void> stopDeviceFlow(WidgetTester tester) async {
      await tester.tap(find.text('Cancel'));
      await pollOnce(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('sign in with the device flow, then post an issue with the '
        'latest turn attached', (tester) async {
      await mount(tester);
      expect(find.text('Not connected to GitHub.'), findsOneWidget);
      expect(find.text('Report a bug…'), findsNothing);

      await startDeviceFlow(tester);

      // The student can read the code and knows where to type it. Nothing is
      // stored yet — approval has not happened.
      expect(
        find.byKey(const ValueKey('github-device-dialog')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const ValueKey('github-device-code')),
            )
            .data,
        'WDJB-MJHT',
      );
      expect(
        find.text('Enter the code at https://github.com/login/device'),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('github_token'), isFalse);

      // It keeps polling while the student is still in the browser.
      await pollOnce(tester);
      expect(
        find.byKey(const ValueKey('github-device-dialog')),
        findsOneWidget,
      );
      expect(find.text('Not connected to GitHub.'), findsOneWidget);

      // …and picks the token up on the first poll after approval.
      githubApproved = true;
      await pollOnce(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('github-device-dialog')), findsNothing);
      // Status line plus the confirmation snackbar.
      expect(find.text('Connected to GitHub as yvan.'), findsNWidgets(2));
      expect(prefs.getString('github_token'), 'ghp_valid');

      // The scope asked for is the one the OAuth app has to be registered
      // with, so it is pinned here as well as in the flow's own test.
      final deviceCode = githubRequests.firstWhere(
        (r) => r.url.path == '/login/device/code',
      );
      expect(Uri.splitQueryString(deviceCode.body)['scope'], 'public_repo');

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

      final post = githubRequests.singleWhere(
        (r) => r.url.path == '/repos/$kBugReportRepo/issues',
      );
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

    testWidgets('the panel opens a browser at the verification URL and '
        'copies the code', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await mount(tester);
      await startDeviceFlow(tester);

      await tester.tap(find.text('Open GitHub'));
      await tester.pump();
      expect(browserLaunches, [Uri.parse('https://github.com/login/device')]);

      await tester.tap(find.text('Copy code'));
      await pumpFrames(tester);
      expect(copied, ['WDJB-MJHT']);
      // Inside the dialog, not a snackbar behind its barrier.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('github-device-notice')))
            .data,
        'Code copied to the clipboard.',
      );

      await stopDeviceFlow(tester);
      await unmount(tester);
    });

    testWidgets('a machine with no browser is told the URL instead of being '
        'left guessing', (tester) async {
      await mount(tester);
      browserOpens = false;
      await startDeviceFlow(tester);

      await tester.tap(find.text('Open GitHub'));
      await pumpFrames(tester);

      expect(
        find.text(
          'Could not open a browser. Go to '
          'https://github.com/login/device yourself.',
        ),
        findsOneWidget,
      );

      await stopDeviceFlow(tester);
      await unmount(tester);
    });

    testWidgets('cancelling stops the flow and stores nothing', (tester) async {
      await mount(tester);
      await startDeviceFlow(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      // The loop is parked in GitHub's interval; it notices on the next tick.
      await pollOnce(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('github-device-dialog')), findsNothing);
      expect(find.text('Not connected to GitHub.'), findsOneWidget);
      expect(find.textContaining('Could not connect'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('github_token'), isFalse);
      // Connecting is offered again, not left disabled.
      expect(find.text('Connect GitHub'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('a request declined on GitHub is reported and stores nothing', (
      tester,
    ) async {
      await mount(tester);
      await startDeviceFlow(tester);

      githubPollError = 'access_denied';
      await pollOnce(tester);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The request was declined on GitHub, so nothing was '
          'connected.',
        ),
        findsOneWidget,
      );
      expect(find.text('Not connected to GitHub.'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('github_token'), isFalse);

      await unmount(tester);
    });

    testWidgets('an expired code says so rather than failing silently', (
      tester,
    ) async {
      await mount(tester);
      await startDeviceFlow(tester);

      githubPollError = 'expired_token';
      await pollOnce(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('The code expired before it was approved. Try again.'),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('github_token'), isFalse);

      await unmount(tester);
    });

    // A fork that never registered an OAuth app is a legitimate build, and it
    // must not offer a sign-in that can only end in `unauthorized_client`.
    testWidgets('a build with no OAuth client id says so and offers no '
        'sign-in', (tester) async {
      await mount(tester, oauthClientId: '');

      expect(
        find.byKey(const ValueKey('github-not-configured')),
        findsOneWidget,
      );
      expect(
        find.textContaining('compiled without a GitHub OAuth client id'),
        findsOneWidget,
      );
      expect(find.text('Connect GitHub'), findsNothing);
      expect(find.text('Not connected to GitHub.'), findsNothing);
      // The card itself is still there — the feature is unavailable, not
      // invisible.
      expect(find.text('Bug reports'), findsOneWidget);
      expect(githubRequests, isEmpty);

      await unmount(tester);
    });

    // A token already on the device keeps working even on such a build:
    // taking the sign-in away is not a reason to take the reporting away.
    testWidgets('a stored token still reports on a build with no client id', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'github_token': 'ghp_valid'});
      await mount(tester, oauthClientId: '');
      await tester.pump();

      expect(find.text('Connected to GitHub as yvan.'), findsOneWidget);
      expect(find.text('Report a bug…'), findsOneWidget);

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

  // #32 — appearance, model and progress transfer.
  group('appearance', () {
    testWidgets('picking Light stores the choice and flips the palette', (
      tester,
    ) async {
      await mount(tester);
      final container = containerOf(tester);
      expect(container.read(themeServiceProvider), AppThemeChoice.system);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();

      expect(container.read(themeServiceProvider), AppThemeChoice.light);
      expect(container.read(appPaletteProvider), AppPalette.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme'), 'light');

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(container.read(appPaletteProvider), AppPalette.dark);

      await unmount(tester);
    });
  });

  group('AI model', () {
    testWidgets('own-key accounts see the card, and the school default is the '
        'starting choice', (tester) async {
      await mount(tester, globalModel: 'gpt-4.1');

      expect(find.text('AI model'), findsOneWidget);
      expect(find.text('School default (gpt-4.1)'), findsOneWidget);
      for (final model in kSelectableModels) {
        expect(find.text(model), findsOneWidget, reason: model);
      }

      await unmount(tester);
    });

    testWidgets('picking a model stores a per-device override', (tester) async {
      await mount(tester);
      final container = containerOf(tester);
      expect(container.read(modelPreferenceProvider), isNull);

      await tester.tap(find.text('gpt-5-mini'));
      await tester.pumpAndSettle();

      expect(container.read(modelPreferenceProvider), 'gpt-5-mini');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_model'), 'gpt-5-mini');

      // Back to the school default.
      await tester.tap(find.text('School default (gpt-4o)'));
      await tester.pumpAndSettle();
      expect(container.read(modelPreferenceProvider), isNull);
      expect(prefs.getString('openai_model'), isNull);

      await unmount(tester);
    });

    testWidgets('a student on the bundled key cannot change the model', (
      tester,
    ) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester);

      expect(find.text('AI model'), findsNothing);

      await unmount(tester);
    });

    testWidgets('a developer build sees it even on the bundled key', (
      tester,
    ) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester, devTools: true);

      expect(find.text('AI model'), findsOneWidget);

      await unmount(tester);
    });
  });

  group('export / import progress', () {
    testWidgets('export writes the account state as JSON with no identity in '
        'it', (tester) async {
      await mount(tester);

      await tester.tap(find.text('Export progress…'));
      await tester.pumpAndSettle();

      expect(archiveIo.savedName, endsWith('.json'));
      final written = jsonDecode(archiveIo.savedContents!) as Map;
      expect(written['kind'], ProgressArchive.kind);
      expect(written['progress'], hasLength(3));
      expect(written['history'], hasLength(2));
      expect(written['beliefs'], hasLength(2));
      expect(archiveIo.savedContents, isNot(contains(_uid)));
      expect(find.textContaining('Progress saved to'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('cancelling the save dialog reports nothing', (tester) async {
      await mount(tester);
      archiveIo.cancelSave = true;

      await tester.tap(find.text('Export progress…'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Progress saved to'), findsNothing);

      await unmount(tester);
    });

    testWidgets('import asks first, then replaces the account state', (
      tester,
    ) async {
      await mount(tester);

      // Take a file from this account, then wipe it so the import has
      // something to restore.
      await tester.tap(find.text('Export progress…'));
      await tester.pumpAndSettle();
      final file = archiveIo.savedContents!;

      await tester.tap(find.text('Reset all progress'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset everything'));
      await tester.pumpAndSettle();
      expect(progress.docs, isEmpty);
      await clearSnacks(tester);

      archiveIo.toOpen = (name: 'sam-progress.json', contents: file);
      await tester.tap(find.text('Import progress…'));
      await tester.pumpAndSettle();

      // Cancelling leaves the wiped state alone.
      expect(find.text('Replace your progress?'), findsOneWidget);
      expect(
        find.textContaining('sam-progress.json'),
        findsOneWidget,
        reason: 'the dialog should name the file being imported',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(progress.docs, isEmpty);

      await tester.tap(find.text('Import progress…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import and replace'));
      await tester.pumpAndSettle();

      expect(progress.docs, hasLength(3));
      expect(progress['${_uid}_s1']!['progress'], 1.0);
      expect(history.docs, hasLength(2));
      expect(beliefs.docs, hasLength(2));
      expect(accounts[_uid]!['calibration']['difficulty'], 'hard');
      expect(
        find.text('Imported 3 goals, 2 history entries and 2 skill estimates.'),
        findsOneWidget,
      );

      await unmount(tester);
    });

    testWidgets('a file that is not a progress archive is refused, not '
        'half-applied', (tester) async {
      await mount(tester);
      archiveIo.toOpen = (name: 'holiday.json', contents: '{"photos": 12}');

      await tester.tap(find.text('Import progress…'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Import and replace'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Import failed'), findsOneWidget);
      expect(progress.docs, hasLength(3), reason: 'nothing should have moved');
      expect(beliefs.docs, hasLength(2));

      await unmount(tester);
    });
  });

  testWidgets('about card shows the app version', (tester) async {
    await mount(tester);
    expect(find.text('Version $kAppVersion'), findsOneWidget);
    await unmount(tester);
  });

  // #48 — before this the About card was a version string and nothing else:
  // there was no way to ask for an update, and a check that failed left no
  // trace anywhere in the UI.
  group('about — update', () {
    UpdateServices services({
      UpdateInfo? latest,
      Object? feedError,
      List<File>? ran,
    }) => UpdateServices(
      localVersion: '1.0.0',
      autoCheck: false,
      feed: () async {
        if (feedError != null) throw feedError;
        return latest;
      },
      download: (_, _) async => File('not-a-real-installer.exe'),
      verify: (_, _) async => true,
      run: (file) async => ran?.add(file),
      log: (_) {},
    );

    String statusText(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('about-update-status')))
        .data!;

    testWidgets('starts idle and offers only a check', (tester) async {
      await mount(tester, update: services());

      expect(statusText(tester), 'No update check has run yet.');
      expect(find.byKey(const ValueKey('about-update-check')), findsOneWidget);
      expect(find.byKey(const ValueKey('about-update-apply')), findsNothing);

      await unmount(tester);
    });

    // The manual check has to work on a build that never checks by itself —
    // `autoCheck` is `kReleaseMode` (#47), so on a debug build this button is
    // the only way the feature runs at all.
    testWidgets('the check button finds a release and offers to apply it', (
      tester,
    ) async {
      final ran = <File>[];
      await mount(
        tester,
        update: services(
          latest: UpdateInfo(
            '2.0.0',
            Uri.parse('https://example.com/setup.exe'),
            'abc',
          ),
          ran: ran,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('about-update-check')));
      await tester.pumpAndSettle();

      expect(statusText(tester), 'Version 2.0.0 is available.');
      expect(find.text('Update to 2.0.0'), findsOneWidget);
      expect(ran, isEmpty, reason: 'the check installed something by itself');

      await unmount(tester);
    });

    testWidgets('the check button reports a failure it would otherwise '
        'have swallowed', (tester) async {
      await mount(
        tester,
        update: services(
          feedError: UpdateCheckException('release lookup returned HTTP 500'),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('about-update-check')));
      await tester.pumpAndSettle();

      expect(statusText(tester), contains('HTTP 500'));
      expect(find.byKey(const ValueKey('about-update-apply')), findsNothing);

      await unmount(tester);
    });

    testWidgets('an up-to-date build says so', (tester) async {
      await mount(tester, update: services(latest: null));

      await tester.tap(find.byKey(const ValueKey('about-update-check')));
      await tester.pumpAndSettle();

      expect(statusText(tester), 'You have the newest version.');

      await unmount(tester);
    });
  });
}
