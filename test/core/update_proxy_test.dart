// #133: the proxy setting the updater honours — read from the environment
// or from Internet Options — and what it hands each transport. These pin the
// parsing of the two on-disk shapes, the bypass rules, and the two spellings
// (`HttpClient.findProxy`'s and `curl --proxy`'s) that have to agree.

import 'package:ai_tutor_python/core/update_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final Uri github = Uri.parse(
    'https://api.github.com/repos/yvanvds/AI-tutor-Python/releases/latest',
  );

  group('proxyFromInternetSettings', () {
    test('one proxy for every protocol', () {
      final proxy = proxyFromInternetSettings((
        enabled: true,
        server: 'proxy.school.be:8080',
        override: null,
      ));
      expect(proxy?.url, Uri.parse('http://proxy.school.be:8080'));
      expect(proxy?.bypass, isEmpty);
    });

    test('is off when ProxyEnable is not 1, whatever ProxyServer says', () {
      expect(
        proxyFromInternetSettings((
          enabled: false,
          server: 'proxy.school.be:8080',
          override: '<local>',
        )),
        isNull,
      );
    });

    test('is off when ProxyServer is missing or blank', () {
      expect(
        proxyFromInternetSettings((
          enabled: true,
          server: null,
          override: null,
        )),
        isNull,
      );
      expect(
        proxyFromInternetSettings((
          enabled: true,
          server: '  ',
          override: null,
        )),
        isNull,
      );
    });

    // "Use the same proxy server for all protocols" unticked: WinINET
    // applies the https= entry to HTTPS and nothing else.
    test('takes the https= entry of a per-protocol list', () {
      final proxy = proxyFromInternetSettings((
        enabled: true,
        server:
            'http=proxy.school.be:8080;https=secure.school.be:8443;'
            'ftp=proxy.school.be:21',
        override: null,
      ));
      expect(proxy?.url, Uri.parse('http://secure.school.be:8443'));
    });

    test('a per-protocol list without https= names no proxy for HTTPS', () {
      expect(
        proxyFromInternetSettings((
          enabled: true,
          server: 'http=proxy.school.be:8080',
          override: null,
        )),
        isNull,
      );
    });

    test('tolerates a scheme in front and no port behind', () {
      expect(
        proxyFromInternetSettings((
          enabled: true,
          server: 'http://proxy.school.be',
          override: null,
        ))?.url,
        Uri.parse('http://proxy.school.be:80'),
      );
      expect(
        proxyFromInternetSettings((
          enabled: true,
          server: 'https=https://proxy.school.be:3128/',
          override: null,
        ))?.url,
        Uri.parse('http://proxy.school.be:3128'),
      );
    });

    test('ProxyOverride becomes the bypass list, entry by entry', () {
      final proxy = proxyFromInternetSettings((
        enabled: true,
        server: 'proxy.school.be:8080',
        override: '*.school.be;10.*;<local>',
      ));
      expect(proxy?.bypass, <String>['*.school.be', '10.*', '<local>']);
    });
  });

  group('proxyFromEnvironment', () {
    test('reads https_proxy in either case, URL or bare address', () {
      expect(
        proxyFromEnvironment(const {
          'https_proxy': 'http://proxy.school.be:8080',
        })?.url,
        Uri.parse('http://proxy.school.be:8080'),
      );
      expect(
        proxyFromEnvironment(const {'HTTPS_PROXY': 'proxy.school.be:8080'})
            ?.url,
        Uri.parse('http://proxy.school.be:8080'),
      );
    });

    test('falls back to all_proxy', () {
      expect(
        proxyFromEnvironment(const {'ALL_PROXY': 'http://proxy.school.be:8080'})
            ?.url,
        Uri.parse('http://proxy.school.be:8080'),
      );
    });

    // http_proxy is for http:// URLs, and the updater has none.
    test('ignores http_proxy on its own', () {
      expect(
        proxyFromEnvironment(const {'http_proxy': 'http://proxy:8080'}),
        isNull,
      );
    });

    test('is none when nothing is set or the value is blank', () {
      expect(proxyFromEnvironment(const {}), isNull);
      expect(proxyFromEnvironment(const {'https_proxy': ''}), isNull);
      expect(proxyFromEnvironment(const {'https_proxy': '   '}), isNull);
    });

    // Neither transport speaks SOCKS; pretending otherwise would turn a
    // working direct connection into a failing one.
    test('a SOCKS proxy counts as none', () {
      expect(
        proxyFromEnvironment(const {'all_proxy': 'socks5://proxy:1080'}),
        isNull,
      );
    });

    test('keeps credentials, and defaults the port to 1080 as curl does', () {
      final proxy = proxyFromEnvironment(const {
        'https_proxy': 'http://student:secret@proxy.school.be',
      });
      expect(
        proxy?.url,
        Uri.parse('http://student:secret@proxy.school.be:1080'),
      );
    });

    test('no_proxy becomes the bypass list', () {
      final proxy = proxyFromEnvironment(const {
        'https_proxy': 'http://proxy:8080',
        'NO_PROXY': 'localhost,.school.be, 127.0.0.1',
      });
      expect(proxy?.bypass, <String>['localhost', '.school.be', ' 127.0.0.1']);
    });
  });

  group('UpdateProxy', () {
    final proxy = UpdateProxy(Uri.parse('http://proxy.school.be:8080'));

    test('spells itself the way HttpClient.findProxy wants', () {
      expect(proxy.findProxy(github), 'PROXY proxy.school.be:8080');
      expect(
        UpdateProxy(Uri.parse('http://student:secret@proxy.school.be:8080'))
            .findProxy(github),
        'PROXY student:secret@proxy.school.be:8080',
      );
    });

    test('spells itself the way curl --proxy wants', () {
      expect(proxy.curlProxyFor(github), 'http://proxy.school.be:8080');
    });

    // The password goes to the two transports and nowhere else: not into
    // the launch log, not into a bug report that quotes it.
    test('keeps its credentials out of a log line', () {
      final withCredentials = UpdateProxy(
        Uri.parse('http://student:secret@proxy.school.be:8080'),
        bypass: const ['<local>'],
      );
      expect(withCredentials.redactedUrl, 'http://proxy.school.be:8080');
      expect(withCredentials.toString(), isNot(contains('secret')));
      expect(
        withCredentials.toString(),
        'UpdateProxy(http://proxy.school.be:8080, bypass: [<local>])',
      );
      // ...while the transports still get them.
      expect(withCredentials.findProxy(github), contains('student:secret@'));
      expect(withCredentials.curlProxyFor(github), contains('student:secret@'));
    });

    group('bypasses', () {
      UpdateProxy withBypass(List<String> bypass) =>
          UpdateProxy(proxy.url, bypass: bypass);

      test('nothing without a list', () {
        expect(proxy.bypasses(github), isFalse);
        expect(proxy.bypasses(Uri.parse('https://intranet/')), isFalse);
      });

      test('<local> is a host without a dot', () {
        final p = withBypass(const ['<local>']);
        expect(p.bypasses(Uri.parse('https://intranet/')), isTrue);
        expect(p.bypasses(github), isFalse);
      });

      test('wildcards glob over the host', () {
        final p = withBypass(const ['*.school.be', '10.*']);
        expect(p.bypasses(Uri.parse('https://portal.school.be/')), isTrue);
        expect(p.bypasses(Uri.parse('http://10.0.0.7/')), isTrue);
        expect(p.bypasses(Uri.parse('https://school.be/')), isFalse);
        expect(p.bypasses(github), isFalse);
      });

      test('a plain entry matches the host and its subdomains', () {
        final p = withBypass(const ['github.com', '.example.org']);
        expect(p.bypasses(Uri.parse('https://github.com/')), isTrue);
        expect(p.bypasses(Uri.parse('https://api.github.com/')), isTrue);
        expect(p.bypasses(Uri.parse('https://www.example.org/')), isTrue);
        expect(p.bypasses(Uri.parse('https://notgithub.com/')), isFalse);
      });

      test('ignores a scheme, a port and case on the entry', () {
        final p = withBypass(const ['https://API.GitHub.com:443']);
        expect(p.bypasses(github), isTrue);
      });

      test('a lone * bypasses everything', () {
        expect(withBypass(const ['*']).bypasses(github), isTrue);
      });

      test('a bypassed host goes direct on both transports', () {
        final p = withBypass(const ['*.github.com']);
        expect(p.findProxy(github), 'DIRECT');
        expect(p.curlProxyFor(github), isNull);
      });
    });
  });
}
