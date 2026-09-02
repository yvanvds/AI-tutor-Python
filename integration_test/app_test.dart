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

import 'flows/bug_report_oauth.dart' as bug_report_oauth;
import 'flows/editor_comment_space.dart' as editor_comment_space;
import 'flows/evidence_provenance.dart' as evidence_provenance;
import 'flows/goals_import_replace.dart' as goals_import_replace;
import 'flows/goals_row_highlight.dart' as goals_row_highlight;
import 'flows/instructions_row_highlight.dart' as instructions_row_highlight;
import 'flows/language_switch.dart' as language_switch;
import 'flows/lesson_flow.dart' as lesson_flow;
import 'flows/options_panel.dart' as options_panel;
import 'flows/playground_files.dart' as playground_files;
import 'flows/practice_complete_code.dart' as practice_complete_code;
import 'flows/quiz_ligatures.dart' as quiz_ligatures;
import 'flows/students_bulk_class.dart' as students_bulk_class;
import 'flows/students_class_filter.dart' as students_class_filter;
import 'flows/students_current_goal.dart' as students_current_goal;
import 'flows/students_progress_column.dart' as students_progress_column;
import 'flows/students_sort.dart' as students_sort;
import 'flows/students_sort_persist.dart' as students_sort_persist;
import 'flows/students_view_prefs_persist.dart' as students_view_prefs_persist;
import 'flows/turtle_run_notice.dart' as turtle_run_notice;
import 'flows/update_dev_build.dart' as update_dev_build;
import 'flows/update_failure.dart' as update_failure;
import 'flows/update_install.dart' as update_install;
import 'flows/update_manual_check.dart' as update_manual_check;
import 'flows/update_prompt.dart' as update_prompt;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  lesson_flow.main();
  language_switch.main();
  playground_files.main();
  editor_comment_space.main();
  practice_complete_code.main();
  evidence_provenance.main();
  quiz_ligatures.main();
  turtle_run_notice.main();
  options_panel.main();
  bug_report_oauth.main();
  goals_import_replace.main();
  students_class_filter.main();
  students_bulk_class.main();
  students_current_goal.main();
  students_progress_column.main();
  students_sort.main();
  students_sort_persist.main();
  students_view_prefs_persist.main();
  goals_row_highlight.main();
  instructions_row_highlight.main();
  update_prompt.main();
  update_failure.main();
  update_install.main();
  update_dev_build.main();
  update_manual_check.main();
}
