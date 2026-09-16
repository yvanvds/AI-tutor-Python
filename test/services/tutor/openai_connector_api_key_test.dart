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
// The wire-level tests drive the real connector over a scripted HTTP client
// and read the `Authorization` header the request actually carried.

import 'dart:convert';

import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/openai_wiring.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_openai.dart';

const _own = 'sk-own-key';
const _school = 'sk-school-key';

Account _account({required bool mayUseGlobalKey}) => Account(
  uid: 'u1',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  targetGoal: 'Python',
  mayUseGlobalKey: mayUseGlobalKey,
);

/// The signed-in account, already loaded — no Cosmos, no auth listener.
class _FixedAccount extends AccountService {
  _FixedAccount(this._account);
  final Account? _account;

  @override
  Account? build() => _account;
}

void main() {
  group('OpenaiConnector.resolveApiKey', () {
    test("the school's key when the account is on it", () {
      final c = OpenaiConnector(getApiKey: () => const SchoolKey(_school));
      expect(c.resolveApiKey(), _school);
    });

    test('the own key when the account is on its own', () {
      final c = OpenaiConnector(getApiKey: () => const OwnKey(_own));
      expect(c.resolveApiKey(), _own);
    });

    test('an own-key account with nothing stored is refused, never the '
        "school's key", () {
      for (final source in const [OwnKey(null), OwnKey('')]) {
        final c = OpenaiConnector(getApiKey: () => source);
        expect(
          c.resolveApiKey,
          throwsA(
            isA<NoApiKeyException>().having((e) => e.source, 'source', source),
          ),
          reason: '$source',
        );
      }
    });

    test('an empty school key is refused too', () {
      final c = OpenaiConnector(getApiKey: () => const SchoolKey(''));
      expect(c.resolveApiKey, throwsA(isA<NoApiKeyException>()));
    });

    test("without a seam it is the build's school key", () {
      expect(OpenaiConnector().resolveApiKey(), Env.apiKey);
    });
  });

  group('tutorApiKeyProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ProviderContainer container({required Account? account, String? localKey}) {
      if (localKey != null) {
        SharedPreferences.setMockInitialValues({'local_api_key': localKey});
      }
      final c = ProviderContainer(
        overrides: [
          accountServiceProvider.overrideWith(() => _FixedAccount(account)),
          schoolApiKeyProvider.overrideWithValue(_school),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// The stored key is hydrated one microtask after the first read.
    Future<ApiKeySource> resolve(ProviderContainer c) async {
      c.read(tutorApiKeyProvider);
      await Future<void>.delayed(Duration.zero);
      return c.read(tutorApiKeyProvider);
    }

    test("an account on the school's key gets it, and a stray local key "
        'is ignored', () async {
      final c = container(
        account: _account(mayUseGlobalKey: true),
        localKey: _own,
      );
      expect(await resolve(c), const SchoolKey(_school));
    });

    test('an own-key account gets the key stored on this device', () async {
      final c = container(
        account: _account(mayUseGlobalKey: false),
        localKey: _own,
      );
      expect(await resolve(c), const OwnKey(_own));
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

    test(
      'a missing school key is reported the same way, without a request',
      () async {
        source = const SchoolKey('');
        final c = connector();
        expect(
          ((await send(c)) as ConnectorFailure).notice,
          const ChatNotice(ChatNoticeKind.schoolKeyInvalid),
        );
        expect(openai.requests, isEmpty);
      },
    );

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
}
