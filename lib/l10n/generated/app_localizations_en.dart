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

  @override
  String get sidebar_teacherHeader => 'Teacher';

  @override
  String get sidebar_section_session => 'Session';

  @override
  String get sidebar_section_map => 'Learning path';

  @override
  String get sidebar_section_goals => 'Goals';

  @override
  String get sidebar_section_lessonContent => 'Lesson content';

  @override
  String get sidebar_section_instructions => 'Instructions';

  @override
  String get sidebar_section_students => 'Students';

  @override
  String get session_mode_explain => 'Explain';

  @override
  String get session_mode_practice => 'Practice';

  @override
  String get session_mode_playground => 'Playground';

  @override
  String topBar_greeting(String name) {
    return 'Hi $name,';
  }

  @override
  String get topBar_subline_default => 'let\'s get started';

  @override
  String topBar_subline_withTopic(String topic) {
    return 'let\'s get started with $topic';
  }

  @override
  String get topBar_streak_days => 'days';

  @override
  String topBar_xp_level(int level) {
    return 'Level $level';
  }

  @override
  String get auth_signIn_appBarTitle => 'Sign in';

  @override
  String get auth_signIn_prompt =>
      'Sign in with your school Microsoft account to continue.';

  @override
  String auth_signIn_errorPrefix(String error) {
    return 'Sign in failed: $error';
  }

  @override
  String get auth_signIn_button_idle => 'Sign in with school account';

  @override
  String get auth_signIn_button_busy => 'Signing in…';

  @override
  String get auth_localKey_appBarTitle => 'Provide Your API Key';

  @override
  String get auth_localKey_explainer =>
      'Your account is not yet approved to use the global key.\n\nYou can either wait until your account is approved, or provide your own OpenAI API key to continue immediately. Your key will be stored locally on this device and only used by this app.';

  @override
  String get auth_localKey_field_label => 'API Key';

  @override
  String get auth_localKey_field_helper =>
      'We\'ll store this key locally for this user on this device.';

  @override
  String get auth_localKey_tooltip_showKey => 'Show key';

  @override
  String get auth_localKey_tooltip_hideKey => 'Hide key';

  @override
  String get auth_localKey_tooltip_paste => 'Paste';

  @override
  String get auth_localKey_button_save => 'Save key';

  @override
  String get auth_localKey_validation_empty => 'Please enter an API key.';

  @override
  String get auth_localKey_saved => 'API key saved locally.';

  @override
  String auth_localKey_saveFailed(String error) {
    return 'Failed to save key: $error';
  }

  @override
  String get auth_localKey_footnote =>
      'Note: You can change or remove this key later in Settings.';

  @override
  String get crash_title => 'We hit a problem';

  @override
  String get crash_defaultMessage =>
      'This can happen after permission or rules changes.\nTry resetting the app. You’ll be signed out and caches will be cleared.';

  @override
  String get crash_resetButton => 'Reset app (fix permissions)';

  @override
  String get update_dialog_title => 'Update available';

  @override
  String update_dialog_message(String version) {
    return 'A newer version ($version) of the application is available. The update will now be installed. You can open it again in a moment.';
  }

  @override
  String get update_dialog_ok => 'OK';
}
