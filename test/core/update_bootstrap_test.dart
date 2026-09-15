// #49: the app's half of "an update needs no administrator and the app comes
// back". The installer's half — per-user install under %LOCALAPPDATA%, and the
// `[Run]` entry guarded by `WantsRelaunch` — lives in
// `windows/packaging/exe/installer.iss` and cannot be reached from Dart. What
// can be, and what these pin, is the command line the app hands it: drop
// `/RELAUNCH=1` and the installer's only unguarded `[Run]` entry is
// `skipifsilent`, so the app updates and never returns.
//
// #124: the second process this file may spawn — `curl.exe`, the
// Windows-native transport the updater falls back to when Dart cannot
// complete a TLS handshake. Pinned the same way: the command line it is
// handed, against a fake runner; and, where the machine has the real binary,
// one round trip through it against a loopback server.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// What the fake `curl.exe` was told, and what it will pretend happened.
class _FakeCurl {
  _FakeCurl({
    this.exitCode = 0,
    this.stdout = '200',
    this.stderr = '',
    this.body = const <int>[],
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Written to whatever `-o` names, the way the real one would.
  final List<int> body;

  final List<({String executable, List<String> arguments})> calls = [];

  Future<ProcessResult> run(String executable, List<String> arguments) async {
    calls.add((executable: executable, arguments: arguments));
    final int o = arguments.indexOf('-o');
    if (o >= 0 && exitCode == 0) {
      File(arguments[o + 1]).writeAsBytesSync(body);
    }
    return ProcessResult(4242, exitCode, stdout, stderr);
  }

  /// The value after [flag], or `null` when the flag is absent.
  String? argAfter(String flag) {
    final List<String> args = calls.single.arguments;
    final int i = args.indexOf(flag);
    return i < 0 ? null : args[i + 1];
  }
}

void main() {
  test('the silent install arguments carry the relaunch switch', () {
    expect(
      kSilentInstallArguments,
      containsAll(<String>[
        '/SILENT',
        '/NOCANCEL',
        '/NORESTART',
        '/RELAUNCH=1',
      ]),
    );
    // `/VERYSILENT` shows the student nothing at all while ~250 MB is
    // unpacked, which reads as a crash.
    expect(kSilentInstallArguments, isNot(contains('/VERYSILENT')));
  });

  group('curlNativeGet', () {
    // A path that exists so the factory hands back a transport: the file is
    // never run, the fake runner is.
    late File curl;
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('update_bootstrap_test_');
      curl = File('${tmp.path}${Platform.pathSeparator}curl.exe')
        ..writeAsBytesSync(const <int>[]);
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    // Windows 10 before 1803, or a machine somebody stripped: keep today's
    // behaviour and today's error text rather than fail differently.
    test('is null when curl.exe is not there', () {
      expect(
        curlNativeGet(curlPath: '${tmp.path}${Platform.pathSeparator}nope.exe'),
        isNull,
      );
    });

    test('shapes the request the way the fallback needs it', () async {
      final fake = _FakeCurl(body: utf8.encode('{"tag_name":"v9"}'));
      final NativeGet get = curlNativeGet(curlPath: curl.path, run: fake.run)!;
      final Uri url = Uri.parse(
        'https://api.github.com/repos/x/y/releases/latest',
      );

      final http.Response res = await get(
        url,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        timeout: const Duration(seconds: 10),
      );

      expect(res.statusCode, 200);
      expect(utf8.decode(res.bodyBytes), '{"tag_name":"v9"}');

      expect(fake.calls.single.executable, curl.path);
      final List<String> args = fake.calls.single.arguments;
      expect(args.last, url.toString(), reason: 'the URL goes last');
      // Silent but not mute, and following the 302 the installer asset makes
      // to objects.githubusercontent.com.
      expect(args, containsAllInOrder(<String>['-sS', '-L']));
      expect(fake.argAfter('--max-time'), '10');
      expect(fake.argAfter('--connect-timeout'), '10');
      expect(fake.argAfter('--speed-limit'), '1');
      expect(
        fake.argAfter('--speed-time'),
        '${kDownloadStallTimeout.inSeconds}',
      );
      expect(fake.argAfter('-w'), '%{http_code}');
      final List<String> headers = <String>[
        for (int i = 0; i < args.length; i++)
          if (args[i] == '-H') args[i + 1],
      ];
      expect(headers, <String>[
        'Accept: application/vnd.github+json',
        'X-GitHub-Api-Version: 2022-11-28',
      ]);
      // Never `-k`: the fallback trusts what Windows trusts, not everything.
      expect(args, isNot(contains('-k')));
      expect(args, isNot(contains('--insecure')));
      // The scratch file a small response was read from is gone again.
      expect(File(fake.argAfter('-o')!).existsSync(), isFalse);
    });

    test(
      'a download goes into the file it was given, with no deadline',
      () async {
        final fake = _FakeCurl(body: const <int>[1, 2, 3, 4]);
        final NativeGet get = curlNativeGet(
          curlPath: curl.path,
          run: fake.run,
        )!;
        final File to = File('${tmp.path}${Platform.pathSeparator}setup.exe');

        final http.Response res = await get(
          Uri.parse('https://github.com/x/y/releases/download/v9/setup.exe'),
          to: to,
        );

        expect(res.statusCode, 200);
        expect(res.bodyBytes, isEmpty, reason: 'the body is in the file');
        expect(to.readAsBytesSync(), <int>[1, 2, 3, 4]);
        expect(fake.argAfter('-o'), to.path);
        expect(fake.argAfter('--max-time'), isNull);
        // ...but a stall still is one.
        expect(fake.argAfter('--speed-time'), isNotNull);
      },
    );

    test('an HTTP error is a status, not an exception', () async {
      final fake = _FakeCurl(stdout: '404');
      final NativeGet get = curlNativeGet(curlPath: curl.path, run: fake.run)!;
      final http.Response res = await get(Uri.parse('https://example.com/x'));
      expect(res.statusCode, 404);
    });

    // curl's own words are the diagnostic — `SEC_E_UNTRUSTED_ROOT` says more
    // than "exit 60" to whoever reads About.
    test(
      'a non-zero exit is an UpdateCheckException carrying stderr',
      () async {
        final fake = _FakeCurl(
          exitCode: 60,
          stdout: '000',
          stderr: 'curl: (60) schannel: SEC_E_UNTRUSTED_ROOT (0x80090325)',
        );
        final NativeGet get = curlNativeGet(
          curlPath: curl.path,
          run: fake.run,
        )!;
        await expectLater(
          get(Uri.parse('https://example.com/x')),
          throwsA(
            isA<UpdateCheckException>().having(
              (e) => e.message,
              'message',
              allOf(contains('60'), contains('SEC_E_UNTRUSTED_ROOT')),
            ),
          ),
        );
      },
    );

    test('an unreadable status is an UpdateCheckException', () async {
      final fake = _FakeCurl(stdout: 'garbage');
      final NativeGet get = curlNativeGet(curlPath: curl.path, run: fake.run)!;
      await expectLater(
        get(Uri.parse('https://example.com/x')),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    // The one test here that runs a real process: the curl.exe Windows
    // ships, against a loopback HTTP server. Not a TLS test — the point is
    // that the command line above is one that binary accepts, follows a
    // redirect with, and reports a status from.
    test(
      'the real curl.exe answers a loopback request through this shape',
      () async {
        final HttpServer server = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => server.close(force: true));
        final List<String> seenAccept = <String>[];
        server.listen((HttpRequest req) async {
          seenAccept.add(req.headers.value('accept') ?? '');
          if (req.uri.path == '/redirect') {
            await req.response.redirect(
              Uri.parse('http://127.0.0.1:${server.port}/final'),
            );
            return;
          }
          if (req.uri.path == '/missing') req.response.statusCode = 404;
          req.response.write(req.uri.path == '/final' ? 'arrived' : '');
          await req.response.close();
        });
        final String base = 'http://127.0.0.1:${server.port}';
        final NativeGet get = curlNativeGet(curlPath: windowsCurlPath())!;

        final http.Response ok = await get(
          Uri.parse('$base/redirect'),
          headers: const {'Accept': 'application/vnd.github+json'},
          timeout: const Duration(seconds: 10),
        );
        expect(ok.statusCode, 200);
        expect(ok.body, 'arrived');
        expect(seenAccept, everyElement('application/vnd.github+json'));

        final http.Response missing = await get(Uri.parse('$base/missing'));
        expect(missing.statusCode, 404);
      },
      skip: File(windowsCurlPath()).existsSync()
          ? false
          : 'no ${windowsCurlPath()} on this machine',
    );
  });

  group('the production wiring of the native transport', () {
    test('the shipped fallback is curl.exe on Windows', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final NativeGet? native = container.read(nativeGetProvider);
      expect(
        native,
        Platform.isWindows && File(windowsCurlPath()).existsSync()
            ? isNotNull
            : isNull,
      );
    });

    // A check that only got through natively hands its release to a download
    // that must not try Dart first: the flag on the release is what carries
    // that across the two seams.
    test('a release found natively is downloaded natively', () async {
      final List<({Uri url, File? to})> calls = [];
      final container = ProviderContainer(
        overrides: [
          updateFeedUrlProvider.overrideWithValue(null),
          nativeGetProvider.overrideWithValue((
            Uri url, {
            Map<String, String> headers = const {},
            Duration? timeout,
            File? to,
          }) async {
            calls.add((url: url, to: to));
            return http.Response('', 200);
          }),
        ],
      );
      addTearDown(container.dispose);

      final Uri installer = Uri.parse(
        // A host that does not resolve: reaching Dart's client here would
        // fail, and the assertion is that it is never reached.
        'https://installer.invalid/python_teacher_install.exe',
      );
      final File file = await container
          .read(updateServicesProvider)
          .download(
            UpdateInfo('9.0.0', installer, 'abc', viaNativeTransport: true),
            (_) {},
          );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      expect(calls, hasLength(1));
      expect(calls.single.url, installer);
      expect(calls.single.to?.path, file.path);
    });
  });

  test(
    'the production run seam launches the downloaded file with them',
    () async {
      final calls = <({String executable, List<String> arguments})>[];
      final container = ProviderContainer(
        overrides: [
          // No feed: this test is about the handover, and an unoverridden feed
          // URL would point the services at the real GitHub API.
          updateFeedUrlProvider.overrideWithValue(null),
          installerLauncherProvider.overrideWithValue((
            executable,
            arguments,
          ) async {
            calls.add((executable: executable, arguments: arguments));
          }),
        ],
      );
      addTearDown(container.dispose);

      final installer = File('C:\\Temp\\python_teacher_install.exe');
      await container.read(updateServicesProvider).run(installer);

      expect(calls, hasLength(1));
      expect(calls.single.executable, installer.path);
      expect(calls.single.arguments, kSilentInstallArguments);
    },
  );
}
