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
  String get settings_language_label => 'Language';

  @override
  String get settings_language_system => 'System';

  @override
  String get settings_language_english => 'English';

  @override
  String get settings_language_dutch => 'Nederlands';

  @override
  String get sidebar_signOut_tooltip => 'Sign out';

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
  String get sidebar_section_options => 'Options';

  @override
  String get options_page_title => 'Options';

  @override
  String get options_page_subtitle => 'Settings, maintenance and bug reports.';

  @override
  String get options_language_title => 'Language';

  @override
  String get options_language_subtitle =>
      'Applies immediately; \"System\" follows the operating system.';

  @override
  String get options_theme_title => 'Appearance';

  @override
  String get options_theme_subtitle =>
      'Light or dark, stored on this device. \"System\" follows the operating system.';

  @override
  String get options_theme_system => 'Follow the system';

  @override
  String get options_theme_light => 'Light';

  @override
  String get options_theme_dark => 'Dark';

  @override
  String get options_model_title => 'AI model';

  @override
  String get options_model_subtitle =>
      'Which OpenAI model the tutor asks. Applies to this device only; a bigger model is slower and costs more.';

  @override
  String options_model_followGlobal(String model) {
    return 'School default ($model)';
  }

  @override
  String get options_progress_title => 'Progress';

  @override
  String get options_progress_subtitle =>
      'Clearing progress also clears the tutor\'s memory of what you know. It cannot be undone.';

  @override
  String get options_progress_resetAll_button => 'Reset all progress';

  @override
  String get options_progress_resetAll_dialog_title => 'Reset all progress?';

  @override
  String get options_progress_resetAll_dialog_message =>
      'This deletes all progress, learning history and tutor beliefs for your account, and resets the difficulty calibration to medium. This cannot be undone.';

  @override
  String get options_progress_resetAll_dialog_confirm => 'Reset everything';

  @override
  String get options_progress_resetAll_done => 'All progress has been reset.';

  @override
  String get options_progress_resetGoal_button => 'Reset one goal…';

  @override
  String get options_progress_resetGoal_dialog_title =>
      'Reset progress for a goal';

  @override
  String get options_progress_resetGoal_dialog_message =>
      'Pick a goal or subgoal. Resetting a goal resets all of its subgoals.';

  @override
  String get options_progress_resetGoal_dialog_empty =>
      'There are no goals yet.';

  @override
  String options_progress_resetGoal_dialog_loadError(String error) {
    return 'Could not load goals: $error';
  }

  @override
  String options_progress_resetGoal_confirm_title(String title) {
    return 'Reset \"$title\"?';
  }

  @override
  String get options_progress_resetGoal_confirm_message_subgoal =>
      'Progress, learning history and tutor beliefs for this subgoal will be deleted. This cannot be undone.';

  @override
  String get options_progress_resetGoal_confirm_message_root =>
      'Progress, learning history and tutor beliefs for every subgoal of this goal will be deleted. This cannot be undone.';

  @override
  String get options_progress_resetGoal_confirm_button => 'Reset';

  @override
  String options_progress_resetGoal_done(String title) {
    return 'Progress for \"$title\" has been reset.';
  }

  @override
  String options_progress_resetFailed(String error) {
    return 'Reset failed: $error';
  }

  @override
  String get options_dialog_cancel => 'Cancel';

  @override
  String get options_transfer_title => 'Export / import progress';

  @override
  String get options_transfer_subtitle =>
      'Save your learning history to a file, or load it into this account — useful when you switch to another account.';

  @override
  String get options_transfer_export_button => 'Export progress…';

  @override
  String get options_transfer_import_button => 'Import progress…';

  @override
  String options_transfer_exported(String path) {
    return 'Progress saved to $path';
  }

  @override
  String options_transfer_exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get options_transfer_import_dialog_title => 'Replace your progress?';

  @override
  String options_transfer_import_dialog_message(String file) {
    return 'Importing \"$file\" deletes the progress, learning history and tutor beliefs this account has now and replaces them with the contents of the file. This cannot be undone.';
  }

  @override
  String get options_transfer_import_dialog_confirm => 'Import and replace';

  @override
  String options_transfer_imported(int goals, int samples, int beliefs) {
    return 'Imported $goals goals, $samples history entries and $beliefs skill estimates.';
  }

  @override
  String options_transfer_importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get options_apiKey_title => 'OpenAI API key';

  @override
  String get options_apiKey_subtitle =>
      'Your own key, stored on this device. Removing it takes you back to the key screen.';

  @override
  String get options_apiKey_status_present => 'A key is stored on this device.';

  @override
  String get options_apiKey_status_missing => 'No key stored on this device.';

  @override
  String get options_apiKey_change_button => 'Change key';

  @override
  String get options_apiKey_remove_button => 'Remove key';

  @override
  String get options_apiKey_dialog_title => 'Change API key';

  @override
  String get options_apiKey_dialog_field => 'New API key';

  @override
  String get options_apiKey_dialog_save => 'Save';

  @override
  String get options_apiKey_saved => 'API key updated.';

  @override
  String get options_apiKey_remove_dialog_title => 'Remove API key?';

  @override
  String get options_apiKey_remove_dialog_message =>
      'The tutor cannot answer without a key. You will be asked for a new key right away.';

  @override
  String get options_apiKey_remove_dialog_confirm => 'Remove';

  @override
  String get options_apiKey_removed => 'API key removed.';

  @override
  String get options_bugReport_title => 'Bug reports';

  @override
  String get options_bugReport_subtitle =>
      'Post an issue on GitHub straight from the app, with the debug data of a recent tutor turn attached.';

  @override
  String get options_bugReport_github_notConnected =>
      'Not connected to GitHub.';

  @override
  String options_bugReport_github_connectedAs(String login) {
    return 'Connected to GitHub as $login.';
  }

  @override
  String get options_bugReport_github_connect_button => 'Connect GitHub';

  @override
  String get options_bugReport_github_disconnect_button => 'Disconnect';

  @override
  String get options_bugReport_github_dialog_title => 'Connect GitHub';

  @override
  String options_bugReport_github_dialog_explainer(String repo) {
    return 'Paste a personal access token with permission to create issues on $repo. The token is stored on this device only.';
  }

  @override
  String get options_bugReport_github_dialog_field => 'Personal access token';

  @override
  String get options_bugReport_github_dialog_connect => 'Connect';

  @override
  String options_bugReport_github_connectFailed(String error) {
    return 'Could not connect: $error';
  }

  @override
  String get options_bugReport_report_button => 'Report a bug…';

  @override
  String get options_bugReport_dialog_title => 'Report a bug';

  @override
  String get options_bugReport_dialog_titleField => 'Title';

  @override
  String get options_bugReport_dialog_titleRequired => 'Please enter a title.';

  @override
  String get options_bugReport_dialog_descriptionField => 'What went wrong?';

  @override
  String get options_bugReport_dialog_turnField => 'Attach tutor turn';

  @override
  String get options_bugReport_dialog_turnNone => 'No turn';

  @override
  String options_bugReport_dialog_turnLabel(int id, String type) {
    return '#$id $type';
  }

  @override
  String get options_bugReport_dialog_submit => 'Post issue';

  @override
  String options_bugReport_posted(String url) {
    return 'Issue posted: $url';
  }

  @override
  String options_bugReport_postFailed(String error) {
    return 'Posting failed: $error';
  }

  @override
  String get options_developer_title => 'Developer tools';

  @override
  String get options_developer_subtitle => 'Only visible in developer builds.';

  @override
  String get options_developer_levelUp_button => 'Show level-up overlay';

  @override
  String get options_developer_triggerQuestion_title => 'Trigger question';

  @override
  String get options_developer_difficulty_label => 'Difficulty:';

  @override
  String get options_developer_recentTurns_title => 'Recent turns';

  @override
  String get options_developer_recentTurns_copyAll => 'Copy all';

  @override
  String options_developer_recentTurns_copied(int count) {
    return 'Copied $count turns to clipboard.';
  }

  @override
  String get options_developer_recentTurns_empty => 'No turns recorded yet.';

  @override
  String options_developer_turnDetail_title(int id) {
    return 'Turn #$id';
  }

  @override
  String get options_developer_turnDetail_close => 'Close';

  @override
  String get options_about_title => 'About';

  @override
  String options_about_version(String version) {
    return 'Version $version';
  }

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
  String get update_status_idle => 'No update check has run yet.';

  @override
  String get update_status_checking => 'Checking for updates…';

  @override
  String get update_status_upToDate => 'You have the newest version.';

  @override
  String update_status_available(String version) {
    return 'Version $version is available.';
  }

  @override
  String update_status_downloading(String version) {
    return 'Downloading version $version…';
  }

  @override
  String update_status_applying(String version) {
    return 'Starting the installer. The app closes itself and comes back as version $version.';
  }

  @override
  String update_status_failed(String reason) {
    return 'The update did not succeed: $reason';
  }

  @override
  String get update_action_apply => 'Update';

  @override
  String update_action_applyVersion(String version) {
    return 'Update to $version';
  }

  @override
  String get update_action_later => 'Later';

  @override
  String get update_action_check => 'Check for updates';

  @override
  String get session_explain_placeholder_noSubgoal =>
      'Pick a subgoal in the learning path to see the explanation.';

  @override
  String get session_explain_loading => 'Loading lesson…';

  @override
  String get session_explain_missingContent =>
      'No lesson content available for this subgoal yet.';

  @override
  String get session_explain_defaultPillLabel => 'Concept';

  @override
  String get session_explain_prev_button => 'Previous';

  @override
  String get session_explain_completeXp => '+10 XP on completion';

  @override
  String get session_explain_tryItYourself => 'Try it yourself';

  @override
  String get session_playground_pill => 'playground';

  @override
  String get session_playground_subtitle => 'No goal — just you and Python.';

  @override
  String get session_playground_open_button => 'Open';

  @override
  String get session_playground_open_tooltip => 'Open saved code';

  @override
  String get session_playground_save_button => 'Save';

  @override
  String get session_playground_save_tooltip => 'Save this code';

  @override
  String get session_playground_dialog_cancel => 'Cancel';

  @override
  String get session_playground_saveDialog_title => 'Save code';

  @override
  String get session_playground_saveDialog_nameLabel => 'File name';

  @override
  String get session_playground_saveDialog_invalidName =>
      'Use letters, digits, spaces, - or _ (max 60 characters).';

  @override
  String get session_playground_saveDialog_confirm => 'Save';

  @override
  String session_playground_overwriteDialog_title(String name) {
    return 'Overwrite \"$name\"?';
  }

  @override
  String get session_playground_overwriteDialog_message =>
      'A file with this name already exists.';

  @override
  String get session_playground_overwriteDialog_confirm => 'Overwrite';

  @override
  String get session_playground_openDialog_title => 'Open saved code';

  @override
  String get session_playground_openDialog_empty => 'No saved files yet.';

  @override
  String get session_playground_openDialog_delete_tooltip => 'Delete';

  @override
  String session_playground_openDialog_conflict(String names) {
    return 'Also changed on another computer. This computer\'s version was kept separately as: $names';
  }

  @override
  String session_playground_deleteDialog_title(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get session_playground_deleteDialog_message =>
      'This cannot be undone.';

  @override
  String get session_playground_deleteDialog_confirm => 'Delete';

  @override
  String get session_playground_discardDialog_title => 'Replace current code?';

  @override
  String get session_playground_discardDialog_message =>
      'Your unsaved changes will be lost.';

  @override
  String get session_playground_discardDialog_confirm => 'Replace';

  @override
  String session_playground_snack_saved(String name) {
    return 'Saved as \"$name\".';
  }

  @override
  String session_playground_snack_saveFailed(String error) {
    return 'Saving failed: $error';
  }

  @override
  String session_playground_snack_openFailed(String error) {
    return 'Opening failed: $error';
  }

  @override
  String session_playground_snack_tooLarge(int max) {
    return 'This code is too large to save (over $max KB).';
  }

  @override
  String session_playground_snack_tooManyFiles(int max) {
    return 'You already have $max saved files, which is the maximum. Delete one first.';
  }

  @override
  String get session_quiz_pill => 'Quiz question';

  @override
  String get session_quiz_next_button => 'Next →';

  @override
  String get session_output_state_idle => 'No output';

  @override
  String get session_output_state_running => 'Running…';

  @override
  String get session_output_state_ok => 'Done';

  @override
  String session_output_state_error_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count errors',
      one: '1 error',
    );
    return '$_temp0';
  }

  @override
  String get session_output_header_label => 'Output';

  @override
  String get session_output_emptyState_runHint =>
      'Press Run to execute your code.';

  @override
  String get session_output_meta_turtleWindow =>
      'A turtle window is open. Close it, or press Stop, to finish the run.';

  @override
  String get session_output_meta_stopped => 'Stopped.';

  @override
  String get session_runControls_tooltip_resetOutput => 'Reset output';

  @override
  String get session_runControls_tooltip_askHint => 'Ask for a hint';

  @override
  String get session_runControls_tooltip_sendToTutor => 'Send to tutor';

  @override
  String get session_runControls_chatMessage_needHint => 'I need a hint.';

  @override
  String get session_runControls_chatMessage_hereIsCode => 'Here is my code.';

  @override
  String get session_runControls_button_run => 'Run';

  @override
  String get session_runControls_button_stop => 'Stop';

  @override
  String get session_objectiveBanner_pill => 'Current goal';

  @override
  String get chat_tutorName => 'Tutor';

  @override
  String get chat_userName_you => 'You';

  @override
  String get chat_loading_thinking => 'Tutor is thinking…';

  @override
  String get chat_header_presence_online => 'online';

  @override
  String get chat_header_presence_helpsWith => ' · helping you with ';

  @override
  String get chat_header_restart_tooltip => 'Restart session';

  @override
  String get chat_composer_idle_hint => 'Type your question or answer…';

  @override
  String get chat_composer_idle_kbd_send => 'send';

  @override
  String get chat_composer_idle_kbd_newline => 'new line';

  @override
  String get chat_composer_idle_tip_prefix => 'tip: type ';

  @override
  String get chat_composer_idle_tip_suffix => ' for a hint';

  @override
  String get chat_composer_idle_hintMessage => 'I need a hint';

  @override
  String get chat_composer_thinking_label => 'Tutor is thinking…';

  @override
  String get chat_composer_continue_prompt => 'Ready for the next part?';

  @override
  String get chat_composer_continue_button => 'Continue';

  @override
  String get chat_composer_mcqDisabled_label => 'Tap an answer above';

  @override
  String get goals_header_title => 'Goals';

  @override
  String get goals_action_export => 'Export goals';

  @override
  String get goals_action_import => 'Import goals';

  @override
  String get goals_snack_noGoalsToExport => 'No goals to export';

  @override
  String goals_snack_exportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String goals_snack_exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get goals_snack_fileEmpty => 'File contained no goals';

  @override
  String goals_snack_addAborted(int count, String sample) {
    return 'Add aborted: $count id(s) already exist (e.g. $sample). Use Replace, or remove the duplicates first.';
  }

  @override
  String goals_snack_imported(int count) {
    return 'Imported $count goal(s)';
  }

  @override
  String goals_snack_importedWithRemoved(int count, int removed) {
    return 'Imported $count goal(s) (removed $removed not in file)';
  }

  @override
  String goals_snack_importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get goals_snack_couldNotRead => 'Could not read selected file';

  @override
  String get goals_snack_invalidFile => 'Invalid goals file';

  @override
  String get goals_import_dialog_title => 'Import goals';

  @override
  String goals_import_dialog_message(int rootCount, int total) {
    return 'The file contains $rootCount root goal(s) and $total total node(s).\n\n• Add: append using the ids from the file. Aborts if any id already exists.\n• Replace: upsert by id (keeps existing lesson content links) and remove any goals not in the file.';
  }

  @override
  String get goals_import_action_cancel => 'Cancel';

  @override
  String get goals_import_action_add => 'Add';

  @override
  String get goals_import_action_replace => 'Replace';

  @override
  String get goals_import_filePicker_title => 'Select goals JSON to import';

  @override
  String get goals_editor_title => 'Edit goal';

  @override
  String get goals_editor_tooltip_delete => 'Delete';

  @override
  String get goals_editor_tooltip_close => 'Close';

  @override
  String get goals_editor_field_title => 'Title';

  @override
  String get goals_editor_untitled => 'Untitled';

  @override
  String get goals_editor_field_description =>
      'Describe this goal for students.';

  @override
  String get goals_editor_switch_optional => 'Optional';

  @override
  String get goals_editor_switch_concept => 'Concept goal';

  @override
  String get goals_editor_switch_concept_subtitle =>
      'Mastering this subgoal triggers the level-up overlay.';

  @override
  String get goals_editor_teachingTips_label => 'Teaching tips';

  @override
  String get goals_editor_teachingTips_hint =>
      'Type a teaching tip and hit Enter';

  @override
  String get goals_editor_teachingTips_empty => 'No teaching tips yet.';

  @override
  String get goals_editor_teachingTips_add => 'Add';

  @override
  String get goals_editor_teachingTips_edit => 'Edit tip';

  @override
  String get goals_editor_teachingTips_delete => 'Delete tip';

  @override
  String get goals_editor_teachingTips_save => 'Save';

  @override
  String get goals_editor_teachingTips_cancel => 'Cancel';

  @override
  String get goals_editor_lesinhoud_label => 'Lesson content';

  @override
  String get goals_editor_lesinhoud_linked => 'Lesson content linked';

  @override
  String get goals_editor_lesinhoud_none => '(no lesson content)';

  @override
  String get goals_editor_lesinhoud_edit => 'Edit';

  @override
  String get goals_editor_lesinhoud_create => 'Create';

  @override
  String get goals_editor_delete_dialog_title => 'Delete goal';

  @override
  String goals_editor_delete_dialog_message_single(String title) {
    return 'Delete \"$title\"?';
  }

  @override
  String goals_editor_delete_dialog_message_withDescendants(
    String title,
    int count,
  ) {
    return 'Delete \"$title\" and its $count descendant(s)?';
  }

  @override
  String get goals_editor_delete_action_cancel => 'Cancel';

  @override
  String get goals_editor_delete_action_confirm => 'Delete';

  @override
  String goals_editor_deleted_single(String title) {
    return 'Deleted \"$title\".';
  }

  @override
  String goals_editor_deleted_withDescendants(String title, int count) {
    return 'Deleted \"$title\" (+$count).';
  }

  @override
  String goals_pane_error(String error) {
    return 'Error: $error';
  }

  @override
  String get goals_pane_noData => 'No data';

  @override
  String goals_pane_reordered(String title) {
    return 'Reordered \"$title\".';
  }

  @override
  String get goals_childPane_empty_pickRoot =>
      'Select a root goal to see its children.';

  @override
  String get goals_childPane_addHint => 'Add child goal… (Enter)';

  @override
  String get goals_childPane_empty_addOne => 'No children yet. Add one above.';

  @override
  String get goals_rootPane_addHint => 'Add root goal… (Enter)';

  @override
  String get goals_rootPane_empty_addOne => 'No goals yet. Add one above.';

  @override
  String get goals_parentField_label => 'Parent';

  @override
  String get goals_parentField_noParent => '(no parent)';

  @override
  String goals_parentField_loadFailed(String error) {
    return 'Failed to load parents: $error';
  }

  @override
  String goals_editorPanel_loadError(String error) {
    return 'Error loading documents: $error';
  }

  @override
  String get goals_editorPanel_noGoalSelected => 'No goal selected.';

  @override
  String get lesson_toolbar_title => 'Lesson content';

  @override
  String get lesson_toolbar_upload => 'Upload .html';

  @override
  String get lesson_toolbar_save => 'Save';

  @override
  String get lesson_toolbar_save_dirty => 'Save *';

  @override
  String get lesson_snack_saved => 'Saved';

  @override
  String get lesson_snack_couldNotRead => 'Could not read file.';

  @override
  String lesson_loadError(String error) {
    return 'Load failed: $error';
  }

  @override
  String get lesson_unlink_dialog_title => 'Unlink lesson content?';

  @override
  String get lesson_unlink_dialog_message =>
      'The content document stays in place, but this subgoal will no longer point to it.';

  @override
  String get lesson_unlink_dialog_cancel => 'Cancel';

  @override
  String get lesson_unlink_dialog_confirm => 'Unlink';

  @override
  String get lesson_editor_empty_pickSubgoal =>
      'Pick a subgoal to edit its lesson content.';

  @override
  String get lesson_editor_field_title => 'Title';

  @override
  String get lesson_editor_button_unlink => 'Unlink';

  @override
  String get lesson_preview_empty =>
      'The preview appears here as soon as you add HTML.';

  @override
  String get lesson_subgoal_noContent => '(no lesson content)';

  @override
  String get lesson_default_moduleTitle => 'Python basics';

  @override
  String get lesson_orphans_header => 'Orphaned lesson content';

  @override
  String get lesson_orphans_hint =>
      'Not linked to any subgoal. Click to reassign.';

  @override
  String get lesson_reassign_dialog_title => 'Reassign lesson content';

  @override
  String lesson_reassign_dialog_message(String title) {
    return 'Pick the subgoal that \"$title\" belongs to.';
  }

  @override
  String get lesson_reassign_dialog_cancel => 'Cancel';

  @override
  String get lesson_reassign_dialog_noSubgoals =>
      'There are no subgoals to assign to.';

  @override
  String get lesson_reassign_overwrite_title =>
      'Replace existing lesson content?';

  @override
  String lesson_reassign_overwrite_message(String target, String title) {
    return '\"$target\" already has lesson content. It will be replaced by \"$title\".';
  }

  @override
  String get lesson_reassign_overwrite_cancel => 'Cancel';

  @override
  String get lesson_reassign_overwrite_confirm => 'Replace';

  @override
  String lesson_snack_reassigned(String target) {
    return 'Lesson content linked to \"$target\".';
  }

  @override
  String get lesson_run_output_label => 'Output';

  @override
  String get lesson_run_button => 'Run';

  @override
  String get lesson_run_running => 'Running…';

  @override
  String get lesson_run_unavailable =>
      'The example can only run inside the app.';

  @override
  String get instructions_toolbar_title => 'Instructions';

  @override
  String get instructions_toolbar_tooltip_new => 'New document';

  @override
  String get instructions_toolbar_tooltip_delete => 'Delete document';

  @override
  String get instructions_toolbar_tooltip_export => 'Export all to Markdown';

  @override
  String get instructions_toolbar_tooltip_import => 'Import from Markdown';

  @override
  String get instructions_toolbar_save => 'Save';

  @override
  String get instructions_toolbar_save_dirty => 'Save *';

  @override
  String get instructions_dialog_common_cancel => 'Cancel';

  @override
  String get instructions_dialog_common_ok => 'OK';

  @override
  String get instructions_dialog_common_delete => 'Delete';

  @override
  String get instructions_dialog_common_add => 'Add';

  @override
  String get instructions_dialog_common_replace => 'Replace';

  @override
  String get instructions_dialog_newDoc_title => 'New document';

  @override
  String get instructions_dialog_newDoc_label =>
      'Document id (e.g. system_prompt)';

  @override
  String get instructions_dialog_renameDoc_title => 'Rename document';

  @override
  String get instructions_dialog_renameDoc_label => 'New document id';

  @override
  String get instructions_dialog_renameSection_title => 'Rename section';

  @override
  String get instructions_dialog_renameSection_label => 'New section key';

  @override
  String get instructions_dialog_addSection_title => 'Add section';

  @override
  String get instructions_dialog_addSection_label =>
      'Section key (e.g. current_context)';

  @override
  String instructions_confirm_deleteDoc_title(String id) {
    return 'Delete \"$id\"?';
  }

  @override
  String get instructions_confirm_deleteDoc_body =>
      'This will permanently delete the document.';

  @override
  String instructions_confirm_deleteSection_title(String key) {
    return 'Delete \"$key\"?';
  }

  @override
  String get instructions_confirm_deleteSection_body =>
      'This removes the section from the document.';

  @override
  String get instructions_import_dialog_title => 'Import instructions';

  @override
  String instructions_import_dialog_message(int docCount) {
    return 'The file contains $docCount document(s).\n\n• Add: only insert sections that don\'t already exist; keep current values.\n• Replace: overwrite each imported document\'s sections with the file\'s contents. Documents not in the file are left alone.';
  }

  @override
  String get instructions_filePicker_title => 'Select Markdown file to import';

  @override
  String get instructions_snack_documentDeleted => 'Document deleted';

  @override
  String get instructions_snack_saved => 'Saved';

  @override
  String instructions_snack_sectionExists(String key) {
    return 'Section \"$key\" already exists';
  }

  @override
  String instructions_snack_sectionExistsRename(String key) {
    return 'A section named \"$key\" already exists';
  }

  @override
  String instructions_snack_renamed(String target) {
    return 'Renamed to \"$target\"';
  }

  @override
  String get instructions_snack_noDocsToExport => 'No documents to export';

  @override
  String instructions_snack_exportedTo(String path) {
    return 'Exported to $path';
  }

  @override
  String instructions_snack_exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get instructions_snack_noDocsInFile => 'No documents found in file';

  @override
  String instructions_snack_importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get instructions_snack_couldNotRead => 'Could not read selected file';

  @override
  String get instructions_snack_replace_nothing =>
      'Nothing changed (file matched existing content)';

  @override
  String get instructions_snack_add_nothing =>
      'Nothing imported (all sections already exist)';

  @override
  String instructions_snack_imported_prefix(int count) {
    return 'Imported $count section(s)';
  }

  @override
  String instructions_snack_stats_newDocs(int count) {
    return '$count new doc(s)';
  }

  @override
  String instructions_snack_stats_updated(int count) {
    return '$count updated';
  }

  @override
  String instructions_snack_stats_replaced(int count) {
    return '$count replaced';
  }

  @override
  String instructions_snack_stats_addedSections(int count) {
    return '$count added section(s)';
  }

  @override
  String instructions_snack_stats_replacedSections(int count) {
    return '$count replaced section(s)';
  }

  @override
  String instructions_body_loadError(String error) {
    return 'Error loading documents: $error';
  }

  @override
  String get instructions_sectionsList_add => 'Add section';

  @override
  String get instructions_sectionsList_delete => 'Delete';

  @override
  String get instructions_docList_header => 'Documents';

  @override
  String get instructions_docHeader_noDoc => 'No document selected';

  @override
  String get instructions_docHeader_renameTooltip => 'Rename document';

  @override
  String get instructions_sectionHeader_noSection => 'No section selected';

  @override
  String get instructions_sectionHeader_renameTooltip => 'Rename section';

  @override
  String get accounts_page_title => 'Students';

  @override
  String get accounts_page_subtitle =>
      'Manage accounts and follow your students\' progress.';

  @override
  String accounts_loadError(String error) {
    return 'Error loading accounts:\n$error';
  }

  @override
  String get accounts_search_hint => 'Search by name or email…';

  @override
  String accounts_pageSize_label(int n) {
    return '$n / page';
  }

  @override
  String get accounts_column_email => 'EMAIL';

  @override
  String get accounts_column_name => 'NAME';

  @override
  String get accounts_column_streak => 'STREAK';

  @override
  String get accounts_column_currentGoal => 'CURRENT GOAL';

  @override
  String get accounts_column_progress => 'PROGRESS';

  @override
  String get accounts_column_status => 'STATUS';

  @override
  String get accounts_column_key => 'KEY';

  @override
  String get accounts_column_actions => 'ACTIONS';

  @override
  String accounts_email_lastActive(String ts) {
    return 'last active: $ts';
  }

  @override
  String get accounts_tooltip_deleteAccount => 'Delete account';

  @override
  String get accounts_tooltip_firstPage => 'First page';

  @override
  String get accounts_tooltip_previousPage => 'Previous page';

  @override
  String get accounts_tooltip_nextPage => 'Next page';

  @override
  String get accounts_tooltip_lastPage => 'Last page';

  @override
  String accounts_pagination_showing(int start, int end, int total) {
    return 'Showing $start–$end of $total';
  }

  @override
  String accounts_pagination_pageOf(int page, int total) {
    return 'Page $page / $total';
  }

  @override
  String get accounts_delete_dialog_title => 'Delete account';

  @override
  String accounts_delete_dialog_message(String email) {
    return 'This will delete the account profile for:\n\n$email\n\nThis does NOT remove the user from the school account directory. Continue?';
  }

  @override
  String get accounts_delete_dialog_cancel => 'Cancel';

  @override
  String get accounts_delete_dialog_confirm => 'Delete';

  @override
  String accounts_delete_success(String email) {
    return 'Deleted account: $email';
  }

  @override
  String accounts_delete_failed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get accounts_status_tooltip_active => 'Made progress recently.';

  @override
  String get accounts_status_tooltip_idle => 'No progress in the last 7 days.';

  @override
  String get accounts_badge_unackTooltip => 'Unacknowledged signal events';

  @override
  String get drawer_close_tooltip => 'Close';

  @override
  String get drawer_section_goals => 'Goals';

  @override
  String drawer_statusSummary_active_with_goal(String title) {
    return 'Recently active on \"$title\".';
  }

  @override
  String get drawer_statusSummary_active_noGoal => 'Recently active.';

  @override
  String get drawer_statusSummary_idle => 'No recent activity.';

  @override
  String get drawer_signals_title => 'Signal events';

  @override
  String get drawer_signals_button_busy => 'Working…';

  @override
  String drawer_signals_button_acknowledge(int count) {
    return 'Acknowledge ($count)';
  }

  @override
  String get drawer_signals_empty => 'No events';

  @override
  String drawer_signals_ackFailed(String error) {
    return 'Acknowledge failed: $error';
  }

  @override
  String get drawer_signals_kind_stuckLoAdvance => 'Stuck LO at transition';

  @override
  String get drawer_signals_kind_singleLoDeadlock => 'Single-LO impasse';

  @override
  String get drawer_signals_kind_repeatedDemotions => 'Repeated demotion';

  @override
  String get drawer_signals_kind_sustainedLlmFailure => 'Sustained LLM failure';

  @override
  String get drawer_signals_kind_cascadeHalt => 'Cascade halt (audit)';

  @override
  String get drawer_signals_kind_emptyObjectivesBlock =>
      'Subgoal without LOs (audit)';

  @override
  String get drawer_signals_kind_subgoalDeletedRedirect =>
      'Subgoal deleted (audit)';

  @override
  String get drawer_statusReports_title => 'Status reports';

  @override
  String get drawer_statusReports_loadError => 'Could not load status reports.';

  @override
  String get drawer_statusReports_empty => 'No status reports yet.';

  @override
  String get drawer_history_title => 'Progress over time';

  @override
  String get drawer_history_loadError => 'Could not load history.';

  @override
  String get drawer_history_empty => 'No history yet.';

  @override
  String get drawer_history_card_empty => 'No history yet';

  @override
  String get drawer_history_legend_average => 'average';

  @override
  String get progress_loadError => 'Could not load goals.';

  @override
  String get progress_empty => 'No goals available yet.';

  @override
  String get leerpad_header_title => 'Learning path';

  @override
  String get leerpad_header_subtitle_default => 'Python — beginner\'s journey';

  @override
  String get leerpad_card_completed => 'completed';

  @override
  String get leerpad_card_button_continue => 'Continue';

  @override
  String get goalTile_button_faster => 'Go faster';

  @override
  String get goalTile_button_workOn => 'Work on this';

  @override
  String get common_undo => 'Undo';

  @override
  String get crash_permissionDenied => 'Permission denied while reading data.';

  @override
  String get auth_browser_signedIn_title => 'Signed in';

  @override
  String get auth_browser_signedIn_body =>
      'You can close this tab and return to the app.';

  @override
  String get auth_browser_failed_title => 'Sign-in failed';

  @override
  String get auth_browser_failed_noCode => 'No authorization code returned.';

  @override
  String get auth_browser_failed_stateMismatch =>
      'State mismatch — possible CSRF, please try again.';

  @override
  String levelUp_caption(int xp) {
    return '+$xp XP · CONCEPT UNLOCKED';
  }

  @override
  String levelUp_level(int level) {
    return 'Level $level';
  }

  @override
  String get levelUp_subtitle_generic => 'You\'ve mastered the next concept.';

  @override
  String levelUp_subtitle_concept(String concept) {
    return 'You\'ve mastered $concept.';
  }

  @override
  String get levelUp_button_continue => 'Keep learning';

  @override
  String get splash_title => 'Goal reached!';

  @override
  String get splash_phrase_01 =>
      'LEGENDARY! Your code will be sung about for centuries!';

  @override
  String get splash_phrase_02 => 'Wow! Even your keyboard is applauding you!';

  @override
  String get splash_phrase_03 => 'Watch out, the AI is getting jealous of you!';

  @override
  String get splash_phrase_04 =>
      'You just moved the god of computer science to tears.';

  @override
  String get splash_phrase_05 => 'BAM! One more victory for the Hall of Fame!';

  @override
  String get splash_phrase_06 =>
      'Your keys are smoking — that\'s how fast you program!';

  @override
  String get splash_phrase_07 =>
      'Brilliant! Even Stack Overflow is speechless.';

  @override
  String get splash_phrase_08 => 'The bug police lost today!';

  @override
  String get splash_phrase_09 =>
      'What a masterpiece! Rembrandt, but in Python.';

  @override
  String get splash_phrase_10 =>
      'You just improved the internet. You\'re welcome!';

  @override
  String get splash_phrase_11 =>
      'The government is calling: they want to buy your algorithm.';

  @override
  String get splash_phrase_12 =>
      'Applause! The bits and bytes are giving you a standing ovation!';

  @override
  String get splash_phrase_13 =>
      'The compiler is smiling. That rarely happens.';

  @override
  String get splash_phrase_14 =>
      'Your code is so clean you can see right through it.';

  @override
  String get splash_phrase_15 =>
      'The matrix has noticed you… and nods approvingly.';

  @override
  String get splash_phrase_16 => 'The mouse whispers: \'I am not worthy\'.';

  @override
  String get splash_phrase_17 => 'Even your laptop wants your autograph now.';

  @override
  String get splash_phrase_18 => 'A new record! The pixels are cheering!';

  @override
  String get splash_phrase_19 =>
      'You have exceeded the limits of human understanding.';

  @override
  String get splash_phrase_20 => 'Mathematicians are weeping with emotion.';

  @override
  String get splash_phrase_21 =>
      'Python itself whispers: \'thank you, master\'.';

  @override
  String get splash_phrase_22 => 'This is no longer success. This is folklore.';

  @override
  String get splash_phrase_23 =>
      'NASA is calling: \'can you come debug for us?\'';

  @override
  String get splash_phrase_24 =>
      'The AI tutor has decided that you will tutor it from now on.';

  @override
  String get splash_phrase_25 =>
      'Stop! You\'re too good. Give the others a chance.';

  @override
  String get chat_role_explanation => 'explanation';

  @override
  String get chat_role_example => 'example';

  @override
  String get chat_role_question => 'think about it';

  @override
  String get chat_role_correct => 'correct';

  @override
  String get session_writeCode_template => '# Write your code here';

  @override
  String get difficulty_easy => 'easy';

  @override
  String get difficulty_medium => 'medium';

  @override
  String get difficulty_hard => 'hard';

  @override
  String chat_notice_tutorFailed(String detail) {
    return 'Something went wrong with the tutor: $detail';
  }

  @override
  String chat_notice_sessionStartFailed(String detail) {
    return 'The session could not start: $detail';
  }

  @override
  String get chat_notice_databaseUnavailable =>
      'The connection to the database dropped for a moment. Try again shortly.';

  @override
  String get chat_notice_tutorTimeout => 'The tutor did not respond in time.';

  @override
  String get chat_notice_tutorUnreachable => 'No connection to the tutor.';

  @override
  String get chat_notice_replyTruncated => 'The tutor\'s reply was cut off.';

  @override
  String get chat_notice_noPreviousRequest => 'No previous request to retry.';

  @override
  String get chat_notice_emptyResponse => 'Empty response from the tutor.';

  @override
  String chat_notice_unparseableResponse(String raw) {
    return 'Could not process the response: $raw';
  }

  @override
  String chat_notice_unknownResponseType(String type) {
    return 'Unknown response type: $type';
  }

  @override
  String get chat_notice_unknownResponse => 'Received an unknown response.';

  @override
  String get chat_notice_subgoalDeletedRedirect =>
      'Your previous topic was removed by your teacher. Continuing with the next one.';

  @override
  String get chat_notice_subgoalSaturated =>
      'You already have a good grip on this subgoal. Ready to move on?';

  @override
  String get chat_notice_noGoalsLeft =>
      'There are no goals left to work on. Congratulations!';

  @override
  String get chat_notice_emptyObjectives =>
      'This subgoal isn\'t quite finished yet — ask your teacher to complete it, or pick another subgoal.';

  @override
  String get chat_notice_preparingExercise => 'Preparing your next exercise...';

  @override
  String get chat_notice_feedbackDegraded =>
      'Something is wrong with the feedback. Try again in a few minutes.';

  @override
  String chat_notice_newGoalSelected(String title) {
    return 'New goal selected: $title';
  }

  @override
  String chat_notice_difficultyChanged(String from, String to) {
    return 'Difficulty adjusted: $from -> $to';
  }

  @override
  String get chat_notice_submitViaEditor =>
      'Adjust your code in the editor on the left and press Run to submit your solution.';
}
