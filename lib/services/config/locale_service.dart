import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selected app locale, or `null` to follow the system locale.
///
/// State value: `null` (follow system), `Locale('en')`, or `Locale('nl')`.
class LocaleService extends Notifier<Locale?> {
  static const String _prefsKey = 'app_locale';
  static const Set<String> _supportedLanguageCodes = {'en', 'nl'};

  @override
  Locale? build() {
    _hydrate();
    return null;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    if (!_supportedLanguageCodes.contains(raw)) return;
    state = Locale(raw);
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefsKey);
      state = null;
      return;
    }
    if (!_supportedLanguageCodes.contains(locale.languageCode)) {
      return;
    }
    await prefs.setString(_prefsKey, locale.languageCode);
    state = locale;
  }
}

final localeServiceProvider = NotifierProvider<LocaleService, Locale?>(
  LocaleService.new,
);
