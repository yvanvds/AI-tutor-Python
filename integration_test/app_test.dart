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
// Run:
//   flutter test integration_test -d windows

import 'package:integration_test/integration_test.dart';

import 'flows/language_switch.dart' as language_switch;
import 'flows/lesson_flow.dart' as lesson_flow;
import 'flows/options_panel.dart' as options_panel;
import 'flows/playground_files.dart' as playground_files;
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
  turtle_run_notice.main();
  options_panel.main();
  update_prompt.main();
  update_failure.main();
  update_install.main();
  update_dev_build.main();
  update_manual_check.main();
}
