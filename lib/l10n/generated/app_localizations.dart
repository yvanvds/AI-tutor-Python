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

  /// No description provided for @sidebar_signOut_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get sidebar_signOut_tooltip;

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

  /// No description provided for @sidebar_section_options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get sidebar_section_options;

  /// No description provided for @options_page_title.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options_page_title;

  /// No description provided for @options_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Settings, maintenance and bug reports.'**
  String get options_page_subtitle;

  /// No description provided for @options_language_title.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get options_language_title;

  /// No description provided for @options_language_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Applies immediately; \"System\" follows the operating system.'**
  String get options_language_subtitle;

  /// No description provided for @options_theme_title.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get options_theme_title;

  /// No description provided for @options_theme_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Light or dark, stored on this device. \"System\" follows the operating system.'**
  String get options_theme_subtitle;

  /// No description provided for @options_theme_system.
  ///
  /// In en, this message translates to:
  /// **'Follow the system'**
  String get options_theme_system;

  /// No description provided for @options_theme_light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get options_theme_light;

  /// No description provided for @options_theme_dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get options_theme_dark;

  /// No description provided for @options_model_title.
  ///
  /// In en, this message translates to:
  /// **'AI model'**
  String get options_model_title;

  /// No description provided for @options_model_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Which OpenAI model the tutor asks. Applies to this device only; a bigger model is slower and costs more.'**
  String get options_model_subtitle;

  /// No description provided for @options_model_followGlobal.
  ///
  /// In en, this message translates to:
  /// **'School default ({model})'**
  String options_model_followGlobal(String model);

  /// No description provided for @options_progress_title.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get options_progress_title;

  /// No description provided for @options_progress_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Clearing progress also clears the tutor\'s memory of what you know. It cannot be undone.'**
  String get options_progress_subtitle;

  /// No description provided for @options_progress_resetAll_button.
  ///
  /// In en, this message translates to:
  /// **'Reset all progress'**
  String get options_progress_resetAll_button;

  /// No description provided for @options_progress_resetAll_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Reset all progress?'**
  String get options_progress_resetAll_dialog_title;

  /// No description provided for @options_progress_resetAll_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'This deletes all progress, learning history and tutor beliefs for your account, and resets the difficulty calibration to medium. This cannot be undone.'**
  String get options_progress_resetAll_dialog_message;

  /// No description provided for @options_progress_resetAll_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Reset everything'**
  String get options_progress_resetAll_dialog_confirm;

  /// No description provided for @options_progress_resetAll_done.
  ///
  /// In en, this message translates to:
  /// **'All progress has been reset.'**
  String get options_progress_resetAll_done;

  /// No description provided for @options_progress_resetGoal_button.
  ///
  /// In en, this message translates to:
  /// **'Reset one goal…'**
  String get options_progress_resetGoal_button;

  /// No description provided for @options_progress_resetGoal_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Reset progress for a goal'**
  String get options_progress_resetGoal_dialog_title;

  /// No description provided for @options_progress_resetGoal_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'Pick a goal or subgoal. Resetting a goal resets all of its subgoals.'**
  String get options_progress_resetGoal_dialog_message;

  /// No description provided for @options_progress_resetGoal_dialog_empty.
  ///
  /// In en, this message translates to:
  /// **'There are no goals yet.'**
  String get options_progress_resetGoal_dialog_empty;

  /// No description provided for @options_progress_resetGoal_dialog_loadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load goals: {error}'**
  String options_progress_resetGoal_dialog_loadError(String error);

  /// No description provided for @options_progress_resetGoal_confirm_title.
  ///
  /// In en, this message translates to:
  /// **'Reset \"{title}\"?'**
  String options_progress_resetGoal_confirm_title(String title);

  /// No description provided for @options_progress_resetGoal_confirm_message_subgoal.
  ///
  /// In en, this message translates to:
  /// **'Progress, learning history and tutor beliefs for this subgoal will be deleted. This cannot be undone.'**
  String get options_progress_resetGoal_confirm_message_subgoal;

  /// No description provided for @options_progress_resetGoal_confirm_message_root.
  ///
  /// In en, this message translates to:
  /// **'Progress, learning history and tutor beliefs for every subgoal of this goal will be deleted. This cannot be undone.'**
  String get options_progress_resetGoal_confirm_message_root;

  /// No description provided for @options_progress_resetGoal_confirm_button.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get options_progress_resetGoal_confirm_button;

  /// No description provided for @options_progress_resetGoal_done.
  ///
  /// In en, this message translates to:
  /// **'Progress for \"{title}\" has been reset.'**
  String options_progress_resetGoal_done(String title);

  /// No description provided for @options_progress_resetFailed.
  ///
  /// In en, this message translates to:
  /// **'Reset failed: {error}'**
  String options_progress_resetFailed(String error);

  /// No description provided for @options_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get options_dialog_cancel;

  /// No description provided for @options_transfer_title.
  ///
  /// In en, this message translates to:
  /// **'Export / import progress'**
  String get options_transfer_title;

  /// No description provided for @options_transfer_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Save your learning history to a file, or load it into this account — useful when you switch to another account.'**
  String get options_transfer_subtitle;

  /// No description provided for @options_transfer_export_button.
  ///
  /// In en, this message translates to:
  /// **'Export progress…'**
  String get options_transfer_export_button;

  /// No description provided for @options_transfer_import_button.
  ///
  /// In en, this message translates to:
  /// **'Import progress…'**
  String get options_transfer_import_button;

  /// No description provided for @options_transfer_exported.
  ///
  /// In en, this message translates to:
  /// **'Progress saved to {path}'**
  String options_transfer_exported(String path);

  /// No description provided for @options_transfer_exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String options_transfer_exportFailed(String error);

  /// No description provided for @options_transfer_import_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Replace your progress?'**
  String get options_transfer_import_dialog_title;

  /// No description provided for @options_transfer_import_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'Importing \"{file}\" deletes the progress, learning history and tutor beliefs this account has now and replaces them with the contents of the file. This cannot be undone.'**
  String options_transfer_import_dialog_message(String file);

  /// No description provided for @options_transfer_import_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Import and replace'**
  String get options_transfer_import_dialog_confirm;

  /// No description provided for @options_transfer_imported.
  ///
  /// In en, this message translates to:
  /// **'Imported {goals} goals, {samples} history entries and {beliefs} skill estimates.'**
  String options_transfer_imported(int goals, int samples, int beliefs);

  /// No description provided for @options_transfer_importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String options_transfer_importFailed(String error);

  /// No description provided for @options_apiKey_title.
  ///
  /// In en, this message translates to:
  /// **'OpenAI API key'**
  String get options_apiKey_title;

  /// No description provided for @options_apiKey_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Your own key, stored on this device. Removing it takes you back to the key screen.'**
  String get options_apiKey_subtitle;

  /// No description provided for @options_apiKey_status_present.
  ///
  /// In en, this message translates to:
  /// **'A key is stored on this device.'**
  String get options_apiKey_status_present;

  /// No description provided for @options_apiKey_status_missing.
  ///
  /// In en, this message translates to:
  /// **'No key stored on this device.'**
  String get options_apiKey_status_missing;

  /// No description provided for @options_apiKey_change_button.
  ///
  /// In en, this message translates to:
  /// **'Change key'**
  String get options_apiKey_change_button;

  /// No description provided for @options_apiKey_remove_button.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get options_apiKey_remove_button;

  /// No description provided for @options_apiKey_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Change API key'**
  String get options_apiKey_dialog_title;

  /// No description provided for @options_apiKey_dialog_field.
  ///
  /// In en, this message translates to:
  /// **'New API key'**
  String get options_apiKey_dialog_field;

  /// No description provided for @options_apiKey_dialog_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get options_apiKey_dialog_save;

  /// No description provided for @options_apiKey_saved.
  ///
  /// In en, this message translates to:
  /// **'API key updated.'**
  String get options_apiKey_saved;

  /// No description provided for @options_apiKey_remove_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Remove API key?'**
  String get options_apiKey_remove_dialog_title;

  /// No description provided for @options_apiKey_remove_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'The tutor cannot answer without a key. You will be asked for a new key right away.'**
  String get options_apiKey_remove_dialog_message;

  /// No description provided for @options_apiKey_remove_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get options_apiKey_remove_dialog_confirm;

  /// No description provided for @options_apiKey_removed.
  ///
  /// In en, this message translates to:
  /// **'API key removed.'**
  String get options_apiKey_removed;

  /// No description provided for @options_bugReport_title.
  ///
  /// In en, this message translates to:
  /// **'Bug reports'**
  String get options_bugReport_title;

  /// No description provided for @options_bugReport_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Post an issue on GitHub straight from the app, with the debug data of a recent tutor turn attached.'**
  String get options_bugReport_subtitle;

  /// No description provided for @options_bugReport_github_notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to GitHub.'**
  String get options_bugReport_github_notConnected;

  /// No description provided for @options_bugReport_github_connectedAs.
  ///
  /// In en, this message translates to:
  /// **'Connected to GitHub as {login}.'**
  String options_bugReport_github_connectedAs(String login);

  /// No description provided for @options_bugReport_github_connect_button.
  ///
  /// In en, this message translates to:
  /// **'Connect GitHub'**
  String get options_bugReport_github_connect_button;

  /// No description provided for @options_bugReport_github_disconnect_button.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get options_bugReport_github_disconnect_button;

  /// No description provided for @options_bugReport_github_notConfigured.
  ///
  /// In en, this message translates to:
  /// **'This build cannot sign in to GitHub: it was compiled without a GitHub OAuth client id, so bug reports can only be filed on github.com by hand.'**
  String get options_bugReport_github_notConfigured;

  /// No description provided for @options_bugReport_github_device_explainer.
  ///
  /// In en, this message translates to:
  /// **'Type this code on GitHub to let the app create issues on {repo}. Nothing is stored until you approve it.'**
  String options_bugReport_github_device_explainer(String repo);

  /// No description provided for @options_bugReport_github_device_instruction.
  ///
  /// In en, this message translates to:
  /// **'Enter the code at {url}'**
  String options_bugReport_github_device_instruction(String url);

  /// No description provided for @options_bugReport_github_device_waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you to approve it on GitHub…'**
  String get options_bugReport_github_device_waiting;

  /// No description provided for @options_bugReport_github_device_openBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open GitHub'**
  String get options_bugReport_github_device_openBrowser;

  /// No description provided for @options_bugReport_github_device_copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get options_bugReport_github_device_copyCode;

  /// No description provided for @options_bugReport_github_device_codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied to the clipboard.'**
  String get options_bugReport_github_device_codeCopied;

  /// No description provided for @options_bugReport_github_device_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get options_bugReport_github_device_cancel;

  /// No description provided for @options_bugReport_github_device_browserFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open a browser. Go to {url} yourself.'**
  String options_bugReport_github_device_browserFailed(String url);

  /// No description provided for @options_bugReport_github_device_expired.
  ///
  /// In en, this message translates to:
  /// **'The code expired before it was approved. Try again.'**
  String get options_bugReport_github_device_expired;

  /// No description provided for @options_bugReport_github_device_denied.
  ///
  /// In en, this message translates to:
  /// **'The request was declined on GitHub, so nothing was connected.'**
  String get options_bugReport_github_device_denied;

  /// No description provided for @options_bugReport_github_connectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect: {error}'**
  String options_bugReport_github_connectFailed(String error);

  /// No description provided for @options_bugReport_report_button.
  ///
  /// In en, this message translates to:
  /// **'Report a bug…'**
  String get options_bugReport_report_button;

  /// No description provided for @options_bugReport_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Report a bug'**
  String get options_bugReport_dialog_title;

  /// No description provided for @options_bugReport_dialog_titleField.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get options_bugReport_dialog_titleField;

  /// No description provided for @options_bugReport_dialog_titleRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title.'**
  String get options_bugReport_dialog_titleRequired;

  /// No description provided for @options_bugReport_dialog_descriptionField.
  ///
  /// In en, this message translates to:
  /// **'What went wrong?'**
  String get options_bugReport_dialog_descriptionField;

  /// No description provided for @options_bugReport_dialog_turnField.
  ///
  /// In en, this message translates to:
  /// **'Attach tutor turn'**
  String get options_bugReport_dialog_turnField;

  /// No description provided for @options_bugReport_dialog_turnNone.
  ///
  /// In en, this message translates to:
  /// **'No turn'**
  String get options_bugReport_dialog_turnNone;

  /// No description provided for @options_bugReport_dialog_turnLabel.
  ///
  /// In en, this message translates to:
  /// **'#{id} {type}'**
  String options_bugReport_dialog_turnLabel(int id, String type);

  /// No description provided for @options_bugReport_dialog_submit.
  ///
  /// In en, this message translates to:
  /// **'Post issue'**
  String get options_bugReport_dialog_submit;

  /// No description provided for @options_bugReport_posted.
  ///
  /// In en, this message translates to:
  /// **'Issue posted: {url}'**
  String options_bugReport_posted(String url);

  /// No description provided for @options_bugReport_postFailed.
  ///
  /// In en, this message translates to:
  /// **'Posting failed: {error}'**
  String options_bugReport_postFailed(String error);

  /// No description provided for @options_developer_title.
  ///
  /// In en, this message translates to:
  /// **'Developer tools'**
  String get options_developer_title;

  /// No description provided for @options_developer_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Only visible in developer builds.'**
  String get options_developer_subtitle;

  /// No description provided for @options_developer_levelUp_button.
  ///
  /// In en, this message translates to:
  /// **'Show level-up overlay'**
  String get options_developer_levelUp_button;

  /// No description provided for @options_developer_triggerQuestion_title.
  ///
  /// In en, this message translates to:
  /// **'Trigger question'**
  String get options_developer_triggerQuestion_title;

  /// No description provided for @options_developer_difficulty_label.
  ///
  /// In en, this message translates to:
  /// **'Difficulty:'**
  String get options_developer_difficulty_label;

  /// No description provided for @options_developer_recentTurns_title.
  ///
  /// In en, this message translates to:
  /// **'Recent turns'**
  String get options_developer_recentTurns_title;

  /// No description provided for @options_developer_recentTurns_copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get options_developer_recentTurns_copyAll;

  /// No description provided for @options_developer_recentTurns_copied.
  ///
  /// In en, this message translates to:
  /// **'Copied {count} turns to clipboard.'**
  String options_developer_recentTurns_copied(int count);

  /// No description provided for @options_developer_recentTurns_empty.
  ///
  /// In en, this message translates to:
  /// **'No turns recorded yet.'**
  String get options_developer_recentTurns_empty;

  /// No description provided for @options_developer_turnDetail_title.
  ///
  /// In en, this message translates to:
  /// **'Turn #{id}'**
  String options_developer_turnDetail_title(int id);

  /// No description provided for @options_developer_turnDetail_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get options_developer_turnDetail_close;

  /// No description provided for @options_about_title.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get options_about_title;

  /// No description provided for @options_about_version.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String options_about_version(String version);

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

  /// No description provided for @update_status_idle.
  ///
  /// In en, this message translates to:
  /// **'No update check has run yet.'**
  String get update_status_idle;

  /// No description provided for @update_status_checking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get update_status_checking;

  /// No description provided for @update_status_upToDate.
  ///
  /// In en, this message translates to:
  /// **'You have the newest version.'**
  String get update_status_upToDate;

  /// No description provided for @update_status_available.
  ///
  /// In en, this message translates to:
  /// **'Version {version} is available.'**
  String update_status_available(String version);

  /// No description provided for @update_status_downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading version {version}…'**
  String update_status_downloading(String version);

  /// No description provided for @update_status_applying.
  ///
  /// In en, this message translates to:
  /// **'Starting the installer. The app closes itself and comes back as version {version}.'**
  String update_status_applying(String version);

  /// No description provided for @update_status_failed.
  ///
  /// In en, this message translates to:
  /// **'The update did not succeed: {reason}'**
  String update_status_failed(String reason);

  /// No description provided for @update_action_apply.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update_action_apply;

  /// No description provided for @update_action_applyVersion.
  ///
  /// In en, this message translates to:
  /// **'Update to {version}'**
  String update_action_applyVersion(String version);

  /// No description provided for @update_action_later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get update_action_later;

  /// No description provided for @update_action_check.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get update_action_check;

  /// No description provided for @session_explain_placeholder_noSubgoal.
  ///
  /// In en, this message translates to:
  /// **'Pick a subgoal in the learning path to see the explanation.'**
  String get session_explain_placeholder_noSubgoal;

  /// No description provided for @session_explain_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading lesson…'**
  String get session_explain_loading;

  /// No description provided for @session_explain_missingContent.
  ///
  /// In en, this message translates to:
  /// **'No lesson content available for this subgoal yet.'**
  String get session_explain_missingContent;

  /// Fallback label for the explain-view root pill when no root goal is set; displayed uppercase
  ///
  /// In en, this message translates to:
  /// **'Concept'**
  String get session_explain_defaultPillLabel;

  /// No description provided for @session_explain_prev_button.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get session_explain_prev_button;

  /// No description provided for @session_explain_completeXp.
  ///
  /// In en, this message translates to:
  /// **'+10 XP on completion'**
  String get session_explain_completeXp;

  /// No description provided for @session_explain_tryItYourself.
  ///
  /// In en, this message translates to:
  /// **'Try it yourself'**
  String get session_explain_tryItYourself;

  /// No description provided for @session_playground_pill.
  ///
  /// In en, this message translates to:
  /// **'playground'**
  String get session_playground_pill;

  /// No description provided for @session_playground_subtitle.
  ///
  /// In en, this message translates to:
  /// **'No goal — just you and Python.'**
  String get session_playground_subtitle;

  /// No description provided for @session_playground_open_button.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get session_playground_open_button;

  /// No description provided for @session_playground_open_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Open saved code'**
  String get session_playground_open_tooltip;

  /// No description provided for @session_playground_save_button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get session_playground_save_button;

  /// No description provided for @session_playground_save_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Save this code'**
  String get session_playground_save_tooltip;

  /// No description provided for @session_playground_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get session_playground_dialog_cancel;

  /// No description provided for @session_playground_saveDialog_title.
  ///
  /// In en, this message translates to:
  /// **'Save code'**
  String get session_playground_saveDialog_title;

  /// No description provided for @session_playground_saveDialog_nameLabel.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get session_playground_saveDialog_nameLabel;

  /// No description provided for @session_playground_saveDialog_invalidName.
  ///
  /// In en, this message translates to:
  /// **'Use letters, digits, spaces, - or _ (max 60 characters).'**
  String get session_playground_saveDialog_invalidName;

  /// No description provided for @session_playground_saveDialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get session_playground_saveDialog_confirm;

  /// No description provided for @session_playground_overwriteDialog_title.
  ///
  /// In en, this message translates to:
  /// **'Overwrite \"{name}\"?'**
  String session_playground_overwriteDialog_title(String name);

  /// No description provided for @session_playground_overwriteDialog_message.
  ///
  /// In en, this message translates to:
  /// **'A file with this name already exists.'**
  String get session_playground_overwriteDialog_message;

  /// No description provided for @session_playground_overwriteDialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get session_playground_overwriteDialog_confirm;

  /// No description provided for @session_playground_openDialog_title.
  ///
  /// In en, this message translates to:
  /// **'Open saved code'**
  String get session_playground_openDialog_title;

  /// No description provided for @session_playground_openDialog_empty.
  ///
  /// In en, this message translates to:
  /// **'No saved files yet.'**
  String get session_playground_openDialog_empty;

  /// No description provided for @session_playground_openDialog_delete_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get session_playground_openDialog_delete_tooltip;

  /// Shown above the file list after a sync had to keep two versions of a file
  ///
  /// In en, this message translates to:
  /// **'Also changed on another computer. This computer\'s version was kept separately as: {names}'**
  String session_playground_openDialog_conflict(String names);

  /// No description provided for @session_playground_deleteDialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String session_playground_deleteDialog_title(String name);

  /// No description provided for @session_playground_deleteDialog_message.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get session_playground_deleteDialog_message;

  /// No description provided for @session_playground_deleteDialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get session_playground_deleteDialog_confirm;

  /// No description provided for @session_playground_discardDialog_title.
  ///
  /// In en, this message translates to:
  /// **'Replace current code?'**
  String get session_playground_discardDialog_title;

  /// No description provided for @session_playground_discardDialog_message.
  ///
  /// In en, this message translates to:
  /// **'Your unsaved changes will be lost.'**
  String get session_playground_discardDialog_message;

  /// No description provided for @session_playground_discardDialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get session_playground_discardDialog_confirm;

  /// No description provided for @session_playground_snack_saved.
  ///
  /// In en, this message translates to:
  /// **'Saved as \"{name}\".'**
  String session_playground_snack_saved(String name);

  /// No description provided for @session_playground_snack_saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Saving failed: {error}'**
  String session_playground_snack_saveFailed(String error);

  /// No description provided for @session_playground_snack_openFailed.
  ///
  /// In en, this message translates to:
  /// **'Opening failed: {error}'**
  String session_playground_snack_openFailed(String error);

  /// No description provided for @session_playground_snack_tooLarge.
  ///
  /// In en, this message translates to:
  /// **'This code is too large to save (over {max} KB).'**
  String session_playground_snack_tooLarge(int max);

  /// No description provided for @session_playground_snack_tooManyFiles.
  ///
  /// In en, this message translates to:
  /// **'You already have {max} saved files, which is the maximum. Delete one first.'**
  String session_playground_snack_tooManyFiles(int max);

  /// Quiz header pill — displayed uppercase
  ///
  /// In en, this message translates to:
  /// **'Quiz question'**
  String get session_quiz_pill;

  /// No description provided for @session_quiz_next_button.
  ///
  /// In en, this message translates to:
  /// **'Next →'**
  String get session_quiz_next_button;

  /// No description provided for @session_output_state_idle.
  ///
  /// In en, this message translates to:
  /// **'No output'**
  String get session_output_state_idle;

  /// No description provided for @session_output_state_running.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get session_output_state_running;

  /// No description provided for @session_output_state_ok.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get session_output_state_ok;

  /// No description provided for @session_output_state_error_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 error} other{{count} errors}}'**
  String session_output_state_error_count(int count);

  /// No description provided for @session_output_header_label.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get session_output_header_label;

  /// No description provided for @session_output_emptyState_runHint.
  ///
  /// In en, this message translates to:
  /// **'Press Run to execute your code.'**
  String get session_output_emptyState_runHint;

  /// Faint meta line pushed to the output panel when a run's code imports turtle — the Tk window opens outside the app and turtle.done() blocks until it is closed (#51)
  ///
  /// In en, this message translates to:
  /// **'A turtle window is open. Close it, or press Stop, to finish the run.'**
  String get session_output_meta_turtleWindow;

  /// Faint meta line pushed to the output panel when the student presses Stop (#51)
  ///
  /// In en, this message translates to:
  /// **'Stopped.'**
  String get session_output_meta_stopped;

  /// No description provided for @session_runControls_tooltip_resetOutput.
  ///
  /// In en, this message translates to:
  /// **'Reset output'**
  String get session_runControls_tooltip_resetOutput;

  /// No description provided for @session_runControls_tooltip_askHint.
  ///
  /// In en, this message translates to:
  /// **'Ask for a hint'**
  String get session_runControls_tooltip_askHint;

  /// No description provided for @session_runControls_tooltip_sendToTutor.
  ///
  /// In en, this message translates to:
  /// **'Send to tutor'**
  String get session_runControls_tooltip_sendToTutor;

  /// No description provided for @session_runControls_chatMessage_needHint.
  ///
  /// In en, this message translates to:
  /// **'I need a hint.'**
  String get session_runControls_chatMessage_needHint;

  /// No description provided for @session_runControls_chatMessage_hereIsCode.
  ///
  /// In en, this message translates to:
  /// **'Here is my code.'**
  String get session_runControls_chatMessage_hereIsCode;

  /// No description provided for @session_runControls_button_run.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get session_runControls_button_run;

  /// No description provided for @session_runControls_button_stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get session_runControls_button_stop;

  /// Banner header pill at the top of practice view — displayed uppercase
  ///
  /// In en, this message translates to:
  /// **'Current goal'**
  String get session_objectiveBanner_pill;

  /// No description provided for @chat_tutorName.
  ///
  /// In en, this message translates to:
  /// **'Tutor'**
  String get chat_tutorName;

  /// No description provided for @chat_userName_you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chat_userName_you;

  /// No description provided for @chat_loading_thinking.
  ///
  /// In en, this message translates to:
  /// **'Tutor is thinking…'**
  String get chat_loading_thinking;

  /// No description provided for @chat_header_presence_online.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get chat_header_presence_online;

  /// Connective fragment between 'online' and the topic name; leading dot and bullet are part of the string
  ///
  /// In en, this message translates to:
  /// **' · helping you with '**
  String get chat_header_presence_helpsWith;

  /// No description provided for @chat_header_restart_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Restart session'**
  String get chat_header_restart_tooltip;

  /// No description provided for @chat_composer_idle_hint.
  ///
  /// In en, this message translates to:
  /// **'Type your question or answer…'**
  String get chat_composer_idle_hint;

  /// No description provided for @chat_composer_idle_kbd_send.
  ///
  /// In en, this message translates to:
  /// **'send'**
  String get chat_composer_idle_kbd_send;

  /// No description provided for @chat_composer_idle_kbd_newline.
  ///
  /// In en, this message translates to:
  /// **'new line'**
  String get chat_composer_idle_kbd_newline;

  /// No description provided for @chat_composer_idle_tip_prefix.
  ///
  /// In en, this message translates to:
  /// **'tip: type '**
  String get chat_composer_idle_tip_prefix;

  /// Trailing fragment of the hint tip — leading space is part of the string
  ///
  /// In en, this message translates to:
  /// **' for a hint'**
  String get chat_composer_idle_tip_suffix;

  /// No description provided for @chat_composer_idle_hintMessage.
  ///
  /// In en, this message translates to:
  /// **'I need a hint'**
  String get chat_composer_idle_hintMessage;

  /// No description provided for @chat_composer_thinking_label.
  ///
  /// In en, this message translates to:
  /// **'Tutor is thinking…'**
  String get chat_composer_thinking_label;

  /// No description provided for @chat_composer_continue_prompt.
  ///
  /// In en, this message translates to:
  /// **'Ready for the next part?'**
  String get chat_composer_continue_prompt;

  /// No description provided for @chat_composer_continue_button.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get chat_composer_continue_button;

  /// No description provided for @chat_composer_mcqDisabled_label.
  ///
  /// In en, this message translates to:
  /// **'Tap an answer above'**
  String get chat_composer_mcqDisabled_label;

  /// No description provided for @goals_header_title.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get goals_header_title;

  /// No description provided for @goals_action_export.
  ///
  /// In en, this message translates to:
  /// **'Export goals'**
  String get goals_action_export;

  /// No description provided for @goals_action_import.
  ///
  /// In en, this message translates to:
  /// **'Import goals'**
  String get goals_action_import;

  /// No description provided for @goals_snack_noGoalsToExport.
  ///
  /// In en, this message translates to:
  /// **'No goals to export'**
  String get goals_snack_noGoalsToExport;

  /// No description provided for @goals_snack_exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String goals_snack_exportedTo(String path);

  /// No description provided for @goals_snack_exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String goals_snack_exportFailed(String error);

  /// No description provided for @goals_snack_fileEmpty.
  ///
  /// In en, this message translates to:
  /// **'File contained no goals'**
  String get goals_snack_fileEmpty;

  /// No description provided for @goals_snack_addAborted.
  ///
  /// In en, this message translates to:
  /// **'Add aborted: {count} id(s) already exist (e.g. {sample}). Use Replace, or remove the duplicates first.'**
  String goals_snack_addAborted(int count, String sample);

  /// No description provided for @goals_snack_imported.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} goal(s)'**
  String goals_snack_imported(int count);

  /// No description provided for @goals_snack_importedWithRemoved.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} goal(s) (removed {removed} not in file)'**
  String goals_snack_importedWithRemoved(int count, int removed);

  /// No description provided for @goals_snack_importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String goals_snack_importFailed(String error);

  /// No description provided for @goals_snack_couldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read selected file'**
  String get goals_snack_couldNotRead;

  /// No description provided for @goals_snack_invalidFile.
  ///
  /// In en, this message translates to:
  /// **'Invalid goals file'**
  String get goals_snack_invalidFile;

  /// No description provided for @goals_import_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Import goals'**
  String get goals_import_dialog_title;

  /// No description provided for @goals_import_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'The file contains {rootCount} root goal(s) and {total} total node(s).\n\n• Add: append using the ids from the file. Aborts if any id already exists.\n• Replace: update the matching set(s) by id (keeps existing lesson content links) and remove only goals under those sets that are not in the file. Other sets are left untouched.\n• Replace all: remove every goal not in the file, across all sets.'**
  String goals_import_dialog_message(int rootCount, int total);

  /// No description provided for @goals_import_action_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get goals_import_action_cancel;

  /// No description provided for @goals_import_action_add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get goals_import_action_add;

  /// No description provided for @goals_import_action_replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get goals_import_action_replace;

  /// No description provided for @goals_import_action_replaceAll.
  ///
  /// In en, this message translates to:
  /// **'Replace all'**
  String get goals_import_action_replaceAll;

  /// No description provided for @goals_import_action_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get goals_import_action_continue;

  /// No description provided for @goals_import_unmatched_title.
  ///
  /// In en, this message translates to:
  /// **'No matching set'**
  String get goals_import_unmatched_title;

  /// No description provided for @goals_import_unmatched_message.
  ///
  /// In en, this message translates to:
  /// **'The set \"{rootTitle}\" in the file does not match any existing set. Choose what to do with it.'**
  String goals_import_unmatched_message(String rootTitle);

  /// No description provided for @goals_import_unmatched_addAsNew.
  ///
  /// In en, this message translates to:
  /// **'Add as a new set'**
  String get goals_import_unmatched_addAsNew;

  /// No description provided for @goals_import_unmatched_replaceOption.
  ///
  /// In en, this message translates to:
  /// **'Replace \"{rootTitle}\"'**
  String goals_import_unmatched_replaceOption(String rootTitle);

  /// No description provided for @goals_import_preview_title.
  ///
  /// In en, this message translates to:
  /// **'Confirm replace'**
  String get goals_import_preview_title;

  /// No description provided for @goals_import_preview_replaceLine.
  ///
  /// In en, this message translates to:
  /// **'Replaces \"{rootTitle}\" ({count} goal(s) in file, {removed} will be removed)'**
  String goals_import_preview_replaceLine(
    String rootTitle,
    int count,
    int removed,
  );

  /// No description provided for @goals_import_preview_newSetLine.
  ///
  /// In en, this message translates to:
  /// **'Adds new set \"{rootTitle}\"'**
  String goals_import_preview_newSetLine(String rootTitle);

  /// No description provided for @goals_import_previewAll_title.
  ///
  /// In en, this message translates to:
  /// **'Replace all sets'**
  String get goals_import_previewAll_title;

  /// No description provided for @goals_import_previewAll_message.
  ///
  /// In en, this message translates to:
  /// **'This removes every goal not in the file, across all sets: {removed} goal(s) will be removed.'**
  String goals_import_previewAll_message(int removed);

  /// No description provided for @goals_import_filePicker_title.
  ///
  /// In en, this message translates to:
  /// **'Select goals JSON to import'**
  String get goals_import_filePicker_title;

  /// No description provided for @goals_editor_title.
  ///
  /// In en, this message translates to:
  /// **'Edit goal'**
  String get goals_editor_title;

  /// No description provided for @goals_editor_tooltip_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get goals_editor_tooltip_delete;

  /// No description provided for @goals_editor_tooltip_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get goals_editor_tooltip_close;

  /// No description provided for @goals_editor_field_title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get goals_editor_field_title;

  /// No description provided for @goals_editor_untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get goals_editor_untitled;

  /// No description provided for @goals_editor_field_description.
  ///
  /// In en, this message translates to:
  /// **'Describe this goal for students.'**
  String get goals_editor_field_description;

  /// No description provided for @goals_editor_switch_optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get goals_editor_switch_optional;

  /// No description provided for @goals_editor_switch_concept.
  ///
  /// In en, this message translates to:
  /// **'Concept goal'**
  String get goals_editor_switch_concept;

  /// No description provided for @goals_editor_switch_concept_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Mastering this subgoal triggers the level-up overlay.'**
  String get goals_editor_switch_concept_subtitle;

  /// No description provided for @goals_editor_teachingTips_label.
  ///
  /// In en, this message translates to:
  /// **'Teaching tips'**
  String get goals_editor_teachingTips_label;

  /// No description provided for @goals_editor_teachingTips_hint.
  ///
  /// In en, this message translates to:
  /// **'Type a teaching tip and hit Enter'**
  String get goals_editor_teachingTips_hint;

  /// No description provided for @goals_editor_teachingTips_empty.
  ///
  /// In en, this message translates to:
  /// **'No teaching tips yet.'**
  String get goals_editor_teachingTips_empty;

  /// No description provided for @goals_editor_teachingTips_add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get goals_editor_teachingTips_add;

  /// No description provided for @goals_editor_teachingTips_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit tip'**
  String get goals_editor_teachingTips_edit;

  /// No description provided for @goals_editor_teachingTips_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete tip'**
  String get goals_editor_teachingTips_delete;

  /// No description provided for @goals_editor_teachingTips_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get goals_editor_teachingTips_save;

  /// No description provided for @goals_editor_teachingTips_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get goals_editor_teachingTips_cancel;

  /// No description provided for @goals_editor_lesinhoud_label.
  ///
  /// In en, this message translates to:
  /// **'Lesson content'**
  String get goals_editor_lesinhoud_label;

  /// No description provided for @goals_editor_lesinhoud_linked.
  ///
  /// In en, this message translates to:
  /// **'Lesson content linked'**
  String get goals_editor_lesinhoud_linked;

  /// No description provided for @goals_editor_lesinhoud_none.
  ///
  /// In en, this message translates to:
  /// **'(no lesson content)'**
  String get goals_editor_lesinhoud_none;

  /// No description provided for @goals_editor_lesinhoud_edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get goals_editor_lesinhoud_edit;

  /// No description provided for @goals_editor_lesinhoud_create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get goals_editor_lesinhoud_create;

  /// No description provided for @goals_editor_delete_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete goal'**
  String get goals_editor_delete_dialog_title;

  /// No description provided for @goals_editor_delete_dialog_message_single.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String goals_editor_delete_dialog_message_single(String title);

  /// No description provided for @goals_editor_delete_dialog_message_withDescendants.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" and its {count} descendant(s)?'**
  String goals_editor_delete_dialog_message_withDescendants(
    String title,
    int count,
  );

  /// No description provided for @goals_editor_delete_action_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get goals_editor_delete_action_cancel;

  /// No description provided for @goals_editor_delete_action_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get goals_editor_delete_action_confirm;

  /// No description provided for @goals_editor_deleted_single.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\".'**
  String goals_editor_deleted_single(String title);

  /// No description provided for @goals_editor_deleted_withDescendants.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\" (+{count}).'**
  String goals_editor_deleted_withDescendants(String title, int count);

  /// No description provided for @goals_pane_error.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String goals_pane_error(String error);

  /// No description provided for @goals_pane_noData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get goals_pane_noData;

  /// No description provided for @goals_pane_reordered.
  ///
  /// In en, this message translates to:
  /// **'Reordered \"{title}\".'**
  String goals_pane_reordered(String title);

  /// No description provided for @goals_childPane_empty_pickRoot.
  ///
  /// In en, this message translates to:
  /// **'Select a root goal to see its children.'**
  String get goals_childPane_empty_pickRoot;

  /// No description provided for @goals_childPane_addHint.
  ///
  /// In en, this message translates to:
  /// **'Add child goal… (Enter)'**
  String get goals_childPane_addHint;

  /// No description provided for @goals_childPane_empty_addOne.
  ///
  /// In en, this message translates to:
  /// **'No children yet. Add one above.'**
  String get goals_childPane_empty_addOne;

  /// No description provided for @goals_rootPane_addHint.
  ///
  /// In en, this message translates to:
  /// **'Add root goal… (Enter)'**
  String get goals_rootPane_addHint;

  /// No description provided for @goals_rootPane_empty_addOne.
  ///
  /// In en, this message translates to:
  /// **'No goals yet. Add one above.'**
  String get goals_rootPane_empty_addOne;

  /// No description provided for @goals_parentField_label.
  ///
  /// In en, this message translates to:
  /// **'Parent'**
  String get goals_parentField_label;

  /// No description provided for @goals_parentField_noParent.
  ///
  /// In en, this message translates to:
  /// **'(no parent)'**
  String get goals_parentField_noParent;

  /// No description provided for @goals_parentField_loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load parents: {error}'**
  String goals_parentField_loadFailed(String error);

  /// No description provided for @goals_editorPanel_loadError.
  ///
  /// In en, this message translates to:
  /// **'Error loading documents: {error}'**
  String goals_editorPanel_loadError(String error);

  /// No description provided for @goals_editorPanel_noGoalSelected.
  ///
  /// In en, this message translates to:
  /// **'No goal selected.'**
  String get goals_editorPanel_noGoalSelected;

  /// No description provided for @lesson_toolbar_title.
  ///
  /// In en, this message translates to:
  /// **'Lesson content'**
  String get lesson_toolbar_title;

  /// No description provided for @lesson_toolbar_upload.
  ///
  /// In en, this message translates to:
  /// **'Upload .html'**
  String get lesson_toolbar_upload;

  /// No description provided for @lesson_toolbar_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get lesson_toolbar_save;

  /// No description provided for @lesson_toolbar_save_dirty.
  ///
  /// In en, this message translates to:
  /// **'Save *'**
  String get lesson_toolbar_save_dirty;

  /// No description provided for @lesson_snack_saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get lesson_snack_saved;

  /// No description provided for @lesson_snack_couldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read file.'**
  String get lesson_snack_couldNotRead;

  /// No description provided for @lesson_loadError.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String lesson_loadError(String error);

  /// No description provided for @lesson_unlink_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Unlink lesson content?'**
  String get lesson_unlink_dialog_title;

  /// No description provided for @lesson_unlink_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'The content document stays in place, but this subgoal will no longer point to it.'**
  String get lesson_unlink_dialog_message;

  /// No description provided for @lesson_unlink_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get lesson_unlink_dialog_cancel;

  /// No description provided for @lesson_unlink_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get lesson_unlink_dialog_confirm;

  /// No description provided for @lesson_editor_empty_pickSubgoal.
  ///
  /// In en, this message translates to:
  /// **'Pick a subgoal to edit its lesson content.'**
  String get lesson_editor_empty_pickSubgoal;

  /// No description provided for @lesson_editor_field_title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get lesson_editor_field_title;

  /// No description provided for @lesson_editor_button_unlink.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get lesson_editor_button_unlink;

  /// No description provided for @lesson_preview_empty.
  ///
  /// In en, this message translates to:
  /// **'The preview appears here as soon as you add HTML.'**
  String get lesson_preview_empty;

  /// No description provided for @lesson_subgoal_noContent.
  ///
  /// In en, this message translates to:
  /// **'(no lesson content)'**
  String get lesson_subgoal_noContent;

  /// No description provided for @lesson_default_moduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Python basics'**
  String get lesson_default_moduleTitle;

  /// No description provided for @lesson_orphans_header.
  ///
  /// In en, this message translates to:
  /// **'Orphaned lesson content'**
  String get lesson_orphans_header;

  /// No description provided for @lesson_orphans_hint.
  ///
  /// In en, this message translates to:
  /// **'Not linked to any subgoal. Click to reassign.'**
  String get lesson_orphans_hint;

  /// No description provided for @lesson_reassign_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Reassign lesson content'**
  String get lesson_reassign_dialog_title;

  /// No description provided for @lesson_reassign_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'Pick the subgoal that \"{title}\" belongs to.'**
  String lesson_reassign_dialog_message(String title);

  /// No description provided for @lesson_reassign_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get lesson_reassign_dialog_cancel;

  /// No description provided for @lesson_reassign_dialog_noSubgoals.
  ///
  /// In en, this message translates to:
  /// **'There are no subgoals to assign to.'**
  String get lesson_reassign_dialog_noSubgoals;

  /// No description provided for @lesson_reassign_overwrite_title.
  ///
  /// In en, this message translates to:
  /// **'Replace existing lesson content?'**
  String get lesson_reassign_overwrite_title;

  /// No description provided for @lesson_reassign_overwrite_message.
  ///
  /// In en, this message translates to:
  /// **'\"{target}\" already has lesson content. It will be replaced by \"{title}\".'**
  String lesson_reassign_overwrite_message(String target, String title);

  /// No description provided for @lesson_reassign_overwrite_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get lesson_reassign_overwrite_cancel;

  /// No description provided for @lesson_reassign_overwrite_confirm.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get lesson_reassign_overwrite_confirm;

  /// No description provided for @lesson_snack_reassigned.
  ///
  /// In en, this message translates to:
  /// **'Lesson content linked to \"{target}\".'**
  String lesson_snack_reassigned(String target);

  /// Header above the live output of a runnable code block inside a lesson
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get lesson_run_output_label;

  /// No description provided for @lesson_run_button.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get lesson_run_button;

  /// No description provided for @lesson_run_running.
  ///
  /// In en, this message translates to:
  /// **'Running…'**
  String get lesson_run_running;

  /// No description provided for @lesson_run_unavailable.
  ///
  /// In en, this message translates to:
  /// **'The example can only run inside the app.'**
  String get lesson_run_unavailable;

  /// No description provided for @instructions_toolbar_title.
  ///
  /// In en, this message translates to:
  /// **'Instructions'**
  String get instructions_toolbar_title;

  /// No description provided for @instructions_toolbar_tooltip_new.
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get instructions_toolbar_tooltip_new;

  /// No description provided for @instructions_toolbar_tooltip_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete document'**
  String get instructions_toolbar_tooltip_delete;

  /// No description provided for @instructions_toolbar_tooltip_export.
  ///
  /// In en, this message translates to:
  /// **'Export all to Markdown'**
  String get instructions_toolbar_tooltip_export;

  /// No description provided for @instructions_toolbar_tooltip_import.
  ///
  /// In en, this message translates to:
  /// **'Import from Markdown'**
  String get instructions_toolbar_tooltip_import;

  /// No description provided for @instructions_toolbar_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get instructions_toolbar_save;

  /// No description provided for @instructions_toolbar_save_dirty.
  ///
  /// In en, this message translates to:
  /// **'Save *'**
  String get instructions_toolbar_save_dirty;

  /// No description provided for @instructions_dialog_common_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get instructions_dialog_common_cancel;

  /// No description provided for @instructions_dialog_common_ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get instructions_dialog_common_ok;

  /// No description provided for @instructions_dialog_common_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get instructions_dialog_common_delete;

  /// No description provided for @instructions_dialog_common_add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get instructions_dialog_common_add;

  /// No description provided for @instructions_dialog_common_replace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get instructions_dialog_common_replace;

  /// No description provided for @instructions_dialog_newDoc_title.
  ///
  /// In en, this message translates to:
  /// **'New document'**
  String get instructions_dialog_newDoc_title;

  /// No description provided for @instructions_dialog_newDoc_label.
  ///
  /// In en, this message translates to:
  /// **'Document id (e.g. system_prompt)'**
  String get instructions_dialog_newDoc_label;

  /// No description provided for @instructions_dialog_renameDoc_title.
  ///
  /// In en, this message translates to:
  /// **'Rename document'**
  String get instructions_dialog_renameDoc_title;

  /// No description provided for @instructions_dialog_renameDoc_label.
  ///
  /// In en, this message translates to:
  /// **'New document id'**
  String get instructions_dialog_renameDoc_label;

  /// No description provided for @instructions_dialog_renameSection_title.
  ///
  /// In en, this message translates to:
  /// **'Rename section'**
  String get instructions_dialog_renameSection_title;

  /// No description provided for @instructions_dialog_renameSection_label.
  ///
  /// In en, this message translates to:
  /// **'New section key'**
  String get instructions_dialog_renameSection_label;

  /// No description provided for @instructions_dialog_addSection_title.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get instructions_dialog_addSection_title;

  /// No description provided for @instructions_dialog_addSection_label.
  ///
  /// In en, this message translates to:
  /// **'Section key (e.g. current_context)'**
  String get instructions_dialog_addSection_label;

  /// No description provided for @instructions_confirm_deleteDoc_title.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{id}\"?'**
  String instructions_confirm_deleteDoc_title(String id);

  /// No description provided for @instructions_confirm_deleteDoc_body.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete the document.'**
  String get instructions_confirm_deleteDoc_body;

  /// No description provided for @instructions_confirm_deleteSection_title.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{key}\"?'**
  String instructions_confirm_deleteSection_title(String key);

  /// No description provided for @instructions_confirm_deleteSection_body.
  ///
  /// In en, this message translates to:
  /// **'This removes the section from the document.'**
  String get instructions_confirm_deleteSection_body;

  /// No description provided for @instructions_import_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Import instructions'**
  String get instructions_import_dialog_title;

  /// No description provided for @instructions_import_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'The file contains {docCount} document(s).\n\n• Add: only insert sections that don\'t already exist; keep current values.\n• Replace: overwrite each imported document\'s sections with the file\'s contents. Documents not in the file are left alone.'**
  String instructions_import_dialog_message(int docCount);

  /// No description provided for @instructions_filePicker_title.
  ///
  /// In en, this message translates to:
  /// **'Select Markdown file to import'**
  String get instructions_filePicker_title;

  /// No description provided for @instructions_snack_documentDeleted.
  ///
  /// In en, this message translates to:
  /// **'Document deleted'**
  String get instructions_snack_documentDeleted;

  /// No description provided for @instructions_snack_saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get instructions_snack_saved;

  /// No description provided for @instructions_snack_sectionExists.
  ///
  /// In en, this message translates to:
  /// **'Section \"{key}\" already exists'**
  String instructions_snack_sectionExists(String key);

  /// No description provided for @instructions_snack_sectionExistsRename.
  ///
  /// In en, this message translates to:
  /// **'A section named \"{key}\" already exists'**
  String instructions_snack_sectionExistsRename(String key);

  /// No description provided for @instructions_snack_renamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed to \"{target}\"'**
  String instructions_snack_renamed(String target);

  /// No description provided for @instructions_snack_noDocsToExport.
  ///
  /// In en, this message translates to:
  /// **'No documents to export'**
  String get instructions_snack_noDocsToExport;

  /// No description provided for @instructions_snack_exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to {path}'**
  String instructions_snack_exportedTo(String path);

  /// No description provided for @instructions_snack_exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String instructions_snack_exportFailed(String error);

  /// No description provided for @instructions_snack_noDocsInFile.
  ///
  /// In en, this message translates to:
  /// **'No documents found in file'**
  String get instructions_snack_noDocsInFile;

  /// No description provided for @instructions_snack_importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String instructions_snack_importFailed(String error);

  /// No description provided for @instructions_snack_couldNotRead.
  ///
  /// In en, this message translates to:
  /// **'Could not read selected file'**
  String get instructions_snack_couldNotRead;

  /// No description provided for @instructions_snack_replace_nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing changed (file matched existing content)'**
  String get instructions_snack_replace_nothing;

  /// No description provided for @instructions_snack_add_nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing imported (all sections already exist)'**
  String get instructions_snack_add_nothing;

  /// No description provided for @instructions_snack_imported_prefix.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} section(s)'**
  String instructions_snack_imported_prefix(int count);

  /// No description provided for @instructions_snack_stats_newDocs.
  ///
  /// In en, this message translates to:
  /// **'{count} new doc(s)'**
  String instructions_snack_stats_newDocs(int count);

  /// No description provided for @instructions_snack_stats_updated.
  ///
  /// In en, this message translates to:
  /// **'{count} updated'**
  String instructions_snack_stats_updated(int count);

  /// No description provided for @instructions_snack_stats_replaced.
  ///
  /// In en, this message translates to:
  /// **'{count} replaced'**
  String instructions_snack_stats_replaced(int count);

  /// No description provided for @instructions_snack_stats_addedSections.
  ///
  /// In en, this message translates to:
  /// **'{count} added section(s)'**
  String instructions_snack_stats_addedSections(int count);

  /// No description provided for @instructions_snack_stats_replacedSections.
  ///
  /// In en, this message translates to:
  /// **'{count} replaced section(s)'**
  String instructions_snack_stats_replacedSections(int count);

  /// No description provided for @instructions_body_loadError.
  ///
  /// In en, this message translates to:
  /// **'Error loading documents: {error}'**
  String instructions_body_loadError(String error);

  /// No description provided for @instructions_sectionsList_add.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get instructions_sectionsList_add;

  /// No description provided for @instructions_sectionsList_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get instructions_sectionsList_delete;

  /// No description provided for @instructions_docList_header.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get instructions_docList_header;

  /// No description provided for @instructions_docHeader_noDoc.
  ///
  /// In en, this message translates to:
  /// **'No document selected'**
  String get instructions_docHeader_noDoc;

  /// No description provided for @instructions_docHeader_renameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename document'**
  String get instructions_docHeader_renameTooltip;

  /// No description provided for @instructions_sectionHeader_noSection.
  ///
  /// In en, this message translates to:
  /// **'No section selected'**
  String get instructions_sectionHeader_noSection;

  /// No description provided for @instructions_sectionHeader_renameTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename section'**
  String get instructions_sectionHeader_renameTooltip;

  /// No description provided for @accounts_page_title.
  ///
  /// In en, this message translates to:
  /// **'Students'**
  String get accounts_page_title;

  /// No description provided for @accounts_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage accounts and follow your students\' progress.'**
  String get accounts_page_subtitle;

  /// No description provided for @accounts_loadError.
  ///
  /// In en, this message translates to:
  /// **'Error loading accounts:\n{error}'**
  String accounts_loadError(String error);

  /// No description provided for @accounts_search_hint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email…'**
  String get accounts_search_hint;

  /// No description provided for @accounts_pageSize_label.
  ///
  /// In en, this message translates to:
  /// **'{n} / page'**
  String accounts_pageSize_label(int n);

  /// No description provided for @accounts_classFilter_all.
  ///
  /// In en, this message translates to:
  /// **'All classes'**
  String get accounts_classFilter_all;

  /// No description provided for @accounts_classFilter_none.
  ///
  /// In en, this message translates to:
  /// **'No class'**
  String get accounts_classFilter_none;

  /// No description provided for @accounts_column_email.
  ///
  /// In en, this message translates to:
  /// **'EMAIL'**
  String get accounts_column_email;

  /// No description provided for @accounts_column_name.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get accounts_column_name;

  /// No description provided for @accounts_column_class.
  ///
  /// In en, this message translates to:
  /// **'CLASS'**
  String get accounts_column_class;

  /// No description provided for @accounts_column_streak.
  ///
  /// In en, this message translates to:
  /// **'STREAK'**
  String get accounts_column_streak;

  /// No description provided for @accounts_column_currentGoal.
  ///
  /// In en, this message translates to:
  /// **'CURRENT GOAL'**
  String get accounts_column_currentGoal;

  /// No description provided for @accounts_column_progress.
  ///
  /// In en, this message translates to:
  /// **'PROGRESS'**
  String get accounts_column_progress;

  /// No description provided for @accounts_column_status.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get accounts_column_status;

  /// No description provided for @accounts_column_key.
  ///
  /// In en, this message translates to:
  /// **'KEY'**
  String get accounts_column_key;

  /// No description provided for @accounts_column_actions.
  ///
  /// In en, this message translates to:
  /// **'ACTIONS'**
  String get accounts_column_actions;

  /// No description provided for @accounts_email_lastActive.
  ///
  /// In en, this message translates to:
  /// **'last active: {ts}'**
  String accounts_email_lastActive(String ts);

  /// No description provided for @accounts_tooltip_deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accounts_tooltip_deleteAccount;

  /// No description provided for @accounts_tooltip_firstPage.
  ///
  /// In en, this message translates to:
  /// **'First page'**
  String get accounts_tooltip_firstPage;

  /// No description provided for @accounts_tooltip_previousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get accounts_tooltip_previousPage;

  /// No description provided for @accounts_tooltip_nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get accounts_tooltip_nextPage;

  /// No description provided for @accounts_tooltip_lastPage.
  ///
  /// In en, this message translates to:
  /// **'Last page'**
  String get accounts_tooltip_lastPage;

  /// No description provided for @accounts_pagination_showing.
  ///
  /// In en, this message translates to:
  /// **'Showing {start}–{end} of {total}'**
  String accounts_pagination_showing(int start, int end, int total);

  /// No description provided for @accounts_pagination_pageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {page} / {total}'**
  String accounts_pagination_pageOf(int page, int total);

  /// No description provided for @accounts_delete_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accounts_delete_dialog_title;

  /// No description provided for @accounts_delete_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'This will delete the account profile for:\n\n{email}\n\nThis does NOT remove the user from the school account directory. Continue?'**
  String accounts_delete_dialog_message(String email);

  /// No description provided for @accounts_delete_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accounts_delete_dialog_cancel;

  /// No description provided for @accounts_delete_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get accounts_delete_dialog_confirm;

  /// No description provided for @accounts_delete_success.
  ///
  /// In en, this message translates to:
  /// **'Deleted account: {email}'**
  String accounts_delete_success(String email);

  /// No description provided for @accounts_delete_failed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String accounts_delete_failed(String error);

  /// No description provided for @accounts_class_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Assign class'**
  String get accounts_class_dialog_title;

  /// No description provided for @accounts_class_dialog_hint.
  ///
  /// In en, this message translates to:
  /// **'Class name (leave empty to clear)'**
  String get accounts_class_dialog_hint;

  /// No description provided for @accounts_class_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get accounts_class_dialog_cancel;

  /// No description provided for @accounts_class_dialog_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get accounts_class_dialog_save;

  /// No description provided for @accounts_class_saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save class: {error}'**
  String accounts_class_saveFailed(String error);

  /// No description provided for @accounts_bulk_selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String accounts_bulk_selectedCount(int count);

  /// No description provided for @accounts_bulk_assignClass.
  ///
  /// In en, this message translates to:
  /// **'Assign class'**
  String get accounts_bulk_assignClass;

  /// No description provided for @accounts_bulk_clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get accounts_bulk_clearSelection;

  /// No description provided for @accounts_bulk_assignSuccess.
  ///
  /// In en, this message translates to:
  /// **'Class updated for {count} students'**
  String accounts_bulk_assignSuccess(int count);

  /// No description provided for @accounts_status_tooltip_active.
  ///
  /// In en, this message translates to:
  /// **'Made progress recently.'**
  String get accounts_status_tooltip_active;

  /// No description provided for @accounts_status_tooltip_idle.
  ///
  /// In en, this message translates to:
  /// **'No progress in the last 7 days.'**
  String get accounts_status_tooltip_idle;

  /// No description provided for @accounts_badge_unackTooltip.
  ///
  /// In en, this message translates to:
  /// **'Unacknowledged signal events'**
  String get accounts_badge_unackTooltip;

  /// No description provided for @drawer_close_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get drawer_close_tooltip;

  /// No description provided for @drawer_section_goals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get drawer_section_goals;

  /// No description provided for @drawer_statusSummary_active_with_goal.
  ///
  /// In en, this message translates to:
  /// **'Recently active on \"{title}\".'**
  String drawer_statusSummary_active_with_goal(String title);

  /// No description provided for @drawer_statusSummary_active_noGoal.
  ///
  /// In en, this message translates to:
  /// **'Recently active.'**
  String get drawer_statusSummary_active_noGoal;

  /// No description provided for @drawer_statusSummary_idle.
  ///
  /// In en, this message translates to:
  /// **'No recent activity.'**
  String get drawer_statusSummary_idle;

  /// No description provided for @drawer_signals_title.
  ///
  /// In en, this message translates to:
  /// **'Signal events'**
  String get drawer_signals_title;

  /// No description provided for @drawer_signals_button_busy.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get drawer_signals_button_busy;

  /// No description provided for @drawer_signals_button_acknowledge.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge ({count})'**
  String drawer_signals_button_acknowledge(int count);

  /// No description provided for @drawer_signals_empty.
  ///
  /// In en, this message translates to:
  /// **'No events'**
  String get drawer_signals_empty;

  /// No description provided for @drawer_signals_ackFailed.
  ///
  /// In en, this message translates to:
  /// **'Acknowledge failed: {error}'**
  String drawer_signals_ackFailed(String error);

  /// No description provided for @drawer_signals_kind_stuckLoAdvance.
  ///
  /// In en, this message translates to:
  /// **'Stuck LO at transition'**
  String get drawer_signals_kind_stuckLoAdvance;

  /// No description provided for @drawer_signals_kind_singleLoDeadlock.
  ///
  /// In en, this message translates to:
  /// **'Single-LO impasse'**
  String get drawer_signals_kind_singleLoDeadlock;

  /// No description provided for @drawer_signals_kind_repeatedDemotions.
  ///
  /// In en, this message translates to:
  /// **'Repeated demotion'**
  String get drawer_signals_kind_repeatedDemotions;

  /// No description provided for @drawer_signals_kind_sustainedLlmFailure.
  ///
  /// In en, this message translates to:
  /// **'Sustained LLM failure'**
  String get drawer_signals_kind_sustainedLlmFailure;

  /// No description provided for @drawer_signals_kind_cascadeHalt.
  ///
  /// In en, this message translates to:
  /// **'Cascade halt (audit)'**
  String get drawer_signals_kind_cascadeHalt;

  /// No description provided for @drawer_signals_kind_emptyObjectivesBlock.
  ///
  /// In en, this message translates to:
  /// **'Subgoal without LOs (audit)'**
  String get drawer_signals_kind_emptyObjectivesBlock;

  /// No description provided for @drawer_signals_kind_subgoalDeletedRedirect.
  ///
  /// In en, this message translates to:
  /// **'Subgoal deleted (audit)'**
  String get drawer_signals_kind_subgoalDeletedRedirect;

  /// No description provided for @drawer_statusReports_title.
  ///
  /// In en, this message translates to:
  /// **'Status reports'**
  String get drawer_statusReports_title;

  /// No description provided for @drawer_statusReports_loadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load status reports.'**
  String get drawer_statusReports_loadError;

  /// No description provided for @drawer_statusReports_empty.
  ///
  /// In en, this message translates to:
  /// **'No status reports yet.'**
  String get drawer_statusReports_empty;

  /// No description provided for @drawer_history_title.
  ///
  /// In en, this message translates to:
  /// **'Progress over time'**
  String get drawer_history_title;

  /// No description provided for @drawer_history_loadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load history.'**
  String get drawer_history_loadError;

  /// No description provided for @drawer_history_empty.
  ///
  /// In en, this message translates to:
  /// **'No history yet.'**
  String get drawer_history_empty;

  /// No description provided for @drawer_history_card_empty.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get drawer_history_card_empty;

  /// No description provided for @drawer_history_legend_average.
  ///
  /// In en, this message translates to:
  /// **'average'**
  String get drawer_history_legend_average;

  /// No description provided for @progress_loadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load goals.'**
  String get progress_loadError;

  /// No description provided for @progress_empty.
  ///
  /// In en, this message translates to:
  /// **'No goals available yet.'**
  String get progress_empty;

  /// No description provided for @leerpad_header_title.
  ///
  /// In en, this message translates to:
  /// **'Learning path'**
  String get leerpad_header_title;

  /// No description provided for @leerpad_header_subtitle_default.
  ///
  /// In en, this message translates to:
  /// **'Python — beginner\'s journey'**
  String get leerpad_header_subtitle_default;

  /// No description provided for @leerpad_card_completed.
  ///
  /// In en, this message translates to:
  /// **'completed'**
  String get leerpad_card_completed;

  /// No description provided for @leerpad_card_button_continue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get leerpad_card_button_continue;

  /// No description provided for @goalTile_button_faster.
  ///
  /// In en, this message translates to:
  /// **'Go faster'**
  String get goalTile_button_faster;

  /// No description provided for @goalTile_button_workOn.
  ///
  /// In en, this message translates to:
  /// **'Work on this'**
  String get goalTile_button_workOn;

  /// No description provided for @common_undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get common_undo;

  /// No description provided for @crash_permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied while reading data.'**
  String get crash_permissionDenied;

  /// No description provided for @auth_browser_signedIn_title.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get auth_browser_signedIn_title;

  /// No description provided for @auth_browser_signedIn_body.
  ///
  /// In en, this message translates to:
  /// **'You can close this tab and return to the app.'**
  String get auth_browser_signedIn_body;

  /// No description provided for @auth_browser_failed_title.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed'**
  String get auth_browser_failed_title;

  /// No description provided for @auth_browser_failed_noCode.
  ///
  /// In en, this message translates to:
  /// **'No authorization code returned.'**
  String get auth_browser_failed_noCode;

  /// No description provided for @auth_browser_failed_stateMismatch.
  ///
  /// In en, this message translates to:
  /// **'State mismatch — possible CSRF, please try again.'**
  String get auth_browser_failed_stateMismatch;

  /// No description provided for @levelUp_caption.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP · CONCEPT UNLOCKED'**
  String levelUp_caption(int xp);

  /// No description provided for @levelUp_level.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String levelUp_level(int level);

  /// No description provided for @levelUp_subtitle_generic.
  ///
  /// In en, this message translates to:
  /// **'You\'ve mastered the next concept.'**
  String get levelUp_subtitle_generic;

  /// No description provided for @levelUp_subtitle_concept.
  ///
  /// In en, this message translates to:
  /// **'You\'ve mastered {concept}.'**
  String levelUp_subtitle_concept(String concept);

  /// No description provided for @levelUp_button_continue.
  ///
  /// In en, this message translates to:
  /// **'Keep learning'**
  String get levelUp_button_continue;

  /// No description provided for @splash_title.
  ///
  /// In en, this message translates to:
  /// **'Goal reached!'**
  String get splash_title;

  /// No description provided for @splash_phrase_01.
  ///
  /// In en, this message translates to:
  /// **'LEGENDARY! Your code will be sung about for centuries!'**
  String get splash_phrase_01;

  /// No description provided for @splash_phrase_02.
  ///
  /// In en, this message translates to:
  /// **'Wow! Even your keyboard is applauding you!'**
  String get splash_phrase_02;

  /// No description provided for @splash_phrase_03.
  ///
  /// In en, this message translates to:
  /// **'Watch out, the AI is getting jealous of you!'**
  String get splash_phrase_03;

  /// No description provided for @splash_phrase_04.
  ///
  /// In en, this message translates to:
  /// **'You just moved the god of computer science to tears.'**
  String get splash_phrase_04;

  /// No description provided for @splash_phrase_05.
  ///
  /// In en, this message translates to:
  /// **'BAM! One more victory for the Hall of Fame!'**
  String get splash_phrase_05;

  /// No description provided for @splash_phrase_06.
  ///
  /// In en, this message translates to:
  /// **'Your keys are smoking — that\'s how fast you program!'**
  String get splash_phrase_06;

  /// No description provided for @splash_phrase_07.
  ///
  /// In en, this message translates to:
  /// **'Brilliant! Even Stack Overflow is speechless.'**
  String get splash_phrase_07;

  /// No description provided for @splash_phrase_08.
  ///
  /// In en, this message translates to:
  /// **'The bug police lost today!'**
  String get splash_phrase_08;

  /// No description provided for @splash_phrase_09.
  ///
  /// In en, this message translates to:
  /// **'What a masterpiece! Rembrandt, but in Python.'**
  String get splash_phrase_09;

  /// No description provided for @splash_phrase_10.
  ///
  /// In en, this message translates to:
  /// **'You just improved the internet. You\'re welcome!'**
  String get splash_phrase_10;

  /// No description provided for @splash_phrase_11.
  ///
  /// In en, this message translates to:
  /// **'The government is calling: they want to buy your algorithm.'**
  String get splash_phrase_11;

  /// No description provided for @splash_phrase_12.
  ///
  /// In en, this message translates to:
  /// **'Applause! The bits and bytes are giving you a standing ovation!'**
  String get splash_phrase_12;

  /// No description provided for @splash_phrase_13.
  ///
  /// In en, this message translates to:
  /// **'The compiler is smiling. That rarely happens.'**
  String get splash_phrase_13;

  /// No description provided for @splash_phrase_14.
  ///
  /// In en, this message translates to:
  /// **'Your code is so clean you can see right through it.'**
  String get splash_phrase_14;

  /// No description provided for @splash_phrase_15.
  ///
  /// In en, this message translates to:
  /// **'The matrix has noticed you… and nods approvingly.'**
  String get splash_phrase_15;

  /// No description provided for @splash_phrase_16.
  ///
  /// In en, this message translates to:
  /// **'The mouse whispers: \'I am not worthy\'.'**
  String get splash_phrase_16;

  /// No description provided for @splash_phrase_17.
  ///
  /// In en, this message translates to:
  /// **'Even your laptop wants your autograph now.'**
  String get splash_phrase_17;

  /// No description provided for @splash_phrase_18.
  ///
  /// In en, this message translates to:
  /// **'A new record! The pixels are cheering!'**
  String get splash_phrase_18;

  /// No description provided for @splash_phrase_19.
  ///
  /// In en, this message translates to:
  /// **'You have exceeded the limits of human understanding.'**
  String get splash_phrase_19;

  /// No description provided for @splash_phrase_20.
  ///
  /// In en, this message translates to:
  /// **'Mathematicians are weeping with emotion.'**
  String get splash_phrase_20;

  /// No description provided for @splash_phrase_21.
  ///
  /// In en, this message translates to:
  /// **'Python itself whispers: \'thank you, master\'.'**
  String get splash_phrase_21;

  /// No description provided for @splash_phrase_22.
  ///
  /// In en, this message translates to:
  /// **'This is no longer success. This is folklore.'**
  String get splash_phrase_22;

  /// No description provided for @splash_phrase_23.
  ///
  /// In en, this message translates to:
  /// **'NASA is calling: \'can you come debug for us?\''**
  String get splash_phrase_23;

  /// No description provided for @splash_phrase_24.
  ///
  /// In en, this message translates to:
  /// **'The AI tutor has decided that you will tutor it from now on.'**
  String get splash_phrase_24;

  /// No description provided for @splash_phrase_25.
  ///
  /// In en, this message translates to:
  /// **'Stop! You\'re too good. Give the others a chance.'**
  String get splash_phrase_25;

  /// No description provided for @chat_role_explanation.
  ///
  /// In en, this message translates to:
  /// **'explanation'**
  String get chat_role_explanation;

  /// No description provided for @chat_role_example.
  ///
  /// In en, this message translates to:
  /// **'example'**
  String get chat_role_example;

  /// No description provided for @chat_role_question.
  ///
  /// In en, this message translates to:
  /// **'think about it'**
  String get chat_role_question;

  /// No description provided for @chat_role_correct.
  ///
  /// In en, this message translates to:
  /// **'correct'**
  String get chat_role_correct;

  /// Python comment placed in the editor when a write-code exercise starts
  ///
  /// In en, this message translates to:
  /// **'# Write your code here'**
  String get session_writeCode_template;

  /// No description provided for @difficulty_easy.
  ///
  /// In en, this message translates to:
  /// **'easy'**
  String get difficulty_easy;

  /// No description provided for @difficulty_medium.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get difficulty_medium;

  /// No description provided for @difficulty_hard.
  ///
  /// In en, this message translates to:
  /// **'hard'**
  String get difficulty_hard;

  /// No description provided for @chat_notice_tutorFailed.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong with the tutor: {detail}'**
  String chat_notice_tutorFailed(String detail);

  /// No description provided for @chat_notice_sessionStartFailed.
  ///
  /// In en, this message translates to:
  /// **'The session could not start: {detail}'**
  String chat_notice_sessionStartFailed(String detail);

  /// No description provided for @chat_notice_databaseUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The connection to the database dropped for a moment. Try again shortly.'**
  String get chat_notice_databaseUnavailable;

  /// No description provided for @chat_notice_tutorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The tutor did not respond in time.'**
  String get chat_notice_tutorTimeout;

  /// No description provided for @chat_notice_tutorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'No connection to the tutor.'**
  String get chat_notice_tutorUnreachable;

  /// No description provided for @chat_notice_replyTruncated.
  ///
  /// In en, this message translates to:
  /// **'The tutor\'s reply was cut off.'**
  String get chat_notice_replyTruncated;

  /// No description provided for @chat_notice_noPreviousRequest.
  ///
  /// In en, this message translates to:
  /// **'No previous request to retry.'**
  String get chat_notice_noPreviousRequest;

  /// No description provided for @chat_notice_emptyResponse.
  ///
  /// In en, this message translates to:
  /// **'Empty response from the tutor.'**
  String get chat_notice_emptyResponse;

  /// No description provided for @chat_notice_unparseableResponse.
  ///
  /// In en, this message translates to:
  /// **'Could not process the response: {raw}'**
  String chat_notice_unparseableResponse(String raw);

  /// No description provided for @chat_notice_unknownResponseType.
  ///
  /// In en, this message translates to:
  /// **'Unknown response type: {type}'**
  String chat_notice_unknownResponseType(String type);

  /// No description provided for @chat_notice_unknownResponse.
  ///
  /// In en, this message translates to:
  /// **'Received an unknown response.'**
  String get chat_notice_unknownResponse;

  /// No description provided for @chat_notice_exerciseWithoutBlank.
  ///
  /// In en, this message translates to:
  /// **'That exercise had nothing left to fill in. Fetching a new one.'**
  String get chat_notice_exerciseWithoutBlank;

  /// No description provided for @chat_notice_subgoalDeletedRedirect.
  ///
  /// In en, this message translates to:
  /// **'Your previous topic was removed by your teacher. Continuing with the next one.'**
  String get chat_notice_subgoalDeletedRedirect;

  /// No description provided for @chat_notice_subgoalSaturated.
  ///
  /// In en, this message translates to:
  /// **'You already have a good grip on this subgoal. Ready to move on?'**
  String get chat_notice_subgoalSaturated;

  /// No description provided for @chat_notice_noGoalsLeft.
  ///
  /// In en, this message translates to:
  /// **'There are no goals left to work on. Congratulations!'**
  String get chat_notice_noGoalsLeft;

  /// No description provided for @chat_notice_emptyObjectives.
  ///
  /// In en, this message translates to:
  /// **'This subgoal isn\'t quite finished yet — ask your teacher to complete it, or pick another subgoal.'**
  String get chat_notice_emptyObjectives;

  /// No description provided for @chat_notice_preparingExercise.
  ///
  /// In en, this message translates to:
  /// **'Preparing your next exercise...'**
  String get chat_notice_preparingExercise;

  /// No description provided for @chat_notice_feedbackDegraded.
  ///
  /// In en, this message translates to:
  /// **'Something is wrong with the feedback. Try again in a few minutes.'**
  String get chat_notice_feedbackDegraded;

  /// No description provided for @chat_notice_newGoalSelected.
  ///
  /// In en, this message translates to:
  /// **'New goal selected: {title}'**
  String chat_notice_newGoalSelected(String title);

  /// No description provided for @chat_notice_difficultyChanged.
  ///
  /// In en, this message translates to:
  /// **'Difficulty adjusted: {from} -> {to}'**
  String chat_notice_difficultyChanged(String from, String to);

  /// No description provided for @chat_notice_submitViaEditor.
  ///
  /// In en, this message translates to:
  /// **'Adjust your code in the editor on the left and press Run to submit your solution.'**
  String get chat_notice_submitViaEditor;
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
