// End-to-end (#28, exercising #32): the three things the Options panel grew —
// a light theme, a per-device AI model, and export / import of progress.
//
// Why this has to run against the real app rather than the widget test next
// to it:
//
//   - the theme is a *global* palette behind flat `AppColors.x` tokens. What
//     can break is not the Options card but everything else: a widget that
//     kept a colour from the palette that was active when it was first built.
//     Only a real shell — sidebar, top bar, workspace — can show that, and
//     only after a real switch.
//   - progress export / import is a round trip through a file on disk and
//     back into Cosmos, and its effect is visible in the top bar's XP pill,
//     which is derived three providers away from the docs that move.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/options_panel.dart -d windows

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:ai_tutor_python/services/config/model_preference.dart';
import 'package:ai_tutor_python/services/progress/progress_archive.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness/app_harness.dart';
import '../harness/seed.dart';

/// One completed subgoal = 100 XP (`shell_state.dart`), so the pill reads
/// "100 / 1500" while the seeded progress is in place and "0 / 1500" once it
/// has been wiped.
const String _xpWithProgress = '100 / 1500';
const String _xpWiped = '0 / 1500';

/// Brings a card further down the Options list into view. The panel is a real
/// `ListView` in a real window, so anything below the fold is not built yet —
/// and a widget that is built but off-screen would be "tapped" at the wrong
/// place without a sound.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(OptionsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  // Always search downwards from the top: `scrollUntilVisible` only moves one
  // way, and a flow steps between cards in both directions.
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  // It stops as soon as the widget is *built*, which on a real window still
  // leaves it below the fold.
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _tapRow(WidgetTester tester, String label) async {
  await _scrollTo(tester, find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Options: light theme repaints the whole shell', (tester) async {
    // The starting theme is stated, not inherited. With no stored preference
    // the app follows the operating system, so a flow that assumed dark was
    // really asserting that whoever ran it had a dark desktop.
    final harness = AppHarness(systemBrightness: Brightness.dark);
    await harness.boot(tester);

    Brightness themeBrightness() =>
        Theme.of(tester.element(find.byType(OptionsPage))).brightness;

    // The colour a widget actually painted with, not the one the theme says:
    // the page reads `AppColors.ink0` directly.
    Color pageBackground() => tester
        .widget<Container>(
          find
              .descendant(
                of: find.byType(OptionsPage),
                matching: find.byType(Container),
              )
              .first,
        )
        .color!;

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    expect(themeBrightness(), Brightness.dark);
    expect(pageBackground(), AppPalette.dark.ink0);

    await tester.tap(find.text('Light'));
    await pumpUntil(
      tester,
      () => themeBrightness() == Brightness.light,
      reason: 'the app never repainted in the light theme',
    );

    expect(pageBackground(), AppPalette.light.ink0);
    // The sidebar is built from `const` widgets that read `AppColors`; it is
    // the surface that went stale before the palette switch remounted the
    // shell.
    expect(find.byType(Sidebar), findsOneWidget);
    expect(
      tester
          .widget<Container>(
            find
                .descendant(
                  of: find.byType(Sidebar),
                  matching: find.byType(Container),
                )
                .first,
          )
          .color,
      AppPalette.light.ink1,
    );
    // Still the same app, in the same place.
    expect(find.text('Options'), findsWidgets);
    expect(find.byTooltip('Learning path'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme'), 'light');

    await tester.tap(find.text('Dark'));
    await pumpUntil(
      tester,
      () => themeBrightness() == Brightness.dark,
      reason: 'the app never went back to the dark theme',
    );
    expect(pageBackground(), AppPalette.dark.ink0);

    await harness.dispose(tester);
  });

  // The other resolution of "follow the system" — and the one that broke the
  // aggregated CI run, whose Windows runner ships in light mode while the
  // machine this was written on is dark.
  testWidgets('Options: a light desktop starts the app light, until the '
      'student says otherwise', (tester) async {
    final harness = AppHarness(systemBrightness: Brightness.light);
    await harness.boot(tester);

    Brightness themeBrightness() =>
        Theme.of(tester.element(find.byType(OptionsPage))).brightness;

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    // Nothing stored yet: the app takes the desktop's word for it.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_theme'), isNull);
    expect(themeBrightness(), Brightness.light);

    // An explicit choice overrides the system, in the direction the system
    // was not pointing.
    await tester.tap(find.text('Dark'));
    await pumpUntil(
      tester,
      () => themeBrightness() == Brightness.dark,
      reason: 'the explicit Dark choice never overrode the light desktop',
    );
    expect(prefs.getString('app_theme'), 'dark');

    // …and handing it back to the system returns to light.
    await tester.tap(find.text('Follow the system'));
    await pumpUntil(
      tester,
      () => themeBrightness() == Brightness.light,
      reason: 'the app never went back to following the desktop',
    );
    expect(prefs.getString('app_theme'), isNull);

    await harness.dispose(tester);
  });

  testWidgets('Options: the AI model choice is stored for this device', (
    tester,
  ) async {
    final harness = AppHarness();
    await harness.boot(tester);

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    // The seeded config doc names gpt-4o as the school-wide default.
    await _scrollTo(tester, find.text('School default (gpt-4o)'));
    expect(find.text('School default (gpt-4o)'), findsOneWidget);

    await _tapRow(tester, 'gpt-5-mini');
    await pumpUntil(
      tester,
      () => harness.container.read(modelPreferenceProvider) != null,
      reason: 'the model choice never reached the app state',
    );
    expect(harness.container.read(modelPreferenceProvider), 'gpt-5-mini');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('openai_model'), 'gpt-5-mini');

    await harness.dispose(tester);
  });

  testWidgets('Options: progress survives a round trip through a file', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('ai_tutor_archive_');
    final file = File('${dir.path}/progress.json');
    final harness = AppHarness(archiveFile: file);
    await harness.boot(tester);

    // A finished subgoal, written the way the conductor would.
    harness.cosmos['progress'].docs['${kStudentUid}_s1'] = {
      'id': '${kStudentUid}_s1',
      'uid': kStudentUid,
      'goalId': 's1',
      'progress': 1.0,
      'updatedAt': '2026-05-01T10:00:00Z',
      'lastSessionAt': '2026-05-01T10:00:00Z',
    };

    await pumpUntil(
      tester,
      () => find.text(_xpWithProgress).evaluate().isNotEmpty,
      reason: 'the XP pill never picked up the seeded progress',
    );

    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));

    await _tapRow(tester, 'Export progress…');
    await pumpUntil(
      tester,
      file.existsSync,
      reason: 'export never wrote the file',
    );
    final written = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(written['kind'], ProgressArchive.kind);
    expect(written['progress'], hasLength(1));
    expect(file.readAsStringSync(), isNot(contains(kStudentUid)));

    // Wipe it the way a student would, and watch the shell agree.
    await _tapRow(tester, 'Reset all progress');
    await pumpUntilFound(tester, find.text('Reset all progress?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Reset everything'));
    await pumpUntil(
      tester,
      () => find.text(_xpWiped).evaluate().isNotEmpty,
      reason: 'the reset never reached the XP pill',
    );

    await _tapRow(tester, 'Import progress…');
    await pumpUntilFound(tester, find.text('Replace your progress?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Import and replace'));
    await pumpUntil(
      tester,
      () => find.text(_xpWithProgress).evaluate().isNotEmpty,
      reason: 'the imported progress never reached the XP pill',
    );

    expect(harness.cosmos['progress']['${kStudentUid}_s1'], isNotNull);

    await harness.dispose(tester);
    dir.deleteSync(recursive: true);
  });
}
