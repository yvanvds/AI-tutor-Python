// Issue #32 — the per-device model override: what is stored, and how it wins
// over the school-wide `GlobalConfig.Model` inside the connector.

import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/model_preference.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ModelPreference', () {
    test('defaults to null (follow the school-wide config)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(modelPreferenceProvider), isNull);
    });

    test('setModel persists and updates state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(modelPreferenceProvider.notifier)
          .setModel('gpt-5-mini');
      expect(container.read(modelPreferenceProvider), 'gpt-5-mini');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_model'), 'gpt-5-mini');
    });

    test('setModel(null) clears the override', () async {
      SharedPreferences.setMockInitialValues({'openai_model': 'gpt-4.1'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(modelPreferenceProvider.notifier).setModel(null);
      expect(container.read(modelPreferenceProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('openai_model'), isNull);
    });

    test('hydrates from shared_preferences on first read', () async {
      SharedPreferences.setMockInitialValues({'openai_model': 'gpt-4o-mini'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(modelPreferenceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(modelPreferenceProvider), 'gpt-4o-mini');
    });

    test('every offered model is a distinct, non-empty name', () {
      expect(kSelectableModels, isNotEmpty);
      expect(kSelectableModels.toSet(), hasLength(kSelectableModels.length));
      for (final m in kSelectableModels) {
        expect(m.trim(), isNotEmpty);
      }
    });
  });

  group('OpenaiConnector.resolveModel', () {
    OpenaiConnector connector({String? config, String? override}) =>
        OpenaiConnector(
          getConfig: config == null
              ? null
              : () => GlobalConfig(model: config, apiKey: ''),
          getModelOverride: override == null ? null : () => override,
        );

    test('the device override wins over the school-wide model', () {
      expect(
        connector(config: 'gpt-4o', override: 'gpt-5').resolveModel(),
        'gpt-5',
      );
    });

    test('an empty override falls through to the school-wide model', () {
      expect(
        connector(config: 'gpt-4.1', override: '').resolveModel(),
        'gpt-4.1',
      );
    });

    test('without an override the school-wide model is used', () {
      expect(connector(config: 'gpt-4.1-mini').resolveModel(), 'gpt-4.1-mini');
    });

    test('an unfilled config doc falls back to the built-in default', () {
      expect(
        connector(config: '').resolveModel(),
        OpenaiConnector.defaultModel,
      );
      expect(connector().resolveModel(), OpenaiConnector.defaultModel);
    });
  });
}
