// Issue #23 — the language the app starts in: the user's override when set,
// else the operating-system locale when there is a translation for it, else
// English.

import 'dart:ui';

import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('resolveAppLocale', () {
    test('a Dutch system locale (any region) starts the app in Dutch', () {
      expect(
        resolveAppLocale(null, const Locale('nl', 'BE')),
        const Locale('nl'),
      );
      expect(
        resolveAppLocale(null, const Locale('nl', 'NL')),
        const Locale('nl'),
      );
      expect(resolveAppLocale(null, const Locale('nl')), const Locale('nl'));
    });

    test('any other system locale falls back to English', () {
      expect(
        resolveAppLocale(null, const Locale('fr', 'BE')),
        const Locale('en'),
      );
      expect(resolveAppLocale(null, const Locale('de')), const Locale('en'));
      expect(
        resolveAppLocale(null, const Locale('en', 'GB')),
        const Locale('en'),
      );
    });

    test('a user override wins over the system locale', () {
      expect(
        resolveAppLocale(const Locale('en'), const Locale('nl', 'BE')),
        const Locale('en'),
      );
      expect(
        resolveAppLocale(const Locale('nl'), const Locale('en', 'US')),
        const Locale('nl'),
      );
    });
  });

  group('appLocaleProvider', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('follows the system locale until the user picks a language', () async {
      final container = ProviderContainer(
        overrides: [
          systemLocaleProvider.overrideWithValue(const Locale('nl', 'BE')),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(appLocaleProvider), const Locale('nl'));
      expect(
        container.read(appLocalizationsProvider).sidebar_section_map,
        'Leerpad',
      );

      await container
          .read(localeServiceProvider.notifier)
          .setLocale(const Locale('en'));

      expect(container.read(appLocaleProvider), const Locale('en'));
      expect(
        container.read(appLocalizationsProvider).sidebar_section_map,
        'Learning path',
      );
    });

    test('a stored override is applied once hydrated', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'nl'});
      final container = ProviderContainer(
        overrides: [
          systemLocaleProvider.overrideWithValue(const Locale('en', 'US')),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(appLocaleProvider), const Locale('en'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appLocaleProvider), const Locale('nl'));
    });
  });
}
