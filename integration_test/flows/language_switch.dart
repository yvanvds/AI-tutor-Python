// End-to-end (#28, exercising #23 / #25): switching the language on the
// Options page re-renders the whole shell — sidebar tooltips, top-bar
// greeting, mode switcher — in place, and switching back restores English.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/language_switch.dart -d windows

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Options -> Nederlands re-renders the shell in Dutch; English '
      'restores it', (tester) async {
    final harness = AppHarness();
    await harness.boot(tester);

    expect(find.text('Hi Sam,'), findsOneWidget);
    expect(find.byTooltip('Learning path'), findsOneWidget);
    expect(find.text('Explain'), findsOneWidget);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.text('Nederlands'));
    await pumpUntilFound(tester, find.text('Opties'));

    expect(find.text('Hoi Sam,'), findsOneWidget);
    expect(find.text('Hi Sam,'), findsNothing);
    expect(find.byTooltip('Leerpad'), findsOneWidget);
    expect(find.byTooltip('Learning path'), findsNothing);
    expect(find.byTooltip('Afmelden'), findsOneWidget);
    expect(find.text('Uitleg'), findsOneWidget);
    expect(find.text('Taal'), findsOneWidget);

    await tester.tap(find.text('English'));
    await pumpUntilFound(tester, find.text('Options'));

    expect(find.text('Hi Sam,'), findsOneWidget);
    expect(find.byTooltip('Learning path'), findsOneWidget);
    expect(find.text('Explain'), findsOneWidget);
    expect(find.text('Opties'), findsNothing);

    await harness.dispose(tester);
  });
}
