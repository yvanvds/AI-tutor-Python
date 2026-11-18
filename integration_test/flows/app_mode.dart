// End-to-end (#262, #264): the mode decides what the app starts on.
//
// One build, two modes. With a school configuration the app starts as it
// always has — signed in, on the shell. Without one it is stand-alone: a
// welcome screen asks for a name and makes a local profile, the key screen
// asks for the user's own OpenAI key, and then the shell opens — all on the
// app's own local storage (`LocalCosmosClient`) over a temp folder, with the
// real `AuthService`. A second start goes straight to the shell.
//
// The content the app ships with (#266) is loaded at start. This build's
// assets hold no bundle yet, so the first test meets an empty app; the
// second loads the fixture bundle (test/fixtures/curriculum_bundle) and the
// student finds its goals on the learning path.
//
// What needs a school is left out of the stand-alone app (#267): no grade
// formula, no reports, no teacher group in the rail; no lesson badges, class
// podium or teacher's badges in the trophy case; no word about a teacher or
// the school year in Options. The school mode keeps all of it — the last test
// holds that.
//
// Every other flow runs in school mode (the harness default); this one boots
// the real app in both.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/app_mode.dart -d windows

import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/curriculum_bundle.dart';
import 'package:ai_tutor_python/features/auth/local_key_gate_screen.dart';
import 'package:ai_tutor_python/features/auth/sign_in_page.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/standalone/standalone_welcome_page.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness/app_harness.dart';

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
    'app — with the debug data of a recent exercise attached.',
  ),
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without a school: welcome, own key, then the app; a second '
      'start goes straight to the app', (tester) async {
    final data = Directory.systemTemp.createTempSync('ai_tutor_standalone_');
    addTearDown(() {
      if (data.existsSync()) data.deleteSync(recursive: true);
    });

    // First start: nothing on the pc yet.
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
    // A while longer: the empty local database does not knock it over.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Hi Alex,'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsNothing);
    expect(tester.takeException(), isNull);
    // The account landed in the local storage, not anywhere else.
    expect(Directory('${data.path}/accounts').existsSync(), isTrue);

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

    await harness.dispose(tester);
  });

  testWidgets('without a school, with the shipped content: after welcome and '
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
}
