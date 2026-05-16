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

  @override
  String get sidebar_teacherHeader => 'Docent';

  @override
  String get sidebar_section_session => 'Sessie';

  @override
  String get sidebar_section_map => 'Leerpad';

  @override
  String get sidebar_section_goals => 'Doelen';

  @override
  String get sidebar_section_lessonContent => 'Lesinhoud';

  @override
  String get sidebar_section_instructions => 'Instructies';

  @override
  String get sidebar_section_students => 'Studenten';

  @override
  String get session_mode_explain => 'Uitleg';

  @override
  String get session_mode_practice => 'Oefenen';

  @override
  String get session_mode_playground => 'Playground';

  @override
  String topBar_greeting(String name) {
    return 'Hoi $name,';
  }

  @override
  String get topBar_subline_default => 'aan de slag';

  @override
  String topBar_subline_withTopic(String topic) {
    return 'aan de slag met $topic';
  }

  @override
  String get topBar_streak_days => 'dagen';

  @override
  String topBar_xp_level(int level) {
    return 'Level $level';
  }

  @override
  String get auth_signIn_appBarTitle => 'Aanmelden';

  @override
  String get auth_signIn_prompt =>
      'Meld je aan met je school-Microsoft-account om verder te gaan.';

  @override
  String auth_signIn_errorPrefix(String error) {
    return 'Aanmelden mislukt: $error';
  }

  @override
  String get auth_signIn_button_idle => 'Aanmelden met schoolaccount';

  @override
  String get auth_signIn_button_busy => 'Bezig met aanmelden…';

  @override
  String get auth_localKey_appBarTitle => 'Geef je API-sleutel op';

  @override
  String get auth_localKey_explainer =>
      'Je account is nog niet goedgekeurd voor gebruik van de globale sleutel.\n\nJe kunt wachten tot je account is goedgekeurd, of je eigen OpenAI-API-sleutel opgeven om meteen verder te kunnen. Je sleutel wordt lokaal op dit toestel opgeslagen en alleen door deze app gebruikt.';

  @override
  String get auth_localKey_field_label => 'API-sleutel';

  @override
  String get auth_localKey_field_helper =>
      'We bewaren deze sleutel lokaal voor deze gebruiker op dit toestel.';

  @override
  String get auth_localKey_tooltip_showKey => 'Sleutel tonen';

  @override
  String get auth_localKey_tooltip_hideKey => 'Sleutel verbergen';

  @override
  String get auth_localKey_tooltip_paste => 'Plakken';

  @override
  String get auth_localKey_button_save => 'Sleutel opslaan';

  @override
  String get auth_localKey_validation_empty => 'Geef een API-sleutel op.';

  @override
  String get auth_localKey_saved => 'API-sleutel lokaal opgeslagen.';

  @override
  String auth_localKey_saveFailed(String error) {
    return 'Opslaan mislukt: $error';
  }

  @override
  String get auth_localKey_footnote =>
      'Opmerking: je kunt deze sleutel later wijzigen of verwijderen in Instellingen.';

  @override
  String get crash_title => 'Er ging iets mis';

  @override
  String get crash_defaultMessage =>
      'Dit kan gebeuren na wijzigingen aan rechten of regels.\nProbeer de app te resetten. Je wordt afgemeld en de caches worden gewist.';

  @override
  String get crash_resetButton => 'App resetten (rechten herstellen)';

  @override
  String get update_dialog_title => 'Update beschikbaar';

  @override
  String update_dialog_message(String version) {
    return 'Er is een nieuwere versie ($version) van de applicatie beschikbaar. De update wordt nu geïnstalleerd. Je kunt de app over enkele momenten opnieuw openen.';
  }

  @override
  String get update_dialog_ok => 'OK';
}
