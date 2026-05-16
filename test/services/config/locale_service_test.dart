import 'dart:ui';

import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LocaleService', () {
    test('default state is null (follow system)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(localeServiceProvider), isNull);
    });

    test('setLocale(en) persists and updates state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(localeServiceProvider.notifier)
          .setLocale(const Locale('en'));
      expect(container.read(localeServiceProvider), const Locale('en'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_locale'), 'en');
    });

    test('setLocale(null) clears the stored override', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'nl'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(localeServiceProvider.notifier).setLocale(null);
      expect(container.read(localeServiceProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_locale'), isNull);
    });

    test('setLocale ignores unsupported language codes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(localeServiceProvider.notifier)
          .setLocale(const Locale('fr'));
      expect(container.read(localeServiceProvider), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_locale'), isNull);
    });

    test('hydrates state from shared_preferences on first read', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'nl'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(localeServiceProvider);
      await Future.delayed(Duration.zero);
      expect(container.read(localeServiceProvider), const Locale('nl'));
    });

    test('ignores unsupported language codes during hydration', () async {
      SharedPreferences.setMockInitialValues({'app_locale': 'fr'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(localeServiceProvider);
      await Future.delayed(Duration.zero);
      expect(container.read(localeServiceProvider), isNull);
    });
  });
}
