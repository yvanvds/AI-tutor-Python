import 'package:shared_preferences/shared_preferences.dart';

class LocalApiKeyStorage {
  static const _keyName = 'local_api_key';

  /// Save the key locally.
  static Future<void> saveKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, apiKey);
  }

  /// Retrieve the stored key (null if missing).
  static Future<String?> loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyName);
  }

  /// Remove the stored key (for logout or reset).
  static Future<void> clearKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyName);
  }

  /// Quick check if a key exists.
  static Future<bool> hasKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_keyName);
  }
}
