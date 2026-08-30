// Issue #32 — light / dark selection: what is stored, what is hydrated, and
// how a choice resolves against the operating system's brightness.

import 'package:ai_tutor_python/services/config/theme_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeService', () {
    test('defaults to following the system', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(themeServiceProvider), AppThemeChoice.system);
    });

    test('setChoice(light) persists and updates state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(themeServiceProvider.notifier)
          .setChoice(AppThemeChoice.light);
      expect(container.read(themeServiceProvider), AppThemeChoice.light);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme'), 'light');
    });

    test('setChoice(system) clears the stored override', () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'dark'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(themeServiceProvider.notifier)
          .setChoice(AppThemeChoice.system);
      expect(container.read(themeServiceProvider), AppThemeChoice.system);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme'), isNull);
    });

    test('hydrates from shared_preferences on first read', () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'light'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeServiceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeServiceProvider), AppThemeChoice.light);
    });

    test('a stored value this build does not know is ignored', () async {
      SharedPreferences.setMockInitialValues({'app_theme': 'sepia'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(themeServiceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeServiceProvider), AppThemeChoice.system);
    });
  });

  group('resolveAppPalette', () {
    test('an explicit choice wins over the system', () {
      expect(
        resolveAppPalette(AppThemeChoice.light, Brightness.dark),
        AppPalette.light,
      );
      expect(
        resolveAppPalette(AppThemeChoice.dark, Brightness.light),
        AppPalette.dark,
      );
    });

    test('system follows the operating system', () {
      expect(
        resolveAppPalette(AppThemeChoice.system, Brightness.light),
        AppPalette.light,
      );
      expect(
        resolveAppPalette(AppThemeChoice.system, Brightness.dark),
        AppPalette.dark,
      );
    });
  });

  group('appPaletteProvider', () {
    test('combines the stored choice with the system brightness', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          systemBrightnessProvider.overrideWithValue(Brightness.light),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(appPaletteProvider), AppPalette.light);

      await container
          .read(themeServiceProvider.notifier)
          .setChoice(AppThemeChoice.dark);
      expect(container.read(appPaletteProvider), AppPalette.dark);
    });
  });
}
