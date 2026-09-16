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
// export / import of progress. #125 turned both model cards' fixed lists into
// a text field whose Save unlocks only after a Test — a real chat completion
// on the typed id — has passed; the probe here is scripted. #127 made the
// bug report a file first: the dialog is reachable with no GitHub account at
// all, and `Save as file` writes the same redacted report through the
// archive seam the progress export uses. #130 put a "What's new" button in
// About that brings the post-update release notes back on demand.
//
// The end-to-end half of the panel — the theme switch repainting the whole
// shell, and the progress round trip through a real file — lives in
// `integration_test/flows/options_panel.dart`, which boots the real app.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/whats_new_controller.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
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
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
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

/// The school's OpenAI key as it sits in the config doc. Only the teacher
/// flows touch it, and only to prove the school-wide model write did not
/// take it with it (#118).
const _schoolKey = 'sk-school';

const _identity = AccountIdentity(
  oid: _uid,
  displayName: 'Sam Student',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  isTeacher: false,
);

/// The same person with the teacher role from Entra (#90); the account doc
/// is untouched, so the key situation is whatever the test seeded.
const _teacherIdentity = AccountIdentity(
  oid: _uid,
  displayName: 'Sam Student',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  isTeacher: true,
);

class _SignedInAuth extends AuthService {
  _SignedInAuth(this._who);
  final AccountIdentity _who;

  @override
  AccountIdentity? build() => _who;
}

/// The school-wide config doc over an in-memory container (#118), so the
/// teacher-only write lands somewhere the test can read back — with the first
/// value already in place for the first frame instead of one poll later.
class _SeededGlobalConfig extends GlobalConfigService {
  _SeededGlobalConfig({required super.container, required this.initial});

  final GlobalConfig initial;

  @override
  GlobalConfig? build() {
    super.build();
    return initial;
  }
}

/// The connector behind the Test button (#125), answering from a script
/// instead of OpenAI. [answer] is consulted per probe; [probed] lists every
/// id the page asked about, so a test can prove an invalid id never left the
/// field.
class _FakeProbe extends OpenaiConnector {
  Future<ModelProbe> Function(String model) answer = (model) async =>
      ModelProbeOk(model, const Duration(milliseconds: 1234));
  final List<String> probed = <String>[];

  @override
  Future<ModelProbe> probe(String model) {
    probed.add(model);
    return answer(model);
  }
}

/// What OpenAI says about an id it does not know.
ModelProbeFailed _unknownModel(String model) => ModelProbeFailed(
  StateError('404'),
  StackTrace.current,
  ChatNotice.raw(
    'The model `$model` does not exist or you do not have access to it.',
  ),
);

/// Stands in for the OS file dialogs behind progress export / import (#32)
/// and the bug report's `Save as file` (#127).
class _FakeArchiveIo implements ProgressArchiveIo {
  String? savedName;
  String? savedContents;
  List<String>? savedExtensions;
  bool cancelSave = false;
  Object? saveError;
  ArchiveFile? toOpen;
  Object? openError;

