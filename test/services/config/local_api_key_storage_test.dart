import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalApiKeyStorage', () {
    test('hasKey returns false when no key stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final storage = container.read(localApiKeyStorageProvider.notifier);
      expect(await storage.hasKey(), isFalse);
    });

    test('loadKey returns null when no key stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final storage = container.read(localApiKeyStorageProvider.notifier);
      expect(await storage.loadKey(), isNull);
    });

    test('saveKey stores the key and sets isKeyPresent to true', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final storage = container.read(localApiKeyStorageProvider.notifier);
      await storage.saveKey('sk-test-123');
      expect(await storage.hasKey(), isTrue);
      expect(await storage.loadKey(), 'sk-test-123');
      expect(container.read(localApiKeyStorageProvider), isTrue);
    });

    test('clearKey removes the key and sets isKeyPresent to false', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final storage = container.read(localApiKeyStorageProvider.notifier);
      await storage.saveKey('sk-test-456');
      await storage.clearKey();
      expect(await storage.hasKey(), isFalse);
      expect(await storage.loadKey(), isNull);
      expect(container.read(localApiKeyStorageProvider), isFalse);
    });

    test('isKeyPresent updates asynchronously on construction when key exists',
        () async {
      SharedPreferences.setMockInitialValues({'local_api_key': 'existing-key'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Trigger build by reading.
      container.read(localApiKeyStorageProvider);
      // Let the constructor's async init complete
      await Future.delayed(Duration.zero);
      expect(container.read(localApiKeyStorageProvider), isTrue);
    });
  });
}
