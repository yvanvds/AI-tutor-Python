import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalApiKeyStorage extends Notifier<bool> {
  static const String _keyName = 'local_api_key';

  @override
  bool build() {
    _initPresence();
    return false;
  }

  Future<void> _initPresence() async {
    state = await hasKey();
  }

  Future<void> saveKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, apiKey);
    state = true;
  }

  Future<String?> loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyName);
  }

  Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
    state = false;
  }

  Future<bool> hasKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyName);
  }
}

final localApiKeyStorageProvider = NotifierProvider<LocalApiKeyStorage, bool>(
  LocalApiKeyStorage.new,
);
