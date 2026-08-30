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
}
