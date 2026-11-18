// End-to-end (#262, #264): the mode decides what the app starts on.
//
// One build, two modes. With a school configuration the app starts as it
// always has — signed in, on the shell. Without one it is stand-alone: a
// welcome screen asks for a name and makes a local profile, the key screen
// asks for the user's own OpenAI key, and then the shell opens — all on the
// app's own local storage (`LocalCosmosClient`) over a temp folder, with the
// real `AuthService`. A second start goes straight to the shell.
//
// Content (goals, lessons) is not bundled yet (#266), so the stand-alone app
// is empty; this flow is about getting in, not about what is inside.
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
import 'package:ai_tutor_python/features/auth/local_key_gate_screen.dart';
import 'package:ai_tutor_python/features/auth/sign_in_page.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/features/standalone/standalone_welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness/app_harness.dart';

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

  testWidgets('with a school the app starts in school mode, on the shell', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(StandaloneWelcomePage), findsNothing);
    expect(find.byTooltip('Sign out'), findsOneWidget);

    await harness.dispose(tester);
  });
}
