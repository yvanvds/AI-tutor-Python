// Issue #126 — whose OpenAI key a call goes out on.
//
// Before: the connector set `Env.apiKey` (the school's bundled key) on every
// call, so an account made to enter its own key at the local-key gate was
// billed to the school regardless. Now:
//
//   - `tutorApiKeyProvider` decides per account: `mayUseGlobalKey` → the
//     school's key, with any leftover local key ignored; otherwise the key
//     stored on this device, or none;
//   - `resolveApiKey()` hands that key to every call — non-streaming,
//     streaming and the Test button's probe — and refuses the call outright
//     when the account has none, instead of falling back on the school's;
//   - a key OpenAI rejects (401) is reported against whoever owns it: the
//     student's own points at Options, the school's at the teacher.
//
// Issue #337 — where the school's key comes from. In the school mode it is
// `ApiKey` on `config/global`; `OPEN_AI_API_KEY` from `.env` is only the
// fallback for an empty field, and without one there is no fallback: the
// call is then refused with a notice that the school has no key, and no
// request goes out. While `config/global` has not been read, a call waits
// for it. The connector itself knows no key, and the three connectors take
// theirs from the same place.
//
// The wire-level tests drive the real connector over a scripted HTTP client
// and read the `Authorization` header the request actually carried.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:ai_tutor_python/services/grading/grade_proposal_service.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/openai_wiring.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_openai.dart';
import '../../helpers/test_app_mode.dart';

const _own = 'sk-own-key';
const _school = 'sk-school-key';

/// The fallback for the school's key (#337), as from `.env`.
const _fallback = 'sk-fallback-key';

/// `ApiKey` on `config/global` (#337).
const _configured = 'sk-config-key';

Account _account({required bool mayUseGlobalKey}) => Account(
  uid: 'u1',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  targetGoal: 'Python',
  mayUseGlobalKey: mayUseGlobalKey,
);

GlobalConfig _config(String apiKey) =>
    GlobalConfig(model: 'gpt-4o', apiKey: apiKey);

/// The signed-in account, already loaded — no Cosmos, no auth listener.
class _FixedAccount extends AccountService {
  _FixedAccount(this._account);
  final Account? _account;

  @override
  Account? build() => _account;
}

/// `config/global` without Cosmos: [polled] is what the poll has published
/// so far (`null`: nothing yet), [read] what a read of the doc answers —
/// the polled value unless a test makes it wait or fail.
class _Configs extends GlobalConfigService {
  _Configs(this._polled, {this.read});

  final GlobalConfig? _polled;
  final Future<GlobalConfig?> Function()? read;

  /// How often the doc was read outside the poll.
  int reads = 0;

  @override
  GlobalConfig? build() => _polled;

  @override
  Future<GlobalConfig?> getConfig() {
    reads++;
    return read?.call() ?? Future.value(_polled);
  }

  void publish(GlobalConfig? config) => state = config;
}

