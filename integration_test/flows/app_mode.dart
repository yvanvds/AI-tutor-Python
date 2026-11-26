// End-to-end (#262, #264): the mode decides what the app starts on.
//
// One build, two modes. With a school configuration the app starts as it
// always has — signed in, on the shell. Without one it is stand-alone: a
// welcome screen asks for a name and makes a local profile, the key screen
// asks for the user's own OpenAI key, and then the shell opens — all on the
// app's own local storage (`LocalCosmosClient`) over a temp folder, with the
// real `AuthService`. A second start goes straight to the shell.
//
// The content the app ships with (#266) is loaded at start. The first test
// runs on this build's own assets, the bundle exported from the live content
// (#265): the student finds its first goal on the learning path, and the
// second start loads nothing again. The second test loads the small fixture
// bundle (test/fixtures/curriculum_bundle) instead.
//
// What needs a school is left out of the stand-alone app (#267): no grade
// formula, no reports, no teacher group in the rail; no lesson badges, class
// podium or teacher's badges in the trophy case; no word about a teacher or
// the school year in Options. The school mode keeps all of it — the last test
// holds that.
//
// Which mode the app starts in is decided at start (#307): a stored school
// file, an earlier "without a school", or the build's own school — else the
// first-start choice asks, with no silent default. The choice leads to the
// school's sign-in or to the stand-alone welcome; a refused file says why and
// changes nothing; a build with a school starts as it always did. Switching
// mode later (Options, the key screen) takes a restart, and the next start
// follows the file.
//
// The transitional release (#308, step 1) keeps the build's school as the
// school file at start: a signed-in student gets the file and stays signed
// in, the next start writes nothing, and nothing is written after leaving
// the school or without a school.
//
// The release after it (#308, step 3; #336) has no school data. The school
// file of step 1 says nothing about the access, and still reaches the
// database: with a token from the stored sign-in, on every request. The
// student stays signed in, and the file stays as step 1 wrote it. A pc that
// skipped step 1 has no file: the first-start choice asks and says that the
// teacher gives the school file, and with that file the stored sign-in still
// holds. The key screen says it too, for whoever went on without a school.
//
// Every other flow runs in school mode (the harness default); this one boots
// the real app in both.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/app_mode.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/curriculum_bundle.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/features/auth/local_key_gate_screen.dart';
import 'package:ai_tutor_python/features/auth/sign_in_page.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/school/first_start_page.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/standalone/standalone_welcome_page.dart';
import 'package:ai_tutor_python/services/auth/cosmos_token_source.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/helpers/memory_school_file_store.dart';
import '../../test/helpers/test_app_mode.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// An unsigned id token with [claims], as Entra's token endpoint returns it.
String _jwt(Map<String, Object?> claims) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

