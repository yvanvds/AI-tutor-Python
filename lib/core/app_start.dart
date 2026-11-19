// Which mode the app starts in (#307, part of #261).
//
// Decided once, in `main()`, before the first frame:
//
//   1. a stored school file (the user imported it) → that school;
//   2. "without a school" chosen before → stand-alone;
//   3. the build's own school configuration → that school, as it has always
//      been — unless the user left that school in Options;
//   4. otherwise nothing is decided: the first-start choice asks. There is no
//      silent default, so a student who clicks too fast does not end up
//      practising on their own without noticing.
//
// The transitional release (#308, step 1): an install that runs on the
// build's school and has no school file gets one at start, written from the
// build's school configuration as if the student had imported it
// ([keepBuildSchoolAsFile]). The configuration is the same, so the student
// stays signed in and keeps every preference; once the build no longer
// carries a school (#308, step 3), the file decides.
//
// Switching mode — importing a school file, or leaving the school — only
// changes what the next start decides; the app asks for a restart. The two
// modes keep their own data (`AppMode.scopedPrefsKey`, `localDataDir`) and
// nothing here touches it, so nothing is ever merged or lost.

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Set once the user chose to go on without a school; kept with the
/// stand-alone mode's own preferences.
final String kStartWithoutSchoolPrefsKey = const StandaloneMode()
    .scopedPrefsKey('start_without_school_v1');

/// Set once the user left the school; the build's own school then no longer
/// applies, and the next start asks.
const String kLeftSchoolPrefsKey = 'school_left_v1';

/// The mode to start in, or `null` when the first-start choice has to ask.
/// [stored] is the imported school file ([SchoolFileStore.read]); [build] is
/// the build's own school ([SchoolConfig.fromBuild]).
AppMode? decideStartMode({
  required SchoolConfig? stored,
  required SchoolConfig? build,
  required SharedPreferences prefs,
}) {
  if (stored != null) return SchoolMode(stored);
  if (prefs.getBool(kStartWithoutSchoolPrefsKey) ?? false) {
    return const StandaloneMode();
  }
  if (build != null && !(prefs.getBool(kLeftSchoolPrefsKey) ?? false)) {
    return SchoolMode(build);
  }
  return null;
}

/// The transitional release (#308, step 1): when the start would use the
/// build's school ([build]) and no school file is kept, writes [build] to
/// [store] as the school file, as if the user had imported it. Returns the
/// school file to decide the start with: [stored], or the one just written.
///
/// Writes nothing when a school file exists (even one it cannot read: that
/// is never overwritten), when the build has no school, after "without a
/// school" or after leaving the school. A write that fails, or a file that
/// would not read back as exactly [build], is logged and left: the start
/// goes on with the build's school as before, and the next start tries again.
Future<SchoolConfig?> keepBuildSchoolAsFile({
  required SchoolConfig? stored,
  required SchoolConfig? build,
  required SharedPreferences prefs,
  required SchoolFileStore store,
}) async {
  if (stored != null || build == null) return stored;
  if (prefs.getBool(kStartWithoutSchoolPrefsKey) ?? false) return null;
  if (prefs.getBool(kLeftSchoolPrefsKey) ?? false) return null;
  try {
    if (await store.exists()) return null;
    final school = build.schoolName == null
        ? build.named(kBuildSchoolName)
        : build;
    // The file must give back this very configuration, or the next start
    // would differ from this one.
    if (parseSchoolFile(encodeSchoolFile(school)) != school) {
      debugPrint('keepBuildSchoolAsFile: the build school does not round-trip');
      return null;
    }
    await store.write(school);
    return school;
  } catch (e) {
    debugPrint('keepBuildSchoolAsFile: not written: $e');
    return null;
  }
}

/// The user goes on without a school: stand-alone, now and at every start
/// until they import a school file.
Future<void> chooseWithoutSchool(SharedPreferences prefs) =>
    prefs.setBool(kStartWithoutSchoolPrefsKey, true);

/// Reads, checks and stores a school file's [text]; the next start is in
/// that school's mode. Throws [SchoolFileException], and then changes
/// nothing.
Future<SchoolConfig> importSchoolFile(
  String text, {
  required SchoolFileStore store,
  required SharedPreferences prefs,
}) async {
  final config = parseSchoolFile(text);
  await store.write(config);
  await prefs.remove(kStartWithoutSchoolPrefsKey);
  return config;
}

/// Forgets the school: the next start asks again. The school's data stays
/// with the school, and the stand-alone data stays on the pc.
Future<void> leaveSchool({
  required SchoolFileStore store,
  required SharedPreferences prefs,
}) async {
  await store.delete();
  await prefs.remove(kStartWithoutSchoolPrefsKey);
  await prefs.setBool(kLeftSchoolPrefsKey, true);
}
