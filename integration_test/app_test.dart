// Single entrypoint for every end-to-end flow (#28).
//
// Why one file: on Windows desktop, Flutter 3.44 can launch the app only
// for the *first* `*_test.dart` file of a `flutter test integration_test`
// invocation — every later file fails with "Unable to start the app on the
// device" before any test code runs (reproduced with two empty tests). So
// the flows live under `flows/` without the `_test` suffix and this file
// runs them all in one app process; each flow still runs on its own by
// path (`flutter test integration_test/flows/<flow>.dart -d windows`).
//
// That per-flow standalone property is load-bearing (#81): when the
// aggregated run dies in flutter_tools' own temp-file handling, CI
// (scripts/run_integration_tests.ps1) falls back to running every file
// under flows/ individually. Keep new flows self-contained.
//
// Run:
//   flutter test integration_test -d windows

import 'package:integration_test/integration_test.dart';

import 'flows/bug_report_file.dart' as bug_report_file;
import 'flows/bug_report_oauth.dart' as bug_report_oauth;
import 'flows/chat_collapse.dart' as chat_collapse;
import 'flows/chat_composer_growth.dart' as chat_composer_growth;
import 'flows/content_question.dart' as content_question;
import 'flows/cross_subgoal_signal.dart' as cross_subgoal_signal;
import 'flows/difficulty_asymmetry.dart' as difficulty_asymmetry;
import 'flows/difficulty_ratchet.dart' as difficulty_ratchet;
import 'flows/editor_comment_space.dart' as editor_comment_space;
import 'flows/editor_gutter_alignment.dart' as editor_gutter_alignment;
import 'flows/evidence_provenance.dart' as evidence_provenance;
import 'flows/exercise_history.dart' as exercise_history;
import 'flows/explain_paging.dart' as explain_paging;
import 'flows/explain_poll_steady.dart' as explain_poll_steady;
import 'flows/garbled_reply_retry.dart' as garbled_reply_retry;
import 'flows/goals_import_replace.dart' as goals_import_replace;
import 'flows/goals_row_highlight.dart' as goals_row_highlight;
import 'flows/grade_proposal.dart' as grade_proposal;
import 'flows/instructions_row_highlight.dart' as instructions_row_highlight;
import 'flows/language_switch.dart' as language_switch;
import 'flows/legacy_ratchet.dart' as legacy_ratchet;
import 'flows/level_up_gate.dart' as level_up_gate;
import 'flows/lesson_flow.dart' as lesson_flow;
import 'flows/my_reports_tab.dart' as my_reports_tab;
import 'flows/near_goal_recheck.dart' as near_goal_recheck;
import 'flows/options_panel.dart' as options_panel;
import 'flows/own_key.dart' as own_key;
import 'flows/playground_during_mcq.dart' as playground_during_mcq;
import 'flows/playground_files.dart' as playground_files;
import 'flows/practice_complete_code.dart' as practice_complete_code;
import 'flows/puntenformule_tab.dart' as puntenformule_tab;
import 'flows/quiz_ligatures.dart' as quiz_ligatures;
import 'flows/quiz_verdict_colors.dart' as quiz_verdict_colors;
import 'flows/sidebar_rail.dart' as sidebar_rail;
import 'flows/status_report_retry.dart' as status_report_retry;
import 'flows/stuck_advance_progress.dart' as stuck_advance_progress;
import 'flows/students_bulk_class.dart' as students_bulk_class;
import 'flows/students_class_filter.dart' as students_class_filter;
import 'flows/students_current_goal.dart' as students_current_goal;
import 'flows/students_progress_column.dart' as students_progress_column;
import 'flows/students_sort.dart' as students_sort;
import 'flows/students_sort_persist.dart' as students_sort_persist;
import 'flows/students_view_prefs_persist.dart' as students_view_prefs_persist;
import 'flows/transfer_credit.dart' as transfer_credit;
import 'flows/turtle_run_notice.dart' as turtle_run_notice;
import 'flows/tutor_language.dart' as tutor_language;
import 'flows/unconfirmed_recheck.dart' as unconfirmed_recheck;
import 'flows/update_check_failed_notice.dart' as update_check_failed_notice;
import 'flows/update_dev_build.dart' as update_dev_build;
import 'flows/update_failure.dart' as update_failure;
import 'flows/update_install.dart' as update_install;
import 'flows/update_manual_check.dart' as update_manual_check;
import 'flows/update_prompt.dart' as update_prompt;
import 'flows/update_proxy.dart' as update_proxy;
import 'flows/update_required.dart' as update_required;
import 'flows/update_tls_fallback.dart' as update_tls_fallback;
import 'flows/warm_up_review.dart' as warm_up_review;
import 'flows/whats_new_overlay.dart' as whats_new_overlay;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  lesson_flow.main();
  explain_paging.main();
  explain_poll_steady.main();
  chat_collapse.main();
  chat_composer_growth.main();
  content_question.main();
  language_switch.main();
  tutor_language.main();
  playground_files.main();
  editor_comment_space.main();
  editor_gutter_alignment.main();
  practice_complete_code.main();
  garbled_reply_retry.main();
  exercise_history.main();
  evidence_provenance.main();
  difficulty_ratchet.main();
  difficulty_asymmetry.main();
  legacy_ratchet.main();
  transfer_credit.main();
  cross_subgoal_signal.main();
  warm_up_review.main();
  near_goal_recheck.main();
  unconfirmed_recheck.main();
  quiz_ligatures.main();
  quiz_verdict_colors.main();
  playground_during_mcq.main();
  turtle_run_notice.main();
  puntenformule_tab.main();
  options_panel.main();
  own_key.main();
  status_report_retry.main();
  stuck_advance_progress.main();
  level_up_gate.main();
  bug_report_oauth.main();
  bug_report_file.main();
  goals_import_replace.main();
  students_class_filter.main();
  students_bulk_class.main();
  students_current_goal.main();
  students_progress_column.main();
  students_sort.main();
  students_sort_persist.main();
  students_view_prefs_persist.main();
  grade_proposal.main();
  my_reports_tab.main();
  sidebar_rail.main();
  goals_row_highlight.main();
  instructions_row_highlight.main();
  update_prompt.main();
  update_failure.main();
  update_install.main();
  update_dev_build.main();
  update_manual_check.main();
  update_check_failed_notice.main();
  update_tls_fallback.main();
  update_proxy.main();
  update_required.main();
  whats_new_overlay.main();
}
