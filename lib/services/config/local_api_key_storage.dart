import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalApiKeyStorage {
  final _keyName = 'local_api_key';
  final ValueNotifier<bool> isKeyPresent = ValueNotifier<bool>(false);

  LocalApiKeyStorage() {
    // Initialize the presence notifier
    hasKey().then((exists) {
      isKeyPresent.value = exists;
    });
  }

  /// Save the key locally.
  Future<void> saveKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, apiKey);
    isKeyPresent.value = true;
  }

  /// Retrieve the stored key (null if missing).
  Future<String?> loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyName);
  }

  /// Remove the stored key (for logout or reset).
  Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    isKeyPresent.value = false;
  }

  /// Quick check if a key exists.
  Future<bool> hasKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyName);
  }
}
