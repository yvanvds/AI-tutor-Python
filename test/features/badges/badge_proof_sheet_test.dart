// Issue #220 — the proof sheet the teacher reviews the badges on: ten badges
// in ten states, at 32, 64 and 128 pixels, on the dark and the light
// palette whatever theme the app is in; the whole set; the notice; and an
// example trophy case.

import 'package:ai_tutor_python/features/badges/badge_proof_sheet.dart';
import 'package:ai_tutor_python/features/badges/prijzenkast_page.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/theme/badge_style.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/badges/badge_frame.dart';
import 'package:ai_tutor_python/widgets/badges/badge_toast_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

void main() {
  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWith((ref) => const Locale('en')),
          translationServiceProvider.overrideWithValue(
            TranslationService(
              container: InMemoryCosmos.partitioned('language').container,
            ),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BadgeProofSheetPage(),
        ),
      ),
    );
    await tester.pump();
  }

  Iterable<BadgeFrame> framesIn(WidgetTester tester, String panel) =>
      tester.widgetList<BadgeFrame>(
        find.descendant(
          of: find.byKey(ValueKey('badge-proof-$panel')),
          matching: find.byType(BadgeFrame),
        ),
      );

  testWidgets('ten states at 32, 64 and 128 px, and the whole set, on each '
      'palette', (tester) async {
    await mount(tester);
    // Every badge the rules count, a medal and the teacher's three (#221).
    final setSize = badgeProofSheetSet().length;
    expect(
      setSize,
      BadgeCatalog.all(expertGoalIds: ['x']).length +
          1 +
          BadgeCatalog.teacher.length,
    );
    for (final (panel, palette) in [
      ('dark', AppPalette.dark),
      ('light', AppPalette.light),
    ]) {
      final frames = framesIn(tester, panel).toList();
      expect(frames.every((f) => f.palette == palette), isTrue, reason: panel);
      expect(frames.where((f) => f.size == 128), hasLength(10), reason: panel);
      // The ten states at 64, and the whole set at 64 and at 32.
      expect(
        frames.where((f) => f.size == 64),
        hasLength(10 + setSize),
        reason: panel,
      );
      expect(
        frames.where((f) => f.size == 32),
        hasLength(10 + setSize),
        reason: panel,
      );

      final states = frames.where((f) => f.size == 128).toList();
      expect(states.map((f) => f.tone).toSet(), {
        BadgeTone.locked,
        BadgeTone.bronze,
        BadgeTone.silver,
        BadgeTone.gold,
        BadgeTone.expert,
        BadgeTone.fun,
      });
      expect(states.where((f) => f.hidden), hasLength(1), reason: 'a secret');
      expect(
        states.where((f) => f.pips > 0 && f.pipsReached > 0),
        isNotEmpty,
        reason: 'dots past the third tier',
      );
    }
    expect(find.text('not earned'), findsNWidgets(2));
    expect(find.text('tier 6 of 6'), findsNWidgets(2));
    expect(find.text('secret'), findsNWidgets(2));
    expect(find.text('secret, found'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the notice, for one badge and as a summary', (tester) async {
    await mount(tester);
    expect(find.byType(BadgeToast), findsNWidgets(4));
    expect(find.text("You've already earned 4 badges!"), findsOneWidget);
    // #221: a medal and a badge from the teacher.
    expect(find.text('Gold: Variabelen'), findsWidgets);
    expect(
      find.text('From your teacher, 2× now · You helped a classmate.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the example trophy case opens over it', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Trophy case preview'));
    await tester.pumpAndSettle();
    expect(find.byType(PrijzenkastView), findsOneWidget);
    expect(find.text('Trophy case'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
