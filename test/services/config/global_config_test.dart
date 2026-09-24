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

  group('MinimumVersion (#165)', () {
    test('is parsed, trimmed, and absent when missing or blank', () {
      expect(
        GlobalConfig.fromMap({'MinimumVersion': '2.6.0'}).minimumVersion,
        '2.6.0',
      );
      expect(
        GlobalConfig.fromMap({'MinimumVersion': ' 2.6.0+23 '}).minimumVersion,
        '2.6.0+23',
      );
      expect(GlobalConfig.fromMap({}).minimumVersion, isNull);
      expect(
        GlobalConfig.fromMap({'MinimumVersion': ''}).minimumVersion,
        isNull,
      );
      expect(
        GlobalConfig.fromMap({'MinimumVersion': '   '}).minimumVersion,
        isNull,
      );
      expect(
        GlobalConfig.fromMap({'MinimumVersion': null}).minimumVersion,
        isNull,
      );
    });

    test('is written only when set, and survives a round trip', () {
      expect(
        const GlobalConfig(
          model: 'gpt-4o',
          apiKey: 'k',
        ).toMap().containsKey('MinimumVersion'),
        isFalse,
      );
      const withMinimum = GlobalConfig(
        model: 'gpt-4o',
        apiKey: 'k',
        minimumVersion: '2.6.0',
      );
      expect(withMinimum.toMap()['MinimumVersion'], '2.6.0');
      expect(GlobalConfig.fromMap(withMinimum.toMap()).minimumVersion, '2.6.0');
    });
  });

  group('the question bank mix (#186)', () {
    test(
      'QuestionBankMinimum is a whole number of at least 1, else absent',
      () {
        int? minimum(Object? raw) =>
            GlobalConfig.fromMap({'QuestionBankMinimum': raw})
                .questionBankMinimum;
        expect(minimum(8), 8);
        expect(minimum(3.0), 3);
        expect(minimum(1), 1);
        expect(minimum(0), isNull);
        expect(minimum(-2), isNull);
        expect(minimum('8'), isNull);
        expect(minimum(null), isNull);
        expect(GlobalConfig.fromMap({}).questionBankMinimum, isNull);
      },
    );

    test('QuestionBankShare is a number held to 0..1, else absent', () {
      double? share(Object? raw) =>
          GlobalConfig.fromMap({'QuestionBankShare': raw}).questionBankShare;
      expect(share(0.5), 0.5);
      expect(share(0), 0.0);
      expect(share(1), 1.0);
      expect(share(1.7), 1.0);
      expect(share(-0.2), 0.0);
      expect(share(double.nan), isNull);
      expect(share('0.5'), isNull);
      expect(GlobalConfig.fromMap({}).questionBankShare, isNull);
    });

    test('both are written only when set, and survive a round trip', () {
      final plain = const GlobalConfig(model: 'gpt-4o', apiKey: 'k').toMap();
      expect(plain.containsKey('QuestionBankMinimum'), isFalse);
      expect(plain.containsKey('QuestionBankShare'), isFalse);

      const set = GlobalConfig(
        model: 'gpt-4o',
        apiKey: 'k',
        questionBankMinimum: 4,
        questionBankShare: 0.25,
      );
      final back = GlobalConfig.fromMap(set.toMap());
      expect(back.questionBankMinimum, 4);
      expect(back.questionBankShare, 0.25);
    });
  });
}
