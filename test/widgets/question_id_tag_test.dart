// Issue #304 — the small copy button next to a question's short ID. A
// student who thinks a question is off passes its ID on to the teacher: a
// click puts it on the clipboard as it is shown, with `#`, which the lookup
// on the Questions page takes. For a moment the button shows that it worked.
//
// The end-to-end run (integration_test/flows/question_id.dart) clicks it in
// the real quiz header, the real strip above the editor and on the
// teacher's card, with the real clipboard.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/question_id_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _id = 's1_3fa91c0b5e7d4a2f9c8b1e6d0a4f7c2e';
const _otherId = 's1_77b2e40b5e7d4a2f9c8b1e6d0a4f7c2e';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late List<String> copied;

  Future<void> mount(
    WidgetTester tester, {
    String id = _id,
    String locale = 'en',
    String? tooltip,
  }) async {
    copied = [];
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
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: QuestionIdTag(id, tooltip: tooltip)),
        ),
      ),
    );
    await tester.pump();
  }

  final button = find.byKey(QuestionIdTag.copyKey);
  Icon icon(WidgetTester tester) => tester.widget<Icon>(
    find.descendant(of: button, matching: find.byType(Icon)),
  );

  testWidgets('a click puts the ID on the clipboard as it is shown, with #', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('#3fa91c'), findsOneWidget);
    expect(copied, isEmpty);

    await tester.tap(button);
    await tester.pump();

    expect(copied, ['#3fa91c']);
    await tester.pump(QuestionIdTag.copiedFor);
  });

  testWidgets('the button is small, as muted as the ID and right of it', (
    tester,
  ) async {
    await mount(tester);

    expect(icon(tester).icon, Icons.copy_rounded);
    expect(icon(tester).color, AppColors.fgFaint);
    expect(icon(tester).size, lessThan(14));
    final id = tester.getRect(find.text('#3fa91c'));
    final copy = tester.getRect(button);
    expect(copy.left, greaterThanOrEqualTo(id.right));
    expect(copy.left - id.right, lessThan(6));
    expect((copy.center.dy - id.center.dy).abs(), lessThan(2));
    expect(copy.width, lessThanOrEqualTo(16));
    // No taller than the tag was without it, give or take a pixel.
    expect(tester.getSize(find.byType(QuestionIdTag)).height, lessThan(17));
  });

  testWidgets('after a click it shows for a moment that it worked', (
    tester,
  ) async {
    await mount(tester);
    expect(find.byTooltip('Copy the ID'), findsOneWidget);
    expect(find.byTooltip('Copied'), findsNothing);

    await tester.tap(button);
    await tester.pump();
    expect(icon(tester).icon, Icons.check_rounded);
    expect(find.byTooltip('Copied'), findsOneWidget);
    expect(find.byTooltip('Copy the ID'), findsNothing);

    await tester.pump(
      QuestionIdTag.copiedFor - const Duration(milliseconds: 100),
    );
    expect(icon(tester).icon, Icons.check_rounded);

    await tester.pump(const Duration(milliseconds: 100));
    expect(icon(tester).icon, Icons.copy_rounded);
    expect(find.byTooltip('Copy the ID'), findsOneWidget);

    // And again.
    await tester.tap(button);
    await tester.pump();
    expect(copied, ['#3fa91c', '#3fa91c']);
    expect(icon(tester).icon, Icons.check_rounded);
    await tester.pump(QuestionIdTag.copiedFor);
  });

  testWidgets('in Dutch', (tester) async {
    await mount(tester, locale: 'nl');
    expect(find.byTooltip('Kopieer de ID'), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(find.byTooltip('Gekopieerd'), findsOneWidget);
    await tester.pump(QuestionIdTag.copiedFor);
  });

  testWidgets('the next question is not marked as copied', (tester) async {
    await mount(tester);
    await tester.tap(button);
    await tester.pump();
    expect(icon(tester).icon, Icons.check_rounded);

    await mount(tester, id: _otherId);
    expect(find.text('#77b2e4'), findsOneWidget);
    expect(icon(tester).icon, Icons.copy_rounded);

    await tester.tap(button);
    await tester.pump();
    expect(copied, ['#77b2e4']);
    await tester.pump(QuestionIdTag.copiedFor);
  });

  testWidgets('the tooltip of the place stays on the ID, next to that of '
      'the button', (tester) async {
    await mount(tester, tooltip: 'What the ID is for');

    expect(
      find.ancestor(
        of: find.text('#3fa91c'),
        matching: find.byTooltip('What the ID is for'),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(of: button, matching: find.byTooltip('Copy the ID')),
      findsOneWidget,
    );
  });

  testWidgets('removed while it shows the check, it leaves no timer', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(button);
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(QuestionIdTag.copiedFor);
    expect(tester.takeException(), isNull);
  });
}
