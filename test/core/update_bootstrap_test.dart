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
//
// #133: the proxy both transports are handed. The command line grows a
// `--proxy` when the machine states one; the setting is resolved from the
// environment first and Internet Options second, with the registry read
// behind a seam; and the production provider is driven with the real
// `curl.exe` through a loopback proxy, which is the only way to see that the
// binary Windows ships accepts what it is given.
//
// #135: the third source, a PAC script or WPAD, resolved through WinHTTP.
// The ordering and the cap on a slow script are pinned with fake seams and
// strings; the bindings themselves — the one part a fake cannot vouch for —
// are driven for real against a loopback PAC server, the way the e2e flow
// drives the whole app.
//
// #140: a proxy that authenticates. The command line grows
// `--proxy-anyauth --proxy-user :` beside `--proxy` — curl's spelling of
// "answer the challenge as the logged-in Windows user" — and the real binary
// is driven through a loopback proxy that demands a login, which is the only
// way to see that it answers one at all.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/update_proxy.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/loopback_proxy.dart';
import '../helpers/loopback_tls.dart';

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
      // No proxy was stated, so none is passed — curl's own reading of the
      // environment is left alone — and no proxy login either (#140).
      expect(args, isNot(contains('--proxy')));
      expect(args, isNot(contains('--proxy-anyauth')));
      expect(args, isNot(contains('--proxy-user')));
      // The scratch file a small response was read from is gone again.
      expect(File(fake.argAfter('-o')!).existsSync(), isFalse);
    });

    // #133: curl.exe reads https_proxy from the environment by itself but
    // never Internet Options, so the proxy the app resolved is passed
    // explicitly — the same one Dart's client is configured with.
    test('passes the machine proxy as --proxy', () async {
      final fake = _FakeCurl();
      final NativeGet get = curlNativeGet(
        curlPath: curl.path,
        run: fake.run,
        proxy: () => UpdateProxy(Uri.parse('http://proxy.school.be:8080')),
      )!;
      await get(Uri.parse('https://api.github.com/x'));
      expect(fake.argAfter('--proxy'), 'http://proxy.school.be:8080');
    });

    test('leaves --proxy off for a host on the bypass list', () async {
      final fake = _FakeCurl();
      final NativeGet get = curlNativeGet(
        curlPath: curl.path,
        run: fake.run,
        proxy: () => UpdateProxy(
          Uri.parse('http://proxy.school.be:8080'),
          bypass: const <String>['*.github.com'],
        ),
      )!;
      await get(Uri.parse('https://api.github.com/x'));
      expect(fake.calls.single.arguments, isNot(contains('--proxy')));
      expect(fake.calls.single.arguments, isNot(contains('--proxy-user')));
    });

    // #140: a proxy that authenticates answers the CONNECT with a 407.
    // `--proxy-anyauth` lets curl pick what the proxy offers (Negotiate,
    // NTLM); `--proxy-user :` — a bare colon — is the documented way to have
    // an SSPI build answer as the logged-in Windows user. Nothing is stored
    // or passed: the colon is the whole credential.
    test('answers a proxy login challenge as the Windows user', () async {
      final fake = _FakeCurl();
      final NativeGet get = curlNativeGet(
        curlPath: curl.path,
        run: fake.run,
        proxy: () => UpdateProxy(Uri.parse('http://proxy.school.be:8080')),
      )!;
      await get(Uri.parse('https://api.github.com/x'));
      expect(
        fake.calls.single.arguments,
        containsAllInOrder(<String>[
          '--proxy',
          'http://proxy.school.be:8080',
          '--proxy-anyauth',
          '--proxy-user',
          ':',
        ]),
      );
      expect(fake.argAfter('--proxy-user'), ':');
    });

    // A login stated in the proxy URL (`https_proxy=http://user:pw@…`) is
    // the one curl is left to send, as Dart's client sends it: a
    // `--proxy-user` would replace it with the empty one.
    test('keeps a login the proxy URL states, and adds none', () async {
      final fake = _FakeCurl();
      final NativeGet get = curlNativeGet(
        curlPath: curl.path,
        run: fake.run,
        proxy: () => UpdateProxy(
          Uri.parse('http://student:secret@proxy.school.be:8080'),
        ),
      )!;
      await get(Uri.parse('https://api.github.com/x'));
      final List<String> args = fake.calls.single.arguments;
      expect(
        fake.argAfter('--proxy'),
        'http://student:secret@proxy.school.be:8080',
      );
      expect(args, isNot(contains('--proxy-anyauth')));
      expect(args, isNot(contains('--proxy-user')));
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

  // #133, #135: where the proxy comes from. The parsers have their own tests
  // (update_proxy_test.dart); these pin the order and the seams.
  group('systemUpdateProxy', () {
    final Uri target = Uri.parse(
      'https://api.github.com/repos/yvanvds/AI-tutor-Python/releases/latest',
    );
    const InternetSettingsProxy schoolProxy = (
      enabled: true,
      server: 'proxy.school.be:8080',
      override: '<local>',
    );
    const InternetSettingsProxy noExplicitProxy = (
      enabled: false,
      server: null,
      override: null,
    );
    const AutoProxyConfig noAutoProxy = (autoDetect: false, configUrl: null);
    const AutoProxyConfig schoolPac = (
      autoDetect: false,
      configUrl: 'http://proxy.school.be/proxy.pac',
    );

    /// A WinHTTP that records what it was asked and answers with [result].
    ({AutoProxyResolver resolve, List<(Uri, AutoProxyConfig)> asked})
    fakeWinHttp(FutureOr<AutoProxyResult> Function() result) {
      final List<(Uri, AutoProxyConfig)> asked = [];
      return (
        resolve: (Uri url, AutoProxyConfig config) async {
          asked.add((url, config));
          return result();
        },
        asked: asked,
      );
    }

    test('the environment wins, and nothing else is even read', () async {
      var reads = 0;
      final winHttp = fakeWinHttp(() => (proxy: 'pac-proxy:1', bypass: null));
      final proxy = await systemUpdateProxy(
        target,
        environment: const {'https_proxy': 'http://env-proxy:3128'},
        internetSettings: () {
          reads++;
          return schoolProxy;
        },
        autoProxyConfig: () {
          reads++;
          return schoolPac;
        },
        autoProxy: winHttp.resolve,
        windows: true,
      );
      expect(proxy?.url, Uri.parse('http://env-proxy:3128'));
      expect(reads, 0);
      expect(winHttp.asked, isEmpty);
    });

    test('with nothing in the environment, an explicit Internet Options proxy '
        'decides, and the script is not asked', () async {
      final winHttp = fakeWinHttp(() => (proxy: 'pac-proxy:1', bypass: null));
      final proxy = await systemUpdateProxy(
        target,
        environment: const {},
        internetSettings: () => schoolProxy,
        autoProxyConfig: () => schoolPac,
        autoProxy: winHttp.resolve,
        windows: true,
      );
      expect(proxy?.url, Uri.parse('http://proxy.school.be:8080'));
      expect(proxy?.bypass, <String>['<local>']);
      expect(winHttp.asked, isEmpty);
    });

    // #135: the case the issue is about — a school that publishes its proxy
    // only as a script. WinHTTP is asked for the endpoint, with the script
    // Internet Options name, and its answer is read like ProxyServer.
    test(
      'with no explicit proxy, the PAC script names one for the endpoint',
      () async {
        final winHttp = fakeWinHttp(
          () => (proxy: 'filter.school.be:3128', bypass: '<local>;*.school.be'),
        );
        final proxy = await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () => noExplicitProxy,
          autoProxyConfig: () => schoolPac,
          autoProxy: winHttp.resolve,
          windows: true,
        );
        expect(proxy?.url, Uri.parse('http://filter.school.be:3128'));
        expect(proxy?.bypass, <String>['<local>', '*.school.be']);
        expect(winHttp.asked, [(target, schoolPac)]);
      },
    );

    test('WPAD alone is enough to ask', () async {
      const AutoProxyConfig wpad = (autoDetect: true, configUrl: null);
      final winHttp = fakeWinHttp(
        () => (proxy: 'wpad-proxy:8080', bypass: null),
      );
      final proxy = await systemUpdateProxy(
        target,
        environment: const {},
        internetSettings: () => noExplicitProxy,
        autoProxyConfig: () => wpad,
        autoProxy: winHttp.resolve,
        windows: true,
      );
      expect(proxy?.url, Uri.parse('http://wpad-proxy:8080'));
      expect(winHttp.asked, [(target, wpad)]);
    });

    // The Windows default — neither box ticked — costs no WinHTTP session.
    test('with neither box ticked, WinHTTP is not asked', () async {
      final winHttp = fakeWinHttp(() => (proxy: 'pac-proxy:1', bypass: null));
      expect(
        await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () => noExplicitProxy,
          autoProxyConfig: () => noAutoProxy,
          autoProxy: winHttp.resolve,
          windows: true,
        ),
        isNull,
      );
      expect(winHttp.asked, isEmpty);
    });

    test('a script that says DIRECT is no proxy', () async {
      final winHttp = fakeWinHttp(() => (proxy: null, bypass: null));
      expect(
        await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () => noExplicitProxy,
          autoProxyConfig: () => schoolPac,
          autoProxy: winHttp.resolve,
          windows: true,
        ),
        isNull,
      );
    });

    // A script WinHTTP could not fetch or run — the URL is stale, the server
    // is down, WPAD found nothing — is the network as it was before #135:
    // the check goes direct, and does not die over it.
    test('a script WinHTTP cannot resolve counts as no proxy', () async {
      final winHttp = fakeWinHttp(
        () => throw StateError(
          'WinHttpGetProxyForUrl failed: error 12167 '
          '(ERROR_WINHTTP_UNABLE_TO_DOWNLOAD_SCRIPT)',
        ),
      );
      expect(
        await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () => noExplicitProxy,
          autoProxyConfig: () => schoolPac,
          autoProxy: winHttp.resolve,
          windows: true,
        ),
        isNull,
      );
      expect(winHttp.asked, hasLength(1));
    });

    // The one the issue insists on: a script server that accepts and never
    // answers must not hold the check. The cap is applied to whatever the
    // seam returns, so a never-completing fake pins it.
    test('a script that does not answer in time counts as no proxy', () async {
      final winHttp = fakeWinHttp(() => Completer<AutoProxyResult>().future);
      final Stopwatch clock = Stopwatch()..start();
      expect(
        await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () => noExplicitProxy,
          autoProxyConfig: () => schoolPac,
          autoProxy: winHttp.resolve,
          autoProxyTimeout: const Duration(milliseconds: 200),
          windows: true,
        ),
        isNull,
      );
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('off Windows there are no Internet Options to read', () async {
      var reads = 0;
      final winHttp = fakeWinHttp(() => (proxy: 'pac-proxy:1', bypass: null));
      expect(
        await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () {
            reads++;
            return schoolProxy;
          },
          autoProxyConfig: () {
            reads++;
            return schoolPac;
          },
          autoProxy: winHttp.resolve,
          windows: false,
        ),
        isNull,
      );
      expect(reads, 0);
      expect(winHttp.asked, isEmpty);
    });

    // The update check must not die over its own diagnostics.
    test('a registry read that throws counts as no explicit proxy', () async {
      final winHttp = fakeWinHttp(() => (proxy: 'pac-proxy:1', bypass: null));
      expect(
        await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () => throw StateError('registry unavailable'),
          autoProxyConfig: () => noAutoProxy,
          autoProxy: winHttp.resolve,
          windows: true,
        ),
        isNull,
      );
    });

    test('an auto-proxy setting that cannot be read counts as none', () async {
      final winHttp = fakeWinHttp(() => (proxy: 'pac-proxy:1', bypass: null));
      expect(
        await systemUpdateProxy(
          target,
          environment: const {},
          internetSettings: () => noExplicitProxy,
          autoProxyConfig: () => throw StateError('WinHTTP unavailable'),
          autoProxy: winHttp.resolve,
          windows: true,
        ),
        isNull,
      );
      expect(winHttp.asked, isEmpty);
    });

    // The real reads, against whatever this machine has: they must come
    // back with a well-formed record rather than throw, whether or not a
    // proxy is set here. What the records mean is pinned above and in
    // update_proxy_test.dart.
    test('the registry read answers on this machine', () {
      final InternetSettingsProxy settings = readInternetSettingsProxy();
      expect(settings.enabled, isA<bool>());
      if (settings.server != null) {
        expect(settings.server, isNotEmpty);
      }
    }, skip: Platform.isWindows ? false : 'Internet Options are Windows-only');

    test('the WinHTTP configuration read answers on this machine', () {
      final AutoProxyConfig config = readAutoProxyConfig();
      expect(config.autoDetect, isA<bool>());
      if (config.configUrl != null) {
        expect(config.configUrl, isNotEmpty);
      }
    }, skip: Platform.isWindows ? false : 'WinHTTP is Windows-only');

    // The bindings for real: the WinHTTP Windows ships fetches a script
    // from a loopback server, evaluates it for two URLs, and hands back the
    // proxy for one and DIRECT for the other. Not a network test — the
    // point is that the structs, flags and strings crossing the FFI
    // boundary are the ones WinHTTP expects, which no fake can vouch for.
    test(
      'the real WinHTTP evaluates a loopback script through this shape',
      () async {
        final LoopbackPacServer pac = await LoopbackPacServer.start(
          script: pacScript(
            proxy: '127.0.0.1:8080',
            direct: const <String>['direct.school.be'],
          ),
        );
        addTearDown(pac.close);
        final AutoProxyConfig config = (
          autoDetect: false,
          configUrl: pac.url.toString(),
        );

        final AutoProxyResult proxied = await resolveAutoProxy(
          Uri.parse('https://api.github.com/repos/x/y/releases/latest'),
          config,
        );
        expect(proxied.proxy, '127.0.0.1:8080');
        expect(pac.fetches, greaterThanOrEqualTo(1));

        final AutoProxyResult direct = await resolveAutoProxy(
          Uri.parse('https://direct.school.be/'),
          config,
        );
        expect(direct.proxy, isNull);
      },
      skip: Platform.isWindows ? false : 'WinHTTP is Windows-only',
    );

    // A script URL nobody serves: WinHTTP must say so, not hang, and must
    // say so as an error the resolver surfaces rather than a proxy of none.
    test('the real WinHTTP reports a script it cannot download', () async {
      // A port that was listening a moment ago and is not any more.
      final ServerSocket gone = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int port = gone.port;
      await gone.close();
      await expectLater(
        resolveAutoProxy(Uri.parse('https://api.github.com/'), (
          autoDetect: false,
          configUrl: 'http://127.0.0.1:$port/proxy.pac',
        )),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('WinHttpGetProxyForUrl'),
          ),
        ),
      );
    }, skip: Platform.isWindows ? false : 'WinHTTP is Windows-only');
  });

  group('the production proxy provider', () {
    // With the feed off there is nothing to reach: no registry, no WinHTTP,
    // no wait — which is also what keeps every test boot off the machine's
    // setting without an override.
    test('resolves to no proxy without touching anything when the feed is '
        'off', () async {
      final container = ProviderContainer(
        overrides: [updateFeedUrlProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      expect(await container.read(updateProxyProvider)(), isNull);
    });

    // Reading the wiring is not a request: nothing is resolved until one
    // asks, and then once — so a debug launch that never checks never
    // probes WinHTTP, and the release, the checksum and the installer share
    // one answer rather than three lookups.
    test('resolves lazily, and once', () async {
      final container = ProviderContainer(
        overrides: [
          updateFeedUrlProvider.overrideWithValue(
            Uri.parse('https://example.com/releases/latest'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final UpdateProxyLookup lookup = container.read(updateProxyProvider);
      // Two calls, one future: the memo is the whole guarantee, and it is
      // observable without knowing what this machine would resolve to.
      expect(identical(lookup(), lookup()), isTrue);
    });
  });

  group('the production wiring of the native transport', () {
    test('the shipped fallback is curl.exe on Windows', () {
      final container = ProviderContainer(
        overrides: [
          updateProxyProvider.overrideWithValue(fixedUpdateProxy(null)),
        ],
      );
      addTearDown(container.dispose);
      final NativeGet? native = container.read(nativeGetProvider);
      expect(
        native,
        Platform.isWindows && File(windowsCurlPath()).existsSync()
            ? isNotNull
            : isNull,
      );
    });

    // #133, with the real binary: the shipped fallback, built by the
    // production provider from the proxy the app resolved, reaches a server
    // that is only there through the proxy. The URL names a black hole — a
    // direct dial connects and then hears nothing, which is what a
    // firewalled route looks like — and the proxy routes that same address
    // to a loopback TLS server. Schannel then refuses the loopback
    // certificate, as it must (it is in no store); that refusal is the
    // proof: the handshake happened with the routed server, not the hole.
    // Without `--proxy` curl waits on the hole until `--max-time` and reports
    // a timeout instead, and the proxy sees no CONNECT.
    test(
      'the shipped fallback goes through the machine proxy',
      () async {
        final BlackHole hole = await BlackHole.start();
        addTearDown(hole.close);
        final HttpServer server = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          SecurityContext()
            ..useCertificateChainBytes(utf8.encode(kLoopbackCertificatePem))
            ..usePrivateKeyBytes(utf8.encode(kLoopbackPrivateKeyPem)),
        );
        addTearDown(() => server.close(force: true));
        server.listen((HttpRequest req) => req.response.close());
        final LoopbackProxy proxy = await LoopbackProxy.start(
          routes: <String, String>{
            hole.authority: '${server.address.address}:${server.port}',
          },
        );
        addTearDown(proxy.close);

        final container = ProviderContainer(
          overrides: [
            updateProxyProvider.overrideWithValue(
              fixedUpdateProxy(proxy.updateProxy),
            ),
          ],
        );
        addTearDown(container.dispose);
        final NativeGet native = container.read(nativeGetProvider)!;

        await expectLater(
          native(
            Uri.parse('https://${hole.authority}/releases/latest'),
            timeout: const Duration(seconds: 5),
          ),
          throwsA(
            isA<UpdateCheckException>().having(
              (e) => e.message,
              'message',
              allOf(contains('exited with 60'), isNot(contains('timed out'))),
            ),
          ),
        );
        expect(proxy.connects, <String>[hole.authority]);
        expect(hole.connections, 0, reason: 'curl dialled the hole directly');
      },
      skip: Platform.isWindows && File(windowsCurlPath()).existsSync()
          ? false
          : 'no ${windowsCurlPath()} on this machine',
    );

    // #140, with the real binary: the same proxy, now demanding a login on
    // the CONNECT with a `Negotiate` challenge, as a school's AD-joined
    // filter does. The shipped fallback, built by the production provider
    // with a proxy that names no login, has to answer by itself —
    // `--proxy-anyauth --proxy-user :` makes SSPI answer as the logged-in
    // Windows user — and the proof is the same as above: Schannel's refusal
    // of the loopback certificate means the authenticated CONNECT was
    // tunnelled to the routed server. Without those switches curl gives up
    // on the 407 with exit 7 ("CONNECT tunnel failed, response 407") and
    // never meets a certificate at all. What SSPI produces on a machine
    // outside any domain is NTLM's first message for the local account —
    // enough to see the challenge answered with the Windows session, which
    // is all a test without a domain can see; the proxy accepts that first
    // leg without verifying it.
    test(
      'the shipped fallback answers the machine proxy\'s login challenge',
      () async {
        final BlackHole hole = await BlackHole.start();
        addTearDown(hole.close);
        final HttpServer server = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          SecurityContext()
            ..useCertificateChainBytes(utf8.encode(kLoopbackCertificatePem))
            ..usePrivateKeyBytes(utf8.encode(kLoopbackPrivateKeyPem)),
        );
        addTearDown(() => server.close(force: true));
        server.listen((HttpRequest req) => req.response.close());
        final LoopbackProxy proxy = await LoopbackProxy.start(
          routes: <String, String>{
            hole.authority: '${server.address.address}:${server.port}',
          },
          requireLogin: true,
        );
        addTearDown(proxy.close);

        final container = ProviderContainer(
          overrides: [
            updateProxyProvider.overrideWithValue(
              fixedUpdateProxy(proxy.updateProxy),
            ),
          ],
        );
        addTearDown(container.dispose);
        final NativeGet native = container.read(nativeGetProvider)!;

        await expectLater(
          native(
            Uri.parse('https://${hole.authority}/releases/latest'),
            timeout: const Duration(seconds: 5),
          ),
          throwsA(
            isA<UpdateCheckException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('exited with 60'),
                isNot(contains('407')),
                isNot(contains('timed out')),
              ),
            ),
          ),
        );
        // Challenged once, answered once — both CONNECTs for the same target
        // — and answered with an SSPI token, not with any stored login.
        expect(proxy.challenges, 1);
        expect(proxy.logins, hasLength(1));
        expect(proxy.logins.single, startsWith('Negotiate '));
        expect(proxy.connects, <String>[hole.authority, hole.authority]);
        expect(hole.connections, 0, reason: 'curl dialled the hole directly');
      },
      skip: Platform.isWindows && File(windowsCurlPath()).existsSync()
          ? false
          : 'no ${windowsCurlPath()} on this machine',
    );

    // A check that only got through natively hands its release to a download
    // that must not try Dart first: the flag on the release is what carries
    // that across the two seams.
    test('a release found natively is downloaded natively', () async {
      final List<({Uri url, File? to})> calls = [];
      final container = ProviderContainer(
        overrides: [
          updateFeedUrlProvider.overrideWithValue(null),
          // Not this machine's setting: the download must be deterministic.
          updateProxyProvider.overrideWithValue(fixedUpdateProxy(null)),
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
          updateProxyProvider.overrideWithValue(fixedUpdateProxy(null)),
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
