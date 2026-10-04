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

  /// No description provided for @sidebar_section_puntenformule.
  ///
  /// In en, this message translates to:
  /// **'Grade formula'**
  String get sidebar_section_puntenformule;

  /// Student section listing their own released reports; the teacher's class-wide run is sidebar_section_reports
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get sidebar_section_myReports;

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

  /// No description provided for @sidebar_section_questions.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get sidebar_section_questions;

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

  /// Teacher section listing the classes with their weekly lessons (#218)
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get sidebar_section_classes;

  /// No description provided for @sidebar_section_milestones.
  ///
  /// In en, this message translates to:
  /// **'Milestones'**
  String get sidebar_section_milestones;

  /// No description provided for @sidebar_section_reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get sidebar_section_reports;

  /// No description provided for @sidebar_section_options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get sidebar_section_options;

  /// No description provided for @puntenformule_header_note.
  ///
  /// In en, this message translates to:
  /// **'How your report grade is computed. The document is public and versioned; this is the version this build of the app ships with.'**
  String get puntenformule_header_note;

  /// No description provided for @puntenformule_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading the grade formula…'**
  String get puntenformule_loading;

  /// No description provided for @puntenformule_loadError.
  ///
  /// In en, this message translates to:
  /// **'The grade formula could not be loaded: {error}'**
  String puntenformule_loadError(String error);

  /// No description provided for @milestones_page_title.
  ///
  /// In en, this message translates to:
  /// **'Milestones'**
  String get milestones_page_title;

  /// No description provided for @milestones_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Which goals should be known by which report date, and which of them gate the pass mark.'**
  String get milestones_page_subtitle;

  /// No description provided for @milestones_list_empty.
  ///
  /// In en, this message translates to:
  /// **'No milestones yet.'**
  String get milestones_list_empty;

  /// No description provided for @milestones_button_new.
  ///
  /// In en, this message translates to:
  /// **'New milestone'**
  String get milestones_button_new;

  /// No description provided for @milestones_button_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get milestones_button_save;

  /// No description provided for @milestones_button_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get milestones_button_delete;

  /// No description provided for @milestones_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Pick a milestone on the left, or create a new one.'**
  String get milestones_placeholder;

  /// No description provided for @milestones_field_title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get milestones_field_title;

  /// No description provided for @milestones_field_periodStart.
  ///
  /// In en, this message translates to:
  /// **'Period start (YYYY-MM-DD)'**
  String get milestones_field_periodStart;

  /// No description provided for @milestones_field_dueAt.
  ///
  /// In en, this message translates to:
  /// **'Report date (YYYY-MM-DD)'**
  String get milestones_field_dueAt;

  /// No description provided for @milestones_field_pickDate.
  ///
  /// In en, this message translates to:
  /// **'Pick a date'**
  String get milestones_field_pickDate;

  /// No description provided for @milestones_field_expectedDifficulty.
  ///
  /// In en, this message translates to:
  /// **'Expected level for the core'**
  String get milestones_field_expectedDifficulty;

  /// No description provided for @milestones_difficulty_easy.
  ///
  /// In en, this message translates to:
  /// **'easy'**
  String get milestones_difficulty_easy;

  /// No description provided for @milestones_difficulty_medium.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get milestones_difficulty_medium;

  /// No description provided for @milestones_difficulty_hard.
  ///
  /// In en, this message translates to:
  /// **'hard'**
  String get milestones_difficulty_hard;

  /// No description provided for @milestones_goals_heading.
  ///
  /// In en, this message translates to:
  /// **'Goals in this milestone'**
  String get milestones_goals_heading;

  /// No description provided for @milestones_goals_hint.
  ///
  /// In en, this message translates to:
  /// **'Tick a subgoal to include its learning objectives. Then mark, per objective, whether a student who just passes masters it (core) or not (extension).'**
  String get milestones_goals_hint;

  /// No description provided for @milestones_lo_core.
  ///
  /// In en, this message translates to:
  /// **'core'**
  String get milestones_lo_core;

  /// No description provided for @milestones_lo_extension.
  ///
  /// In en, this message translates to:
  /// **'extension'**
  String get milestones_lo_extension;

  /// No description provided for @milestones_validation_title.
  ///
  /// In en, this message translates to:
  /// **'Give the milestone a title.'**
  String get milestones_validation_title;

  /// No description provided for @milestones_validation_date.
  ///
  /// In en, this message translates to:
  /// **'Use the form YYYY-MM-DD.'**
  String get milestones_validation_date;

  /// No description provided for @milestones_validation_order.
  ///
  /// In en, this message translates to:
  /// **'The report date must come after the period start.'**
  String get milestones_validation_order;

  /// No description provided for @milestones_validation_goals.
  ///
  /// In en, this message translates to:
  /// **'Include at least one subgoal.'**
  String get milestones_validation_goals;

  /// No description provided for @milestones_saved.
  ///
  /// In en, this message translates to:
  /// **'Milestone saved.'**
  String get milestones_saved;

  /// No description provided for @milestones_deleted.
  ///
  /// In en, this message translates to:
  /// **'Milestone deleted.'**
  String get milestones_deleted;

  /// No description provided for @milestones_delete_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete milestone'**
  String get milestones_delete_dialog_title;

  /// No description provided for @milestones_delete_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"? Grade proposals already computed against it stay as they are.'**
  String milestones_delete_dialog_message(String title);

  /// No description provided for @milestones_delete_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get milestones_delete_dialog_cancel;

  /// No description provided for @milestones_delete_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get milestones_delete_dialog_confirm;

  /// No description provided for @milestones_overdue_noReports.
  ///
  /// In en, this message translates to:
  /// **'Report date passed — no reports generated yet.'**
  String get milestones_overdue_noReports;

  /// No description provided for @milestones_summary.
  ///
  /// In en, this message translates to:
  /// **'{core} core, {extension} extension learning objectives'**
  String milestones_summary(int core, int extension);

  /// No description provided for @reports_page_title.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports_page_title;

  /// No description provided for @reports_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Generate and review the milestone reports of a whole class.'**
  String get reports_page_subtitle;

  /// No description provided for @reports_class_label.
  ///
  /// In en, this message translates to:
  /// **'Class'**
  String get reports_class_label;

  /// No description provided for @reports_generate.
  ///
  /// In en, this message translates to:
  /// **'Generate reports'**
  String get reports_generate;

  /// No description provided for @reports_generating.
  ///
  /// In en, this message translates to:
  /// **'Generating… {done} / {total}'**
  String reports_generating(int done, int total);

  /// No description provided for @reports_noStudents.
  ///
  /// In en, this message translates to:
  /// **'No students in this class.'**
  String get reports_noStudents;

  /// No description provided for @reports_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Pick a student on the left.'**
  String get reports_placeholder;

  /// No description provided for @reports_status_noData.
  ///
  /// In en, this message translates to:
  /// **'no data'**
  String get reports_status_noData;

  /// No description provided for @reports_status_computed.
  ///
  /// In en, this message translates to:
  /// **'computed'**
  String get reports_status_computed;

  /// No description provided for @reports_status_justified.
  ///
  /// In en, this message translates to:
  /// **'justification'**
  String get reports_status_justified;

  /// No description provided for @reports_status_signedOff.
  ///
  /// In en, this message translates to:
  /// **'signed off'**
  String get reports_status_signedOff;

  /// No description provided for @reports_rowError.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String reports_rowError(String error);

  /// No description provided for @reports_retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get reports_retry;

  /// No description provided for @reports_previous.
  ///
  /// In en, this message translates to:
  /// **'Previous student'**
  String get reports_previous;

  /// No description provided for @reports_next.
  ///
  /// In en, this message translates to:
  /// **'Next student'**
  String get reports_next;

  /// No description provided for @reports_grade_title.
  ///
  /// In en, this message translates to:
  /// **'Grade proposal'**
  String get reports_grade_title;

  /// No description provided for @reports_grade_noMilestones.
  ///
  /// In en, this message translates to:
  /// **'No milestones defined yet — create one under Milestones.'**
  String get reports_grade_noMilestones;

  /// No description provided for @reports_grade_milestone_label.
  ///
  /// In en, this message translates to:
  /// **'Milestone'**
  String get reports_grade_milestone_label;

  /// No description provided for @reports_grade_button_compute.
  ///
  /// In en, this message translates to:
  /// **'Compute proposal'**
  String get reports_grade_button_compute;

  /// No description provided for @reports_grade_button_recompute.
  ///
  /// In en, this message translates to:
  /// **'Recompute'**
  String get reports_grade_button_recompute;

  /// No description provided for @reports_grade_button_justify.
  ///
  /// In en, this message translates to:
  /// **'Write justification'**
  String get reports_grade_button_justify;

  /// No description provided for @reports_grade_button_signOff.
  ///
  /// In en, this message translates to:
  /// **'Sign off'**
  String get reports_grade_button_signOff;

  /// No description provided for @reports_grade_button_busy.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get reports_grade_button_busy;

  /// No description provided for @reports_recompute_unchanged.
  ///
  /// In en, this message translates to:
  /// **'The grade did not change: {grade}/100.'**
  String reports_recompute_unchanged(int grade);

  /// No description provided for @reports_recompute_unchanged_rewritten.
  ///
  /// In en, this message translates to:
  /// **'The grade did not change: {grade}/100. The justification was rewritten.'**
  String reports_recompute_unchanged_rewritten(int grade);

  /// No description provided for @reports_recompute_unchanged_kept.
  ///
  /// In en, this message translates to:
  /// **'The grade did not change: {grade}/100. Your own text stays as it is.'**
  String reports_recompute_unchanged_kept(int grade);

  /// No description provided for @reports_grade_proposal_label.
  ///
  /// In en, this message translates to:
  /// **'Proposal'**
  String get reports_grade_proposal_label;

  /// No description provided for @reports_grade_masteryEnd.
  ///
  /// In en, this message translates to:
  /// **'Mastery now: {value}'**
  String reports_grade_masteryEnd(String value);

  /// No description provided for @reports_grade_core.
  ///
  /// In en, this message translates to:
  /// **'Core at level: {counted} / {total}'**
  String reports_grade_core(int counted, int total);

  /// No description provided for @reports_grade_extension.
  ///
  /// In en, this message translates to:
  /// **'Extension mastered: {counted} / {total}'**
  String reports_grade_extension(int counted, int total);

  /// No description provided for @reports_grade_hard.
  ///
  /// In en, this message translates to:
  /// **'Demonstrated at hard: {counted} / {total} mastered'**
  String reports_grade_hard(int counted, int total);

  /// No description provided for @reports_grade_reliability.
  ///
  /// In en, this message translates to:
  /// **'Stale: {stale} LOs (never probed: {never}). Exercises this period: {supervised} supervised, {home} at home.'**
  String reports_grade_reliability(
    int stale,
    int never,
    int supervised,
    int home,
  );

  /// No description provided for @reports_grade_reliability_unwired.
  ///
  /// In en, this message translates to:
  /// **'Stale: {stale} LOs (never probed: {never}).'**
  String reports_grade_reliability_unwired(int stale, int never);

  /// No description provided for @reports_grade_formulaVersion.
  ///
  /// In en, this message translates to:
  /// **'Formula v{version}, computed {ts}'**
  String reports_grade_formulaVersion(String version, String ts);

  /// No description provided for @reports_grade_justification_title.
  ///
  /// In en, this message translates to:
  /// **'Justification'**
  String get reports_grade_justification_title;

  /// No description provided for @reports_grade_justification_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not write the justification: {error}'**
  String reports_grade_justification_failed(String error);

  /// No description provided for @reports_grade_justification_edit.
  ///
  /// In en, this message translates to:
  /// **'Rewrite'**
  String get reports_grade_justification_edit;

  /// No description provided for @reports_grade_justification_save.
  ///
  /// In en, this message translates to:
  /// **'Save text'**
  String get reports_grade_justification_save;

  /// No description provided for @reports_grade_justification_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get reports_grade_justification_cancel;

  /// No description provided for @reports_grade_justification_field_label.
  ///
  /// In en, this message translates to:
  /// **'Justification for the student'**
  String get reports_grade_justification_field_label;

  /// No description provided for @reports_grade_justification_edited.
  ///
  /// In en, this message translates to:
  /// **'Rewritten by you on {ts}'**
  String reports_grade_justification_edited(String ts);

  /// No description provided for @reports_grade_justification_stale.
  ///
  /// In en, this message translates to:
  /// **'The grade changed after you wrote this text — reread it before signing off.'**
  String get reports_grade_justification_stale;

  /// No description provided for @reports_grade_adjusted_label.
  ///
  /// In en, this message translates to:
  /// **'Grade for the report card'**
  String get reports_grade_adjusted_label;

  /// No description provided for @reports_grade_adjusted_invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from 0 to 100.'**
  String get reports_grade_adjusted_invalid;

  /// No description provided for @reports_grade_note_label.
  ///
  /// In en, this message translates to:
  /// **'Reason for adjustment (optional)'**
  String get reports_grade_note_label;

  /// No description provided for @reports_grade_signed.
  ///
  /// In en, this message translates to:
  /// **'Signed off {ts}: {grade}/100'**
  String reports_grade_signed(String ts, int grade);

  /// No description provided for @reports_grade_signed_note.
  ///
  /// In en, this message translates to:
  /// **'Note: {note}'**
  String reports_grade_signed_note(String note);

  /// No description provided for @reports_grade_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not compute the proposal: {error}'**
  String reports_grade_failed(String error);

  /// No description provided for @reports_release.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get reports_release;

  /// No description provided for @reports_release_count.
  ///
  /// In en, this message translates to:
  /// **'{count} released'**
  String reports_release_count(int count);

  /// No description provided for @reports_release_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Release reports'**
  String get reports_release_dialog_title;

  /// No description provided for @reports_release_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'Publish the {count} signed-off reports of this milestone? Those students can read their grade and its justification from that moment on. Do this when the grades go into the report card, so nobody reads theirs days before a classmate.'**
  String reports_release_dialog_message(int count);

  /// No description provided for @reports_release_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get reports_release_dialog_cancel;

  /// No description provided for @reports_release_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get reports_release_dialog_confirm;

  /// No description provided for @reports_release_failed.
  ///
  /// In en, this message translates to:
  /// **'Releasing failed: {error}'**
  String reports_release_failed(String error);

  /// No description provided for @reports_published_at.
  ///
  /// In en, this message translates to:
  /// **'Released to the student {ts}'**
  String reports_published_at(String ts);

  /// No description provided for @reports_published_revised.
  ///
  /// In en, this message translates to:
  /// **'Republished {ts} with your rewritten justification.'**
  String reports_published_revised(String ts);

  /// No description provided for @reports_published_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Released to the student'**
  String get reports_published_tooltip;

  /// No description provided for @myReports_page_title.
  ///
  /// In en, this message translates to:
  /// **'My reports'**
  String get myReports_page_title;

  /// No description provided for @myReports_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'The reports your teacher has released, newest first — your grade and why you got it.'**
  String get myReports_page_subtitle;

  /// No description provided for @myReports_empty.
  ///
  /// In en, this message translates to:
  /// **'No report has been released to you yet. One shows up here at a report moment, together with the reasoning behind the grade.'**
  String get myReports_empty;

  /// No description provided for @myReports_grade_outOf.
  ///
  /// In en, this message translates to:
  /// **'/100'**
  String get myReports_grade_outOf;

  /// When the formula measured — earlier than the release, and not the same moment for every class
  ///
  /// In en, this message translates to:
  /// **'Computed on {ts}'**
  String myReports_computedAt(String ts);

  /// No description provided for @myReports_revised.
  ///
  /// In en, this message translates to:
  /// **'Rewritten on {ts} — this is the current text of your report.'**
  String myReports_revised(String ts);

  /// No description provided for @myReports_note.
  ///
  /// In en, this message translates to:
  /// **'Note from your teacher: {note}'**
  String myReports_note(String note);

  /// No description provided for @myReports_breakdown_title.
  ///
  /// In en, this message translates to:
  /// **'How this grade was computed'**
  String get myReports_breakdown_title;

  /// No description provided for @myReports_breakdown_mastery.
  ///
  /// In en, this message translates to:
  /// **'Mastery score M = {value} (the proposed grade is M, rounded)'**
  String myReports_breakdown_mastery(String value);

  /// The three fractions of PUNTENFORMULE §2.2, named as the document names them
  ///
  /// In en, this message translates to:
  /// **'k = {k} (core) · u = {u} (extension) · d = {d} (shown at hard)'**
  String myReports_breakdown_fractions(String k, String u, String d);

  /// No description provided for @myReports_breakdown_core.
  ///
  /// In en, this message translates to:
  /// **'Core at the expected level: {counted} / {total}'**
  String myReports_breakdown_core(int counted, int total);

  /// No description provided for @myReports_breakdown_extension.
  ///
  /// In en, this message translates to:
  /// **'Extension mastered: {counted} / {total}'**
  String myReports_breakdown_extension(int counted, int total);

  /// No description provided for @myReports_breakdown_expectedLevel.
  ///
  /// In en, this message translates to:
  /// **'Expected level for the core: {level}'**
  String myReports_breakdown_expectedLevel(String level);

  /// No description provided for @myReports_breakdown_hint.
  ///
  /// In en, this message translates to:
  /// **'Recompute it yourself with the grade formula (§2) — this grade used formula v{version}.'**
  String myReports_breakdown_hint(String version);

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

  /// No description provided for @options_globalModel_title.
  ///
  /// In en, this message translates to:
  /// **'School-wide AI model'**
  String get options_globalModel_title;

  /// No description provided for @options_globalModel_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Which model every student\'s tutor asks. Teachers only. A device that picked its own model above keeps it; the rest follow within a few seconds.'**
  String get options_globalModel_subtitle;

  /// No description provided for @options_globalModel_saved.
  ///
  /// In en, this message translates to:
  /// **'The school now uses {model}.'**
  String options_globalModel_saved(String model);

  /// No description provided for @options_globalModel_saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not change the school-wide model: {error}'**
  String options_globalModel_saveFailed(String error);

  /// No description provided for @options_model_override.
  ///
  /// In en, this message translates to:
  /// **'Another model on this device'**
  String get options_model_override;

  /// No description provided for @options_model_saved.
  ///
  /// In en, this message translates to:
  /// **'This device now uses {model}.'**
  String options_model_saved(String model);

  /// No description provided for @options_modelField_label.
  ///
  /// In en, this message translates to:
  /// **'Model id'**
  String get options_modelField_label;

  /// No description provided for @options_modelField_hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. gpt-5-mini'**
  String get options_modelField_hint;

  /// No description provided for @options_modelField_helper.
  ///
  /// In en, this message translates to:
  /// **'The exact id from platform.openai.com/docs/models, case-sensitive. Test it before saving.'**
  String get options_modelField_helper;

  /// No description provided for @options_modelField_invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter one model id, without spaces.'**
  String get options_modelField_invalid;

  /// No description provided for @options_modelField_test_button.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get options_modelField_test_button;

  /// No description provided for @options_modelField_save_button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get options_modelField_save_button;

  /// No description provided for @options_modelField_testing.
  ///
  /// In en, this message translates to:
  /// **'Testing {model}…'**
  String options_modelField_testing(String model);

  /// No description provided for @options_modelField_testPassed.
  ///
  /// In en, this message translates to:
  /// **'{model} answered in {seconds} s.'**
  String options_modelField_testPassed(String model, String seconds);

  /// No description provided for @options_modelField_testFailed.
  ///
  /// In en, this message translates to:
  /// **'Test failed: {reason}'**
  String options_modelField_testFailed(String reason);

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
  /// **'Save a report as a text file to send to your teacher, or post it on GitHub straight from the app — with the debug data of a recent tutor turn attached.'**
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
  /// **'This build cannot sign in to GitHub: it was compiled without a GitHub OAuth client id. Reports can still be saved as a file.'**
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
  /// **'Post on GitHub'**
  String get options_bugReport_dialog_submit;

  /// No description provided for @options_bugReport_dialog_saveFile.
  ///
  /// In en, this message translates to:
  /// **'Save as file'**
  String get options_bugReport_dialog_saveFile;

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

  /// No description provided for @options_bugReport_saved.
  ///
  /// In en, this message translates to:
  /// **'Report saved as {path}. Send this file to your teacher.'**
  String options_bugReport_saved(String path);

  /// No description provided for @options_bugReport_saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Saving failed: {error}'**
  String options_bugReport_saveFailed(String error);

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

  /// No description provided for @options_answersKept_title.
  ///
  /// In en, this message translates to:
  /// **'Your answers'**
  String get options_answersKept_title;

  /// #228: the one sentence that tells a student the content of their oefeningen is stored, and until when.
  ///
  /// In en, this message translates to:
  /// **'Your questions and answers are kept until the end of the school year, so your teacher can see where you get stuck.'**
  String get options_answersKept_text;

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

  /// About button that shows the running version's release notes in the What's new overlay (#130)
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get options_about_whatsNew;

  /// Label of the What's new button while the release notes are being looked up
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get options_about_whatsNew_loading;

  /// No description provided for @options_about_whatsNew_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the release notes: {error}'**
  String options_about_whatsNew_failed(String error);

  /// Snack when no published release carries the running version's tag — a dev build, typically
  ///
  /// In en, this message translates to:
  /// **'No release notes for version {version}.'**
  String options_about_whatsNew_none(String version);

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

  /// Dismissible shell notice after the launch's own update check failed (#124); the reason itself is in Options → About
  ///
  /// In en, this message translates to:
  /// **'Checking for updates did not succeed — see Options → About.'**
  String get update_notice_checkFailed;

  /// No description provided for @update_notice_dismiss.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get update_notice_dismiss;

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

  /// Full-screen gate a build below config/global's MinimumVersion gets instead of the app (#165)
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get update_required_title;

  /// No description provided for @update_required_message.
  ///
  /// In en, this message translates to:
  /// **'This version of the app ({local}) is older than the version the school requires ({minimum}). Update to continue.'**
  String update_required_message(String local, String minimum);

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

  /// Notice above the theory page when the lesson has no translation into the app language and its Dutch text is shown instead. Names the app language itself. Never shown in Dutch, the language lessons are written in.
  ///
  /// In en, this message translates to:
  /// **'This lesson is not available in English yet, so it is shown in Dutch.'**
  String get session_explain_translationMissing;

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

  /// Explain-view footer button that pages forward through already-seen theory pages; only shown after the student paged back
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get session_explain_next_button;

  /// Explain-view footer caption naming the XP the current subgoal is worth once it is fully completed; only shown on the newest theory page
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP on completion'**
  String session_explain_completeXp(int xp);

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

  /// Hover text on the question's short ID (#3fa91c) in the header of an exercise (#216)
  ///
  /// In en, this message translates to:
  /// **'The ID of this question. Your teacher can use it to find the question.'**
  String get session_questionId_tooltip;

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

  /// Tooltip of the chat header button that folds the chat panel to an edge strip; only offered in the theory (explain) view
  ///
  /// In en, this message translates to:
  /// **'Hide chat'**
  String get chat_header_collapse_tooltip;

  /// Tooltip of the one button on the folded chat strip, which brings the full chat panel back
  ///
  /// In en, this message translates to:
  /// **'Show chat'**
  String get chat_panel_expand_tooltip;

  /// No description provided for @chat_composer_idle_hint.
  ///
  /// In en, this message translates to:
  /// **'Type your question or answer…'**
  String get chat_composer_idle_hint;

  /// Hint in the chat input while a theory page is on screen: a question typed now is answered about that page (#132)
  ///
  /// In en, this message translates to:
  /// **'Ask a question about this explanation…'**
  String get chat_composer_idle_pageHint;

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

  /// Notice above the goal editor's title field when the chosen translation language has no translation of the goal
  ///
  /// In en, this message translates to:
  /// **'This goal has no {language} translation yet. Students who use the app in {language} see the Dutch title and description.'**
  String goals_editor_translation_none(String language);

  /// No description provided for @goals_editor_translation_stale.
  ///
  /// In en, this message translates to:
  /// **'Outdated: the Dutch title or description changed after this {language} translation was made. Update it and save it again.'**
  String goals_editor_translation_stale(String language);

  /// No description provided for @goals_editor_translation_save.
  ///
  /// In en, this message translates to:
  /// **'Save translation'**
  String get goals_editor_translation_save;

  /// No description provided for @goals_editor_translation_saved.
  ///
  /// In en, this message translates to:
  /// **'{language} translation saved'**
  String goals_editor_translation_saved(String language);

  /// No description provided for @goals_editor_language_discard_message.
  ///
  /// In en, this message translates to:
  /// **'The {language} title and description have changes that are not saved. Switching to {target} discards them.'**
  String goals_editor_language_discard_message(String language, String target);

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

  /// Notice above the Lesinhoud editor when the chosen translation language has no translation of the lesson
  ///
  /// In en, this message translates to:
  /// **'This lesson has no {language} translation yet. Students who use the app in {language} see the Dutch lesson.'**
  String lesson_translation_none(String language);

  /// No description provided for @lesson_translation_stale.
  ///
  /// In en, this message translates to:
  /// **'Outdated: the Dutch lesson changed after this {language} translation was made. Update it and save it again.'**
  String lesson_translation_stale(String language);

  /// No description provided for @lesson_translation_needsSource.
  ///
  /// In en, this message translates to:
  /// **'This subgoal has no Dutch lesson yet. Write and save the Dutch lesson first: translations are made from it.'**
  String get lesson_translation_needsSource;

  /// No description provided for @lesson_translation_containerMissing.
  ///
  /// In en, this message translates to:
  /// **'Translations cannot be saved yet: the Cosmos container `translations` does not exist. Create it with partition key `/language` (README, step 3).'**
  String get lesson_translation_containerMissing;

  /// No description provided for @lesson_translation_writeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not write the translation: {error}'**
  String lesson_translation_writeFailed(String error);

  /// No description provided for @lesson_editor_button_deleteTranslation.
  ///
  /// In en, this message translates to:
  /// **'Delete translation'**
  String get lesson_editor_button_deleteTranslation;

  /// No description provided for @lesson_deleteTranslation_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete the {language} translation?'**
  String lesson_deleteTranslation_dialog_title(String language);

  /// No description provided for @lesson_deleteTranslation_dialog_message.
  ///
  /// In en, this message translates to:
  /// **'Only the {language} translation is removed; the Dutch lesson stays as it is. Students who use the app in {language} see the Dutch lesson until there is a new translation.'**
  String lesson_deleteTranslation_dialog_message(String language);

  /// No description provided for @lesson_deleteTranslation_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get lesson_deleteTranslation_dialog_cancel;

  /// No description provided for @lesson_deleteTranslation_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get lesson_deleteTranslation_dialog_confirm;

  /// No description provided for @lesson_snack_translationDeleted.
  ///
  /// In en, this message translates to:
  /// **'{language} translation deleted'**
  String lesson_snack_translationDeleted(String language);

  /// No description provided for @lesson_language_discard_title.
  ///
  /// In en, this message translates to:
  /// **'Discard unsaved changes?'**
  String get lesson_language_discard_title;

  /// No description provided for @lesson_language_discard_message.
  ///
  /// In en, this message translates to:
  /// **'The {language} lesson has changes that are not saved. Switching to {target} discards them.'**
  String lesson_language_discard_message(String language, String target);

  /// No description provided for @lesson_language_discard_cancel.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get lesson_language_discard_cancel;

  /// No description provided for @lesson_language_discard_confirm.
  ///
  /// In en, this message translates to:
  /// **'Discard and switch'**
  String get lesson_language_discard_confirm;

  /// No description provided for @lesson_upload_langMismatch_title.
  ///
  /// In en, this message translates to:
  /// **'This file is in another language'**
  String get lesson_upload_langMismatch_title;

  /// Warning when an uploaded lesson's <html lang> does not match the language chosen in the Lesinhoud toolbar
  ///
  /// In en, this message translates to:
  /// **'The file is marked as {fileLanguage} (lang=\"{code}\"), but you are editing the {language} lesson. Put it in this lesson anyway?'**
  String lesson_upload_langMismatch_message(
    String fileLanguage,
    String code,
    String language,
  );

  /// No description provided for @lesson_upload_langMismatch_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get lesson_upload_langMismatch_cancel;

  /// No description provided for @lesson_upload_langMismatch_confirm.
  ///
  /// In en, this message translates to:
  /// **'Upload anyway'**
  String get lesson_upload_langMismatch_confirm;

  /// The source language's option in a teacher's language picker: lessons and goals are written in it and translated from it
  ///
  /// In en, this message translates to:
  /// **'{language} (source)'**
  String translation_language_source(String language);

  /// No description provided for @translation_status_current.
  ///
  /// In en, this message translates to:
  /// **'{language} translation: up to date'**
  String translation_status_current(String language);

  /// No description provided for @translation_status_stale.
  ///
  /// In en, this message translates to:
  /// **'{language} translation: outdated, the Dutch text changed after it was translated'**
  String translation_status_stale(String language);

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

  /// No description provided for @accounts_class_choice_hint.
  ///
  /// In en, this message translates to:
  /// **'Choose a class'**
  String get accounts_class_choice_hint;

  /// No description provided for @accounts_class_choice_none.
  ///
  /// In en, this message translates to:
  /// **'No class'**
  String get accounts_class_choice_none;

  /// No description provided for @accounts_class_choice_noClasses.
  ///
  /// In en, this message translates to:
  /// **'There are no classes yet. Add them on the Classes page.'**
  String get accounts_class_choice_noClasses;

  /// No description provided for @accounts_class_choice_unlisted.
  ///
  /// In en, this message translates to:
  /// **'Not in the class list.'**
  String get accounts_class_choice_unlisted;

  /// No description provided for @accounts_class_unlisted_tooltip.
  ///
  /// In en, this message translates to:
  /// **'This class is not in the class list. Add it on the Classes page, or choose a class from the list.'**
  String get accounts_class_unlisted_tooltip;

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

  /// No description provided for @accounts_usage_title.
  ///
  /// In en, this message translates to:
  /// **'Token usage per class'**
  String get accounts_usage_title;

  /// No description provided for @accounts_usage_summary.
  ///
  /// In en, this message translates to:
  /// **'{tokens} tokens in the last 30 days'**
  String accounts_usage_summary(String tokens);

  /// No description provided for @accounts_usage_subtitle.
  ///
  /// In en, this message translates to:
  /// **'What the tutor\'s calls to the AI model used for your students\' graded exercises. Input leaves out the tokens that came from the cache.'**
  String get accounts_usage_subtitle;

  /// No description provided for @accounts_usage_last7.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get accounts_usage_last7;

  /// No description provided for @accounts_usage_last30.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get accounts_usage_last30;

  /// No description provided for @accounts_usage_class.
  ///
  /// In en, this message translates to:
  /// **'CLASS'**
  String get accounts_usage_class;

  /// No description provided for @accounts_usage_input.
  ///
  /// In en, this message translates to:
  /// **'INPUT'**
  String get accounts_usage_input;

  /// No description provided for @accounts_usage_cached.
  ///
  /// In en, this message translates to:
  /// **'CACHED'**
  String get accounts_usage_cached;

  /// No description provided for @accounts_usage_output.
  ///
  /// In en, this message translates to:
  /// **'OUTPUT'**
  String get accounts_usage_output;

  /// No description provided for @accounts_usage_empty.
  ///
  /// In en, this message translates to:
  /// **'No token usage recorded in the last 30 days.'**
  String get accounts_usage_empty;

  /// No description provided for @accounts_usage_loadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load token usage: {error}'**
  String accounts_usage_loadError(String error);

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

  /// Signal event (#225): the grader judged the learning objective the question asked about, and the app dropped that judgment because the LO fell outside its grading scope. The oefening did not count for its own LO. Audit (amber dot) for one; strong (red dot) on the third question in a row (#229).
  ///
  /// In en, this message translates to:
  /// **'Grade on the asked LO lost'**
  String get drawer_signals_kind_targetSignalLost;

  /// The detail line of a strong grade-lost signal event (#229): how many questions in a row lost the grade on the learning objective they asked about, and that LO for the last of them.
  ///
  /// In en, this message translates to:
  /// **'{count} questions in a row without a grade on the LO they asked about, the last on {lo}'**
  String drawer_signals_targetSignalLost_run_detail(int count, String lo);

  /// Signal event (#229): the student worked long on one subgoal without newly mastering a learning objective, and most of the last answers were not right.
  ///
  /// In en, this message translates to:
  /// **'Stuck without progress'**
  String get drawer_signals_kind_noProgress;

  /// The detail line of a no-progress signal event (#229): the subgoal, the clock time of the last progress, the minutes since, and how many of the last answers were not right.
  ///
  /// In en, this message translates to:
  /// **'{subgoal} since {since} ({minutes} min): {notRight} of the last {answers} answers not right'**
  String drawer_signals_noProgress_detail(
    String subgoal,
    String since,
    int minutes,
    int notRight,
    int answers,
  );

  /// Follows the no-progress detail line after a comma (#229): the learning objective asked most often since the last progress, and its belief mean, already formatted with two decimals.
  ///
  /// In en, this message translates to:
  /// **'most asked: {lo} (μ {mean})'**
  String drawer_signals_noProgress_mostAsked(String lo, String mean);

  /// No description provided for @drawer_signals_kind_provenanceGap.
  ///
  /// In en, this message translates to:
  /// **'Class work contradicts home work'**
  String get drawer_signals_kind_provenanceGap;

  /// The detail line of a provenance-gap signal event (#107): the learning objective, and how many of its direct signals were positive at home and in the lessons after that home work.
  ///
  /// In en, this message translates to:
  /// **'{lo}: at home {homePositive} of {homeSignals} positive, in class afterwards {supervisedPositive} of {supervisedSignals} (last {days} days)'**
  String drawer_signals_provenanceGap_detail(
    String lo,
    int homePositive,
    int homeSignals,
    int supervisedPositive,
    int supervisedSignals,
    int days,
  );

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

  /// No description provided for @levelUp_caption_oefening.
  ///
  /// In en, this message translates to:
  /// **'+{xp} XP · EXERCISE DONE'**
  String levelUp_caption_oefening(int xp);

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

  /// No description provided for @levelUp_subtitle_oefeningen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You\'ve done 1 exercise so far.} other{You\'ve done {count} exercises so far.}}'**
  String levelUp_subtitle_oefeningen(int count);

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

  /// The reply's prose carried a run of characters from another alphabet — a stray token out of a small model (#147)
  ///
  /// In en, this message translates to:
  /// **'The tutor\'s reply came back garbled.'**
  String get chat_notice_replyGarbled;

  /// An account without the school key has no key stored, so the tutor made no call (#126)
  ///
  /// In en, this message translates to:
  /// **'No OpenAI API key is stored on this device. Add yours under Options → OpenAI API key.'**
  String get chat_notice_ownKeyMissing;

  /// OpenAI answered 401 on the key the user stored on this device (#126)
  ///
  /// In en, this message translates to:
  /// **'OpenAI rejected your API key. Check it under Options → OpenAI API key.'**
  String get chat_notice_ownKeyRejected;

  /// OpenAI answered 401 on the school's bundled key, or the build has none; nothing the student can fix (#126)
  ///
  /// In en, this message translates to:
  /// **'The school\'s OpenAI API key is not working. Let your teacher know.'**
  String get chat_notice_schoolKeyInvalid;

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

  /// No description provided for @chat_notice_warmUpReview.
  ///
  /// In en, this message translates to:
  /// **'Quick warm-up first: one review question on {title}.'**
  String chat_notice_warmUpReview(String title);

  /// No description provided for @chat_notice_recheck.
  ///
  /// In en, this message translates to:
  /// **'In between: one check question on {title}, so you can show you\'ve got it now.'**
  String chat_notice_recheck(String title);

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

  /// No description provided for @questions_page_title.
  ///
  /// In en, this message translates to:
  /// **'Questions'**
  String get questions_page_title;

  /// No description provided for @questions_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'A new question only lands here when the first student answers it correctly, and the app hides a question that is answered wrong too often by itself. Hide or delete what is still wrong or unclear: a hidden question is not asked again.'**
  String get questions_page_subtitle;

  /// No description provided for @questions_refresh_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get questions_refresh_tooltip;

  /// No description provided for @questions_containerMissing_title.
  ///
  /// In en, this message translates to:
  /// **'The question bank has not been set up yet'**
  String get questions_containerMissing_title;

  /// No description provided for @questions_containerMissing_body.
  ///
  /// In en, this message translates to:
  /// **'The Cosmos container `questions` does not exist. Create it with partition key `/subgoalId` (README, step 3). Until then students practise as usual, but their questions are not stored.'**
  String get questions_containerMissing_body;

  /// No description provided for @questions_loadError.
  ///
  /// In en, this message translates to:
  /// **'The question bank could not be loaded: {error}'**
  String questions_loadError(String error);

  /// No description provided for @questions_retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get questions_retry;

  /// No description provided for @questions_tree_empty.
  ///
  /// In en, this message translates to:
  /// **'No questions stored yet. They appear here once a student answers a new question correctly.'**
  String get questions_tree_empty;

  /// No description provided for @questions_tree_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 question} other{{count} questions}}'**
  String questions_tree_count(int count);

  /// Questions of a subgoal that are hidden, by the teacher or automatically
  ///
  /// In en, this message translates to:
  /// **'{count} hidden'**
  String questions_tree_hidden(int count);

  /// No description provided for @questions_tree_unknownSubgoal.
  ///
  /// In en, this message translates to:
  /// **'Removed subgoal ({id})'**
  String questions_tree_unknownSubgoal(String id);

  /// No description provided for @questions_tree_otherGroup.
  ///
  /// In en, this message translates to:
  /// **'No longer in the curriculum'**
  String get questions_tree_otherGroup;

  /// No description provided for @questions_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Pick a subgoal on the left.'**
  String get questions_placeholder;

  /// No description provided for @questions_filter_hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden only'**
  String get questions_filter_hidden;

  /// No description provided for @questions_sort_newest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get questions_sort_newest;

  /// No description provided for @questions_sort_shareAsc.
  ///
  /// In en, this message translates to:
  /// **'Share correct ↑'**
  String get questions_sort_shareAsc;

  /// No description provided for @questions_sort_shareDesc.
  ///
  /// In en, this message translates to:
  /// **'Share correct ↓'**
  String get questions_sort_shareDesc;

  /// No description provided for @questions_sort_mostAsked.
  ///
  /// In en, this message translates to:
  /// **'Most asked'**
  String get questions_sort_mostAsked;

  /// No description provided for @questions_list_empty.
  ///
  /// In en, this message translates to:
  /// **'No questions for this subgoal.'**
  String get questions_list_empty;

  /// No description provided for @questions_list_noneHidden.
  ///
  /// In en, this message translates to:
  /// **'No hidden questions for this subgoal.'**
  String get questions_list_noneHidden;

  /// No description provided for @questions_type_mcQuestion.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice'**
  String get questions_type_mcQuestion;

  /// No description provided for @questions_type_completeCodeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Complete the code'**
  String get questions_type_completeCodeQuestion;

  /// No description provided for @questions_type_explainCodeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Explain the code'**
  String get questions_type_explainCodeQuestion;

  /// No description provided for @questions_type_writeCodeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Write code'**
  String get questions_type_writeCodeQuestion;

  /// No description provided for @questions_type_socraticQuestion.
  ///
  /// In en, this message translates to:
  /// **'Open question'**
  String get questions_type_socraticQuestion;

  /// No description provided for @questions_asked.
  ///
  /// In en, this message translates to:
  /// **'asked {count}×'**
  String questions_asked(int count);

  /// No description provided for @questions_shareCorrect.
  ///
  /// In en, this message translates to:
  /// **'{percent}% correct ({correct}/{answered})'**
  String questions_shareCorrect(int percent, int correct, int answered);

  /// No description provided for @questions_notAnswered.
  ///
  /// In en, this message translates to:
  /// **'no answers yet'**
  String get questions_notAnswered;

  /// No description provided for @questions_targets.
  ///
  /// In en, this message translates to:
  /// **'LO {ids}'**
  String questions_targets(String ids);

  /// No description provided for @questions_badge_hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get questions_badge_hidden;

  /// No description provided for @questions_badge_autoHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden automatically'**
  String get questions_badge_autoHidden;

  /// No description provided for @questions_badge_autoHidden_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Less than half correct on {count} or more answers. Show it again and the app no longer hides it by itself.'**
  String questions_badge_autoHidden_tooltip(int count);

  /// No description provided for @questions_keyDisagreement.
  ///
  /// In en, this message translates to:
  /// **'The grading disagreed with the answer key at least once.'**
  String get questions_keyDisagreement;

  /// No description provided for @questions_keyDisputed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The grading called the answer key wrong once.} other{The grading called the answer key wrong {count} times.}}'**
  String questions_keyDisputed(int count);

  /// No description provided for @questions_noKey.
  ///
  /// In en, this message translates to:
  /// **'No answer key: the model did not name the correct option.'**
  String get questions_noKey;

  /// No description provided for @questions_answerKey_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Answer key'**
  String get questions_answerKey_tooltip;

  /// No description provided for @questions_action_hide.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get questions_action_hide;

  /// No description provided for @questions_action_unhide.
  ///
  /// In en, this message translates to:
  /// **'Show again'**
  String get questions_action_unhide;

  /// No description provided for @questions_action_delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get questions_action_delete;

  /// No description provided for @questions_delete_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete this question?'**
  String get questions_delete_dialog_title;

  /// No description provided for @questions_delete_dialog_body.
  ///
  /// In en, this message translates to:
  /// **'The question is removed from the question bank. If the tutor generates the same question later, it only comes back when the first student answers it correctly.'**
  String get questions_delete_dialog_body;

  /// No description provided for @questions_delete_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get questions_delete_dialog_cancel;

  /// No description provided for @questions_delete_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get questions_delete_dialog_confirm;

  /// No description provided for @questions_actionFailed.
  ///
  /// In en, this message translates to:
  /// **'That did not work: {error}'**
  String questions_actionFailed(String error);

  /// Field on the Questions page to look a question up by the short ID a student sees with the exercise (#216)
  ///
  /// In en, this message translates to:
  /// **'Find by ID'**
  String get questions_lookup_label;

  /// No description provided for @questions_lookup_hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. #3fa91c'**
  String get questions_lookup_hint;

  /// No description provided for @questions_lookup_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get questions_lookup_tooltip;

  /// No description provided for @questions_lookup_clear_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get questions_lookup_clear_tooltip;

  /// No description provided for @questions_lookup_notFound.
  ///
  /// In en, this message translates to:
  /// **'This question is not in the bank. Usually the first answer to it was not (fully) correct, and then a question is not kept. Or it was deleted.'**
  String get questions_lookup_notFound;

  /// No description provided for @questions_lookup_invalid.
  ///
  /// In en, this message translates to:
  /// **'That is not a question ID. An ID looks like #3fa91c.'**
  String get questions_lookup_invalid;

  /// Above the subgoals of the questions a lookup found, when there is more than one
  ///
  /// In en, this message translates to:
  /// **'{count} questions have this ID:'**
  String questions_lookup_several(int count);

  /// Badge on the card a lookup by ID found — displayed uppercase
  ///
  /// In en, this message translates to:
  /// **'Found'**
  String get questions_badge_found;

  /// No description provided for @classes_page_title.
  ///
  /// In en, this message translates to:
  /// **'Classes'**
  String get classes_page_title;

  /// No description provided for @classes_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Every class with its students and its lessons each week. A student\'s class is chosen on the Students page.'**
  String get classes_page_subtitle;

  /// No description provided for @classes_button_new.
  ///
  /// In en, this message translates to:
  /// **'New class'**
  String get classes_button_new;

  /// No description provided for @classes_list_empty.
  ///
  /// In en, this message translates to:
  /// **'No classes yet.'**
  String get classes_list_empty;

  /// No description provided for @classes_studentCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{no students} =1{1 student} other{{count} students}}'**
  String classes_studentCount(int count);

  /// Above the class names that students' accounts carry but the class list does not have, each with an Add button
  ///
  /// In en, this message translates to:
  /// **'On accounts, not in the list'**
  String get classes_unlisted_header;

  /// No description provided for @classes_unlisted_add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get classes_unlisted_add;

  /// No description provided for @classes_placeholder.
  ///
  /// In en, this message translates to:
  /// **'Choose a class, or add one.'**
  String get classes_placeholder;

  /// No description provided for @classes_rename_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get classes_rename_tooltip;

  /// No description provided for @classes_delete_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get classes_delete_tooltip;

  /// No description provided for @classes_delete_blocked_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Only a class without students can be deleted'**
  String get classes_delete_blocked_tooltip;

  /// No description provided for @classes_lessons_header.
  ///
  /// In en, this message translates to:
  /// **'Lessons'**
  String get classes_lessons_header;

  /// No description provided for @classes_lessons_empty.
  ///
  /// In en, this message translates to:
  /// **'No lessons yet.'**
  String get classes_lessons_empty;

  /// No description provided for @classes_lesson_add.
  ///
  /// In en, this message translates to:
  /// **'Add lesson'**
  String get classes_lesson_add;

  /// No description provided for @classes_lesson_weekday_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get classes_lesson_weekday_tooltip;

  /// No description provided for @classes_lesson_start_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get classes_lesson_start_tooltip;

  /// No description provided for @classes_lesson_end_tooltip.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get classes_lesson_end_tooltip;

  /// No description provided for @classes_lesson_delete_tooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete lesson'**
  String get classes_lesson_delete_tooltip;

  /// No description provided for @classes_lesson_endBeforeStart.
  ///
  /// In en, this message translates to:
  /// **'A lesson has to end after it starts.'**
  String get classes_lesson_endBeforeStart;

  /// No description provided for @classes_dialog_new_title.
  ///
  /// In en, this message translates to:
  /// **'New class'**
  String get classes_dialog_new_title;

  /// No description provided for @classes_dialog_rename_title.
  ///
  /// In en, this message translates to:
  /// **'Rename class'**
  String get classes_dialog_rename_title;

  /// No description provided for @classes_dialog_name_label.
  ///
  /// In en, this message translates to:
  /// **'Class name'**
  String get classes_dialog_name_label;

  /// No description provided for @classes_dialog_rename_note.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{There are no students in this class.} =1{The student in this class moves along.} other{The {count} students in this class move along.}}'**
  String classes_dialog_rename_note(int count);

  /// No description provided for @classes_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get classes_dialog_cancel;

  /// No description provided for @classes_dialog_save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get classes_dialog_save;

  /// No description provided for @classes_validation_empty.
  ///
  /// In en, this message translates to:
  /// **'Give the class a name.'**
  String get classes_validation_empty;

  /// No description provided for @classes_validation_taken.
  ///
  /// In en, this message translates to:
  /// **'There already is a class {name}.'**
  String classes_validation_taken(String name);

  /// No description provided for @classes_delete_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String classes_delete_dialog_title(String name);

  /// No description provided for @classes_delete_dialog_body.
  ///
  /// In en, this message translates to:
  /// **'The class and its lessons are removed from the list.'**
  String get classes_delete_dialog_body;

  /// No description provided for @classes_delete_dialog_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get classes_delete_dialog_cancel;

  /// No description provided for @classes_delete_dialog_confirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get classes_delete_dialog_confirm;

  /// No description provided for @classes_delete_hasStudents.
  ///
  /// In en, this message translates to:
  /// **'{name} still has students. Put them in another class first.'**
  String classes_delete_hasStudents(String name);

  /// No description provided for @classes_actionFailed.
  ///
  /// In en, this message translates to:
  /// **'That did not work: {error}'**
  String classes_actionFailed(String error);

  /// No description provided for @sidebar_section_trophies.
  ///
  /// In en, this message translates to:
  /// **'Trophy case'**
  String get sidebar_section_trophies;

  /// No description provided for @badges_page_title.
  ///
  /// In en, this message translates to:
  /// **'Trophy case'**
  String get badges_page_title;

  /// No description provided for @badges_page_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Badges for what you\'ve done. They give no XP and don\'t count towards your grade.'**
  String get badges_page_subtitle;

  /// No description provided for @badges_page_count.
  ///
  /// In en, this message translates to:
  /// **'{earned} of {total} badges earned'**
  String badges_page_count(int earned, int total);

  /// No description provided for @badges_page_loading.
  ///
  /// In en, this message translates to:
  /// **'Counting your badges…'**
  String get badges_page_loading;

  /// No description provided for @badges_page_noProgress.
  ///
  /// In en, this message translates to:
  /// **'Your progress could not be loaded. You see the badges you already have.'**
  String get badges_page_noProgress;

  /// No description provided for @badges_section_tiers.
  ///
  /// In en, this message translates to:
  /// **'In tiers'**
  String get badges_section_tiers;

  /// No description provided for @badges_section_tiers_hint.
  ///
  /// In en, this message translates to:
  /// **'Bronze, silver, gold, and a dot for every tier after that.'**
  String get badges_section_tiers_hint;

  /// No description provided for @badges_section_experts.
  ///
  /// In en, this message translates to:
  /// **'Experts'**
  String get badges_section_experts;

  /// No description provided for @badges_section_experts_hint.
  ///
  /// In en, this message translates to:
  /// **'One per main goal: every learning objective of it mastered.'**
  String get badges_section_experts_hint;

  /// No description provided for @badges_section_fun.
  ///
  /// In en, this message translates to:
  /// **'Just for fun'**
  String get badges_section_fun;

  /// No description provided for @badges_section_fun_hint.
  ///
  /// In en, this message translates to:
  /// **'Most of them are secret. Find out yourself how to get them.'**
  String get badges_section_fun_hint;

  /// No description provided for @badges_tile_tier.
  ///
  /// In en, this message translates to:
  /// **'Tier {tier} of {max}'**
  String badges_tile_tier(int tier, int max);

  /// No description provided for @badges_tile_top.
  ///
  /// In en, this message translates to:
  /// **'Top tier!'**
  String get badges_tile_top;

  /// No description provided for @badges_tile_locked.
  ///
  /// In en, this message translates to:
  /// **'Not earned yet'**
  String get badges_tile_locked;

  /// No description provided for @badges_tile_earned.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get badges_tile_earned;

  /// No description provided for @badges_tile_noLessons.
  ///
  /// In en, this message translates to:
  /// **'Your class has no lesson times yet, so this one waits.'**
  String get badges_tile_noLessons;

  /// No description provided for @badges_secret_name.
  ///
  /// In en, this message translates to:
  /// **'Secret badge'**
  String get badges_secret_name;

  /// No description provided for @badges_secret_description.
  ///
  /// In en, this message translates to:
  /// **'Find out yourself how to get this one.'**
  String get badges_secret_description;

  /// No description provided for @badges_credits_button.
  ///
  /// In en, this message translates to:
  /// **'Icons: game-icons.net (CC BY 3.0)'**
  String get badges_credits_button;

  /// No description provided for @badges_credits_title.
  ///
  /// In en, this message translates to:
  /// **'Badge icons'**
  String get badges_credits_title;

  /// No description provided for @badges_credits_intro.
  ///
  /// In en, this message translates to:
  /// **'The badge icons come from game-icons.net, under the Creative Commons Attribution 3.0 licence (CC BY 3.0). Their background was left out and their colour adapted.'**
  String get badges_credits_intro;

  /// No description provided for @badges_credits_line.
  ///
  /// In en, this message translates to:
  /// **'{icon} by {author}'**
  String badges_credits_line(String icon, String author);

  /// No description provided for @badges_credits_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get badges_credits_close;

  /// No description provided for @badges_toast_caption.
  ///
  /// In en, this message translates to:
  /// **'NEW BADGE'**
  String get badges_toast_caption;

  /// No description provided for @badges_toast_tier.
  ///
  /// In en, this message translates to:
  /// **'Tier {tier}'**
  String badges_toast_tier(int tier);

  /// No description provided for @badges_toast_summary_first.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You\'ve already earned 1 badge!} other{You\'ve already earned {count} badges!}}'**
  String badges_toast_summary_first(int count);

  /// No description provided for @badges_toast_summary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 new badge!} other{{count} new badges!}}'**
  String badges_toast_summary(int count);

  /// No description provided for @badges_toast_open.
  ///
  /// In en, this message translates to:
  /// **'See your trophy case'**
  String get badges_toast_open;

  /// No description provided for @badges_toast_close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get badges_toast_close;

  /// No description provided for @options_badges_title.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get options_badges_title;

  /// No description provided for @options_badges_subtitle.
  ///
  /// In en, this message translates to:
  /// **'The proof sheet: the badges in both themes, at 32, 64 and 128 pixels.'**
  String get options_badges_subtitle;

  /// No description provided for @options_badges_open.
  ///
  /// In en, this message translates to:
  /// **'Open the proof sheet'**
  String get options_badges_open;

  /// No description provided for @options_about_credits.
  ///
  /// In en, this message translates to:
  /// **'Badge icon credits'**
  String get options_about_credits;

  /// No description provided for @badges_proof_title.
  ///
  /// In en, this message translates to:
  /// **'Badge proof sheet'**
  String get badges_proof_title;

  /// No description provided for @badges_proof_intro.
  ///
  /// In en, this message translates to:
  /// **'The frame\'s shape, the tier colours and the glyph\'s size are set in one place: lib/theme/badge_style.dart.'**
  String get badges_proof_intro;

  /// No description provided for @badges_proof_dark.
  ///
  /// In en, this message translates to:
  /// **'Dark theme'**
  String get badges_proof_dark;

  /// No description provided for @badges_proof_light.
  ///
  /// In en, this message translates to:
  /// **'Light theme'**
  String get badges_proof_light;

  /// No description provided for @badges_proof_states.
  ///
  /// In en, this message translates to:
  /// **'Ten badges, each in another state'**
  String get badges_proof_states;

  /// No description provided for @badges_proof_set.
  ///
  /// In en, this message translates to:
  /// **'The whole set'**
  String get badges_proof_set;

  /// No description provided for @badges_proof_previewCase.
  ///
  /// In en, this message translates to:
  /// **'Trophy case preview'**
  String get badges_proof_previewCase;

  /// No description provided for @badges_proof_previewToast.
  ///
  /// In en, this message translates to:
  /// **'Show a notice'**
  String get badges_proof_previewToast;

  /// No description provided for @badges_proof_previewSummary.
  ///
  /// In en, this message translates to:
  /// **'Show a summary'**
  String get badges_proof_previewSummary;

  /// No description provided for @badges_proof_state_locked.
  ///
  /// In en, this message translates to:
  /// **'not earned'**
  String get badges_proof_state_locked;

  /// No description provided for @badges_proof_state_tier.
  ///
  /// In en, this message translates to:
  /// **'tier {tier} of {max}'**
  String badges_proof_state_tier(int tier, int max);

  /// No description provided for @badges_proof_state_secret.
  ///
  /// In en, this message translates to:
  /// **'secret'**
  String get badges_proof_state_secret;

  /// No description provided for @badges_proof_state_found.
  ///
  /// In en, this message translates to:
  /// **'secret, found'**
  String get badges_proof_state_found;

  /// No description provided for @badges_proof_state_expert.
  ///
  /// In en, this message translates to:
  /// **'expert'**
  String get badges_proof_state_expert;

  /// No description provided for @badges_proof_state_fun.
  ///
  /// In en, this message translates to:
  /// **'single'**
  String get badges_proof_state_fun;

  /// No description provided for @badge_expert_name.
  ///
  /// In en, this message translates to:
  /// **'Expert in {goal}'**
  String badge_expert_name(String goal);

  /// No description provided for @badge_expert_description.
  ///
  /// In en, this message translates to:
  /// **'Every learning objective of {goal} mastered.'**
  String badge_expert_description(String goal);

  /// No description provided for @badge_effort_name.
  ///
  /// In en, this message translates to:
  /// **'Effort'**
  String get badge_effort_name;

  /// No description provided for @badge_effort_description.
  ///
  /// In en, this message translates to:
  /// **'Exercises done, right or wrong.'**
  String get badge_effort_description;

  /// No description provided for @badge_homeWork_name.
  ///
  /// In en, this message translates to:
  /// **'Home worker'**
  String get badge_homeWork_name;

  /// No description provided for @badge_homeWork_description.
  ///
  /// In en, this message translates to:
  /// **'Exercises outside lesson time.'**
  String get badge_homeWork_description;

  /// No description provided for @badge_lessonWeeks_name.
  ///
  /// In en, this message translates to:
  /// **'Lesson weeks'**
  String get badge_lessonWeeks_name;

  /// No description provided for @badge_lessonWeeks_description.
  ///
  /// In en, this message translates to:
  /// **'Weeks with at least one exercise in class.'**
  String get badge_lessonWeeks_description;

  /// No description provided for @badge_hardCorrect_name.
  ///
  /// In en, this message translates to:
  /// **'Hard is my middle name'**
  String get badge_hardCorrect_name;

  /// No description provided for @badge_hardCorrect_description.
  ///
  /// In en, this message translates to:
  /// **'Right answers to hard questions.'**
  String get badge_hardCorrect_description;

  /// No description provided for @badge_streak_name.
  ///
  /// In en, this message translates to:
  /// **'On a roll'**
  String get badge_streak_name;

  /// No description provided for @badge_streak_description.
  ///
  /// In en, this message translates to:
  /// **'Right answers in a row, without a mistake in between.'**
  String get badge_streak_description;

  /// No description provided for @badge_gapFiller_name.
  ///
  /// In en, this message translates to:
  /// **'Gap filler'**
  String get badge_gapFiller_name;

  /// No description provided for @badge_gapFiller_description.
  ///
  /// In en, this message translates to:
  /// **'Code completed correctly.'**
  String get badge_gapFiller_description;

  /// No description provided for @badge_fluentPython_name.
  ///
  /// In en, this message translates to:
  /// **'Fluent in Python'**
  String get badge_fluentPython_name;

  /// No description provided for @badge_fluentPython_description.
  ///
  /// In en, this message translates to:
  /// **'Code explained correctly.'**
  String get badge_fluentPython_description;

  /// No description provided for @badge_writer_name.
  ///
  /// In en, this message translates to:
  /// **'Writer'**
  String get badge_writer_name;

  /// No description provided for @badge_writer_description.
  ///
  /// In en, this message translates to:
  /// **'Code written yourself, correctly.'**
  String get badge_writer_description;

  /// No description provided for @badge_allRounder_name.
  ///
  /// In en, this message translates to:
  /// **'All-rounder'**
  String get badge_allRounder_name;

  /// No description provided for @badge_allRounder_description.
  ///
  /// In en, this message translates to:
  /// **'Right on every kind of question: multiple choice, completing, explaining and writing code. Your weakest kind counts.'**
  String get badge_allRounder_description;

  /// No description provided for @badge_knowledge_name.
  ///
  /// In en, this message translates to:
  /// **'Knowledge'**
  String get badge_knowledge_name;

  /// No description provided for @badge_knowledge_description.
  ///
  /// In en, this message translates to:
  /// **'Learning objectives you have mastered.'**
  String get badge_knowledge_description;

  /// No description provided for @badge_milestones_name.
  ///
  /// In en, this message translates to:
  /// **'Milestones'**
  String get badge_milestones_name;

  /// No description provided for @badge_milestones_description.
  ///
  /// In en, this message translates to:
  /// **'Topics you have finished.'**
  String get badge_milestones_description;

  /// No description provided for @badge_elephantMemory_name.
  ///
  /// In en, this message translates to:
  /// **'Memory like an elephant'**
  String get badge_elephantMemory_name;

  /// No description provided for @badge_elephantMemory_description.
  ///
  /// In en, this message translates to:
  /// **'Warm-up questions answered right.'**
  String get badge_elephantMemory_description;

  /// No description provided for @badge_stillSharp_name.
  ///
  /// In en, this message translates to:
  /// **'Still sharp'**
  String get badge_stillSharp_name;

  /// No description provided for @badge_stillSharp_description.
  ///
  /// In en, this message translates to:
  /// **'Check-up questions answered right.'**
  String get badge_stillSharp_description;

  /// No description provided for @badge_oldFriend_name.
  ///
  /// In en, this message translates to:
  /// **'Old friend'**
  String get badge_oldFriend_name;

  /// No description provided for @badge_oldFriend_description.
  ///
  /// In en, this message translates to:
  /// **'Times you used something from before correctly in new code.'**
  String get badge_oldFriend_description;

  /// No description provided for @badge_comeback_name.
  ///
  /// In en, this message translates to:
  /// **'Comeback'**
  String get badge_comeback_name;

  /// No description provided for @badge_comeback_description.
  ///
  /// In en, this message translates to:
  /// **'A right answer after three wrong ones in a row. Not giving up pays off!'**
  String get badge_comeback_description;

  /// No description provided for @badge_wrongToRight_name.
  ///
  /// In en, this message translates to:
  /// **'From wrong to right'**
  String get badge_wrongToRight_name;

  /// No description provided for @badge_wrongToRight_description.
  ///
  /// In en, this message translates to:
  /// **'Follow-up questions answered right after a wrong answer.'**
  String get badge_wrongToRight_description;

  /// No description provided for @badge_hintHit_name.
  ///
  /// In en, this message translates to:
  /// **'Took the hint, hit the mark'**
  String get badge_hintHit_name;

  /// No description provided for @badge_hintHit_description.
  ///
  /// In en, this message translates to:
  /// **'Right after a hint in the same exercise.'**
  String get badge_hintHit_description;

  /// No description provided for @badge_persevere_name.
  ///
  /// In en, this message translates to:
  /// **'Persistent'**
  String get badge_persevere_name;

  /// No description provided for @badge_persevere_description.
  ///
  /// In en, this message translates to:
  /// **'Learning objectives you were stuck on and mastered anyway.'**
  String get badge_persevere_description;

  /// No description provided for @badge_tough_name.
  ///
  /// In en, this message translates to:
  /// **'Tough nut'**
  String get badge_tough_name;

  /// No description provided for @badge_tough_description.
  ///
  /// In en, this message translates to:
  /// **'The most exercises on one learning objective before you mastered it. Struggling is part of learning.'**
  String get badge_tough_description;

  /// No description provided for @badge_helloWorld_name.
  ///
  /// In en, this message translates to:
  /// **'Hello, World!'**
  String get badge_helloWorld_name;

  /// No description provided for @badge_helloWorld_description.
  ///
  /// In en, this message translates to:
  /// **'Your first exercise.'**
  String get badge_helloWorld_description;

  /// No description provided for @badge_fortyTwo_name.
  ///
  /// In en, this message translates to:
  /// **'42'**
  String get badge_fortyTwo_name;

  /// No description provided for @badge_fortyTwo_description.
  ///
  /// In en, this message translates to:
  /// **'Your 42nd exercise: the answer to everything.'**
  String get badge_fortyTwo_description;

  /// No description provided for @badge_offByOne_name.
  ///
  /// In en, this message translates to:
  /// **'Off by one'**
  String get badge_offByOne_name;

  /// No description provided for @badge_offByOne_description.
  ///
  /// In en, this message translates to:
  /// **'Your 99th right answer. Just short of 100.'**
  String get badge_offByOne_description;

  /// No description provided for @badge_earlyBird_name.
  ///
  /// In en, this message translates to:
  /// **'Early bird'**
  String get badge_earlyBird_name;

  /// No description provided for @badge_earlyBird_description.
  ///
  /// In en, this message translates to:
  /// **'An exercise before 8 in the morning.'**
  String get badge_earlyBird_description;

  /// No description provided for @badge_nightOwl_name.
  ///
  /// In en, this message translates to:
  /// **'Night owl'**
  String get badge_nightOwl_name;

  /// No description provided for @badge_nightOwl_description.
  ///
  /// In en, this message translates to:
  /// **'An exercise after 10 at night.'**
  String get badge_nightOwl_description;

  /// No description provided for @badge_weekendWarrior_name.
  ///
  /// In en, this message translates to:
  /// **'Weekend warrior'**
  String get badge_weekendWarrior_name;

  /// No description provided for @badge_weekendWarrior_description.
  ///
  /// In en, this message translates to:
  /// **'An exercise on a Saturday or a Sunday.'**
  String get badge_weekendWarrior_description;

  /// No description provided for @badge_fridayHero_name.
  ///
  /// In en, this message translates to:
  /// **'Friday afternoon hero'**
  String get badge_fridayHero_name;

  /// No description provided for @badge_fridayHero_description.
  ///
  /// In en, this message translates to:
  /// **'A right answer on a Friday after 3 pm.'**
  String get badge_fridayHero_description;

  /// No description provided for @badge_piHour_name.
  ///
  /// In en, this message translates to:
  /// **'Pi hour'**
  String get badge_piHour_name;

  /// No description provided for @badge_piHour_description.
  ///
  /// In en, this message translates to:
  /// **'An exercise at 15:14.'**
  String get badge_piHour_description;

  /// No description provided for @badge_piDay_name.
  ///
  /// In en, this message translates to:
  /// **'Pi day'**
  String get badge_piDay_name;

  /// No description provided for @badge_piDay_description.
  ///
  /// In en, this message translates to:
  /// **'An exercise on 14 March.'**
  String get badge_piDay_description;

  /// No description provided for @badge_spookyCode_name.
  ///
  /// In en, this message translates to:
  /// **'Spooky code'**
  String get badge_spookyCode_name;

  /// No description provided for @badge_spookyCode_description.
  ///
  /// In en, this message translates to:
  /// **'An exercise on 31 October.'**
  String get badge_spookyCode_description;

  /// No description provided for @badge_rubberDuck_name.
  ///
  /// In en, this message translates to:
  /// **'Rubber duck'**
  String get badge_rubberDuck_name;

  /// No description provided for @badge_rubberDuck_description.
  ///
  /// In en, this message translates to:
  /// **'You asked the tutor a question yourself.'**
  String get badge_rubberDuck_description;

  /// No description provided for @badge_ctrlZ_name.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+Z'**
  String get badge_ctrlZ_name;

  /// No description provided for @badge_ctrlZ_description.
  ///
  /// In en, this message translates to:
  /// **'You went back to a topic you had already finished.'**
  String get badge_ctrlZ_description;

  /// No description provided for @badge_bugHunter_name.
  ///
  /// In en, this message translates to:
  /// **'Bug hunter'**
  String get badge_bugHunter_name;

  /// No description provided for @badge_bugHunter_description.
  ///
  /// In en, this message translates to:
  /// **'You were right, the computer wasn\'t.'**
  String get badge_bugHunter_description;

  /// No description provided for @badge_rome_name.
  ///
  /// In en, this message translates to:
  /// **'Rome wasn\'t built in a day'**
  String get badge_rome_name;

  /// No description provided for @badge_rome_description.
  ///
  /// In en, this message translates to:
  /// **'Right after more than 5 minutes on one question.'**
  String get badge_rome_description;

  /// No description provided for @badges_section_podium.
  ///
  /// In en, this message translates to:
  /// **'Class podium'**
  String get badges_section_podium;

  /// No description provided for @badges_section_podium_hint.
  ///
  /// In en, this message translates to:
  /// **'The first three in your class to finish a topic get gold, silver or bronze for it. Only you see your medals.'**
  String get badges_section_podium_hint;

  /// No description provided for @badges_podium_none.
  ///
  /// In en, this message translates to:
  /// **'No medal yet. Finish a topic as one of the first three in your class.'**
  String get badges_podium_none;

  /// No description provided for @badges_podium_noClass.
  ///
  /// In en, this message translates to:
  /// **'You\'re not in a class yet, so you don\'t take part yet.'**
  String get badges_podium_noClass;

  /// No description provided for @badges_section_teacher.
  ///
  /// In en, this message translates to:
  /// **'From your teacher'**
  String get badges_section_teacher;

  /// No description provided for @badges_section_teacher_hint.
  ///
  /// In en, this message translates to:
  /// **'For things the app can\'t see. Your teacher can give you each of them more than once.'**
  String get badges_section_teacher_hint;

  /// No description provided for @badges_tile_count.
  ///
  /// In en, this message translates to:
  /// **'Received {count}×'**
  String badges_tile_count(int count);

  /// No description provided for @badges_toast_fromTeacher.
  ///
  /// In en, this message translates to:
  /// **'From your teacher'**
  String get badges_toast_fromTeacher;

  /// No description provided for @badges_toast_fromTeacherCount.
  ///
  /// In en, this message translates to:
  /// **'From your teacher, {count}× now'**
  String badges_toast_fromTeacherCount(int count);

  /// No description provided for @badges_proof_state_podium.
  ///
  /// In en, this message translates to:
  /// **'class podium'**
  String get badges_proof_state_podium;

  /// No description provided for @badges_proof_state_teacher.
  ///
  /// In en, this message translates to:
  /// **'from the teacher'**
  String get badges_proof_state_teacher;

  /// No description provided for @badge_podium_name.
  ///
  /// In en, this message translates to:
  /// **'{medal}: {subgoal}'**
  String badge_podium_name(String medal, String subgoal);

  /// No description provided for @badge_podium_gold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get badge_podium_gold;

  /// No description provided for @badge_podium_silver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get badge_podium_silver;

  /// No description provided for @badge_podium_bronze.
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get badge_podium_bronze;

  /// No description provided for @badge_podium_unknownSubgoal.
  ///
  /// In en, this message translates to:
  /// **'a topic'**
  String get badge_podium_unknownSubgoal;

  /// No description provided for @badge_podium_first_description.
  ///
  /// In en, this message translates to:
  /// **'You were the first in your class to finish this topic.'**
  String get badge_podium_first_description;

  /// No description provided for @badge_podium_second_description.
  ///
  /// In en, this message translates to:
  /// **'You were the second in your class to finish this topic.'**
  String get badge_podium_second_description;

  /// No description provided for @badge_podium_third_description.
  ///
  /// In en, this message translates to:
  /// **'You were the third in your class to finish this topic.'**
  String get badge_podium_third_description;

  /// No description provided for @badge_faultFinder_name.
  ///
  /// In en, this message translates to:
  /// **'Fault finder'**
  String get badge_faultFinder_name;

  /// No description provided for @badge_faultFinder_description.
  ///
  /// In en, this message translates to:
  /// **'You reported a question that was wrong. Spot one? Tell your teacher the ID at the top of the exercise, like #3fa91c.'**
  String get badge_faultFinder_description;

  /// No description provided for @badge_helpingHand_name.
  ///
  /// In en, this message translates to:
  /// **'Helping hand'**
  String get badge_helpingHand_name;

  /// No description provided for @badge_helpingHand_description.
  ///
  /// In en, this message translates to:
  /// **'You helped a classmate.'**
  String get badge_helpingHand_description;

  /// No description provided for @badge_goodQuestion_name.
  ///
  /// In en, this message translates to:
  /// **'Good question!'**
  String get badge_goodQuestion_name;

  /// No description provided for @badge_goodQuestion_description.
  ///
  /// In en, this message translates to:
  /// **'You asked a question in class that deserved it.'**
  String get badge_goodQuestion_description;

  /// No description provided for @awardBadge_button.
  ///
  /// In en, this message translates to:
  /// **'Award badge'**
  String get awardBadge_button;

  /// No description provided for @awardBadge_title.
  ///
  /// In en, this message translates to:
  /// **'Award a badge to {name}'**
  String awardBadge_title(String name);

  /// No description provided for @awardBadge_intro.
  ///
  /// In en, this message translates to:
  /// **'For things the app can\'t see. {name} gets a notice the next time the app starts, or within seconds if it is open.'**
  String awardBadge_intro(String name);

  /// No description provided for @awardBadge_faultFinder_hint.
  ///
  /// In en, this message translates to:
  /// **'Reported a wrong question, by the ID at the top of the exercise.'**
  String get awardBadge_faultFinder_hint;

  /// No description provided for @awardBadge_helpingHand_hint.
  ///
  /// In en, this message translates to:
  /// **'Helped a classmate.'**
  String get awardBadge_helpingHand_hint;

  /// No description provided for @awardBadge_goodQuestion_hint.
  ///
  /// In en, this message translates to:
  /// **'Asked a question in class that deserved it.'**
  String get awardBadge_goodQuestion_hint;

  /// No description provided for @awardBadge_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Not given yet} other{Given {count}× so far}}'**
  String awardBadge_count(int count);

  /// No description provided for @awardBadge_cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get awardBadge_cancel;

  /// No description provided for @awardBadge_confirm.
  ///
  /// In en, this message translates to:
  /// **'Award'**
  String get awardBadge_confirm;

  /// No description provided for @awardBadge_done.
  ///
  /// In en, this message translates to:
  /// **'{badge} awarded ({count}×).'**
  String awardBadge_done(String badge, int count);

  /// No description provided for @awardBadge_failed.
  ///
  /// In en, this message translates to:
  /// **'The badge could not be awarded. Try again.'**
  String get awardBadge_failed;
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