void main() {
  group('OpenaiConnector.resolveApiKey', () {
    test("the school's key when the account is on it", () async {
      final c = OpenaiConnector(getApiKey: () => const SchoolKey(_school));
      expect(await c.resolveApiKey(), _school);
    });

    test('the own key when the account is on its own', () async {
      final c = OpenaiConnector(getApiKey: () => const OwnKey(_own));
      expect(await c.resolveApiKey(), _own);
    });

    test('an own-key account with nothing stored is refused, never the '
        "school's key", () async {
      for (final source in const [OwnKey(null), OwnKey('')]) {
        final c = OpenaiConnector(getApiKey: () => source);
        await expectLater(
          c.resolveApiKey(),
          throwsA(
            isA<NoApiKeyException>().having((e) => e.source, 'source', source),
          ),
          reason: '$source',
        );
      }
    });

    test('an empty school key is refused too', () async {
      final c = OpenaiConnector(getApiKey: () => const SchoolKey(''));
      await expectLater(c.resolveApiKey(), throwsA(isA<NoApiKeyException>()));
    });

    test('without a seam there is no key: the connector reads none of its '
        'own (#337)', () async {
      await expectLater(
        OpenaiConnector().resolveApiKey(),
        throwsA(
          isA<NoApiKeyException>().having(
            (e) => e.source,
            'source',
            const SchoolKey(''),
          ),
        ),
      );
    });

    test('a key the seam answers later is waited for (#337)', () async {
      final key = Completer<ApiKeySource>();
      final c = OpenaiConnector(getApiKey: () => key.future);
      var resolved = false;
      final pending = c.resolveApiKey().whenComplete(() => resolved = true);
      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse);

      key.complete(const SchoolKey(_configured));
      expect(await pending, _configured);
    });
  });

  group('schoolKeyFrom (#337)', () {
    test('ApiKey on config/global comes first, also over the fallback', () {
      expect(
        schoolKeyFrom(_config(_configured), fallback: _fallback),
        const SchoolKey(_configured),
      );
      expect(schoolKeyFrom(_config(' $_configured\n')).key, _configured);
    });

    test('an empty field uses the fallback', () {
      for (final config in [_config(''), _config('  '), null]) {
        expect(
          schoolKeyFrom(config, fallback: _fallback),
          const SchoolKey(_fallback),
          reason: '$config',
        );
      }
    });

    test('an empty field without a fallback is no key', () {
      expect(schoolKeyFrom(_config('')), const SchoolKey(''));
      expect(schoolKeyFrom(null), const SchoolKey(''));
    });
  });

  group('fallbackSchoolApiKeyProvider (#337)', () {
    test('a placeholder or an empty value is no key: there is no '
        'fallback', () {
      // The values that make a build one without a school (CI's `.env`).
      for (final value in ['', '  ', 'dummy', 'DUMMY-key']) {
        expect(fallbackSchoolApiKeyFrom(value), isNull, reason: value);
      }
      expect(fallbackSchoolApiKeyFrom('sk-proj-abc'), 'sk-proj-abc');
    });

    test('there is a fallback exactly when the build has a school', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      // Booleans only: a failure must not print the key.
      final hasKey = c.read(fallbackSchoolApiKeyProvider) != null;
      expect(hasKey, AppMode.fromBuild is SchoolMode);
    });
  });

  group('tutorApiKeyProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ProviderContainer container({
      required Account? account,
      String? localKey,
      AppMode? mode,
      _Configs? configs,
      String? fallbackKey = _fallback,
    }) {
      if (localKey != null) {
        SharedPreferences.setMockInitialValues({'local_api_key': localKey});
      }
      final c = ProviderContainer(
        overrides: [
          accountServiceProvider.overrideWith(() => _FixedAccount(account)),
          appModeProvider.overrideWithValue(mode ?? kTestSchoolMode),
          globalConfigServiceProvider.overrideWith(
            () => configs ?? _Configs(_config('')),
          ),
          fallbackSchoolApiKeyProvider.overrideWithValue(fallbackKey),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// The stored key is hydrated one microtask after the first read.
    Future<ApiKeySource?> resolve(ProviderContainer c) async {
      c.read(tutorApiKeyProvider);
      await Future<void>.delayed(Duration.zero);
      return c.read(tutorApiKeyProvider);
    }

    test("an account on the school's key gets ApiKey from config/global, "
        'not the fallback, and a stray local key is ignored (#337)', () async {
      final c = container(
        account: _account(mayUseGlobalKey: true),
        localKey: _own,
        configs: _Configs(_config(_configured)),
      );
      expect(await resolve(c), const SchoolKey(_configured));
    });

    test('with ApiKey empty it gets the fallback, as before #337', () async {
      final c = container(
        account: _account(mayUseGlobalKey: true),
        localKey: _own,
      );
      expect(await resolve(c), const SchoolKey(_fallback));
    });

    test('with ApiKey empty and no fallback it gets none', () async {
      final c = container(
        account: _account(mayUseGlobalKey: true),
        fallbackKey: null,
      );
      expect(await resolve(c), const SchoolKey(''));
    });

    test('follows config/global as the poll brings a new ApiKey', () async {
      final configs = _Configs(_config(''));
      final c = container(
        account: _account(mayUseGlobalKey: true),
        configs: configs,
        fallbackKey: null,
      );
      expect(await resolve(c), const SchoolKey(''));

      configs.publish(_config(_configured));
      expect(c.read(tutorApiKeyProvider), const SchoolKey(_configured));
    });

    test('cannot tell yet while config/global has not answered', () async {
      final c = container(
        account: _account(mayUseGlobalKey: true),
        configs: _Configs(null),
      );
      expect(await resolve(c), isNull);
    });

    test('the stand-alone mode is unchanged: the fallback, whatever a '
        'config says', () async {
      final c = container(
        account: _account(mayUseGlobalKey: true),
        mode: const StandaloneMode(),
        configs: _Configs(_config(_configured)),
      );
      expect(await resolve(c), const SchoolKey(_fallback));
    });

    test('an own-key account gets the key stored on this device', () async {
      for (final mode in [kTestSchoolMode, const StandaloneMode()]) {
        final c = container(
          account: _account(mayUseGlobalKey: false),
          localKey: _own,
          mode: mode,
          configs: _Configs(_config(_configured)),
        );
        expect(await resolve(c), const OwnKey(_own), reason: '$mode');
      }
    });

    test('an own-key account with nothing stored gets no key', () async {
      final c = container(account: _account(mayUseGlobalKey: false));
      expect(await resolve(c), const OwnKey(null));
    });

    test(
      'an account that has not loaded is not on the school\'s key',
      () async {
        final c = container(account: null, localKey: _own);
        expect(await resolve(c), const OwnKey(_own));
      },
    );

    test('follows the stored key as it is saved and removed', () async {
      final c = container(account: _account(mayUseGlobalKey: false));
      expect(await resolve(c), const OwnKey(null));

      await c.read(localApiKeyStorageProvider.notifier).saveKey(_own);
      expect(c.read(tutorApiKeyProvider), const OwnKey(_own));

      await c.read(localApiKeyStorageProvider.notifier).clearKey();
      expect(c.read(tutorApiKeyProvider), const OwnKey(null));
    });
  });

  group('resolveTutorApiKeyProvider (#337)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ProviderContainer container(
      _Configs configs, {
      String? fallbackKey = _fallback,
    }) {
      final c = ProviderContainer(
        overrides: [
          accountServiceProvider.overrideWith(
            () => _FixedAccount(_account(mayUseGlobalKey: true)),
          ),
          appModeProvider.overrideWithValue(kTestSchoolMode),
          globalConfigServiceProvider.overrideWith(() => configs),
          fallbackSchoolApiKeyProvider.overrideWithValue(fallbackKey),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a key that is known goes out without another read', () async {
      final configs = _Configs(_config(_configured));
      final c = container(configs);
      expect(
        await c.read(resolveTutorApiKeyProvider)(),
        const SchoolKey(_configured),
      );
      expect(configs.reads, 0);
    });

    test('while config/global has not answered, the key waits for a read of '
        'it', () async {
      final read = Completer<GlobalConfig?>();
      final configs = _Configs(null, read: () => read.future);
      final c = container(configs);

      var resolved = false;
      final pending = c
          .read(resolveTutorApiKeyProvider)()
          .whenComplete(() => resolved = true);
      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse, reason: 'not the fallback in the meantime');

      read.complete(_config(_configured));
      expect(await pending, const SchoolKey(_configured));
      expect(configs.reads, 1);
    });

    test('a school without the doc gets the fallback, and none without '
        'one', () async {
      expect(
        await container(_Configs(null)).read(resolveTutorApiKeyProvider)(),
        const SchoolKey(_fallback),
      );
      expect(
        await container(
          _Configs(null),
          fallbackKey: null,
        ).read(resolveTutorApiKeyProvider)(),
        const SchoolKey(''),
      );
    });

    test('a read that fails uses the fallback; without one the failure is '
        "the call's", () async {
      Future<GlobalConfig?> fail() => Future.error(const SocketException('x'));
      expect(
        await container(_Configs(null, read: fail))
            .read(resolveTutorApiKeyProvider)(),
        const SchoolKey(_fallback),
      );
      await expectLater(
        container(
          _Configs(null, read: fail),
          fallbackKey: null,
        ).read(resolveTutorApiKeyProvider)(),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('on the wire', () {
    late FakeOpenAi openai;
    late ApiKeySource source;

    setUp(() {
      openai = FakeOpenAi(
        text: '<TEXT>Hallo</TEXT><META>{"type":"answer"}</META>',
      );
      source = const OwnKey(_own);
    });

    OpenaiConnector connector() =>
        OpenaiConnector(getApiKey: () => source, client: openai.client);

    Future<ConnectorResult> send(OpenaiConnector c) =>
        c.sendRequest(instructions: 'sys', input: 'vraag');

    Future<List<StreamChunk>> stream(OpenaiConnector c) =>
        c.sendRequestStream(instructions: 'sys', input: 'vraag').toList();

    test('every kind of call carries the resolved key', () async {
      final c = connector();

      expect(await send(c), isA<ConnectorOk>());
      expect((await stream(c)).last, isA<StreamCompleted>());
      expect(await c.probe('gpt-4o'), isA<ModelProbeOk>());

      expect(openai.bearers, ['Bearer $_own', 'Bearer $_own', 'Bearer $_own']);
    });

    test('the key is resolved per call, so a change takes effect on the '
        'next one', () async {
      final c = connector();
      await send(c);
      source = const SchoolKey(_school);
      await send(c);
      expect(openai.bearers, ['Bearer $_own', 'Bearer $_school']);
    });

    test('an own-key account with no key makes no request and is told to '
        'add one', () async {
      source = const OwnKey(null);
      final c = connector();
      const expected = ChatNotice(ChatNoticeKind.ownKeyMissing);

      final result = await send(c);
      expect(result, isA<ConnectorFailure>());
      expect((result as ConnectorFailure).notice, expected);
      expect(result.error, isA<NoApiKeyException>());

      final chunks = await stream(c);
      expect(chunks, hasLength(1));
      expect((chunks.single as StreamFailed).notice, expected);

      final probe = await c.probe('gpt-4o');
      expect((probe as ModelProbeFailed).reason, expected);

      expect(openai.requests, isEmpty, reason: 'nothing may reach OpenAI');
      expect(c.allHistory, isEmpty);
    });

    test('a rejected own key is reported against the student, in every kind '
        'of call', () async {
      openai.answer = (_) => FakeOpenAi.unauthorized();
      final c = connector();
      const expected = ChatNotice(ChatNoticeKind.ownKeyRejected);

      expect(((await send(c)) as ConnectorFailure).notice, expected);
      expect(((await stream(c)).last as StreamFailed).notice, expected);
      expect(((await c.probe('gpt-4o')) as ModelProbeFailed).reason, expected);
      expect(openai.requests, hasLength(3));
    });

    test("a rejected school key is reported against the school, not with "
        "the API's line about a key the student cannot change", () async {
      openai.answer = (_) => FakeOpenAi.unauthorized();
      source = const SchoolKey(_school);
      final c = connector();
      const expected = ChatNotice(ChatNoticeKind.schoolKeyInvalid);

      expect(((await send(c)) as ConnectorFailure).notice, expected);
      expect(((await stream(c)).last as StreamFailed).notice, expected);
      expect(((await c.probe('gpt-4o')) as ModelProbeFailed).reason, expected);
    });

    test('a missing school key makes no request, in any kind of call, and '
        'says the school has no key (#337)', () async {
      source = const SchoolKey('');
      final c = connector();
      const expected = ChatNotice(ChatNoticeKind.schoolKeyMissing);

      expect(((await send(c)) as ConnectorFailure).notice, expected);
      expect(((await stream(c)).single as StreamFailed).notice, expected);
      expect(((await c.probe('gpt-4o')) as ModelProbeFailed).reason, expected);
      expect(openai.requests, isEmpty, reason: 'nothing may reach OpenAI');
      expect(OpenaiConnector.isKeyFailure(expected), isTrue);
    });

    test('a call waits for a key that is not known yet, then goes out on it '
        '(#337)', () async {
      final key = Completer<ApiKeySource>();
      final c = OpenaiConnector(
        getApiKey: () => key.future,
        client: openai.client,
      );
      final result = send(c);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(openai.requests, isEmpty);

      key.complete(const SchoolKey(_configured));
      expect(await result, isA<ConnectorOk>());
      expect(openai.bearers, ['Bearer $_configured']);
    });

    test("any other refusal still carries the API's own message", () async {
      const message = 'You exceeded your current quota.';
      openai.answer = (_) => FakeOpenAi.apiError(
        message,
        status: 429,
        type: 'insufficient_quota',
        code: 'insufficient_quota',
      );
      final c = connector();

      final probe = await c.probe('gpt-4o');
      expect((probe as ModelProbeFailed).reason, ChatNotice.raw(message));

      final result = await send(c);
      expect((result as ConnectorFailure).notice.kind, ChatNoticeKind.raw);
      expect(result.notice.args.single, contains(message));
    });

    test('the request body is unchanged by the key seam', () async {
      final c = connector();
      await send(c);
      final body = jsonDecode(openai.requests.single.body) as Map;
      expect(body['model'], OpenaiConnector.defaultModel);
      expect((body['messages'] as List), hasLength(2));
    });
  });

  group('the connectors of the app (#337)', () {
    late FakeOpenAi openai;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      openai = FakeOpenAi();
    });

    ProviderContainer container(_Configs configs, {String? fallbackKey}) {
      final c = ProviderContainer(
        overrides: [
          accountServiceProvider.overrideWith(
            () => _FixedAccount(_account(mayUseGlobalKey: true)),
          ),
          appModeProvider.overrideWithValue(kTestSchoolMode),
          globalConfigServiceProvider.overrideWith(() => configs),
          fallbackSchoolApiKeyProvider.overrideWithValue(fallbackKey),
          openaiClientProvider.overrideWithValue(openai.client),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the grade justification and the Test button call with ApiKey from '
        'config/global', () async {
      final c = container(
        _Configs(_config(_configured)),
        fallbackKey: _fallback,
      );

      expect(
        await c.read(gradeJustificationConnectorProvider).probe('gpt-4o'),
        isA<ModelProbeOk>(),
      );
      expect(
        await c.read(modelProbeConnectorProvider).probe('gpt-4o'),
        isA<ModelProbeOk>(),
      );
      expect(openai.bearers, ['Bearer $_configured', 'Bearer $_configured']);
    });

    test('they wait for config/global, and say the school has no key when it '
        'has none and there is no fallback', () async {
      final read = Completer<GlobalConfig?>();
      final c = container(_Configs(null, read: () => read.future));

      final probe = c.read(modelProbeConnectorProvider).probe('gpt-4o');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(openai.requests, isEmpty);

      read.complete(_config(''));
      expect(
        ((await probe) as ModelProbeFailed).reason,
        const ChatNotice(ChatNoticeKind.schoolKeyMissing),
      );
      expect(openai.requests, isEmpty);
    });

    test('every connector in lib/ takes its key from the same place', () {
      // The tutor's connector is built inside `TutorService`; this pins all
      // three seams to the one resolver, and the integration flow
      // own_key.dart reads the tutor's key off the wire.
      final seams = <String, int>{};
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        final n = RegExp(r'getApiKey:').allMatches(text).length;
        if (n > 0) seams[p.posix.joinAll(p.split(f.path))] = n;
        final ownSeam = RegExp(
          r'getApiKey:(?!\s*\(\)\s*=>\s*'
          r'ref\.read\(resolveTutorApiKeyProvider\)\(\))',
        );
        expect(
          ownSeam.hasMatch(text),
          isFalse,
          reason: '${f.path} has a key seam of its own',
        );
      }
      expect(seams, {
        'lib/features/options/options_page.dart': 1,
        'lib/services/grading/grade_proposal_service.dart': 1,
        'lib/services/tutor/tutor_service.dart': 1,
      });
    });
  });
}
