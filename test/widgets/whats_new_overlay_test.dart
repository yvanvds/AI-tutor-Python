// #137: the "What's new" card renders the release body as Markdown. Release
// bodies are Markdown by origin — the ones on GitHub already use `-` bullets
// and `**bold**` — and until #137 the card put them up verbatim, markers and
// all. This pins the two halves of the ask: Markdown comes out as structure,
// and plain prose keeps the plain-text look the card had, so the bodies
// written before #137 do not change shape. The card over the real shell,
// with notes that really came off the release feed, is
// `integration_test/flows/whats_new_overlay.dart`.

import 'package:ai_tutor_python/core/whats_new_controller.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/tutor_markdown.dart';
import 'package:ai_tutor_python/widgets/whats_new_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/unordered_ordered_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _version = '9.9.9+9';

final _overlay = find.byKey(const ValueKey('whats-new-overlay'));
final _title = find.byKey(const ValueKey('whats-new-title'));
final _notes = find.byKey(const ValueKey('whats-new-notes'));
final _dismiss = find.byKey(const ValueKey('whats-new-dismiss'));

/// Text under the notes key. Rendered Markdown is `RichText`, which a plain
/// `find.text` never sees.
Finder _inNotes(String text) => find.descendant(
  of: _notes,
  matching: find.textContaining(text, findRichText: true),
);

/// Every run of text the card puts on screen under the notes key, with the
/// style it is actually painted in — the span tree's styles merged down to
/// the leaf, the way the paragraph applies them.
List<({String text, TextStyle style})> _runs(WidgetTester tester) {
  final runs = <({String text, TextStyle style})>[];
  void walk(InlineSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    if (span is TextSpan) {
      final text = span.text;
      if (text != null && text.isNotEmpty) runs.add((text: text, style: style));
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, style);
      }
    }
  }

  for (final rich in tester.widgetList<RichText>(
    find.descendant(of: _notes, matching: find.byType(RichText)),
  )) {
    walk(rich.text, const TextStyle());
  }
  return runs;
}

void main() {
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    container = ProviderContainer();
  });
  tearDown(() => container.dispose());

  /// The overlay the way the shell stacks it: over a page, watching the
  /// controller, so putting notes on the controller is what shows the card.
  Future<void> show(WidgetTester tester, String notes) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(children: [SizedBox.expand(), WhatsNewOverlay()]),
          ),
        ),
      ),
    );
    expect(_overlay, findsNothing);
    container
        .read(whatsNewControllerProvider.notifier)
        .show(ReleaseNotes(version: _version, notes: notes));
    await tester.pumpAndSettle();
    expect(_overlay, findsOneWidget);
  }

  testWidgets('bullets and bold come out as structure, not as markers', (
    tester,
  ) async {
    await show(
      tester,
      'For students\n\n- **Faster** quizzes\n- Clearer hints\n',
    );

    expect(tester.widget<Text>(_title).data, "What's new in $_version");

    // What is on screen: the words, without the syntax around them.
    expect(_inNotes('For students'), findsOneWidget);
    expect(_inNotes('Faster quizzes'), findsOneWidget);
    expect(_inNotes('Clearer hints'), findsOneWidget);
    expect(_inNotes('**'), findsNothing);
    expect(_inNotes('- '), findsNothing);

    // The body reaches the Markdown widget as published, trimmed …
    expect(
      tester.widget<TutorMarkdown>(_notes).text,
      'For students\n\n- **Faster** quizzes\n- Clearer hints',
    );
    // … two bullets, one per `-` line …
    expect(
      find.descendant(of: _notes, matching: find.byType(UnorderedListView)),
      findsNWidgets(2),
    );
    // … and the emphasis is weight, not asterisks.
    final runs = _runs(tester);
    final faster = runs.singleWhere((r) => r.text == 'Faster');
    expect(faster.style.fontWeight, FontWeight.bold);
    final quizzes = runs.singleWhere((r) => r.text == ' quizzes');
    expect(quizzes.style.fontWeight, isNot(FontWeight.bold));
    expect(
      faster.style.color,
      AppColors.fgMute,
      reason: 'bold is still the notes colour, not a theme default',
    );
  });

  testWidgets('plain prose keeps the look the card had', (tester) async {
    await show(tester, '  What changed in $_version.\n');

    // One run of text, trimmed, in exactly the style the plain `Text` used.
    expect(_inNotes('What changed in $_version.'), findsOneWidget);
    final runs = _runs(tester);
    expect(runs.map((r) => r.text), ['What changed in $_version.']);
    final style = runs.single.style;
    expect(style.color, AppColors.fgMute);
    expect(style.fontSize, 14);
    expect(style.height, 1.5);
    expect(style.fontWeight, isNot(FontWeight.bold));
    expect(
      find.descendant(of: _notes, matching: find.byType(UnorderedListView)),
      findsNothing,
    );
  });

  testWidgets('Got it still closes the card, and a click on the notes '
      'does not', (tester) async {
    await show(tester, '- **Faster** quizzes');

    // Clicking into the notes — a student about to scroll or select — is
    // swallowed by the card, not taken as "close".
    await tester.tap(_inNotes('Faster quizzes'));
    await tester.pumpAndSettle();
    expect(_overlay, findsOneWidget);

    await tester.tap(_dismiss);
    await tester.pumpAndSettle();
    expect(_overlay, findsNothing);
    expect(container.read(whatsNewControllerProvider), isNull);
  });
}
