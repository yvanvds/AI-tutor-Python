import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_nl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('nl'),
  ];

  /// Window title and application brand name
  ///
  /// In en, this message translates to:
  /// **'Python Course'**
  String get appTitle;

  /// No description provided for @settings_menuTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_menuTitle;

  /// No description provided for @settings_language_label.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settings_language_label;

  /// No description provided for @settings_language_system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settings_language_system;

  /// No description provided for @settings_language_english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settings_language_english;

  /// Dutch language name, kept in Dutch in both locales
  ///
  /// In en, this message translates to:
  /// **'Nederlands'**
  String get settings_language_dutch;

  /// No description provided for @sidebar_settings_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get sidebar_settings_tooltip;

  /// No description provided for @sidebar_signOut_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get sidebar_signOut_tooltip;

  /// No description provided for @sidebar_debug_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get sidebar_debug_tooltip;

  /// No description provided for @sidebar_teacherHeader.
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get sidebar_teacherHeader;

  /// No description provided for @sidebar_section_session.
  ///
  /// In en, this message translates to:
  /// **'Session'**
  String get sidebar_section_session;

  /// No description provided for @sidebar_section_map.
  ///
  /// In en, this message translates to:
  /// **'Learning path'**
  String get sidebar_section_map;

  /// No description provided for @sidebar_section_goals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get sidebar_section_goals;

  /// No description provided for @sidebar_section_lessonContent.
  ///
  /// In en, this message translates to:
  /// **'Lesson content'**
  String get sidebar_section_lessonContent;

  /// No description provided for @sidebar_section_instructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get sidebar_section_instructions;

  /// No description provided for @sidebar_section_students.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get sidebar_section_students;

  /// No description provided for @session_mode_explain.
  ///
  /// In en, this message translates to:
  /// **'Explain'**
  String get session_mode_explain;

  /// No description provided for @session_mode_practice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get session_mode_practice;

  /// No description provided for @session_mode_playground.
  ///
  /// In en, this message translates to:
  /// **'Playground'**
  String get session_mode_playground;

  /// No description provided for @topBar_greeting.
  ///
  /// In en, this message translates to:
  /// **'Hi {name},'**
  String topBar_greeting(String name);

  /// No description provided for @topBar_subline_default.
  ///
  /// In en, this message translates to:
  /// **'let\'s get started'**
  String get topBar_subline_default;

  /// No description provided for @topBar_subline_withTopic.
  ///
  /// In en, this message translates to:
  /// **'let\'s get started with {topic}'**
  String topBar_subline_withTopic(String topic);

  /// No description provided for @topBar_streak_days.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get topBar_streak_days;

  /// No description provided for @topBar_xp_level.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String topBar_xp_level(int level);

  /// No description provided for @auth_signIn_appBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get auth_signIn_appBarTitle;

  /// No description provided for @auth_signIn_prompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in with your school Microsoft account to continue.'**
  String get auth_signIn_prompt;

  /// No description provided for @auth_signIn_errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed: {error}'**
  String auth_signIn_errorPrefix(String error);

  /// No description provided for @auth_signIn_button_idle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with school account'**
  String get auth_signIn_button_idle;

  /// No description provided for @auth_signIn_button_busy.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get auth_signIn_button_busy;

  /// No description provided for @auth_localKey_appBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Provide Your API Key'**
  String get auth_localKey_appBarTitle;

  /// No description provided for @auth_localKey_explainer.
  ///
  /// In en, this message translates to:
  /// **'Your account is not yet approved to use the global key.\n\nYou can either wait until your account is approved, or provide your own OpenAI API key to continue immediately. Your key will be stored locally on this device and only used by this app.'**
  String get auth_localKey_explainer;

  /// No description provided for @auth_localKey_field_label.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get auth_localKey_field_label;

  /// No description provided for @auth_localKey_field_helper.
  ///
  /// In en, this message translates to:
  /// **'We\'ll store this key locally for this user on this device.'**
  String get auth_localKey_field_helper;

  /// No description provided for @auth_localKey_tooltip_showKey.
  ///
  /// In en, this message translates to:
  /// **'Show key'**
  String get auth_localKey_tooltip_showKey;

  /// No description provided for @auth_localKey_tooltip_hideKey.
  ///
  /// In en, this message translates to:
  /// **'Hide key'**
  String get auth_localKey_tooltip_hideKey;

  /// No description provided for @auth_localKey_tooltip_paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get auth_localKey_tooltip_paste;

  /// No description provided for @auth_localKey_button_save.
  ///
  /// In en, this message translates to:
  /// **'Save key'**
  String get auth_localKey_button_save;

  /// No description provided for @auth_localKey_validation_empty.
  ///
  /// In en, this message translates to:
  /// **'Please enter an API key.'**
  String get auth_localKey_validation_empty;

  /// No description provided for @auth_localKey_saved.
  ///
  /// In en, this message translates to:
  /// **'API key saved locally.'**
  String get auth_localKey_saved;

  /// No description provided for @auth_localKey_saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save key: {error}'**
  String auth_localKey_saveFailed(String error);

  /// No description provided for @auth_localKey_footnote.
  ///
  /// In en, this message translates to:
  /// **'Note: You can change or remove this key later in Settings.'**
  String get auth_localKey_footnote;

  /// No description provided for @crash_title.
  ///
  /// In en, this message translates to:
  /// **'We hit a problem'**
  String get crash_title;

  /// No description provided for @crash_defaultMessage.
  ///
  /// In en, this message translates to:
  /// **'This can happen after permission or rules changes.\nTry resetting the app. You’ll be signed out and caches will be cleared.'**
  String get crash_defaultMessage;

  /// No description provided for @crash_resetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset app (fix permissions)'**
  String get crash_resetButton;

  /// No description provided for @update_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get update_dialog_title;

  /// No description provided for @update_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'A newer version ({version}) of the application is available. The update will now be installed. You can open it again in a moment.'**
  String update_dialog_message(String version);

  /// No description provided for @update_dialog_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get update_dialog_ok;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'nl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'nl':
      return AppLocalizationsNl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
