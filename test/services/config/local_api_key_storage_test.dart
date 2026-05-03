import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalApiKeyStorage', () {
    test('hasKey returns false when no key stored', () async {
      final storage = LocalApiKeyStorage();
      expect(await storage.hasKey(), isFalse);
    });

    test('loadKey returns null when no key stored', () async {
      final storage = LocalApiKeyStorage();
      expect(await storage.loadKey(), isNull);
    });

    test('saveKey stores the key and sets isKeyPresent to true', () async {
      final storage = LocalApiKeyStorage();
      await storage.saveKey('sk-test-123');
      expect(await storage.hasKey(), isTrue);
      expect(await storage.loadKey(), 'sk-test-123');
      expect(storage.isKeyPresent.value, isTrue);
    });

    test('clearKey removes the key and sets isKeyPresent to false', () async {
      final storage = LocalApiKeyStorage();
      await storage.saveKey('sk-test-456');
      await storage.clearKey();
      expect(await storage.hasKey(), isFalse);
      expect(await storage.loadKey(), isNull);
      expect(storage.isKeyPresent.value, isFalse);
    });

    test('isKeyPresent updates asynchronously on construction when key exists',
        () async {
      SharedPreferences.setMockInitialValues({'local_api_key': 'existing-key'});
      final storage = LocalApiKeyStorage();
      // Let the constructor's async init complete
      await Future.delayed(Duration.zero);
      expect(storage.isKeyPresent.value, isTrue);
    });
  });
}
