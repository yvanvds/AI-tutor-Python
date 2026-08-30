// Light / dark theme selection (#32).
//
// Stored per device in SharedPreferences next to the locale override and the
// user's own OpenAI key — a theme is a property of the machine you are sitting
// at (a bright classroom, a dark bedroom), not of the account, and the Cosmos
// account doc is shared by every device a student signs in on.

import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user picked in Options. [system] follows the operating system.
enum AppThemeChoice { system, light, dark }

/// User-selected theme, hydrated from SharedPreferences on first read.
class ThemeService extends Notifier<AppThemeChoice> {
  static const String _prefsKey = 'app_theme';

  @override
  AppThemeChoice build() {
    _hydrate();
    return AppThemeChoice.system;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    for (final choice in AppThemeChoice.values) {
      if (choice.name == raw) {
        state = choice;
        return;
      }
    }
  }

  Future<void> setChoice(AppThemeChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    if (choice == AppThemeChoice.system) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, choice.name);
    }
    state = choice;
  }
}

final themeServiceProvider = NotifierProvider<ThemeService, AppThemeChoice>(
  ThemeService.new,
);

/// Operating-system brightness. Split out so tests can override it, the same
/// way `systemLocaleProvider` is.
final systemBrightnessProvider = Provider<Brightness>(
  (_) => WidgetsBinding.instance.platformDispatcher.platformBrightness,
);

/// The palette the app renders in: the user's choice when they made one, else
/// whatever the operating system is set to.
AppPalette resolveAppPalette(AppThemeChoice choice, Brightness system) {
  switch (choice) {
    case AppThemeChoice.light:
      return AppPalette.light;
    case AppThemeChoice.dark:
      return AppPalette.dark;
    case AppThemeChoice.system:
      return system == Brightness.light ? AppPalette.light : AppPalette.dark;
  }
}

/// Effective palette — what `GoalsApp` installs into [AppColors] and builds
/// its `ThemeData` from.
final appPaletteProvider = Provider<AppPalette>(
  (ref) => resolveAppPalette(
    ref.watch(themeServiceProvider),
    ref.watch(systemBrightnessProvider),
  ),
);
