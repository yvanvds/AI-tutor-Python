// What every production `OpenaiConnector` is built from (#126): whose key
// its calls go out on, and which HTTP transport carries them.
//
// Three connectors are constructed in the app — the tutor's
// (`tutor_service.dart`), the grade justification's
// (`grade_proposal_service.dart`) and the one behind the Test button in
// Options (`options_page.dart`). Each reads its key through
// [resolveTutorApiKeyProvider] and its transport through
// [openaiClientProvider], so the answer to "which key" is decided in exactly
// one place and a stand-in for the socket reaches all three at once.
//
// Where the school's key comes from (#337): in the school mode, `ApiKey` on
// the school's `config/global` doc. `OPEN_AI_API_KEY` from `.env` is only the
// fallback for a doc without one, and a build made without school data
// (#308, step 3) has no fallback at all: the call is then refused with a
// notice that the school has no key, and nothing goes to OpenAI. The
// stand-alone mode has no school and is unchanged.

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// The fallback for the school's key: `OPEN_AI_API_KEY` from `.env`, or
/// `null` when that is no key: an empty value or a placeholder, as in CI's
/// `.env` and in a build without school data (#308, step 3) — see
/// [SchoolConfig.isMissingValue].
///
/// In the school mode it is only the fallback for a `config/global` without
/// `ApiKey` (#337). The only place `Env` is read
/// (test/services/tutor/env_single_reader_test.dart).
///
/// The integration harness pins this to a fixed string (or to `null`, for
/// no fallback), so no flow ever carries a developer's real key into a
/// request it asserts on.
final fallbackSchoolApiKeyProvider = Provider<String?>(
  (_) => fallbackSchoolApiKeyFrom(Env.apiKey),
);

/// [value] as the fallback key: `null` when it stands for none
/// ([SchoolConfig.isMissingValue]).
@visibleForTesting
String? fallbackSchoolApiKeyFrom(String value) =>
    SchoolConfig.isMissingValue(value) ? null : value;

/// The school's key, given what `config/global` holds (#337): its `ApiKey`
/// when that is filled in, else [fallback] (from `.env`), else none — a
/// `SchoolKey('')`, on which the connector refuses the call with
/// [ChatNoticeKind.schoolKeyMissing].
@visibleForTesting
SchoolKey schoolKeyFrom(GlobalConfig? config, {String? fallback}) {
  final configured = config?.apiKey.trim() ?? '';
  if (configured.isNotEmpty) return SchoolKey(configured);
  return SchoolKey(fallback ?? '');
}

/// Whose key the signed-in account's OpenAI calls go out on (#126), as far
/// as it can be told right now.
///
/// An account with `mayUseGlobalKey` is on the school's key; a key it may
/// also have stored on this device is ignored, consistent with the Options
/// page hiding the own-key card for such an account. Every other account —
/// including one whose doc has not loaded yet — is on the key stored on
/// this device, and on nothing at all while there is none: the connector
/// then refuses the call rather than quietly billing the school.
///
/// In the school mode the school's key is [schoolKeyFrom] the polled
/// `config/global` (#337). `null` while that doc has not been read, which
/// the polled state cannot tell apart from a school without the doc:
/// [resolveTutorApiKeyProvider] then reads it before the call goes out. The
/// stand-alone mode has no school, so it is left as it was before #337: the
/// user is on their own key there, and an account on the school's key would
/// get the fallback.
final tutorApiKeyProvider = Provider<ApiKeySource?>((ref) {
  final account = ref.watch(accountServiceProvider);
  if (account == null || !account.mayUseGlobalKey) {
    return OwnKey(ref.watch(localApiKeyStorageProvider));
  }
  final fallback = ref.watch(fallbackSchoolApiKeyProvider);
  if (ref.watch(appModeProvider) is! SchoolMode) {
    return SchoolKey(fallback ?? '');
  }
  final config = ref.watch(globalConfigServiceProvider);
  if (config == null) return null;
  return schoolKeyFrom(config, fallback: fallback);
});

/// Whose key the next call goes out on — what each production connector
/// hands its `getApiKey` seam (#337).
///
/// [tutorApiKeyProvider] when it can tell. While it cannot — an account on
/// the school's key before `config/global` has answered — the call waits for
/// a read of that doc, the way the update gate does
/// (`UpdateRequirementController`), instead of being refused or going out
/// on the fallback while the school's own key is about to arrive. A doc
/// that is not there is a school without `ApiKey`. A read that fails uses
/// the fallback when there is one; without one the failure is the call's,
/// so it is reported rather than taken for a missing key.
final resolveTutorApiKeyProvider = Provider<Future<ApiKeySource> Function()>(
  (ref) => () async {
    final known = ref.read(tutorApiKeyProvider);
    if (known != null) return known;
    final fallback = ref.read(fallbackSchoolApiKeyProvider);
    GlobalConfig? config;
    try {
      config = await ref.read(globalConfigServiceProvider.notifier).getConfig();
    } on Object catch (e) {
      debugPrint('resolveTutorApiKey: could not read config/global: $e');
      if (fallback == null) rethrow;
    }
    return schoolKeyFrom(config, fallback: fallback);
  },
);

/// The HTTP transport every connector sends on. `null` (production) lets
/// `dart_openai` open its own connections; the integration harness passes a
/// scripted client so a flow can read the request the real app made —
/// including the key it carried — and answer it without a socket.
final openaiClientProvider = Provider<http.Client?>((_) => null);
