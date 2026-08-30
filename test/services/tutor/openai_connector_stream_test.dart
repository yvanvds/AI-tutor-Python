// Issue #7 — streaming failure paths in `OpenaiConnector`, driven through
// `assembleStream` over a scripted delta stream (no OpenAI socket):
//
//   - a reply cut off before `</META>` is a `StreamFailed`, not a
//     half-parsed `ErrorResponse` carrying the partial text as its message;
//   - a stream that stalls between chunks hits the idle timeout;
//   - transport exceptions get a student-facing one-liner;
//   - history is only recorded for a completed reply.

import 'dart:async';
import 'dart:io';

import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<StreamChunk>> _collect(
  OpenaiConnector c,
  Stream<String> deltas, {
  Duration idleTimeout = OpenaiConnector.streamIdleTimeout,
}) {
  return c
      .assembleStream(
        deltas,
        input: 'vraag',
        inputs: PreviousInputs.includeSession,
        idleTimeout: idleTimeout,
      )
      .toList();
}

void main() {
  test('a complete envelope streams its text and completes with the parsed '
      'response', () async {
    final c = OpenaiConnector();
    final chunks = await _collect(
      c,
      Stream.fromIterable([
        '<TEXT>Hal',
        'lo daar</TEXT>',
        '<META>{"type":"answer"}</META>',
      ]),
    );

    final text = chunks.whereType<StreamTextDelta>().map((d) => d.text).join();
    expect(text, 'Hallo daar');
    final completed = chunks.last;
    expect(completed, isA<StreamCompleted>());
    final response = (completed as StreamCompleted).response;
    expect(response, isA<Answer>());
    expect((response as Answer).prompt, 'Hallo daar');
    expect(c.sessionHistory, hasLength(1), reason: 'user turn recorded');
  });

  test('a stream cut off before </META> fails instead of completing with '
      'the partial text', () async {
    final c = OpenaiConnector();
    final chunks = await _collect(
      c,
      Stream.fromIterable(['<TEXT>Een lus herhaalt ', 'code zolang']),
    );

    expect(chunks.whereType<StreamTextDelta>(), isNotEmpty);
    expect(chunks.whereType<StreamCompleted>(), isEmpty);
    final failed = chunks.last as StreamFailed;
    expect(failed.message, contains('afgebroken'));
    expect(c.sessionHistory, isEmpty, reason: 'no history for a lost turn');
  });

  test('a stream cut off inside META also fails', () async {
    final c = OpenaiConnector();
    final chunks = await _collect(
      c,
      Stream.fromIterable(['<TEXT>Hi</TEXT><META>{"type":"ans']),
    );

    expect(chunks.last, isA<StreamFailed>());
    expect((chunks.last as StreamFailed).message, contains('afgebroken'));
  });

  test('a stalled stream hits the idle timeout', () async {
    final c = OpenaiConnector();
    final controller = StreamController<String>();
    addTearDown(controller.close);

    final collecting = _collect(
      c,
      controller.stream,
      idleTimeout: const Duration(milliseconds: 50),
    );
    // Long enough that the assembler releases text past its tag lookbehind.
    controller.add('<TEXT>Even geduld, ik denk na over je vraag ');
    // ...and then nothing.

    final chunks = await collecting;
    expect(chunks.first, isA<StreamTextDelta>());
    final failed = chunks.last as StreamFailed;
    expect(failed.error, isA<TimeoutException>());
    expect(failed.message, contains('niet op tijd'));
  });

  test('a transport exception becomes a student-facing failure', () async {
    final c = OpenaiConnector();
    final chunks = await _collect(
      c,
      Stream<String>.error(const SocketException('reset by peer')),
    );

    final failed = chunks.single as StreamFailed;
    expect(failed.error, isA<SocketException>());
    expect(failed.message, 'Geen verbinding met de tutor.');
  });

  test('legacy JSON-only output still completes', () async {
    final c = OpenaiConnector();
    final chunks = await _collect(
      c,
      Stream.fromIterable(['{"type":"answer",', '"prompt":"ok"}']),
    );

    expect(chunks.last, isA<StreamCompleted>());
    expect(((chunks.last as StreamCompleted).response as Answer).prompt, 'ok');
  });

  test('describeTransportError keeps unknown errors verbatim', () {
    expect(
      OpenaiConnector.describeTransportError(StateError('x')),
      contains('x'),
    );
    expect(
      OpenaiConnector.describeTransportError(TimeoutException('t')),
      'De tutor reageerde niet op tijd.',
    );
  });
}
