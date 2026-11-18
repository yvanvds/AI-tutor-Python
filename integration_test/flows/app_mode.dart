// End-to-end (#262): the mode decides what the app starts on.
//
// One build, two modes. With a school configuration the app starts as it
// always has — signed in, on the shell. Without one it is stand-alone, and
// for now shows a placeholder: no sign-in page, no shell, nothing that would
// reach for a school database. #263 and #264 replace the placeholder.
//
// Every other flow runs in school mode (the harness default); this one boots
// the real app in both.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/app_mode.dart -d windows

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/features/auth/sign_in_page.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

final _placeholder = find.byKey(const ValueKey('standalone-placeholder'));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('without a school the app starts stand-alone, on the '
      'placeholder', (tester) async {
    final harness = AppHarness(appMode: const StandaloneMode());
    await harness.boot(tester, waitForShell: false);

    await pumpUntilFound(tester, _placeholder);
    // A while longer: nothing replaces it with a school screen.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(_placeholder, findsOneWidget);
    expect(find.text('The version without a school comes later.'), findsOne);
    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(AppShell), findsNothing);

    await harness.dispose(tester);
  });

  testWidgets('with a school the app starts in school mode, on the shell', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    expect(find.byType(AppShell), findsOneWidget);
    expect(_placeholder, findsNothing);

    await harness.dispose(tester);
  });
}
