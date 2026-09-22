// End-to-end (#146): the tutor asks a question with a bullet list, the
// student starts typing a long answer, and the bottom of the question
// disappears behind the composer.
//
// `flutter_chat_ui` draws the composer *over* the message list — a
// `Positioned` at the bottom of a `Stack` — and the list keeps itself clear
// of it by padding its end with whatever height `ComposerChrome` last
// reported to `ComposerHeightNotifier`. The idle composer's `TextField` has
// `maxLines: null`, so wrapping onto another row is a relayout of the
// child, not a new `ComposerChrome` widget: neither `initState` nor
// `didUpdateWidget` fired, the reported height stayed at two rows, and the
// composer grew straight over the newest message.
//
// Only a real run shows that. A widget test renders the composer in
// isolation, where nothing is behind it to be covered; what the student
// sees is the *composition* — the chat panel's real width in the practice
// workspace, the real bundled font the answer wraps at, the real reversed
// message list and the real padding it takes from the notifier. So this
// flow types a growing answer into the real composer and checks, on every
// step, that no message has slipped under it.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/chat_composer_growth.dart -d windows

import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_chrome.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/student_bubble.dart';
import 'package:ai_tutor_python/features/chat/widgets/tutor_bubble.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/app_harness.dart';

/// The tutor's question, the shape of the one in the report: a line of text
/// and a bullet list whose last bullet is the first thing to go behind a
/// growing composer.
const String _question =
    'Kijk naar deze lus en zeg wat er gebeurt:\n\n'
    '- hoe vaak loopt hij?\n'
    '- welke waarde heeft `i` in de eerste ronde?\n'
    '- welke waarde heeft `i` in de laatste ronde?\n'
    '- wat staat er dan op het scherm?';

/// One line of the answer the student types. Short enough that a count of
/// them is a count of rows in the field.
const String _answerLine = 'ik denk dat de lus drie keer loopt';

/// An answer of [lines] rows.
String _answer(int lines) => List.filled(lines, _answerLine).join('\n');

/// Fresh finders per call: a mode swap unmounts the composer and a reused
/// instance would hold the old element (#133).
Finder _composer() => find.byType(ComposerChrome);
Finder _field() => find.descendant(
  of: find.byType(ComposerIdle),
  matching: find.byType(TextField),
);

/// Top edge of the composer, in global coordinates — the line nothing in
/// the message list may cross.
double _composerTop(WidgetTester tester) => tester.getRect(_composer()).top;

/// How tall the composer is right now.
double _composerHeight(WidgetTester tester) =>
    tester.getSize(_composer()).height;

/// The bottom edge of the lowest thing in the message list: the newest
/// message, whatever kind it is. Measured from the render box rather than a
/// finder rect so a message the list has scrolled partly out of view still
/// reports where it really sits.
double _lowestMessageBottom(WidgetTester tester) {
  var lowest = double.negativeInfinity;
  for (final finder in [
    find.byType(TutorBubble),
    find.byType(StudentBubble),
    find.byType(ChatSystemPill),
  ]) {
    for (final element in finder.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (bottom > lowest) lowest = bottom;
    }
  }
  return lowest;
}

/// Pumps until the composer and the message list have stopped moving.
///
/// Not `pumpAndSettle`: the app never fully settles here (the editor's
/// cursor blink, the 5 s Cosmos polls). What does settle is the chat —
/// `ChatAnimatedList` animates an incoming message and the scroll that
/// follows it, and the composer's re-measure costs a frame of its own — so
/// this waits for both numbers this flow reads to hold still.
Future<void> _settle(WidgetTester tester) async {
  var stable = 0;
  ({double top, double height, double bottom})? last;
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (stable < 3) {
    if (DateTime.now().isAfter(deadline)) {
      fail('the chat never stopped moving');
    }
    await tester.pump(const Duration(milliseconds: 16));
    final now = (
      top: _composerTop(tester),
      height: _composerHeight(tester),
      bottom: _lowestMessageBottom(tester),
    );
    stable = now == last ? stable + 1 : 0;
    last = now;
  }
}

