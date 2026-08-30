import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GlobalConfig.fromMap', () {
    test('parses all fields', () {
      final config = GlobalConfig.fromMap({
        'Model': 'gpt-4o',
        'ApiKey': 'sk-123',
      });
      expect(config.model, 'gpt-4o');
      expect(config.apiKey, 'sk-123');
    });

    test('defaults to empty strings for missing keys', () {
      final config = GlobalConfig.fromMap({});
      expect(config.model, '');
      expect(config.apiKey, '');
    });

    test('treats null values as empty string', () {
      final config = GlobalConfig.fromMap({'Model': null, 'ApiKey': null});
      expect(config.model, '');
      expect(config.apiKey, '');
    });
  });

  group('GlobalConfig.toMap', () {
    test('includes Cosmos id and type fields', () {
      final map = const GlobalConfig(model: 'gpt-4o', apiKey: 'sk-123').toMap();
      expect(map['id'], 'global');
      expect(map['type'], 'config');
      expect(map['Model'], 'gpt-4o');
      expect(map['ApiKey'], 'sk-123');
    });
  });

  group('round-trip', () {
    test('fromMap(toMap()) preserves values', () {
      const original = GlobalConfig(model: 'gpt-4o-mini', apiKey: 'sk-abc');
      final restored = GlobalConfig.fromMap(original.toMap());
      expect(restored.model, original.model);
      expect(restored.apiKey, original.apiKey);
    });
  });
}
