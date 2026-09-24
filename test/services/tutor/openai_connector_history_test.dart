// Issue #184 — how much conversation a call carries.
//
// `PreviousInputs.exercise` is the current exercise's own exchange: the
// question the model asked, and whatever was said about it since — a hint,
// the student's answer, the grade. A question generation goes out on
// `newSession` with no history at all and opens the next exercise; its
// reply is that exercise's first entry. The status report still gets
// everything (`includeAll`).
//
// Driven over the real connector and a scripted HTTP client, so the
// assertions read the `messages` array that actually went on the wire.

import 'dart:convert';

import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/hint.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_openai.dart';

/// `role: text` for every message of request [i], system prompt included.
List<String> _sent(FakeOpenAi openai, int i) {
  final body = jsonDecode(openai.requests[i].body) as Map<String, dynamic>;
  return [
    for (final m in (body['messages'] as List).cast<Map<String, dynamic>>())
      '${m['role']}: ${_text(m['content'])}',
  ];
}

String _text(Object? content) => switch (content) {
  String s => s,
  Map m => '${m['text']}',
  List l => l.map(_text).join(),
  _ => '',
};

CompleteCode _question(String code) =>
    CompleteCode(type: 'complete_code', prompt: 'Vul aan.', code: code);

String _json(ChatResponse response) => jsonEncode(response.toJson());

void main() {
  late FakeOpenAi openai;
  late OpenaiConnector c;

  setUp(() {
    openai = FakeOpenAi(text: '<TEXT>ok</TEXT><META>{"type":"answer"}</META>');
    c = OpenaiConnector(client: openai.client);
  });

  /// One exercise the way the tutor runs it: the question request on
  /// `newSession` (streamed), its reply put on the history, then the
  /// student's answer graded on `exercise`.
  Future<void> exercise(String code, String answer) async {
    await c
        .sendRequestStream(
          instructions: 'sys',
          input: 'vraag $code',
          inputs: PreviousInputs.newSession,
        )
        .drain<void>();
    c.addResponse(_question(code));
    await c.sendRequest(
      instructions: 'sys',
      input: 'antwoord $answer',
      inputs: PreviousInputs.exercise,
    );
    c.addResponse(Answer(type: 'answer', prompt: 'graded $answer'));
  }

  test('a question request carries no history, not even the exercise '
      'before it', () async {
    await exercise('print(___)', 'a1');
    await exercise('x = ___', 'a2');

    expect(_sent(openai, 0), ['system: sys', 'user: vraag print(___)']);
    expect(
      _sent(openai, 2),
      ['system: sys', 'user: vraag x = ___'],
      reason: 'the second question request is sent without the first exercise',
    );
  });

  test('a grade carries its own exercise — the question and nothing of the '
      'exercise before', () async {
    await exercise('print(___)', 'a1');
    await exercise('x = ___', 'a2');

    expect(_sent(openai, 1), [
      'system: sys',
      'assistant: ${_json(_question('print(___)'))}',
      'user: antwoord a1',
    ]);
    expect(_sent(openai, 3), [
      'system: sys',
      'assistant: ${_json(_question('x = ___'))}',
      'user: antwoord a2',
    ]);
  });

  test('a hint asked for during the exercise is part of it: the grade sees '
      'the question, the hint exchange, then the answer', () async {
    await c
        .sendRequestStream(
          instructions: 'sys',
          input: 'vraag',
          inputs: PreviousInputs.newSession,
        )
        .drain<void>();
    c.addResponse(_question('print(___)'));
    await c.sendRequest(
      instructions: 'sys',
      input: 'hint please',
      inputs: PreviousInputs.exercise,
    );
    final hint = Hint(type: 'hint', prompt: 'Denk aan aanhalingstekens.');
    c.addResponse(hint);
    await c.sendRequest(
      instructions: 'sys',
      input: 'antwoord',
      inputs: PreviousInputs.exercise,
    );

    expect(_sent(openai, 2), [
      'system: sys',
      'assistant: ${_json(_question('print(___)'))}',
      'user: hint please',
      'assistant: ${_json(hint)}',
      'user: antwoord',
    ]);
    expect(c.exerciseHistory, hasLength(4));
  });

  test('the status report still reads every exercise', () async {
    await exercise('print(___)', 'a1');
    await exercise('x = ___', 'a2');
    await c.sendRequest(
      instructions: 'sys',
      input: 'status',
      inputs: PreviousInputs.includeAll,
    );

    final sent = _sent(openai, 4);
    expect(sent.first, 'system: sys');
    expect(sent.last, 'user: status');
    // Both question requests, both questions, both answers, both grades.
    expect(sent, hasLength(1 + 8 + 1));
    expect(sent, contains('user: vraag print(___)'));
    expect(sent, contains('user: antwoord a2'));
  });

  test('starting a new session starts a new exercise', () async {
    await exercise('print(___)', 'a1');
    expect(c.exerciseHistory, isNotEmpty);

    c.startNewSession();

    expect(c.exerciseHistory, isEmpty);
    expect(c.sessionHistory, isEmpty);
    expect(c.allHistory, hasLength(4));
  });
}
