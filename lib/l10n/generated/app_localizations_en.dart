// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Python Course';

  @override
  String get settings_menuTitle => 'Settings';

  @override
  String get settings_language_label => 'Language';

  @override
  String get settings_language_system => 'System';

  @override
  String get settings_language_english => 'English';

  @override
  String get settings_language_dutch => 'Nederlands';

  @override
  String get sidebar_settings_tooltip => 'Settings';

  @override
  String get sidebar_signOut_tooltip => 'Sign out';

  @override
  String get sidebar_debug_tooltip => 'Debug';
}
