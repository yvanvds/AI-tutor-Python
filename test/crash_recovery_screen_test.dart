// #331 — every error in the app showed the crash screen with "This can
// happen after permission or rules changes" and one button, "Reset app (fix
// permissions)", which signs out and closes the app. That is no help for an
// error in the app itself, like the dropdown crash of #330, and it left no
// way back to the work. Each error also pushed one more screen. Now an
// error in the app says so, shows its text and leads back to the app; a
// permission error keeps the reset; and one crash screen is up at a time.

import 'package:ai_tutor_python/crash_recovery_screen.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _error = 'Null check operator used on a null value';

void main() {
  /// The app in Dutch on a page standing in for an exercise; returns its
  /// navigator, the one the global error handler pushes on.
  Future<NavigatorState> mountApp(WidgetTester tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('nl'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('Oefening')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return navigator.currentState!;
  }

  testWidgets('an error in the app shows its text and leads back to the '
      'app, without the reset', (tester) async {
    final navigator = await mountApp(tester);

    pushCrashScreen(navigator, const CrashRecoveryScreen(message: _error));
    await tester.pumpAndSettle();
    expect(find.text('Er ging iets mis'), findsOneWidget);
    expect(
      find.textContaining('De app liep tegen een fout aan.'),
      findsOneWidget,
    );
    expect(find.text(_error), findsOneWidget);
    expect(find.text('App resetten (rechten herstellen)'), findsNothing);
    expect(find.textContaining('rechten'), findsNothing);

    await tester.tap(find.text('Terug naar de app'));
    await tester.pumpAndSettle();
    expect(find.byType(CrashRecoveryScreen), findsNothing);
    expect(find.text('Oefening'), findsOneWidget);
  });

  testWidgets('a permission error still offers the reset', (tester) async {
    final navigator = await mountApp(tester);

    pushCrashScreen(navigator, const CrashRecoveryScreen.permissionDenied());
    await tester.pumpAndSettle();
    expect(
      find.text('Geen toegang bij het lezen van gegevens.'),
      findsOneWidget,
    );
    expect(find.text('App resetten (rechten herstellen)'), findsOneWidget);
    expect(find.text('Terug naar de app'), findsNothing);
  });

  testWidgets('one crash screen at a time: a repeating error does not '
      'stack them', (tester) async {
    final navigator = await mountApp(tester);

    pushCrashScreen(navigator, const CrashRecoveryScreen(message: _error));
    pushCrashScreen(navigator, const CrashRecoveryScreen(message: _error));
    await tester.pumpAndSettle();
    pushCrashScreen(navigator, const CrashRecoveryScreen.permissionDenied());
    await tester.pumpAndSettle();
    expect(find.byType(CrashRecoveryScreen), findsOneWidget);

    // One "back" is enough to be back in the app.
    await tester.tap(find.text('Terug naar de app'));
    await tester.pumpAndSettle();
    expect(find.byType(CrashRecoveryScreen), findsNothing);
    expect(find.text('Oefening'), findsOneWidget);

    // A next error shows the screen again.
    pushCrashScreen(navigator, const CrashRecoveryScreen(message: _error));
    await tester.pumpAndSettle();
    expect(find.byType(CrashRecoveryScreen), findsOneWidget);
  });
}
