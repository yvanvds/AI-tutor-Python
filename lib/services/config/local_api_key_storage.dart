import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The OpenAI key the user stored on this device, or `null` while there is
/// none.
///
/// The state carries the key itself, not just whether one exists (#126):
/// `OpenaiConnector.resolveApiKey` runs synchronously on the hot path of
/// every tutor call, so the key has to be readable without an `await` —
/// hydrated once from SharedPreferences on first read, exactly like
/// `ModelPreference`, and published by [saveKey] / [clearKey] from then on.
///
/// Who reads it: `main.dart` (the local-key gate, present-or-not), the
/// Options page's own-key card (present-or-not), and `tutorApiKeyProvider`
/// (the value, for an account without `mayUseGlobalKey`).
class LocalApiKeyStorage extends Notifier<String?> {
  static const String _keyName = 'local_api_key';

  @override
  String? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyName);
    if (raw == null || raw.isEmpty) return;
    state = raw;
  }

  Future<void> saveKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, apiKey);
    state = apiKey;
  }

  Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    state = null;
  }
}

final localApiKeyStorageProvider =
    NotifierProvider<LocalApiKeyStorage, String?>(LocalApiKeyStorage.new);
