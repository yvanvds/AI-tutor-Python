// End-to-end (#126): the key the tutor's calls actually go out on.
//
// An account without `mayUseGlobalKey` is stopped at the local-key gate
// until it enters its own OpenAI key — and then, before #126, every call ran
// on the school's bundled key anyway: the typed key was stored and never
// read. These flows boot the real app with the *production* connectors in
// place and only the socket underneath replaced (`AppHarness.openaiClient`),
// so what is asserted is the `Authorization` header the real tutor, built
// the way `lib/` builds it, put on a real request:
//
//   - own-key account: the key typed at the gate is the one on the wire, and
//     the exercise it buys reaches the editor;
//   - school-key account with a key left on the device from before: the
//     school's key is on the wire, the stray one ignored;
//   - own-key account whose key OpenAI refuses: the chat says so and points
//     at Options, and the Test button in Options says the same — the
//     student's key, not the school's, is what is wrong.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/own_key.dart -d windows

import 'package:ai_tutor_python/features/auth/local_key_gate_screen.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/progress/leerpad_page.dart';
import 'package:ai_tutor_python/features/session/modes/explain_view.dart';
import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/fake_openai.dart';
import '../harness/app_harness.dart';
import '../harness/scripted_llm.dart';
import '../harness/seed.dart';

/// The key the student types at the gate.
const String _ownKey = 'sk-typed-at-the-gate';

/// A key a previous own-key session left in SharedPreferences.
const String _strayKey = 'sk-left-over';

/// The exercise the (fake) model hands out: what the practice editor shows
/// once the request came back, and the proof the call went through.
const String _exerciseCode = 'naam = ___\nprint("Hallo", naam)';

/// The seeded student's account doc, off the school's key.
Map<String, dynamic> _ownKeyAccount() => {
  ...accountDoc(studentIdentity),
  'mayUseGlobalKey': false,
};

/// Opens the practice editor, which asks the model for an exercise on mount
/// — the first real tutor call of a session.
Future<void> _openPractice(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Learning path'));
  await pumpUntilFound(tester, find.byType(LeerpadPage));
  await tester.tap(find.text('Continue'));
  await pumpUntilFound(tester, find.byType(ExplainView));
  await tester.tap(find.text('Try it yourself'));
  await pumpUntilFound(tester, find.byType(PracticeView));
}

String _editorText(WidgetTester tester) =>
    tester.widget<CodeField>(find.byType(CodeField)).controller.text;

/// Brings an Options card into view and taps [finder]. The panel is a real
/// `ListView` in a real window: a row below the fold is not built yet, and
/// one that is built but off-screen would be "tapped" at the wrong place.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  final scrollable = find
      .descendant(
        of: find.byType(OptionsPage),
        matching: find.byType(Scrollable),
      )
      .first;
  await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(finder);
  await tester.pump();
}

Iterable<String> _pills(WidgetTester tester) => tester
    .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
    .map((p) => p.text);