/// Types [text] into the composer and lets the layout settle. The click is
/// what a student does; `enterText` alone focuses a field only through
/// `binding.focusedEditable`, which is a no-op once that already names it.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.tap(_field());
  await tester.pump();
  await tester.enterText(_field(), text);
  await _settle(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the question stays clear of the composer while the answer '
      'grows and shrinks', (tester) async {
    final harness = AppHarness();
    await harness.boot(tester);

    // Practice keeps the full chat panel whatever the fold says, and the
    // tutor's questions live there — it is where a student types an answer.
    await tester.tap(find.text('Practice'));
    await pumpUntilFound(tester, find.byType(PracticeView));
    await pumpUntilFound(tester, _composer());

    harness.container.read(chatServiceProvider).addTutorMessage(_question);
    await pumpUntilFound(tester, find.byType(TutorBubble));
    await _settle(tester);

    // Nothing typed yet: the question sits above the two-row composer.
    final restingHeight = _composerHeight(tester);
    final bottomAtRest = _lowestMessageBottom(tester);
    expect(
      bottomAtRest,
      lessThanOrEqualTo(_composerTop(tester)),
      reason:
          'the question is already behind the composer before a key is '
          'pressed',
    );

    // One row of answer. This is the one step the broken code survived: the
    // first character lights up the send button, which rebuilds
    // `ComposerIdle` and so hands `ComposerChrome` a new widget.
    await _type(tester, _answerLine);
    expect(_composerHeight(tester), restingHeight);
    expect(
      _lowestMessageBottom(tester),
      lessThanOrEqualTo(_composerTop(tester)),
    );

    // The answer keeps coming. The field has text already, so nothing above
    // the `TextField` rebuilds: the composer grows by layout alone.
    await _type(tester, _answer(5));
    final grownHeight = _composerHeight(tester);
    expect(
      grownHeight,
      greaterThan(restingHeight),
      reason:
          'the composer has to have actually grown for this to test '
          'anything',
    );
    final grownTop = _composerTop(tester);
    final bottomWhileGrown = _lowestMessageBottom(tester);
    expect(
      bottomWhileGrown,
      lessThanOrEqualTo(grownTop),
      reason:
          'the last message reaches ${bottomWhileGrown}px while the composer '
          'starts at ${grownTop}px — ${bottomWhileGrown - grownTop}px of the '
          'tutor question is behind the composer the student is typing in',
    );
    // And it moved up by exactly what the composer gained, rather than
    // riding along on some slack the list happened to have.
    expect(
      bottomAtRest - bottomWhileGrown,
      closeTo(grownHeight - restingHeight, 0.5),
      reason:
          'the composer gained ${grownHeight - restingHeight}px while the '
          'question moved up ${bottomAtRest - bottomWhileGrown}px',
    );

    // Past the 140 px cap the field scrolls instead of growing, and the
    // question must not move again.
    await _type(tester, _answer(20));
    final cappedHeight = _composerHeight(tester);
    expect(
      cappedHeight,
      greaterThanOrEqualTo(grownHeight),
      reason: 'the composer may not shrink as the answer gets longer',
    );
    expect(
      _lowestMessageBottom(tester),
      lessThanOrEqualTo(_composerTop(tester)),
    );

    // The student trims the answer back. The field still has text, so again
    // no rebuild — and the question has to come back down with it rather
    // than leave a gap.
    await _type(tester, _answer(2));
    final trimmedHeight = _composerHeight(tester);
    expect(trimmedHeight, lessThan(cappedHeight));
    expect(
      _lowestMessageBottom(tester),
      lessThanOrEqualTo(_composerTop(tester)),
    );
    expect(
      _lowestMessageBottom(tester),
      greaterThan(bottomWhileGrown),
      reason:
          'the question stayed where the taller composer had pushed it, '
          'leaving a gap above the shrunken one',
    );

    await harness.dispose(tester);
  });
}
