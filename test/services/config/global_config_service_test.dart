// #118 — `GlobalConfigService` grew a writer, so a teacher can move the whole
// school onto another model instead of only the machine in front of them.
//
// The thing under test is what the write does to the *rest* of the document:
// `GlobalConfig.toMap()` serialises `ApiKey` too, so a blind upsert from a
// config built in memory would blank the school's OpenAI key — the one field
// nothing in the app could put back.

import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

Map<String, dynamic> _configDoc({
  String model = 'gpt-4o',
  String apiKey = 'sk-school',
  Map<String, dynamic> extra = const {},
}) => {
  'id': 'global',
  'type': 'config',
  'Model': model,
  'ApiKey': apiKey,
  ...extra,
};

void main() {
  late InMemoryCosmos config;

  /// The real service over an in-memory `config` container, built and kept
  /// alive the way a provider container keeps it.
  GlobalConfigService service() {
    final provider = NotifierProvider<GlobalConfigService, GlobalConfig?>(
      () => GlobalConfigService(container: config.container),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container.read(provider.notifier);
  }

  test(
    'setModel writes the model and leaves the stored API key alone',
    () async {
      config = InMemoryCosmos([_configDoc()]);

      await service().setModel('gpt-5-mini');

      expect(config['global']!['Model'], 'gpt-5-mini');
      expect(
        config['global']!['ApiKey'],
        'sk-school',
        reason: 'the write blanked a key it never read',
      );
      expect(config['global']!['id'], 'global');
      expect(config['global']!['type'], 'config');
      expect(config.docs, hasLength(1));
    },
  );

  test('setModel keeps fields the app does not model', () async {
    config = InMemoryCosmos([
      _configDoc(extra: {'Note': 'do not lose me'}),
    ]);

    await service().setModel('gpt-4.1');

    expect(config['global']!['Note'], 'do not lose me');
    expect(config['global']!['Model'], 'gpt-4.1');
  });

  test("setModel does not echo Cosmos' own system fields back", () async {
    config = InMemoryCosmos([
      _configDoc(extra: {'_rid': 'abc', '_etag': '"0x1"', '_ts': 1}),
    ]);

    await service().setModel('gpt-4.1');

    expect(config['global']!.keys, isNot(contains('_rid')));
    expect(config['global']!.keys, isNot(contains('_etag')));
    expect(config['global']!.keys, isNot(contains('_ts')));
  });

  test(
    'setModel creates the doc when the config has never been written',
    () async {
      config = InMemoryCosmos();

      await service().setModel('gpt-4o-mini');

      expect(config['global'], isNotNull);
      expect(config['global']!['Model'], 'gpt-4o-mini');
      expect(config['global']!['ApiKey'], '');
      expect(config['global']!['type'], 'config');
    },
  );

  // The card that calls this shows a radio row per model; waiting a poll
  // interval for it to move would read as a tap that did nothing.
  test(
    'setModel publishes the new config without waiting for the poll',
    () async {
      config = InMemoryCosmos([_configDoc()]);
      final svc = service();

      await svc.setModel('gpt-5');

      expect(svc.cachedConfig?.model, 'gpt-5');
      expect(svc.cachedConfig?.apiKey, 'sk-school');
    },
  );
}
