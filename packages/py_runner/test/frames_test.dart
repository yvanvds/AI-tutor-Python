import 'dart:convert';

import 'package:py_runner/py_runner.dart';
import 'package:test/test.dart';

void main() {
  group('inbound frames', () {
    test('exec round-trips with cwd', () {
      const frame = ExecFrame(
        id: '7f1c-aaaa',
        code: "print('hi')\n",
        cwd: r'C:\tmp\run',
      );
      final decoded = HostInboundFrame.decode(frame.encode()) as ExecFrame;
      expect(decoded.id, frame.id);
      expect(decoded.code, frame.code);
      expect(decoded.cwd, frame.cwd);
      expect(decoded.type, 'exec');
    });

    test('exec round-trips without cwd; cwd field is omitted', () {
      const frame = ExecFrame(id: 'abc', code: 'pass');
      final encoded = frame.encode();
      expect(jsonDecode(encoded), {
        'type': 'exec',
        'id': 'abc',
        'code': 'pass',
      });
      final decoded = HostInboundFrame.decode(encoded) as ExecFrame;
      expect(decoded.cwd, isNull);
    });

    test('cancel round-trips', () {
      const frame = CancelFrame(id: '7f1c-bbbb');
      final decoded = HostInboundFrame.decode(frame.encode()) as CancelFrame;
      expect(decoded.id, frame.id);
      expect(decoded.type, 'cancel');
    });

    test('input_response round-trips', () {
      const frame = InputResponseFrame(
        id: '7f1c-cccc',
        requestId: 1,
        value: 'Yvan',
      );
      final decoded =
          HostInboundFrame.decode(frame.encode()) as InputResponseFrame;
      expect(decoded.id, frame.id);
      expect(decoded.requestId, 1);
      expect(decoded.value, 'Yvan');
      expect(decoded.type, 'input_response');
    });

    test('preserves embedded newlines and unicode in code', () {
      const frame = ExecFrame(
        id: 'unicode',
        code: "print('ë\\né')\n# multi\n# line\n",
      );
      final decoded = HostInboundFrame.decode(frame.encode()) as ExecFrame;
      expect(decoded.code, frame.code);
    });
  });

  group('outbound frames', () {
    test('ready round-trips with optional protocol_version', () {
      const frame = ReadyFrame(
        pythonVersion: '3.14.0',
        platform: 'win_amd64',
        capabilities: ['exec', 'cancel'],
        protocolVersion: 1,
      );
      final decoded = HostOutboundFrame.decode(frame.encode()) as ReadyFrame;
      expect(decoded.pythonVersion, '3.14.0');
      expect(decoded.platform, 'win_amd64');
      expect(decoded.capabilities, ['exec', 'cancel']);
      expect(decoded.protocolVersion, 1);
    });

    test('ready decodes without protocol_version', () {
      const json =
          '{"type":"ready","python_version":"3.14.0","platform":"win_amd64","capabilities":["exec","cancel"]}';
      final decoded = HostOutboundFrame.decode(json) as ReadyFrame;
      expect(decoded.protocolVersion, isNull);
      expect(decoded.capabilities, ['exec', 'cancel']);
    });

    test('stdout round-trips', () {
      const frame = StdoutFrame(id: '7f1c', text: 'hi\n');
      final decoded = HostOutboundFrame.decode(frame.encode()) as StdoutFrame;
      expect(decoded.id, '7f1c');
      expect(decoded.text, 'hi\n');
      expect(decoded.type, 'stdout');
    });

    test('stderr round-trips', () {
      const frame = StderrFrame(id: '7f1c', text: 'oops');
      final decoded = HostOutboundFrame.decode(frame.encode()) as StderrFrame;
      expect(decoded.id, '7f1c');
      expect(decoded.text, 'oops');
      expect(decoded.type, 'stderr');
    });

    test('input_request round-trips', () {
      const frame = InputRequestFrame(
        id: '7f1c',
        requestId: 2,
        prompt: 'Naam? ',
      );
      final decoded =
          HostOutboundFrame.decode(frame.encode()) as InputRequestFrame;
      expect(decoded.requestId, 2);
      expect(decoded.prompt, 'Naam? ');
      expect(decoded.type, 'input_request');
    });

    test('exception round-trips', () {
      const frame = ExceptionFrame(
        id: '7f1c',
        excType: 'ZeroDivisionError',
        message: 'division by zero',
        traceback:
            'Traceback (most recent call last):\n  File "<student>", line 1, in <module>\nZeroDivisionError: division by zero\n',
      );
      final decoded =
          HostOutboundFrame.decode(frame.encode()) as ExceptionFrame;
      expect(decoded.excType, 'ZeroDivisionError');
      expect(decoded.message, 'division by zero');
      expect(decoded.traceback, contains('ZeroDivisionError'));
    });

    test('done round-trips for every status', () {
      for (final status in DoneStatus.values) {
        final frame = DoneFrame(id: '7f1c', status: status, durationMs: 42);
        final decoded = HostOutboundFrame.decode(frame.encode()) as DoneFrame;
        expect(decoded.status, status);
        expect(decoded.durationMs, 42);
        expect(decoded.id, '7f1c');
      }
    });

    test('done rejects unknown status', () {
      const json =
          '{"type":"done","id":"7f1c","status":"weird","duration_ms":0}';
      expect(
        () => HostOutboundFrame.decode(json),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('host_log round-trips for every level', () {
      for (final level in HostLogLevel.values) {
        final frame = HostLogFrame(level: level, message: 'hi from host');
        final decoded =
            HostOutboundFrame.decode(frame.encode()) as HostLogFrame;
        expect(decoded.level, level);
        expect(decoded.message, 'hi from host');
      }
    });

    test('host_log rejects unknown level', () {
      const json = '{"type":"host_log","level":"verbose","message":"x"}';
      expect(
        () => HostOutboundFrame.decode(json),
        throwsA(isA<FrameDecodeException>()),
      );
    });
  });

  group('forward-compat: unknown fields are ignored', () {
    test('extra fields on a known frame survive decode', () {
      const json =
          '{"type":"stdout","id":"7f1c","text":"hi","future_field":123}';
      final decoded = HostOutboundFrame.decode(json) as StdoutFrame;
      expect(decoded.id, '7f1c');
      expect(decoded.text, 'hi');
    });
  });

  group('decode errors', () {
    test('non-JSON line throws', () {
      expect(
        () => HostOutboundFrame.decode('not-json'),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('JSON array (not object) throws', () {
      expect(
        () => HostOutboundFrame.decode('[1,2,3]'),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('unknown frame type on inbound throws', () {
      expect(
        () => HostInboundFrame.decode('{"type":"nope","id":"x"}'),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('unknown frame type on outbound throws', () {
      expect(
        () => HostOutboundFrame.decode('{"type":"mystery"}'),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('missing required string field throws', () {
      expect(
        () => HostInboundFrame.decode('{"type":"exec","id":"x"}'),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('wrong type for required int throws', () {
      expect(
        () => HostInboundFrame.decode(
          '{"type":"input_response","id":"x","request_id":"1","value":"v"}',
        ),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('non-string element in capabilities list throws', () {
      const json =
          '{"type":"ready","python_version":"3.14.0","platform":"win_amd64","capabilities":["exec",2]}';
      expect(
        () => HostOutboundFrame.decode(json),
        throwsA(isA<FrameDecodeException>()),
      );
    });

    test('optional cwd of wrong type is treated as absent (lenient)', () {
      final decoded = HostInboundFrame.decode(
        '{"type":"exec","id":"x","code":"pass","cwd":123}',
      ) as ExecFrame;
      expect(decoded.cwd, isNull);
    });

    test(
      'optional protocol_version of wrong type is treated as absent (lenient)',
      () {
        const json =
            '{"type":"ready","python_version":"3.14.0","platform":"win_amd64","capabilities":["exec"],"protocol_version":"1"}';
        final decoded = HostOutboundFrame.decode(json) as ReadyFrame;
        expect(decoded.protocolVersion, isNull);
      },
    );
  });

  group('exhaustive switches on sealed hierarchies', () {
    test('every HostInboundFrame subtype is handled in a switch', () {
      const frames = <HostInboundFrame>[
        ExecFrame(id: 'a', code: 'b'),
        CancelFrame(id: 'a'),
        InputResponseFrame(id: 'a', requestId: 0, value: 'b'),
      ];
      for (final f in frames) {
        // Compile-time exhaustiveness check: removing a case would fail to
        // compile thanks to the sealed hierarchy.
        final tag = switch (f) {
          ExecFrame() => 'exec',
          CancelFrame() => 'cancel',
          InputResponseFrame() => 'input_response',
        };
        expect(tag, f.type);
      }
    });

    test('every HostOutboundFrame subtype is handled in a switch', () {
      const frames = <HostOutboundFrame>[
        ReadyFrame(
          pythonVersion: '3.14.0',
          platform: 'win_amd64',
          capabilities: ['exec'],
        ),
        StdoutFrame(id: 'a', text: 'b'),
        StderrFrame(id: 'a', text: 'b'),
        InputRequestFrame(id: 'a', requestId: 0, prompt: 'b'),
        ExceptionFrame(id: 'a', excType: 'b', message: 'c', traceback: 'd'),
        DoneFrame(id: 'a', status: DoneStatus.ok, durationMs: 0),
        HostLogFrame(level: HostLogLevel.info, message: 'b'),
      ];
      for (final f in frames) {
        final tag = switch (f) {
          ReadyFrame() => 'ready',
          StdoutFrame() => 'stdout',
          StderrFrame() => 'stderr',
          InputRequestFrame() => 'input_request',
          ExceptionFrame() => 'exception',
          DoneFrame() => 'done',
          HostLogFrame() => 'host_log',
        };
        expect(tag, f.type);
      }
    });
  });
}
