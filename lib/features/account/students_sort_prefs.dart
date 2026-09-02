// Persistence for the Students table sort choice (#92).
//
// The chosen column + direction (#87) live in `_AccountsPageState`, so they
// died with the page: navigating away or restarting the app fell back to
// storage order. Stored per device in SharedPreferences, next to the theme
// and locale overrides — which table order a teacher prefers is a property
// of the person at the machine, not of the shared account docs.
//
// What is stored is the [StudentsSortKey] *name*, never the raw
// `DataColumn` index: #91 already shifted every index by one when the
// select column appeared, and a stored index would have silently pointed
// the restored sort at the wrong column. An enum name survives column
// reordering, and an unrecognized one (a key renamed or removed in a later
// version) decodes to null — storage order — instead of misfiring.

import 'package:ai_tutor_python/features/account/students_sort.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kSortKeyPref = 'students_sort_key';
const String _kSortAscendingPref = 'students_sort_ascending';

/// A persisted sort choice: which key, and which direction.
typedef StudentsSortChoice = ({StudentsSortKey key, bool ascending});

/// Pure decode half of [loadStudentsSortChoice], split out for unit tests:
/// maps a stored enum name back onto its key. Null / unrecognized names —
/// nothing stored yet, or a key from a newer/older app version — mean
/// "no stored choice", never a guess at a different column.
StudentsSortChoice? decodeStudentsSortChoice(String? rawKey, bool? ascending) {
  if (rawKey == null) return null;
  for (final key in StudentsSortKey.values) {
    if (key.name == rawKey) return (key: key, ascending: ascending ?? true);
  }
  return null;
}

/// The sort choice stored on this device, or null for storage order.
Future<StudentsSortChoice?> loadStudentsSortChoice() async {
  final prefs = await SharedPreferences.getInstance();
  return decodeStudentsSortChoice(
    prefs.getString(_kSortKeyPref),
    prefs.getBool(_kSortAscendingPref),
  );
}

/// Stores [choice], or clears the stored one when it is null.
Future<void> saveStudentsSortChoice(StudentsSortChoice? choice) async {
  final prefs = await SharedPreferences.getInstance();
  if (choice == null) {
    await prefs.remove(_kSortKeyPref);
    await prefs.remove(_kSortAscendingPref);
    return;
  }
  await prefs.setString(_kSortKeyPref, choice.key.name);
  await prefs.setBool(_kSortAscendingPref, choice.ascending);
}
