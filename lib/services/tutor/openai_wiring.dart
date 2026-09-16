// What every production `OpenaiConnector` is built from (#126): whose key
// its calls go out on, and which HTTP transport carries them.
//
// Three connectors are constructed in the app — the tutor's
// (`tutor_service.dart`), the grade justification's
// (`grade_proposal_service.dart`) and the one behind the Test button in
// Options (`options_page.dart`). Each reads these two providers, so the
// answer to "which key" is decided in exactly one place and a stand-in for
// the socket reaches all three at once.

import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:ai_tutor_python/services/tutor/env.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// The school's OpenAI key: `OPEN_AI_API_KEY` from `.env`, obfuscated into
/// the build. Whether `GlobalConfig.ApiKey` (the Cosmos `config/global`
/// doc) should be consulted before it — a key rotatable without a release
/// — is a separate decision; this is the one place it would go.
///
/// The integration harness pins this to a fixed string, so no flow ever
/// carries a developer's real key into a request it asserts on.
final schoolApiKeyProvider = Provider<String>((_) => Env.apiKey);

/// Whose key the signed-in account's OpenAI calls go out on (#126).
///
/// An account with `mayUseGlobalKey` is on the school's key; a key it may
/// also have stored on this device is ignored, consistent with the Options
/// page hiding the own-key card for such an account. Every other account —
/// including one whose doc has not loaded yet — is on the key stored on
/// this device, and on nothing at all while there is none: the connector
/// then refuses the call rather than quietly billing the school.
final tutorApiKeyProvider = Provider<ApiKeySource>((ref) {
  final account = ref.watch(accountServiceProvider);
  if (account != null && account.mayUseGlobalKey) {
    return SchoolKey(ref.watch(schoolApiKeyProvider));
  }
  return OwnKey(ref.watch(localApiKeyStorageProvider));
});

/// The HTTP transport every connector sends on. `null` (production) lets
/// `dart_openai` open its own connections; the integration harness passes a
/// scripted client so a flow can read the request the real app made —
/// including the key it carried — and answer it without a socket.
final openaiClientProvider = Provider<http.Client?>((_) => null);
