// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitle => 'Python Cursus';

  @override
  String get settings_menuTitle => 'Instellingen';

  @override
  String get settings_language_label => 'Taal';

  @override
  String get settings_language_system => 'Systeem';

  @override
  String get settings_language_english => 'English';

  @override
  String get settings_language_dutch => 'Nederlands';

  @override
  String get sidebar_settings_tooltip => 'Instellingen';

  @override
  String get sidebar_signOut_tooltip => 'Afmelden';

  @override
  String get sidebar_debug_tooltip => 'Debug';
}
