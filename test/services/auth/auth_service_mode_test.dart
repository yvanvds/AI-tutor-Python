// #262: sign-in follows the app mode. School mode signs in with the school
// configuration and keeps its tokens where they always were, so existing
// installs stay signed in; stand-alone mode has no sign-in and leaves the
// school's tokens alone.
//
// #264: stand-alone mode has a local profile instead: stored under its own
// scope, read back on the next start, never a teacher, and no sign-out.

import 'dart:convert';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/auth/local_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_app_mode.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

final String _storedTokens = jsonEncode({
  'access_token': 'old-access',
  'refresh_token': 'stored-refresh',
  'id_token': null,
  'access_token_expiry': null,
});

void main() {
  test('school mode refreshes the tokens an existing install stored', () async {
    SharedPreferences.setMockInitialValues({
      'azure_auth_tokens_v1': _storedTokens,
    });
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode({
          'access_token': 'new-access',
          'refresh_token': 'new-refresh',
          'id_token': _jwt({'oid': 'oid-1', 'name': 'Sam Example'}),
          'expires_in': 3600,
        }),
        200,
      );
    });
    final container = ProviderContainer(
      overrides: [appModeProvider.overrideWithValue(kTestSchoolMode)],
    );
    addTearDown(container.dispose);

    await http.runWithClient(
      () =>
          container.read(authServiceProvider.notifier).tryAcquireTokenSilent(),
      () => client,
    );

    expect(requests, hasLength(1));
    expect(requests.single.url.path, contains(kTestSchool.tenantId));
    expect(requests.single.bodyFields['client_id'], kTestSchool.clientId);
    expect(requests.single.bodyFields['refresh_token'], 'stored-refresh');
    expect(container.read(authServiceProvider)?.oid, 'oid-1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('azure_auth_tokens_v1'), contains('new-refresh'));
  });

  test(
    "stand-alone mode signs no one in and keeps the school's tokens",
    () async {
      SharedPreferences.setMockInitialValues({
        'azure_auth_tokens_v1': _storedTokens,
      });
      final client = MockClient((_) async => fail('no request expected'));
      final container = ProviderContainer(
        overrides: [appModeProvider.overrideWithValue(const StandaloneMode())],
      );
      addTearDown(container.dispose);

      await http.runWithClient(
        () => container
            .read(authServiceProvider.notifier)
            .tryAcquireTokenSilent(),
        () => client,
      );

      expect(container.read(authServiceProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('azure_auth_tokens_v1'), _storedTokens);
      await expectLater(
        container.read(authServiceProvider.notifier).signIn(),
        throwsStateError,
      );
    },
  );

  group('stand-alone local profile (#264)', () {
    ProviderContainer standalone() {
      final c = ProviderContainer(
        overrides: [appModeProvider.overrideWithValue(const StandaloneMode())],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a first start has no profile, so no identity', () async {
      SharedPreferences.setMockInitialValues({});
      final c = standalone();
      await c.read(authServiceProvider.notifier).tryAcquireTokenSilent();
      expect(c.read(authServiceProvider), isNull);
    });

    test(
      'a saved profile is the identity, now and on the next start',
      () async {
        SharedPreferences.setMockInitialValues({});
        final profile = LocalProfile.create(firstName: ' Alex ', lastName: '');
        final first = standalone();
        await first.read(authServiceProvider.notifier).useLocalProfile(profile);

        final identity = first.read(authServiceProvider)!;
        expect(identity.oid, profile.uid);
        expect(identity.firstName, 'Alex');
        expect(identity.displayName, 'Alex');
        expect(identity.email, '');
        expect(identity.isTeacher, isFalse);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getKeys(), {'standalone.local_profile_v1'});

        // The next start.
        final second = standalone();
        await second.read(authServiceProvider.notifier).tryAcquireTokenSilent();
        expect(second.read(authServiceProvider), identity);
      },
    );

    test('sign-out keeps the profile', () async {
      SharedPreferences.setMockInitialValues({});
      final c = standalone();
      final auth = c.read(authServiceProvider.notifier);
      await auth.useLocalProfile(LocalProfile.create(firstName: 'Alex'));
      await auth.signOut();
      expect(c.read(authServiceProvider)?.firstName, 'Alex');
      expect(await auth.loadLocalProfile(), isNotNull);
    });

    test('school mode has no local profile', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(
        overrides: [appModeProvider.overrideWithValue(kTestSchoolMode)],
      );
      addTearDown(c.dispose);
      await expectLater(
        c
            .read(authServiceProvider.notifier)
            .useLocalProfile(LocalProfile.create(firstName: 'Alex')),
        throwsStateError,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('an unreadable profile counts as none', () async {
      SharedPreferences.setMockInitialValues({
        'standalone.local_profile_v1': 'not json',
      });
      final c = standalone();
      await c.read(authServiceProvider.notifier).tryAcquireTokenSilent();
      expect(c.read(authServiceProvider), isNull);
    });
  });
}
