// Issue #254 — an option that is a sentence with code in backticks
// ("Het programma drukt eerst `m` af ...") was drawn as plain monospace text
// in its tile, backticks and all; the feedback panel under it draws the same
// markdown fine. Now such an option is a sentence in the normal font with
// the code as inline code, and an option without backticks — output or code
// — stays monospace.
//
// This mounts the real `QuizView` with both kinds of option and reads what
// the tiles draw.

import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _sentence =
    'Het programma drukt eerst `m` af en stopt dan met een `IndexError`.';
const _output = 'm\nNone';

const _question = ActiveMcq(
  prompt: 'Welke uitspraak over dit programma is juist?',
  code: 'letters = ["k", "o", "m"]\nprint(letters[2])\nprint(letters[3])',
  options: [_sentence, _output, 'k\no'],
);

final String _mono = AppMono.code().fontFamily!;

bool _isMono(TextStyle? style) => style?.fontFamily == _mono;

/// The paragraph a tile draws for the option that starts with [start].
RichText _paragraph(WidgetTester tester, String start) => tester
    .widgetList<RichText>(
      find.descendant(
        of: find.byType(QuizView),
        matching: find.byType(RichText),
      ),
    )
    .firstWhere((r) => r.text.toPlainText().startsWith(start));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late ProviderContainer pc;

  setUp(() {
    pc = ProviderContainer(
      overrides: [tutorServiceProvider.overrideWith(() => _FakeTutorService())],
    );
  });

  tearDown(() => pc.dispose());

  Future<void> mount(WidgetTester tester, ActiveMcq mcq) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pc.read(activeMcqProvider.notifier).state = mcq;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: QuizView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an option with code in backticks shows no backticks', (
    tester,
  ) async {
    await mount(tester, _question);

    expect(
      find.descendant(
        of: find.byType(QuizView),
        matching: find.textContaining('`', findRichText: true),
      ),
      findsNothing,
      reason: 'the backticks of the option are on screen',
    );
    final sentence = _paragraph(tester, 'Het programma drukt eerst ');
    expect(sentence.text.toPlainText(), contains(' af en stopt dan met een '));
  });

  testWidgets('the sentence is in the normal font, its code is inline code', (
    tester,
  ) async {
    await mount(tester, _question);

    final sentence = _paragraph(tester, 'Het programma drukt eerst ');
    expect(
      _isMono(sentence.text.style),
      isFalse,
      reason: 'a sentence option is drawn in the monospace font',
    );

    for (final code in const ['m', 'IndexError']) {
      final chip = find.descendant(
        of: find.byType(QuizView),
        matching: find.text(code),
      );
      expect(chip, findsOneWidget, reason: 'no inline code for `$code`');
      final style = tester.widget<Text>(chip).style;
      expect(_isMono(style), isTrue, reason: '`$code` is not in code font');
      // On a chip, like a code span in the feedback.
      final box = tester.widget<Container>(
        find.ancestor(of: chip, matching: find.byType(Container)).first,
      );
      expect(box.decoration, isA<BoxDecoration>());
    }
  });

  testWidgets('an option without backticks stays monospace', (tester) async {
    await mount(tester, _question);

    for (final option in const [_output, 'k\no']) {
      final text = tester.widget<Text>(find.text(option));
      expect(_isMono(text.style), isTrue, reason: '"$option" is not mono');
    }
  });

  testWidgets('the code in a sentence takes the tile\'s colour when it is '
      'picked', (tester) async {
    await mount(tester, _question.copyWith(selected: _output));

    // Another option was picked: the sentence and its code fade alike.
    final sentence = _paragraph(tester, 'Het programma drukt eerst ');
    final code = tester.widget<Text>(find.text('IndexError'));
    expect(code.style?.color, sentence.text.style?.color);
  });
}
