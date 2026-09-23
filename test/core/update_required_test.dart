// #165: which builds may still run, as `config/global`'s `MinimumVersion`
// says, and how the answer reaches the root widget. The screen it mounts is
// pinned in test/widgets/update_required_screen_test.dart, the gate in
// test/features/shell/update_required_gate_test.dart, and the whole thing
// end-to-end in integration_test/flows/update_required.dart.

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_required.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cosmos.dart';

/// The real config service over an in-memory container, plus a way to
/// publish a value the way a poll would — without waiting five seconds for
/// one.
class _Configs extends GlobalConfigService {
  _Configs({required super.container});

  void publish(GlobalConfig? config) => state = config;
}

Map<String, dynamic> _doc({String? minimum}) => {
  'id': 'global',
  'type': 'config',
  'Model': 'gpt-4o',
  'ApiKey': 'sk-school',
  if (minimum != null) 'MinimumVersion': minimum,
};

const String _local = '2.5.0+22';

UpdateRequirement? _evaluate(String? minimum, {List<String>? logs}) =>
    evaluateUpdateRequirement(
      localVersion: _local,
      minimumVersion: minimum,
      log: logs?.add,
    );

void main() {
  group('evaluateUpdateRequirement', () {
    test('no minimum, a blank one, or one this build meets asks nothing', () {
      for (final minimum in [
        null,
        '',
        '   ',
        '2.5.0',
        '2.5.0+22',
        '2.5.0+21',
        '2.4.9',
        '1.0.0',
      ]) {
        expect(_evaluate(minimum), isNull, reason: 'minimum "$minimum"');
      }
    });

    test('a minimum above this build is the requirement, trimmed', () {
      for (final minimum in ['2.5.0+23', '2.5.1', '2.6.0', '3.0.0']) {
        expect(
          _evaluate(minimum),
          const UpdateRequirement(
            localVersion: _local,
            minimumVersion: '',
          ).copyWithMinimum(minimum),
          reason: 'minimum "$minimum"',
        );
      }
      expect(
        _evaluate(' 2.6.0 '),
        const UpdateRequirement(localVersion: _local, minimumVersion: '2.6.0'),
      );
    });

    test('a minimum that does not parse is logged and not enforced', () {
      final logs = <String>[];
      expect(_evaluate('banana', logs: logs), isNull);
      expect(logs, hasLength(1));
      expect(logs.single, contains('banana'));
      expect(logs.single, contains('not enforced'));
    });

    test('a local version that cannot be compared is not enforced either', () {
      final logs = <String>[];
      expect(
        evaluateUpdateRequirement(
          localVersion: 'dev',
          minimumVersion: '2.6.0',
          log: logs.add,
        ),
        isNull,
      );
      expect(logs.single, contains('dev'));
    });
  });

  group('updateRequirementProvider', () {
    late InMemoryCosmos config;

    ProviderContainer containerFor(List<Map<String, dynamic>> docs) {
      config = InMemoryCosmos(docs);
      final container = ProviderContainer(
        overrides: [
          appVersionProvider.overrideWithValue(_local),
          globalConfigServiceProvider.overrideWith(
            () => _Configs(container: config.container),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('is unknown until the config has answered, then required', () async {
      final container = containerFor([_doc(minimum: '9.0.0')]);

      // The first read is "not known yet", never "not required": the root
      // widget waits on this the way it waits on the account doc.
      expect(container.read(updateRequirementProvider).isLoading, isTrue);

      expect(
        await container.read(updateRequirementProvider.future),
        const UpdateRequirement(localVersion: _local, minimumVersion: '9.0.0'),
      );
      expect(container.read(updateRequirementProvider).isLoading, isFalse);
    });

    test('a build at or above the minimum runs', () async {
      for (final minimum in ['2.5.0', '2.5.0+22', '2.0.0']) {
        final container = containerFor([_doc(minimum: minimum)]);
        expect(
          await container.read(updateRequirementProvider.future),
          isNull,
          reason: 'minimum "$minimum"',
        );
      }
    });

    test('no minimum on the doc, or no doc at all, asks nothing', () async {
      for (final docs in [
        [_doc()],
        <Map<String, dynamic>>[],
      ]) {
        final container = containerFor(docs);
        expect(await container.read(updateRequirementProvider.future), isNull);
        expect(container.read(updateRequirementProvider).isLoading, isFalse);
      }
    });

    test('follows what the config service publishes afterwards', () async {
      final container = containerFor([_doc()]);
      expect(await container.read(updateRequirementProvider.future), isNull);
      final configs =
          container.read(globalConfigServiceProvider.notifier) as _Configs;

      // The teacher raises the minimum mid-lesson: the next poll gates.
      configs.publish(
        const GlobalConfig(
          model: 'gpt-4o',
          apiKey: 'sk-school',
          minimumVersion: '9.0.0',
        ),
      );
      await container.pump();
      expect(
        container.read(updateRequirementProvider).valueOrNull,
        const UpdateRequirement(localVersion: _local, minimumVersion: '9.0.0'),
      );

      // And lowers it again: the app is let back in without a restart.
      configs.publish(const GlobalConfig(model: 'gpt-4o', apiKey: 'sk-school'));
      await container.pump();
      expect(container.read(updateRequirementProvider).valueOrNull, isNull);
      expect(container.read(updateRequirementProvider).isLoading, isFalse);
    });
  });
}

extension on UpdateRequirement {
  UpdateRequirement copyWithMinimum(String minimum) =>
      UpdateRequirement(localVersion: localVersion, minimumVersion: minimum);
}
