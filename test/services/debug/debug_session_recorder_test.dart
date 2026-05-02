import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:flutter_test/flutter_test.dart';

class _OkResponse implements ChatResponse {
  const _OkResponse();
  @override
  String get type => 'ok';
  @override
  Map<String, dynamic> toJson() => {'type': 'ok', 'value': 1};
}

class _ThrowingResponse implements ChatResponse {
  const _ThrowingResponse();
  @override
  String get type => 'boom';
  @override
  Map<String, dynamic> toJson() => throw StateError('toJson explosion');
}

void _begin(DebugSessionRecorder r) {
  r.beginTurn(
    requestType: 'submitCode',
    currentExerciseTypeAtStart: '',
    tutorStateAtStart: 'working',
    selectedRootGoalId: null,
    selectedChildGoalId: null,
    preferredRootGoalId: null,
    preferredChildGoalId: null,
    streamable: true,
    previousInputsMode: 'includeSession',
  );
}

void main() {
  group('DebugSessionRecorder', () {
    test('ring buffer caps at kBufferCapacity, dropping oldest', () {
      final r = DebugSessionRecorder();
      for (var i = 0; i < kBufferCapacity + 5; i++) {
        _begin(r);
        r.endTurn();
      }

      final buf = r.bufferForTest;
      expect(buf, hasLength(kBufferCapacity));
      expect(buf.first.turnId, 6);
      expect(buf.last.turnId, kBufferCapacity + 5);
    });

    test('beginTurn → payload → events → parsed → endTurn produces one stitched record', () {
      final r = DebugSessionRecorder();
      _begin(r);
      r.recordRequestPayload(
        userInput: '{"x":1}',
        instructions: 'be brief',
        instructionsDocId: 'submitCode',
      );
      r.recordEvent('a');
      r.recordEvent('b', {'k': 1});
      r.recordEvent('c');
      r.recordRawOutput('raw');
      r.recordParsedResponse(const _OkResponse());
      r.endTurn();

      expect(r.currentForTest, isNull);
      final t = r.bufferForTest.single;
      expect(t.userInput, '{"x":1}');
      expect(t.instructions, 'be brief');
      expect(t.instructionsDocId, 'submitCode');
      expect(t.rawOutput, 'raw');
      expect(t.parsedType, 'ok');
      expect(t.parsedResponse, {'type': 'ok', 'value': 1});
      expect(t.events.map((e) => e.name).toList(), ['a', 'b', 'c']);
      expect(t.events[1].data, {'k': 1});
      expect(t.endedAt, isNotNull);
    });

    test('exportJson exposes schema=1 plus the documented top-level keys', () {
      final r = DebugSessionRecorder();
      r.resetSession(uid: 'u-123', email: 'student@x.test', modelName: 'gpt-test');
      _begin(r);
      r.endTurn();

      final out = r.exportJson();
      expect(out['schema'], kSchemaVersion);
      expect(out['schema'], 1);
      expect(out['sessionId'], isA<String>());
      expect(out['sessionStartedAt'], isA<String>());
      expect(out['exportedAt'], isA<String>());
      expect(out, contains('appVersion'));
      expect(out['modelName'], 'gpt-test');
      expect(out['uid'], 'u-123');
      expect(out['email'], 'student@x.test');
      expect(out['turns'], isA<List>());
      expect((out['turns'] as List), hasLength(1));
    });

    test('recordParsedResponse swallows a toJson() that throws', () {
      final r = DebugSessionRecorder();
      _begin(r);
      r.recordParsedResponse(const _ThrowingResponse());
      r.endTurn();

      final t = r.bufferForTest.single;
      expect(t.parsedType, 'boom');
      expect(t.parsedResponse, isNotNull);
      expect(t.parsedResponse!['error'], contains('toJson explosion'));
    });

    test('resetSession clears the buffer and mints a new sessionId', () {
      final r = DebugSessionRecorder();
      _begin(r);
      r.endTurn();
      _begin(r);
      r.endTurn();
      final firstSessionId = r.bufferForTest.first.sessionId;
      expect(r.bufferForTest, hasLength(2));

      r.resetSession();
      expect(r.bufferForTest, isEmpty);

      _begin(r);
      r.endTurn();
      final newSessionId = r.bufferForTest.single.sessionId;
      expect(newSessionId, isNot(firstSessionId));
      expect(r.bufferForTest.single.turnId, 1);
    });
  });
}
