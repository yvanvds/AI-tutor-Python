// The user's own OpenAI key on this device. Since #126 the notifier's state
// is the key itself (`String?`), not a presence flag: the connector reads it
// synchronously on every call, so it is hydrated once from
// shared_preferences and published by save / clear from then on.

import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocalApiKeyStorage', () {
    test('the state is null while no key is stored', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(localApiKeyStorageProvider), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(localApiKeyStorageProvider), isNull);
    });

    test('saveKey persists the key and publishes its value', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(localApiKeyStorageProvider.notifier)
          .saveKey('sk-test-123');
      expect(container.read(localApiKeyStorageProvider), 'sk-test-123');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('local_api_key'), 'sk-test-123');
    });

    test('saving again replaces the published value', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final storage = container.read(localApiKeyStorageProvider.notifier);
      await storage.saveKey('sk-first');
      await storage.saveKey('sk-second');
      expect(container.read(localApiKeyStorageProvider), 'sk-second');
    });

    test('clearKey removes the key and publishes null', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final storage = container.read(localApiKeyStorageProvider.notifier);
      await storage.saveKey('sk-test-456');
      await storage.clearKey();
      expect(container.read(localApiKeyStorageProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('local_api_key'), isFalse);
    });

    test('hydrates the stored key on first read', () async {
      SharedPreferences.setMockInitialValues({'local_api_key': 'existing-key'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(localApiKeyStorageProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(localApiKeyStorageProvider), 'existing-key');
    });

    test('an empty stored value counts as no key', () async {
      SharedPreferences.setMockInitialValues({'local_api_key': ''});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(localApiKeyStorageProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(localApiKeyStorageProvider), isNull);
    });
  });
}