/// Which of [finders] show up anywhere on [page]'s list, scrolled from top
/// to bottom: a `ListView` builds only what is near the screen, so a section
/// that is not there must be looked for all the way down.
Future<Set<String>> _seenOn(
  WidgetTester tester,
  Type page,
  Map<String, Finder> finders,
) async {
  final scrollable = find
      .descendant(of: find.byType(page), matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(0);
  await tester.pump(const Duration(milliseconds: 100));
  final seen = <String>{};
  while (true) {
    for (final e in finders.entries) {
      if (e.value.evaluate().isNotEmpty) seen.add(e.key);
    }
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo(
      (position.pixels + 200).clamp(0.0, position.maxScrollExtent),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  position.jumpTo(0);
  await tester.pump();
  return seen;
}

/// A file of the bundle in this build's assets (#265).
Map<String, dynamic> _assetsJson(String name) =>
    jsonDecode(File('$kCurriculumAssetDir/$name').readAsStringSync())
        as Map<String, dynamic>;

/// The first root goal of the bundle in the assets and its first subgoal,
/// by their English titles where the bundle translates them. Read from the
/// files, so a fresh export needs no change here.
({String goal, String subgoal}) _firstGoalInAssets() {
  List<Map<String, dynamic>> docs(String name) =>
      (_assetsJson(name)['docs'] as List).cast<Map<String, dynamic>>();
  final goals = docs('goals.json');
  final english = {
    for (final t in docs('translations.json'))
      if (t['language'] == 'en' && t['kind'] == 'goal')
        t['refId'] as String: t['title'] as String,
  };
  Map<String, dynamic> first(Iterable<Map<String, dynamic>> gs) =>
      gs.reduce((a, b) => (a['order'] as num) <= (b['order'] as num) ? a : b);
  final root = first(goals.where((g) => g['parentId'] == null));
  final sub = first(goals.where((g) => g['parentId'] == root['id']));
  String title(Map<String, dynamic> g) =>
      english[g['id']] ?? g['title'] as String;
  return (goal: title(root), subgoal: title(sub));
}

/// The school-only parts of the trophy case (#267), and one that stays.
final Map<String, Finder> _trophyParts = {
  'podium': find.byKey(const ValueKey('badges-section-podium')),
  'teacher': find.byKey(const ValueKey('badges-section-teacher')),
  'homeWork': find.byKey(const ValueKey('badge-tile-homeWork')),
  'lessonWeeks': find.byKey(const ValueKey('badge-tile-lessonWeeks')),
  'effort': find.byKey(const ValueKey('badge-tile-effort')),
  'gradeLine': find.textContaining("don't count towards your grade"),
};

/// The parts of Options that name the teacher or the school year (#267).
final Map<String, Finder> _optionsParts = {
  'answersKept': find.byKey(const Key('options-answers-kept')),
  'teacherInBugReport': find.textContaining('to send to your teacher'),
  'bugReportStandalone': find.text(
    'Save a report as a text file, or post it on GitHub straight from the '
    'app — with the debug data of this session attached.',
  ),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without a school: welcome, own key, then the app with the '
      'content it ships with; a second start goes straight to the app', (
    tester,
  ) async {
    final data = Directory.systemTemp.createTempSync('ai_tutor_standalone_');
    addTearDown(() {
      if (data.existsSync()) data.deleteSync(recursive: true);
    });

    // First start: nothing on the pc yet. No `curriculumBundle`: the one in
    // this build's assets, as `main()` loads it.
    var harness = AppHarness(appMode: const StandaloneMode(), localData: data);
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, find.byType(StandaloneWelcomePage));
    expect(find.byType(SignInPage), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('standalone-welcome-first-name')),
      'Alex',
    );
    await tester.tap(find.byKey(const ValueKey('standalone-welcome-start')));

    await pumpUntilFound(tester, find.byType(LocalKeyGateScreen));
    expect(find.textContaining('platform.openai.com/api-keys'), findsOneWidget);
    expect(find.textContaining('not yet approved'), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'sk-own-key');
    await tester.tap(find.text('Save key'));

    await pumpUntilFound(tester, find.byType(AppShell));
    // A while longer: a fresh local database does not knock it over.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Hi Alex,'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsNothing);
    expect(tester.takeException(), isNull);
    // The account landed in the local storage, not anywhere else.
    expect(Directory('${data.path}/accounts').existsSync(), isTrue);

    // The shipped content: the first goal and its first subgoal, in
    // English (the app's locale here) as the bundle translates them.
    final (:goal, :subgoal) = _firstGoalInAssets();
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, find.textContaining(goal));
    await pumpUntilFound(tester, find.textContaining(subgoal));
    expect(tester.takeException(), isNull);
    final loaded = curriculumVersionFile(data);
    expect(jsonDecode(loaded.readAsStringSync()), {
      'contentVersion': _assetsJson('manifest.json')['contentVersion'],
    });
    final loadedAt = loaded.lastModifiedSync();

    // What the first start left in shared preferences: the profile, the key.
    final prefs = await SharedPreferences.getInstance();
    final kept = <String, Object>{
      for (final key in prefs.getKeys()) key: prefs.get(key)!,
    };
    expect(kept.keys, contains('standalone.local_profile_v1'));
    await harness.dispose(tester);

    // Second start, same pc.
    harness = AppHarness(
      appMode: const StandaloneMode(),
      localData: data,
      prefs: kept,
    );
    await harness.boot(tester);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(StandaloneWelcomePage), findsNothing);
    expect(find.byType(LocalKeyGateScreen), findsNothing);
    expect(find.text('Hi Alex,'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The same bundle again: nothing loaded, the content still there.
    expect(loaded.lastModifiedSync(), loadedAt);
    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    await pumpUntilFound(tester, find.textContaining(goal));

    await harness.dispose(tester);
  });

  testWidgets('without a school, with the fixture content: after welcome and '
      'key the student finds its goals', (tester) async {
    final data = Directory.systemTemp.createTempSync('ai_tutor_standalone_');
    addTearDown(() {
      if (data.existsSync()) data.deleteSync(recursive: true);
    });

    final harness = AppHarness(
      appMode: const StandaloneMode(),
      localData: data,
      curriculumBundle: DirectoryCurriculumBundleSource(
        Directory('test/fixtures/curriculum_bundle'),
      ),
    );
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, find.byType(StandaloneWelcomePage));
    await tester.enterText(
      find.byKey(const ValueKey('standalone-welcome-first-name')),
      'Alex',
    );
    await tester.tap(find.byKey(const ValueKey('standalone-welcome-start')));
    await pumpUntilFound(tester, find.byType(LocalKeyGateScreen));
    await tester.enterText(find.byType(TextFormField), 'sk-own-key');
    await tester.tap(find.text('Save key'));
    await pumpUntilFound(tester, find.byType(AppShell));

    await tester.tap(find.byTooltip('Learning path'));
    await pumpUntilFound(tester, find.byType(LeerpadPage));
    // The fixture's root goal and its subgoal (in English, its translation).
    await pumpUntilFound(tester, find.textContaining('Variabelen'));
    await pumpUntilFound(tester, find.textContaining('Assignment'));
    expect(tester.takeException(), isNull);
    // Loaded into the local storage, and remembered as loaded.
    expect(Directory('${data.path}/goals').existsSync(), isTrue);
    expect(curriculumVersionFile(data).existsSync(), isTrue);

    // The rail (#267): what needs a school is not there.
    expect(find.byTooltip('Trophy case'), findsOneWidget);
    expect(find.byTooltip('Grade formula'), findsNothing);
    expect(find.byTooltip('My reports'), findsNothing);
    expect(find.text('TEACHER'), findsNothing);
    // Not even behind the rail's back: a school-only section is left.
    harness.container.read(sectionProvider.notifier).state =
        Section.puntenformule;
    await tester.pump();
    await tester.pump();
    expect(harness.container.read(sectionProvider), Section.session);

    // The trophy case: no lesson badges, podium or teacher's badges.
    await tester.tap(find.byTooltip('Trophy case'));
    await pumpUntilFound(tester, find.byType(PrijzenkastPage));
    await pumpUntilFound(tester, find.byKey(const ValueKey('badges-count')));
    final board = harness.container.read(badgeBoardProvider)!;
    expect(board.standalone, isTrue);
    expect(
      find.text("Badges for what you've done. They give no XP."),
      findsOneWidget,
    );
    expect(await _seenOn(tester, PrijzenkastPage, _trophyParts), {'effort'});
    expect(find.text('0 of ${board.total} badges earned'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Options: nothing kept for a teacher, no teacher in the bug report. The
    // key screen's snack sits over the Options entry until it goes.
    for (var i = 0; i < 60; i++) {
      if (find.byType(SnackBar).evaluate().isEmpty) break;
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    expect(await _seenOn(tester, OptionsPage, _optionsParts), {
      'bugReportStandalone',
    });
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });

  testWidgets('with a school the app starts in school mode, on the shell', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(StandaloneWelcomePage), findsNothing);
    expect(find.byTooltip('Sign out'), findsOneWidget);

    // Everything for a school is still there (#267): students notice nothing.
    expect(find.byTooltip('Grade formula'), findsOneWidget);
    expect(find.byTooltip('My reports'), findsOneWidget);
    await tester.tap(find.byTooltip('Trophy case'));
    await pumpUntilFound(tester, find.byType(PrijzenkastPage));
    await pumpUntilFound(tester, find.byKey(const ValueKey('badges-count')));
    expect(await _seenOn(tester, PrijzenkastPage, _trophyParts), {
      'podium',
      'teacher',
      'homeWork',
      'lessonWeeks',
      'effort',
      'gradeLine',
    });
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    expect(await _seenOn(tester, OptionsPage, _optionsParts), {
      'answersKept',
      'teacherInBugReport',
    });
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });
  // #307 ------------------------------------------------------------------

  Directory tempDir(String prefix) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return dir;
  }

  final exampleSchool = parseSchoolFile(exampleSchoolFile());

  testWidgets('first start, with a school file: the choice, then the '
      "school's sign-in; the next start goes there straight", (tester) async {
    final appData = tempDir('ai_tutor_appdata_');

    var harness = AppHarness(
      decideMode: true,
      schoolData: appData,
      schoolFilePicker: () async => exampleSchoolFile(),
    );
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, find.byType(FirstStartPage));
    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(StandaloneWelcomePage), findsNothing);
    await tester.tap(find.byKey(const ValueKey('first-start-school')));

    await pumpUntilFound(tester, find.byType(SignInPage));
    expect(find.byType(FirstStartPage), findsNothing);
    expect(harness.startedMode, SchoolMode(exampleSchool));
    expect(File('${appData.path}/school.json').existsSync(), isTrue);
    expect(tester.takeException(), isNull);
    await harness.dispose(tester);

    // Second start, same pc: the stored file decides, no choice.
    harness = AppHarness(decideMode: true, schoolData: appData);
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(SignInPage));
    expect(find.byType(FirstStartPage), findsNothing);
    expect(harness.startedMode, SchoolMode(exampleSchool));

    await harness.dispose(tester);
  });

  testWidgets('first start, without a school: the welcome; the key screen '
      'imports a school file for the next start', (tester) async {
    final appData = tempDir('ai_tutor_appdata_');
    final data = tempDir('ai_tutor_standalone_');

    var harness = AppHarness(
      decideMode: true,
      schoolData: appData,
      localData: data,
      schoolFilePicker: () async => exampleSchoolFile(),
    );
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, find.byType(FirstStartPage));
    await tester.tap(find.byKey(const ValueKey('first-start-without-school')));
    await pumpUntilFound(tester, find.byType(StandaloneWelcomePage));
    expect(find.byType(SignInPage), findsNothing);
    expect(harness.startedMode, const StandaloneMode());

    await tester.enterText(
      find.byKey(const ValueKey('standalone-welcome-first-name')),
      'Alex',
    );
    await tester.tap(find.byKey(const ValueKey('standalone-welcome-start')));
    await pumpUntilFound(tester, find.byType(LocalKeyGateScreen));

    // The way to a school, on the key screen: it says where the school file
    // comes from (#308), then stored, then a restart.
    expect(
      find.descendant(
        of: find.byKey(const Key('local-key-school-file')),
        matching: find.text(
          'At a school? Import the school file your teacher gives you.',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('local-key-school-file')));
    await pumpUntilFound(tester, find.byKey(const Key('school-file-restart')));
    expect(
      find.textContaining('The school file of Example School is saved.'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await pumpUntilGone(tester, find.byKey(const Key('school-file-restart')));
    expect(tester.takeException(), isNull);

    final prefs = await SharedPreferences.getInstance();
    final kept = <String, Object>{
      for (final key in prefs.getKeys()) key: prefs.get(key)!,
    };
    expect(kept.keys, contains('standalone.local_profile_v1'));
    await harness.dispose(tester);

    // Next start: the school, from the file. The stand-alone data stays.
    harness = AppHarness(
      decideMode: true,
      schoolData: appData,
      localData: data,
      prefs: kept,
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(SignInPage));
    expect(harness.startedMode, SchoolMode(exampleSchool));
    expect(Directory('${data.path}/accounts').existsSync(), isTrue);

    await harness.dispose(tester);
  });

  testWidgets('"without a school" once is remembered: the next start goes '
      'to the welcome', (tester) async {
    final harness = AppHarness(
      decideMode: true,
      localData: tempDir('ai_tutor_standalone_'),
      prefs: const {'standalone.start_without_school_v1': true},
    );
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, find.byType(StandaloneWelcomePage));
    expect(find.byType(FirstStartPage), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('a refused school file says why and changes nothing', (
    tester,
  ) async {
    final appData = tempDir('ai_tutor_appdata_');
    var file = exampleSchoolFile(formatVersion: 2);
    final harness = AppHarness(
      decideMode: true,
      schoolData: appData,
      schoolFilePicker: () async => file,
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(FirstStartPage));

    await tester.tap(find.byKey(const ValueKey('first-start-school')));
    await pumpUntilFound(
      tester,
      find.byKey(const ValueKey('first-start-error')),
    );
    expect(
      find.text(
        'This school file is for a newer version of the app. Update the app '
        'and try again. Nothing has changed.',
      ),
      findsOneWidget,
    );
    expect(find.byType(FirstStartPage), findsOneWidget);
    expect(harness.startedMode, isNull);
    expect(File('${appData.path}/school.json').existsSync(), isFalse);

    file = '{"formatVersion": 1}';
    await tester.tap(find.byKey(const ValueKey('first-start-school')));
    await pumpUntilFound(
      tester,
      find.textContaining('incomplete or invalid (schoolName)'),
    );
    expect(File('${appData.path}/school.json').existsSync(), isFalse);
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });

  testWidgets('a build with a school starts in it as before: no choice', (
    tester,
  ) async {
    final harness = AppHarness(decideMode: true, buildSchool: kTestSchool);
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, find.byType(SignInPage));
    expect(find.byType(FirstStartPage), findsNothing);
    // The build's school, kept as the school file (#308) under its name.
    expect(
      harness.startedMode,
      SchoolMode(kTestSchool.named(kBuildSchoolName)),
    );

    await harness.dispose(tester);
  });

  // #308, step 1 ----------------------------------------------------------

  testWidgets("the transitional release: a signed-in student on the build's "
      'school gets the school file and stays signed in; the next start '
      'writes nothing', (tester) async {
    final appData = tempDir('ai_tutor_appdata_');
    final school = File('${appData.path}/school.json');
    // As the app's own build school: named, so the file is the same school.
    final build = kTestSchool.named(kBuildSchoolName);
    final refreshes = <http.Request>[];
    final entra = MockClient((request) async {
      refreshes.add(request);
      return http.Response(
        jsonEncode({
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'id_token': _jwt({
            'oid': studentIdentity.oid,
            'name': studentIdentity.displayName,
            'email': studentIdentity.email,
          }),
          'expires_in': 3600,
        }),
        200,
      );
    });
    // An install from before #307: signed in, no school file.
    var prefs = <String, Object>{
      'azure_auth_tokens_v1': jsonEncode({
        'access_token': 'old-access',
        'refresh_token': 'stored-refresh',
        'id_token': null,
        'access_token_expiry': null,
      }),
    };
    expect(school.existsSync(), isFalse);

    DateTime? writtenAt;
    for (final start in ['after the update', 'the next start']) {
      final harness = AppHarness(
        decideMode: true,
        buildSchool: build,
        schoolData: appData,
        prefs: prefs,
        entra: entra,
      );
      await harness.boot(tester, waitForShell: false);
      await pumpUntilFound(tester, find.byType(AppShell));
      expect(find.byType(SignInPage), findsNothing, reason: start);
      expect(find.byType(FirstStartPage), findsNothing, reason: start);
      expect(find.byTooltip('Sign out'), findsOneWidget, reason: start);
      expect(harness.startedMode, SchoolMode(build), reason: start);
      expect(tester.takeException(), isNull, reason: start);
      // The file, as if the student had imported it: the build's school.
      expect(school.existsSync(), isTrue, reason: start);
      expect(parseSchoolFile(school.readAsStringSync()), build);
      // The next start leaves the file from the update as it is.
      writtenAt ??= school.lastModifiedSync();
      expect(school.lastModifiedSync(), writtenAt, reason: start);
      // Signed in with the school the file names.
      expect(refreshes.last.url.path, contains(build.tenantId));
      expect(refreshes.last.bodyFields['client_id'], build.clientId);

      final kept = await SharedPreferences.getInstance();
      prefs = {for (final key in kept.getKeys()) key: kept.get(key)!};
      await harness.dispose(tester);
    }
    expect(refreshes, hasLength(2));
    expect(File('${school.path}.tmp').existsSync(), isFalse);
  });

  testWidgets('the transitional release writes nothing after leaving the '
      'school, nor without a school', (tester) async {
    final appData = tempDir('ai_tutor_appdata_');
    final school = File('${appData.path}/school.json');
    final build = kTestSchool.named(kBuildSchoolName);

    var harness = AppHarness(
      decideMode: true,
      buildSchool: build,
      schoolData: appData,
      prefs: const {'school_left_v1': true},
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(FirstStartPage));
    expect(school.existsSync(), isFalse);
    await harness.dispose(tester);

    harness = AppHarness(
      decideMode: true,
      buildSchool: build,
      schoolData: appData,
      localData: tempDir('ai_tutor_standalone_'),
      prefs: const {'standalone.start_without_school_v1': true},
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(StandaloneWelcomePage));
    expect(harness.startedMode, const StandaloneMode());
    expect(school.existsSync(), isFalse);
    await harness.dispose(tester);
  });

  // #336 ------------------------------------------------------------------

  testWidgets('a build without school data: the school file of step 1 '
      'reaches the database with the sign-in; the student stays signed in, '
      'with no sign-in screen and no choice', (tester) async {
    final appData = tempDir('ai_tutor_appdata_');
    final school = File('${appData.path}/school.json');
    final build = kTestSchool.named(kBuildSchoolName);
    final databaseScope =
        '${CosmosTokenSource.scopeFor(build.databaseEndpoint)} '
        'offline_access';
    const databaseToken = 'database-token';
    bool forDatabase(http.Request r) => r.bodyFields['scope'] == databaseScope;
    final tokenRequests = <http.Request>[];
    final entra = MockClient((request) async {
      tokenRequests.add(request);
      final database = forDatabase(request);
      return http.Response(
        jsonEncode({
          'access_token': database ? databaseToken : 'sign-in-access',
          'refresh_token': 'stored-refresh',
          if (!database)
            'id_token': _jwt({
              'oid': studentIdentity.oid,
              'name': studentIdentity.displayName,
              'email': studentIdentity.email,
            }),
          'expires_in': database ? 4800 : 3600,
        }),
        200,
      );
    });
    // Signed in, as every install of the school is.
    var prefs = <String, Object>{
      'azure_auth_tokens_v1': jsonEncode({
        'access_token': 'old-access',
        'refresh_token': 'stored-refresh',
        'id_token': null,
        'access_token_expiry': null,
      }),
    };

    // The transitional release (#308, step 1), a build with school data:
    // it writes the school file, and reaches the database as it always has.
    var harness = AppHarness(
      decideMode: true,
      buildSchool: build,
      schoolData: appData,
      prefs: prefs,
      entra: entra,
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(AppShell));
    expect(tokenRequests.where(forDatabase), isEmpty);
    expect(harness.cosmos.authorizations, isNotEmpty);
    expect(
      harness.cosmos.authorizations,
      everyElement(startsWith(Uri.encodeComponent('type=master&ver=1.0&'))),
    );
    final written = school.readAsStringSync();
    final writtenAt = school.lastModifiedSync();
    expect(jsonDecode(written), isNot(contains('databaseAccess')));
    final kept = await SharedPreferences.getInstance();
    prefs = {for (final key in kept.getKeys()) key: kept.get(key)!};
    await harness.dispose(tester);

    // The release after it (#308, step 3), a build without school data,
    // on the same pc.
    harness = AppHarness(
      decideMode: true,
      schoolData: appData,
      prefs: prefs,
      entra: entra,
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(AppShell));
    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(FirstStartPage), findsNothing);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(find.text('Hi ${studentIdentity.firstName},'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The school from the file, as the file says it.
    expect(harness.startedMode, SchoolMode(build));

    // One token for the database, silently, with the stored refresh token,
    // from the school's own tenant and app registration.
    final database = tokenRequests.where(forDatabase).toList();
    expect(database, hasLength(1));
    expect(database.single.url.path, contains(build.tenantId));
    expect(database.single.bodyFields['grant_type'], 'refresh_token');
    expect(database.single.bodyFields['refresh_token'], 'stored-refresh');
    expect(database.single.bodyFields['client_id'], build.clientId);
    // Every database request carries it; none the database key.
    expect(harness.cosmos.authorizations, isNotEmpty);
    expect(harness.cosmos.authorizations.toSet(), {
      Uri.encodeComponent('type=aad&ver=1.0&sig=$databaseToken'),
    });
    // The file is left as step 1 wrote it.
    expect(school.readAsStringSync(), written);
    expect(school.lastModifiedSync(), writtenAt);

    await harness.dispose(tester);
  });

  // #308, step 3 ----------------------------------------------------------

  testWidgets('the release without school data on a pc that skipped the '
      'transitional release: the choice says the teacher gives the school '
      'file; with it the student is signed in as before', (tester) async {
    final appData = tempDir('ai_tutor_appdata_');
    final school = File('${appData.path}/school.json');
    final databaseScope =
        '${CosmosTokenSource.scopeFor(exampleSchool.databaseEndpoint)} '
        'offline_access';
    bool forDatabase(http.Request r) => r.bodyFields['scope'] == databaseScope;
    final tokenRequests = <http.Request>[];
    final entra = MockClient((request) async {
      tokenRequests.add(request);
      final database = forDatabase(request);
      return http.Response(
        jsonEncode({
          'access_token': database ? 'database-token' : 'sign-in-access',
          'refresh_token': 'stored-refresh',
          if (!database)
            'id_token': _jwt({
              'oid': studentIdentity.oid,
              'name': studentIdentity.displayName,
              'email': studentIdentity.email,
            }),
          'expires_in': 3600,
        }),
        200,
      );
    });
    // Signed in, as every install of the school is, but without the school
    // file step 1 would have written: a build without school data cannot
    // tell which school this is.
    final harness = AppHarness(
      decideMode: true,
      schoolData: appData,
      schoolFilePicker: () async => exampleSchoolFile(),
      entra: entra,
      prefs: {
        'azure_auth_tokens_v1': jsonEncode({
          'access_token': 'old-access',
          'refresh_token': 'stored-refresh',
          'id_token': null,
          'access_token_expiry': null,
        }),
      },
    );
    await harness.boot(tester, waitForShell: false);

    // The choice, with no school picked for the student, and the line that
    // says where the school file comes from.
    await pumpUntilFound(tester, find.byType(FirstStartPage));
    expect(
      find.text(
        'Using the app at school? Then your teacher gives you a school file.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('first-start-school')), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(AppShell), findsNothing);
    expect(harness.startedMode, isNull);
    expect(school.existsSync(), isFalse);
    expect(tokenRequests, isEmpty);

    // With the file the teacher gave: the stored sign-in still holds, so the
    // student is back in the app without signing in again.
    await tester.tap(find.byKey(const ValueKey('first-start-school')));
    await pumpUntilFound(tester, find.byType(AppShell));
    expect(find.byType(SignInPage), findsNothing);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(harness.startedMode, SchoolMode(exampleSchool));
    expect(school.existsSync(), isTrue);
    expect(tokenRequests.first.bodyFields['refresh_token'], 'stored-refresh');
    expect(tokenRequests.first.url.path, contains(exampleSchool.tenantId));
    // A build without school data: the database with the sign-in.
    expect(harness.cosmos.authorizations, isNotEmpty);
    expect(harness.cosmos.authorizations.toSet(), {
      Uri.encodeComponent('type=aad&ver=1.0&sig=database-token'),
    });
    expect(tester.takeException(), isNull);

    await harness.dispose(tester);
  });

  testWidgets('Options names the school; a student cannot leave it, a '
      'teacher can: a restart, and the next start asks again', (tester) async {
    final appData = tempDir('ai_tutor_appdata_');
    File('${appData.path}/school.json')
        .writeAsStringSync(encodeSchoolFile(exampleSchool));

    // A student: the school's name, no way to leave it.
    var harness = AppHarness(
      appMode: SchoolMode(exampleSchool),
      schoolData: appData,
    );
    await harness.boot(tester);
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.scrollUntilVisible(
      find.byKey(const Key('options-school-import')),
      200,
      scrollable: optionsScrollable(),
    );
    expect(find.text('You work with Example School.'), findsOneWidget);
    expect(find.byKey(const Key('options-school-leave')), findsNothing);
    await harness.dispose(tester);

    // A teacher leaves the school.
    harness = AppHarness(
      identity: teacherIdentity,
      appMode: SchoolMode(exampleSchool),
      schoolData: appData,
    );
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await tester.scrollUntilVisible(
      find.byKey(const Key('options-school-leave')),
      200,
      scrollable: optionsScrollable(),
    );
    // Scrolled into view, not just to its edge: the card sits lower for a
    // teacher, below the school-wide model card.
    await tester.ensureVisible(find.byKey(const Key('options-school-leave')));
    await tester.pump();
    expect(find.text('You work with Example School.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('options-school-leave')));
    await pumpUntilFound(
      tester,
      find.byKey(const Key('options-school-leave-confirm')),
    );
    await tester.tap(find.byKey(const Key('options-school-leave-confirm')));
    await pumpUntilFound(tester, find.byKey(const Key('school-file-restart')));
    expect(File('${appData.path}/school.json').existsSync(), isFalse);
    await tester.tap(find.text('OK'));
    await pumpUntilGone(tester, find.byKey(const Key('school-file-restart')));
    expect(tester.takeException(), isNull);

    final prefs = await SharedPreferences.getInstance();
    final kept = <String, Object>{
      for (final key in prefs.getKeys()) key: prefs.get(key)!,
    };
    await harness.dispose(tester);

    // Even with the school in the build: the choice, no silent default.
    harness = AppHarness(
      decideMode: true,
      buildSchool: kTestSchool,
      schoolData: appData,
      prefs: kept,
    );
    await harness.boot(tester, waitForShell: false);
    await pumpUntilFound(tester, find.byType(FirstStartPage));

    await harness.dispose(tester);
  });
}