  @override
  Future<String?> save({
    required String suggestedName,
    required String contents,
    List<String> allowedExtensions = const ['json'],
  }) async {
    if (saveError != null) throw saveError!;
    savedName = suggestedName;
    savedContents = contents;
    savedExtensions = allowedExtensions;
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
  late InMemoryCosmos config;
  late DebugSessionRecorder recorder;
  late List<http.Request> githubRequests;
  late _FakeArchiveIo archiveIo;
  late _FakeProbe probe;

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
    config = InMemoryCosmos();

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
    probe = _FakeProbe();
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
    bool isTeacher = false,
    UpdateServices? update,
    ReleaseNotesFetcher? notes,
    String globalModel = 'gpt-4o',
    String oauthClientId = 'Ov23liTESTCLIENTID',
  }) => ProviderScope(
    overrides: [
      // The by-tag lookup behind "What's new" (#130): never the production
      // one, which would reach api.github.com from a test.
      releaseNotesFetcherProvider.overrideWithValue(
        notes ??
            (version) async =>
                throw StateError('no release notes fetcher in this test'),
      ),
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
        () => _SeededGlobalConfig(
          container: config.container,
          initial: GlobalConfig(model: globalModel, apiKey: _schoolKey),
        ),
      ),
      progressArchiveIoProvider.overrideWithValue(archiveIo),
      modelProbeConnectorProvider.overrideWithValue(probe),
      authServiceProvider.overrideWith(
        () => _SignedInAuth(isTeacher ? _teacherIdentity : _identity),
      ),
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
    bool isTeacher = false,
    UpdateServices? update,
    ReleaseNotesFetcher? notes,
    String globalModel = 'gpt-4o',
    String oauthClientId = 'Ov23liTESTCLIENTID',
  }) async {
    // Tall viewport so every card is laid out without scrolling — including
    // the teacher's second model card (#118).
    tester.view.physicalSize = const Size(1400, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    config.upsert({
      'id': 'global',
      'type': 'config',
      'Model': globalModel,
      'ApiKey': _schoolKey,
    });
    await tester.pumpWidget(
      buildApp(
        devTools: devTools,
        isTeacher: isTeacher,
        update: update,
        notes: notes,
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

  // #125 — the model field and its two buttons, in the `device` or `global`
  // card. A teacher sees both cards at once, so everything is keyed by card.
  Finder modelField(String scope) => find.byKey(ValueKey('model-field-$scope'));
  Finder testButton(String scope) => find.byKey(ValueKey('model-test-$scope'));
  Finder saveButton(String scope) => find.byKey(ValueKey('model-save-$scope'));
  Finder modelStatus(String scope) =>
      find.byKey(ValueKey('model-status-$scope'));

  bool enabled(WidgetTester tester, Finder button) =>
      tester.widget<ButtonStyleButton>(button).onPressed != null;

  /// Types [id] into the card's field, runs the Test and waits for it.
  Future<void> typeAndTest(WidgetTester tester, String scope, String id) async {
    await tester.enterText(modelField(scope), id);
    await tester.pump();
    await tester.tap(testButton(scope));
    await tester.pumpAndSettle();
  }

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
      // Reporting no longer waits for the sign-in (#127); posting does.
      expect(find.text('Report a bug…'), findsOneWidget);

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
      // Connected: both ways out are on offer (#127).
      expect(find.widgetWithText(FilledButton, 'Save as file'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Post on GitHub'),
        findsOneWidget,
      );

      // Title is required.
      await tester.tap(find.widgetWithText(FilledButton, 'Post on GitHub'));
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
      await tester.tap(find.widgetWithText(FilledButton, 'Post on GitHub'));
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
      // Posted, not saved.
      expect(archiveIo.savedName, isNull);

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
      // The card itself is still there — the sign-in is unavailable, not
      // the reporting (#127).
      expect(find.text('Bug reports'), findsOneWidget);
      expect(find.text('Report a bug…'), findsOneWidget);
      expect(
        enabled(tester, find.byKey(const ValueKey('bug-report-button'))),
        isTrue,
      );
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

    // #127 — the path with no account at all. The report is the same one
    // the issue would have carried, so the assertions on its contents are
    // the same ones the GitHub test makes, plus the redaction of a path the
    // student typed: the teacher may paste this file into a public issue.
    testWidgets('without a GitHub account the report is saved as a text '
        'file, redacted, and the path is confirmed', (tester) async {
      // A second turn whose input carries the student's Windows profile.
      recorder
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
          userInput: r'open(r"C:\Users\sam.student\Desktop\data.txt")',
          instructions: 'SYSTEM PROMPT — must not be saved',
          instructionsDocId: 'submitCode',
        )
        ..endTurn();
      await mount(tester);
      expect(find.text('Not connected to GitHub.'), findsOneWidget);
      expect(
        enabled(tester, find.byKey(const ValueKey('bug-report-button'))),
        isTrue,
      );

      await tester.tap(find.text('Report a bug…'));
      await tester.pumpAndSettle();
      expect(find.text('Report a bug'), findsOneWidget);
      // Not connected: no posting, but the file is right there.
      expect(find.widgetWithText(FilledButton, 'Save as file'), findsOneWidget);
      expect(find.text('Post on GitHub'), findsNothing);
      // The newest turn — the one with the path — is preselected.
      expect(find.text('#2 submitCode'), findsOneWidget);

      // Title is required here too.
      await tester.tap(find.widgetWithText(FilledButton, 'Save as file'));
      await tester.pumpAndSettle();
      expect(find.text('Please enter a title.'), findsOneWidget);
      expect(archiveIo.savedName, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Tutor crashed',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'What went wrong?'),
        'It stopped after my answer.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save as file'));
      await tester.pumpAndSettle();

      // A `.txt` named for the day and the title, offered as such.
      expect(
        archiveIo.savedName,
        matches(
          RegExp(r'^ai-tutor-bugreport-\d{4}-\d{2}-\d{2}-tutor-crashed\.txt$'),
        ),
      );
      expect(archiveIo.savedExtensions, ['txt']);

      final text = archiveIo.savedContents!;
      // A heading that says what the file is on its own…
      expect(text, startsWith('# Tutor crashed\n'));
      expect(
        text,
        contains(
          RegExp(
            r'^Reported: \d{4}-\d{2}-\d{2} \d{2}:\d{2}  ·  App version '
            '${RegExp.escape(kAppVersion)}\$',
            multiLine: true,
          ),
        ),
      );
      // …over the very body a GitHub issue gets.
      expect(text, contains('It stopped after my answer.'));
      expect(text, contains('App version: `$kAppVersion`'));
      expect(text, contains('Python runner state'));
      expect(text, contains('Turn debug payload'));
      expect(text, contains('"turnId": 2'));
      expect(text, isNot(contains('SYSTEM PROMPT')));
      // The student's name is not in it; the path otherwise is.
      expect(text, isNot(contains('sam.student')));
      expect(text, contains(r'C:\\Users\\<user>\\Desktop\\data.txt'));

      expect(
        find.text(
          'Report saved as C:\\Users\\sam\\${archiveIo.savedName}. '
          'Send this file to your teacher.',
        ),
        findsOneWidget,
      );
      // Nothing went to GitHub, and the button is back.
      expect(githubRequests, isEmpty);
      expect(
        enabled(tester, find.byKey(const ValueKey('bug-report-button'))),
        isTrue,
      );

      await unmount(tester);
    });

    // A fork with no OAuth app cannot sign in — which used to mean it could
    // not report. The file needs neither.
    testWidgets('a build with no OAuth client id still saves a report', (
      tester,
    ) async {
      await mount(tester, oauthClientId: '');
      expect(
        find.byKey(const ValueKey('github-not-configured')),
        findsOneWidget,
      );

      await tester.tap(find.text('Report a bug…'));
      await tester.pumpAndSettle();
      expect(find.text('Post on GitHub'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Nothing happens',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save as file'));
      await tester.pumpAndSettle();

      expect(archiveIo.savedName, endsWith('-nothing-happens.txt'));
      expect(archiveIo.savedContents, startsWith('# Nothing happens\n'));
      expect(find.textContaining('Report saved as'), findsOneWidget);
      expect(githubRequests, isEmpty);

      await unmount(tester);
    });

    testWidgets('cancelling the save dialog reports nothing', (tester) async {
      archiveIo.cancelSave = true;
      await mount(tester);

      await tester.tap(find.text('Report a bug…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Tutor crashed',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save as file'));
      await tester.pumpAndSettle();

      // The dialog was reached (the report was built), and then nothing.
      expect(archiveIo.savedName, endsWith('.txt'));
      expect(find.byType(SnackBar), findsNothing);
      expect(
        enabled(tester, find.byKey(const ValueKey('bug-report-button'))),
        isTrue,
      );

      await unmount(tester);
    });

    testWidgets('a save that fails says why', (tester) async {
      archiveIo.saveError = const FileSystemException(
        'Cannot write',
        r'D:\report.txt',
      );
      await mount(tester);

      await tester.tap(find.text('Report a bug…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Tutor crashed',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save as file'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Saving failed: '), findsOneWidget);
      expect(find.textContaining('Cannot write'), findsOneWidget);
      expect(
        enabled(tester, find.byKey(const ValueKey('bug-report-button'))),
        isTrue,
      );

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
    const followDefault = 'School default (gpt-4o)';
    const override = 'Another model on this device';

    testWidgets('own-key accounts see the card, on the school default, with '
        'no field open', (tester) async {
      await mount(tester, globalModel: 'gpt-4.1');

      expect(find.text('AI model'), findsOneWidget);
      expect(find.text('School default (gpt-4.1)'), findsOneWidget);
      expect(find.text(override), findsOneWidget);
      expect(modelField('device'), findsNothing);
      // The school-wide card is a teacher's; an own-key student has one card.
      expect(modelField('global'), findsNothing);

      await unmount(tester);
    });

    testWidgets('naming a model for this device: Test, then Save, stores the '
        'override; the school default clears it', (tester) async {
      await mount(tester);
      final container = containerOf(tester);
      expect(container.read(modelPreferenceProvider), isNull);

      await tester.tap(find.text(override));
      await tester.pumpAndSettle();
      expect(modelField('device'), findsOneWidget);
      expect(
        tester.widget<TextField>(modelField('device')).controller!.text,
        isEmpty,
      );
      // Nothing typed: nothing to test, nothing to save.
      expect(enabled(tester, testButton('device')), isFalse);
      expect(enabled(tester, saveButton('device')), isFalse);

      await tester.enterText(modelField('device'), 'gpt-5-mini');
      await tester.pump();
      expect(enabled(tester, testButton('device')), isTrue);
      expect(
        enabled(tester, saveButton('device')),
        isFalse,
        reason: 'Save unlocked before the id was tested',
      );
      expect(container.read(modelPreferenceProvider), isNull);

      await tester.tap(testButton('device'));
      await tester.pumpAndSettle();
      expect(probe.probed, ['gpt-5-mini']);
      expect(find.text('gpt-5-mini answered in 1.2 s.'), findsOneWidget);
      expect(enabled(tester, saveButton('device')), isTrue);
      // Tested is not saved.
      expect(container.read(modelPreferenceProvider), isNull);

      await tester.tap(saveButton('device'));
      await tester.pumpAndSettle();
      expect(container.read(modelPreferenceProvider), 'gpt-5-mini');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_model'), 'gpt-5-mini');
      expect(find.text('This device now uses gpt-5-mini.'), findsOneWidget);
      // The field stays open on the stored id.
      expect(modelField('device'), findsOneWidget);
      expect(
        tester.widget<TextField>(modelField('device')).controller!.text,
        'gpt-5-mini',
      );

      // Back to the school default: the override goes, and so does the field.
      await tester.tap(find.text(followDefault));
      await tester.pumpAndSettle();
      expect(container.read(modelPreferenceProvider), isNull);
      expect(prefs.getString('openai_model'), isNull);
      expect(modelField('device'), findsNothing);

      await unmount(tester);
    });

    testWidgets('a failed test says why, and Save stays locked', (
      tester,
    ) async {
      probe.answer = (model) async => _unknownModel(model);
      await mount(tester);
      final container = containerOf(tester);

      await tester.tap(find.text(override));
      await tester.pumpAndSettle();
      await typeAndTest(tester, 'device', 'gpt-6-ultra');

      expect(probe.probed, ['gpt-6-ultra']);
      expect(
        find.text(
          'Test failed: The model `gpt-6-ultra` does not exist or you do '
          'not have access to it.',
        ),
        findsOneWidget,
      );
      expect(enabled(tester, saveButton('device')), isFalse);
      expect(container.read(modelPreferenceProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_model'), isNull);

      await unmount(tester);
    });

    testWidgets('editing after a passed test puts the field back to untested', (
      tester,
    ) async {
      await mount(tester);

      await tester.tap(find.text(override));
      await tester.pumpAndSettle();
      await typeAndTest(tester, 'device', 'gpt-5-mini');
      expect(enabled(tester, saveButton('device')), isTrue);

      await tester.enterText(modelField('device'), 'gpt-5-min');
      await tester.pump();
      expect(
        enabled(tester, saveButton('device')),
        isFalse,
        reason: 'Save stayed unlocked for an id the test never saw',
      );
      expect(modelStatus('device'), findsNothing);
      expect(probe.probed, hasLength(1), reason: 'an edit is not a test');

      // Typing the tested id back brings its result back, no round trip.
      await tester.enterText(modelField('device'), 'gpt-5-mini');
      await tester.pump();
      expect(enabled(tester, saveButton('device')), isTrue);
      expect(find.text('gpt-5-mini answered in 1.2 s.'), findsOneWidget);
      expect(probe.probed, hasLength(1));

      await unmount(tester);
    });

    testWidgets('an id with a space in it is refused before any call; '
        'surrounding whitespace is trimmed', (tester) async {
      await mount(tester);

      await tester.tap(find.text(override));
      await tester.pumpAndSettle();
      await tester.enterText(modelField('device'), 'gpt 5 mini');
      await tester.pump();

      expect(find.text('Enter one model id, without spaces.'), findsOneWidget);
      expect(enabled(tester, testButton('device')), isFalse);
      expect(enabled(tester, saveButton('device')), isFalse);
      expect(probe.probed, isEmpty);

      await typeAndTest(tester, 'device', '  gpt-5-mini  ');
      expect(probe.probed, ['gpt-5-mini']);
      expect(find.text('Enter one model id, without spaces.'), findsNothing);
      await tester.tap(saveButton('device'));
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(modelPreferenceProvider), 'gpt-5-mini');

      await unmount(tester);
    });

    testWidgets('while a test runs, the field and both buttons wait', (
      tester,
    ) async {
      final pending = Completer<ModelProbe>();
      probe.answer = (_) => pending.future;
      await mount(tester);

      await tester.tap(find.text(override));
      await tester.pumpAndSettle();
      await tester.enterText(modelField('device'), 'gpt-5');
      await tester.pump();
      await tester.tap(testButton('device'));
      await tester.pump();

      expect(find.text('Testing gpt-5…'), findsOneWidget);
      expect(
        find.descendant(
          of: modelStatus('device'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(enabled(tester, testButton('device')), isFalse);
      expect(enabled(tester, saveButton('device')), isFalse);

      pending.complete(
        const ModelProbeOk('gpt-5', Duration(milliseconds: 2900)),
      );
      await tester.pumpAndSettle();
      expect(find.text('gpt-5 answered in 2.9 s.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(enabled(tester, testButton('device')), isTrue);
      expect(enabled(tester, saveButton('device')), isTrue);

      await unmount(tester);
    });

    // The field stays editable while a probe runs — the cursor must not be
    // taken away after every Test — so a result can land for an id that is
    // no longer in the field. It is bound to the id it ran on, not shown.
    testWidgets('an edit while a test runs leaves its result unshown and '
        'Save locked', (tester) async {
      final pending = Completer<ModelProbe>();
      probe.answer = (_) => pending.future;
      await mount(tester);

      await tester.tap(find.text(override));
      await tester.pumpAndSettle();
      await tester.enterText(modelField('device'), 'gpt-5');
      await tester.pump();
      await tester.tap(testButton('device'));
      await tester.pump();

      await tester.enterText(modelField('device'), 'gpt-5-mini');
      await tester.pump();
      pending.complete(
        const ModelProbeOk('gpt-5', Duration(milliseconds: 800)),
      );
      await tester.pumpAndSettle();

      expect(find.text('gpt-5 answered in 0.8 s.'), findsNothing);
      expect(modelStatus('device'), findsNothing);
      expect(enabled(tester, saveButton('device')), isFalse);
      expect(enabled(tester, testButton('device')), isTrue);
      expect(probe.probed, ['gpt-5']);

      await unmount(tester);
    });

    testWidgets('a stored override opens the card on the field, prefilled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'local_api_key': 'sk-old',
        'openai_model': 'gpt-4.1',
      });
      await mount(tester);

      expect(modelField('device'), findsOneWidget);
      expect(
        tester.widget<TextField>(modelField('device')).controller!.text,
        'gpt-4.1',
      );
      // Prefilled is not tested: a Save would be a no-op anyway, and the
      // rule is one rule.
      expect(enabled(tester, saveButton('device')), isFalse);
      expect(enabled(tester, testButton('device')), isTrue);

      await unmount(tester);
    });

    testWidgets('a student on the bundled key cannot change the model', (
      tester,
    ) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester);

      expect(find.text('AI model'), findsNothing);
      expect(modelField('device'), findsNothing);

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

    // #90 — a teacher on the school's key had no way to see or change the
    // model at all: the card was gated on paying for the calls yourself.
    testWidgets('a teacher on the bundled key sees the card, with the school '
        'default as the starting choice, and can name a model', (tester) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester, isTeacher: true, globalModel: 'gpt-4.1');
      final container = containerOf(tester);

      expect(find.text('AI model'), findsOneWidget);
      expect(find.text('School default (gpt-4.1)'), findsOneWidget);
      // Still on the school's key, so the key card stays away.
      expect(find.text('OpenAI API key'), findsNothing);

      await tester.tap(find.text(override));
      await tester.pumpAndSettle();
      await typeAndTest(tester, 'device', 'gpt-4o-mini');
      await tester.tap(saveButton('device'));
      await tester.pumpAndSettle();
      expect(container.read(modelPreferenceProvider), 'gpt-4o-mini');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_model'), 'gpt-4o-mini');
      // The device override is exactly that: the school-wide doc is untouched
      // by it (#118).
      expect(config['global']!['Model'], 'gpt-4.1');

      await tester.tap(find.text('School default (gpt-4.1)'));
      await tester.pumpAndSettle();
      expect(container.read(modelPreferenceProvider), isNull);
      expect(prefs.getString('openai_model'), isNull);

      await unmount(tester);
    });
  });

  // #118 — the model picker #32 shipped was per device, so a teacher changing
  // it moved only the machine in front of them. The school-wide doc now has a
  // writer, and this card is its only caller. #125 put a tested text field
  // in front of the write.
  group('school-wide AI model', () {
    String globalText(WidgetTester tester) =>
        tester.widget<TextField>(modelField('global')).controller!.text;

    testWidgets('a teacher sets the model for everyone after a passing test, '
        'and the school key survives the write', (tester) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester, isTeacher: true, globalModel: 'gpt-4o');
      final container = containerOf(tester);

      expect(find.text('School-wide AI model'), findsOneWidget);
      expect(globalText(tester), 'gpt-4o');
      expect(enabled(tester, saveButton('global')), isFalse);

      await tester.enterText(modelField('global'), 'gpt-4.1');
      await tester.pump();
      expect(
        enabled(tester, saveButton('global')),
        isFalse,
        reason: 'an untested id must never reach every student',
      );
      expect(config['global']!['Model'], 'gpt-4o');

      await tester.tap(testButton('global'));
      await tester.pumpAndSettle();
      expect(probe.probed, ['gpt-4.1']);
      expect(find.text('gpt-4.1 answered in 1.2 s.'), findsOneWidget);
      expect(config['global']!['Model'], 'gpt-4o', reason: 'tested, not saved');

      await tester.tap(saveButton('global'));
      await tester.pumpAndSettle();

      expect(config['global']!['Model'], 'gpt-4.1');
      expect(
        config['global']!['ApiKey'],
        _schoolKey,
        reason: 'the school-wide write blanked the stored API key',
      );
      // Published straight away, so the card and the tutor agree without
      // waiting for the next poll.
      expect(container.read(globalConfigServiceProvider)?.model, 'gpt-4.1');
      expect(find.text('The school now uses gpt-4.1.'), findsOneWidget);
      // And it left this device's own choice alone.
      expect(container.read(modelPreferenceProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_model'), isNull);

      await unmount(tester);
    });

    testWidgets('the new school default is what the per-device card offers to '
        'follow', (tester) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester, isTeacher: true, globalModel: 'gpt-4o');

      expect(find.text('School default (gpt-4o)'), findsOneWidget);

      await typeAndTest(tester, 'global', 'gpt-5-mini');
      await tester.tap(saveButton('global'));
      await tester.pumpAndSettle();

      expect(find.text('School default (gpt-5-mini)'), findsOneWidget);
      expect(find.text('School default (gpt-4o)'), findsNothing);

      await unmount(tester);
    });

    testWidgets('a failing test blocks the write and says why', (tester) async {
      probe.answer = (model) async => _unknownModel(model);
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester, isTeacher: true, globalModel: 'gpt-4o');

      await typeAndTest(tester, 'global', 'gpt-4.1-turbo');

      expect(
        find.text(
          'Test failed: The model `gpt-4.1-turbo` does not exist or you do '
          'not have access to it.',
        ),
        findsOneWidget,
      );
      expect(enabled(tester, saveButton('global')), isFalse);
      expect(config['global']!['Model'], 'gpt-4o');
      expect(find.textContaining('The school now uses'), findsNothing);

      await unmount(tester);
    });

    // A teacher's card is one of several: another teacher's write, or the
    // poll delivering the doc after the first frame, must show up in the
    // field — but not on top of an id this teacher is halfway through typing.
    testWidgets('the field follows the stored value until the teacher types', (
      tester,
    ) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester, isTeacher: true, globalModel: 'gpt-4o');
      final service = containerOf(tester)
          .read(globalConfigServiceProvider.notifier);

      await service.setModel('gpt-4.1');
      await tester.pumpAndSettle();
      expect(globalText(tester), 'gpt-4.1');

      await tester.enterText(modelField('global'), 'gpt-5');
      await tester.pump();
      await service.setModel('gpt-4o-mini');
      await tester.pumpAndSettle();
      expect(globalText(tester), 'gpt-5', reason: 'typed text was overwritten');
      expect(find.text('School default (gpt-4o-mini)'), findsOneWidget);

      await unmount(tester);
    });

    // The write is gated on the Entra role alone. A developer build and an
    // own-key account both see the *per-device* card — neither may move the
    // whole class.
    testWidgets('an own-key account on a developer build does not get the '
        'card', (tester) async {
      await mount(tester, devTools: true);

      expect(find.text('AI model'), findsOneWidget);
      expect(find.text('School-wide AI model'), findsNothing);
      expect(modelField('global'), findsNothing);

      await unmount(tester);
    });

    testWidgets('a student on the bundled key does not get the card', (
      tester,
    ) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester);

      expect(find.text('School-wide AI model'), findsNothing);
      expect(modelField('global'), findsNothing);

      await unmount(tester);
    });

    // The doc a fresh deployment has never had a Model written into: the
    // field starts empty, and the first save fills it in rather than failing
    // on the read.
    testWidgets('an unset school model starts the field empty, and the first '
        'save fills it in', (tester) async {
      accounts = InMemoryCosmos([_account(mayUseGlobalKey: true)]);
      await mount(tester, isTeacher: true, globalModel: '');

      expect(globalText(tester), isEmpty);
      expect(enabled(tester, testButton('global')), isFalse);
      expect(enabled(tester, saveButton('global')), isFalse);

      await typeAndTest(tester, 'global', 'gpt-5');
      await tester.tap(saveButton('global'));
      await tester.pumpAndSettle();

      expect(config['global']!['Model'], 'gpt-5');
      expect(config['global']!['ApiKey'], _schoolKey);

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
      // The seam grew an extension parameter for #127; the export still
      // asks for its own.
      expect(archiveIo.savedExtensions, ['json']);
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

  // #130 — the post-update "What's new" card had no way back once clicked
  // away, and no way in at all on a build the app did not install itself.
  // The button shows the running version's notes: from the stash the
  // updater left (no network), else from the release published under this
  // version's tag. The overlay lives in the shell; here the card's state is
  // read off the controller, and the end-to-end showing is in
  // `integration_test/flows/whats_new_overlay.dart`.
  group("about — what's new", () {
    final button = find.byKey(const ValueKey('about-whats-new'));

    ReleaseNotes? shown(WidgetTester tester) =>
        containerOf(tester).read(whatsNewControllerProvider);

    testWidgets('sits beside Check for updates and shows the kept notes '
        'without a lookup', (tester) async {
      // The stash the updater left for this build, already dismissed once.
      SharedPreferences.setMockInitialValues({
        kWhatsNewVersionPref: kAppVersion,
        kWhatsNewNotesPref: '- Faster quizzes',
        kWhatsNewSeenPref: true,
      });
      final lookups = <String>[];
      await mount(
        tester,
        notes: (version) async {
          lookups.add(version);
          return null;
        },
      );

      expect(button, findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.byKey(const ValueKey('about-update-check')), findsOneWidget);
      expect(shown(tester), isNull);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(shown(tester)?.version, kAppVersion);
      expect(shown(tester)?.notes, '- Faster quizzes');
      expect(lookups, isEmpty, reason: 'kept notes were fetched anyway');
      expect(find.byType(SnackBar), findsNothing);

      await unmount(tester);
    });

    testWidgets('with nothing kept, looks the running version up and '
        'shows what it finds', (tester) async {
      final lookups = <String>[];
      await mount(
        tester,
        notes: (version) async {
          lookups.add(version);
          return 'For students\n\n- Something new';
        },
      );

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(lookups, [kAppVersion]);
      expect(shown(tester)?.version, kAppVersion);
      expect(shown(tester)?.notes, 'For students\n\n- Something new');

      await unmount(tester);
    });

    testWidgets('is disabled while the lookup is in flight, and a failure '
        'is a snack', (tester) async {
      final pending = Completer<String?>();
      await mount(tester, notes: (_) => pending.future);

      expect(enabled(tester, button), isTrue);

      await tester.tap(button);
      await tester.pump();

      expect(enabled(tester, button), isFalse, reason: 'a second lookup');
      expect(find.text('Loading…'), findsOneWidget);
      expect(find.text("What's new"), findsNothing);

      pending.completeError(
        UpdateCheckException('release lookup returned HTTP 500'),
      );
      await tester.pumpAndSettle();

      expect(shown(tester), isNull);
      expect(enabled(tester, button), isTrue);
      expect(find.text("What's new"), findsOneWidget);
      expect(
        find.textContaining('Could not load the release notes'),
        findsOneWidget,
      );
      expect(find.textContaining('HTTP 500'), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('a version with no release says so', (tester) async {
      await mount(tester, notes: (_) async => null);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(shown(tester), isNull);
      expect(
        find.text('No release notes for version $kAppVersion.'),
        findsOneWidget,
      );
      expect(enabled(tester, button), isTrue);

      await unmount(tester);
    });
  });
}
