import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_tutor_python/core/update_info.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('isNewer', () {
    test(
      'higher patch is newer',
      () => expect(isNewer('1.0.1', '1.0.0'), isTrue),
    );
    test(
      'higher minor is newer',
      () => expect(isNewer('1.1.0', '1.0.0'), isTrue),
    );
    test(
      'higher major is newer',
      () => expect(isNewer('2.0.0', '1.9.9'), isTrue),
    );
    test(
      'same version without build is not newer',
      () => expect(isNewer('1.0.0', '1.0.0'), isFalse),
    );
    test(
      'lower version is not newer',
      () => expect(isNewer('0.9.0', '1.0.0'), isFalse),
    );

    test('same semver, higher build number is newer', () {
      expect(isNewer('1.0.0+2', '1.0.0+1'), isTrue);
    });

    test('same semver and same build is not newer', () {
      expect(isNewer('1.0.0+1', '1.0.0+1'), isFalse);
    });

    test('no build vs build is not newer', () {
      expect(isNewer('1.0.0', '1.0.0+1'), isFalse);
    });

    test('build vs no build is newer', () {
      expect(isNewer('1.0.0+1', '1.0.0'), isTrue);
    });
  });

  group('downloadToTemp', () {
    final url = Uri.parse('https://example.com/installer.exe');

    test('throws on a non-200 instead of returning null', () async {
      final client = MockClient((_) async => http.Response('', 404));
      await expectLater(
        downloadToTemp(url, client: client),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
    });

    test('throws instead of hanging when the server never answers', () async {
      final client = MockClient((_) => Completer<http.Response>().future);
      await expectLater(
        downloadToTemp(
          url,
          client: client,
          responseTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    // #48: `pipe`/`addStream` hand the whole body to the sink and offer no
    // per-chunk hook, so there was no progress to report and the UI showed
    // none while ~250 MB came down.
    test('reports a fraction per chunk when the size is known', () async {
      final client = MockClient.streaming((_, _) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(const [
            [1, 2, 3, 4],
            [5, 6],
            [7, 8, 9, 10],
          ]),
          200,
          contentLength: 10,
        );
      });
      final seen = <double>[];
      final file = await downloadToTemp(
        url,
        client: client,
        onProgress: seen.add,
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      expect(seen, [0.4, 0.6, 1.0]);
      expect(file.readAsBytesSync(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    });

    // No `Content-Length` means no denominator. Reporting 0 anyway would
    // freeze a determinate bar at 0%, which reads as a hang; the UI renders
    // "never reported" as an indeterminate bar instead.
    test('reports nothing when the server declares no size', () async {
      final client = MockClient.streaming((_, _) async {
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable(const [
            [1, 2, 3],
          ]),
          200,
        );
      });
      final seen = <double>[];
      final file = await downloadToTemp(
        url,
        client: client,
        onProgress: seen.add,
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      expect(seen, isEmpty);
      expect(file.readAsBytesSync(), [1, 2, 3]);
    });

    test('throws when the body stalls mid-stream', () async {
      final client = MockClient.streaming((_, _) async {
        // One chunk, then silence: exactly the black-hole download that
        // used to keep the app waiting forever.
        final stalled = StreamController<List<int>>();
        stalled.add([1, 2, 3]);
        return http.StreamedResponse(stalled.stream, 200);
      });
      await expectLater(
        downloadToTemp(
          url,
          client: client,
          stallTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('stalled'),
          ),
        ),
      );
    });
  });

  // #124: the installer sits behind the same TLS inspection as the API, so
  // the download has the same fallback — and the same rule that nothing but
  // a handshake failure reaches it.
  group('downloadToTemp — native transport fallback', () {
    final url = Uri.parse('https://example.com/installer.exe');
    const handshake = HandshakeException(
      'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED)',
    );
    final expectedPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'python_teacher_install.exe';

    /// A seam that writes [bytes] where it is told to and records the call.
    ({NativeGet get, List<({Uri url, File? to})> calls}) recordingNative({
      List<int> bytes = const [1, 2, 3],
      int status = 200,
      Object? failWith,
    }) {
      final calls = <({Uri url, File? to})>[];
      Future<http.Response> get(
        Uri url, {
        Map<String, String> headers = const {},
        Duration? timeout,
        File? to,
      }) async {
        calls.add((url: url, to: to));
        if (failWith != null) throw failWith;
        if (to != null && status == 200) to.writeAsBytesSync(bytes);
        return http.Response('', status);
      }

      return (get: get, calls: calls);
    }

    setUp(() {
      final leftover = File(expectedPath);
      if (leftover.existsSync()) leftover.deleteSync();
    });

    test('a handshake failure is retried through the seam into the temp '
        'file', () async {
      final dart = MockClient((_) async => throw handshake);
      final native = recordingNative(bytes: const [9, 8, 7]);
      final logs = <String>[];

      final file = await downloadToTemp(
        url,
        client: dart,
        nativeGet: native.get,
        log: logs.add,
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      expect(file.path, expectedPath);
      expect(native.calls, hasLength(1));
      expect(native.calls.single.url, url);
      expect(native.calls.single.to?.path, expectedPath);
      expect(file.readAsBytesSync(), [9, 8, 7]);
      expect(logs.join('\n'), contains('TLS handshake'));
    });

    // A check that only got through natively is not going to fare better on
    // the installer: go straight there.
    test('preferNative skips Dart entirely', () async {
      var dartRequests = 0;
      final dart = MockClient((_) async {
        dartRequests++;
        return http.Response('never', 200);
      });
      final native = recordingNative();

      final file = await downloadToTemp(
        url,
        client: dart,
        nativeGet: native.get,
        preferNative: true,
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      expect(dartRequests, 0);
      expect(native.calls, hasLength(1));
    });

    test('preferNative without a seam still uses Dart', () async {
      final dart = MockClient((_) async => http.Response('', 404));
      await expectLater(
        downloadToTemp(url, client: dart, preferNative: true),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
    });

    test('a non-200 through the seam fails and leaves no file', () async {
      final dart = MockClient((_) async => throw handshake);
      final native = recordingNative(status: 403);
      await expectLater(
        downloadToTemp(url, client: dart, nativeGet: native.get),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 403'),
          ),
        ),
      );
      expect(File(expectedPath).existsSync(), isFalse);
    });

    test('without a seam the handshake reason is reported as before', () async {
      final dart = MockClient((_) async => throw handshake);
      await expectLater(
        downloadToTemp(url, client: dart),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            contains('CERTIFICATE_VERIFY_FAILED'),
          ),
        ),
      );
    });

    test('when the seam fails too, both reasons are kept', () async {
      final dart = MockClient((_) async => throw handshake);
      final native = recordingNative(
        failWith: UpdateCheckException('curl.exe exited with 60'),
      );
      await expectLater(
        downloadToTemp(url, client: dart, nativeGet: native.get),
        throwsA(
          isA<UpdateCheckException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('CERTIFICATE_VERIFY_FAILED'),
              contains('curl.exe exited with 60'),
            ),
          ),
        ),
      );
    });

    test('a dead socket, a 404 or a stall never reach the seam', () async {
      final native = recordingNative();

      await expectLater(
        downloadToTemp(
          url,
          client: MockClient(
            (_) async => throw const SocketException('no route to host'),
          ),
          nativeGet: native.get,
        ),
        throwsA(isA<UpdateCheckException>()),
      );
      await expectLater(
        downloadToTemp(
          url,
          client: MockClient((_) async => http.Response('', 404)),
          nativeGet: native.get,
        ),
        throwsA(isA<UpdateCheckException>()),
      );
      await expectLater(
        downloadToTemp(
          url,
          client: MockClient((_) => Completer<http.Response>().future),
          nativeGet: native.get,
          responseTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<UpdateCheckException>()),
      );

      expect(native.calls, isEmpty);
    });
  });

  group('verifySha256', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('update_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('returns true for matching hash', () async {
      final content = Uint8List.fromList([1, 2, 3, 4, 5]);
      final file = File('${tmp.path}/bin')..writeAsBytesSync(content);
      final expected = sha256.convert(content).toString();
      expect(await verifySha256(file, expected), isTrue);
    });

    test('returns false for wrong hash', () async {
      final file = File('${tmp.path}/bin')..writeAsBytesSync([1, 2, 3]);
      expect(await verifySha256(file, 'deadbeef'), isFalse);
    });

    test('comparison is case-insensitive', () async {
      final content = Uint8List.fromList([10, 20, 30]);
      final file = File('${tmp.path}/bin')..writeAsBytesSync(content);
      final upper = sha256.convert(content).toString().toUpperCase();
      expect(await verifySha256(file, upper), isTrue);
    });

    // #48: this used to be `readAsBytes` — the whole ~250 MB installer into
    // RAM, on a machine that had just streamed the same bytes to disk. A file
    // larger than any single read buffer proves the chunked path reassembles
    // the same digest rather than hashing only what one read returned.
    test('hashes a multi-chunk file in one piece', () async {
      final content = Uint8List.fromList(
        List<int>.generate(3 * 1024 * 1024, (i) => i % 256),
      );
      final file = File('${tmp.path}/big')..writeAsBytesSync(content);
      final expected = sha256.convert(content).toString();

      expect(await verifySha256(file, expected), isTrue);
      expect(await verifySha256(file, 'deadbeef'), isFalse);
    });

    test('an empty file hashes to the empty digest', () async {
      final file = File('${tmp.path}/empty')..writeAsBytesSync(const []);
      expect(
        await verifySha256(file, sha256.convert(const []).toString()),
        isTrue,
      );
    });
  });
}