/// Waits for the tutor's request to have gone out and been answered.
Future<void> _pumpUntilRequested(WidgetTester tester, FakeOpenAi openai) =>
    pumpUntil(
      tester,
      () => openai.requests.isNotEmpty,
      timeout: const Duration(seconds: 30),
      reason: 'the app never asked the model for an exercise',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late FakeOpenAi openai;

  setUp(() {
    openai = FakeOpenAi(
      text: completeCodeReply(
        text: 'Vul de ontbrekende naam in.',
        code: _exerciseCode,
      ),
    );
  });

  testWidgets('the key entered at the local-key gate is the one the tutor '
      'calls with', (tester) async {
    final harness = AppHarness(
      openaiClient: openai.client,
      extraDocs: {
        'accounts': [_ownKeyAccount()],
      },
    );
    await harness.boot(tester, waitForShell: false);

    // No school key, no own key: the gate, not the shell.
    await pumpUntilFound(tester, find.byType(LocalKeyGateScreen));
    expect(find.byType(AppShell), findsNothing);

    await tester.enterText(find.byType(TextFormField), _ownKey);
    await tester.pump();
    await tester.tap(find.text('Save key'));
    await pumpUntilFound(tester, find.byType(AppShell));

    // The gate's confirmation outlives the gate: it sits over the bottom of
    // the shell for a few seconds, where the button the flow needs next is.
    await pumpUntilFound(tester, find.text('API key saved locally.'));
    await pumpUntilGone(tester, find.text('API key saved locally.'));

    await _openPractice(tester);
    await _pumpUntilRequested(tester, openai);

    // The real request, from the real connector, on the typed key — and
    // not on the school's.
    expect(openai.bearers, ['Bearer $_ownKey']);
    expect(openai.requests.single.url.path, endsWith('/chat/completions'));

    // And what it bought reached the student.
    await pumpUntil(
      tester,
      () => _editorText(tester).contains('___'),
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );
    expect(_editorText(tester), _exerciseCode);
    expect(
      find.textContaining('Vul de ontbrekende naam in.', findRichText: true),
      findsWidgets,
    );

    await harness.dispose(tester);
  });

  testWidgets("an account on the school's key calls with it, and a key left "
      'on the device is ignored', (tester) async {
    // The seeded account has `mayUseGlobalKey`; the stray key is what an
    // earlier own-key session, or a teacher's toggle since, leaves behind.
    final harness = AppHarness(
      openaiClient: openai.client,
      prefs: const {'local_api_key': _strayKey},
    );
    await harness.boot(tester);

    await _openPractice(tester);
    await _pumpUntilRequested(tester, openai);

    expect(openai.bearers, ['Bearer $kSchoolApiKey']);
    expect(openai.bearers, isNot(contains('Bearer $_strayKey')));

    await pumpUntil(
      tester,
      () => _editorText(tester).contains('___'),
      timeout: const Duration(seconds: 30),
      reason: 'the exercise never reached the editor',
    );

    await harness.dispose(tester);
  });

  testWidgets('a rejected own key is reported as the student\'s to fix, in '
      'the chat and under the Test button', (tester) async {
    openai.answer = (_) => FakeOpenAi.unauthorized();
    final harness = AppHarness(
      openaiClient: openai.client,
      prefs: const {'local_api_key': _ownKey},
      extraDocs: {
        'accounts': [_ownKeyAccount()],
      },
    );
    // A stored key satisfies the gate; the app opens on the shell.
    await harness.boot(tester);

    await _openPractice(tester);
    await _pumpUntilRequested(tester, openai);

    const expected =
        'Something went wrong with the tutor: OpenAI rejected your API key. '
        'Check it under Options → OpenAI API key.';
    await pumpUntil(
      tester,
      () => _pills(tester).contains(expected),
      timeout: const Duration(seconds: 30),
      reason: 'no pill named the rejected key; pills: ${_pills(tester)}',
    );
    // Not the API's own line, which names a key the student cannot change.
    expect(_pills(tester).any((p) => p.contains('Incorrect API key')), isFalse);
    // Every attempt (the first and the app's one retry) went out on the
    // student's key.
    expect(openai.bearers, everyElement('Bearer $_ownKey'));

    // The Test button behind the model field runs on the same key and says
    // the same thing.
    await tester.tap(find.byTooltip('Options'));
    await pumpUntilFound(tester, find.byType(OptionsPage));
    await _scrollAndTap(tester, find.text('Another model on this device'));
    final field = find.byKey(const ValueKey('model-field-device'));
    await pumpUntilFound(tester, field);
    // A click into the field before typing, as a person does; `enterText`'s
    // own refocus does not land the text on a real window (see
    // options_panel.dart).
    await _scrollAndTap(tester, field);
    await tester.enterText(field, 'gpt-4o');
    await tester.pump();
    final probed = openai.requests.length;
    await _scrollAndTap(
      tester,
      find.byKey(const ValueKey('model-test-device')),
    );
    await pumpUntilFound(
      tester,
      find.text(
        'Test failed: OpenAI rejected your API key. Check it under '
        'Options → OpenAI API key.',
      ),
    );
    expect(openai.requests.length, probed + 1);
    expect(openai.bearers.last, 'Bearer $_ownKey');

    await harness.dispose(tester);
  });
}
