// Persistence for the Students table view options (#95): rows-per-page and
// the class filter. Same treatment #92 gave the sort — the values live in
// `_AccountsPageState`, so they died with the page; now they are stored per
// device in SharedPreferences and restored in `initState`.
//
// What is stored is the *value* (the page-size number, the class filter
// string), never a dropdown item index — the option lists can grow or
// reorder without a stored index misfiring (the lesson of #91's column
// shift). Stale values are tolerated on the way back in:
//
//   - A rows-per-page number that is no longer a menu option decodes to
//     null (the default, 25) instead of feeding `DropdownButton` a value
//     with no matching item, which is an assertion failure.
//   - A class filter is handed back verbatim — the sentinels `__all__` /
//     `__none__` are safe to store because real class names are trimmed,
//     non-empty teacher text and never collide with them. A stored class
//     that no longer exists next session is the page's problem to solve:
//     its in-build normalization already falls back to "All", the same
//     path that handles a class emptied out mid-session.

import 'package:shared_preferences/shared_preferences.dart';

const String _kRowsPerPagePref = 'students_rows_per_page';
const String _kClassFilterPref = 'students_class_filter';

/// The page sizes the Students table offers. Single source of truth for the
/// dropdown's items and for what a stored value is checked against.
const List<int> kStudentsRowsPerPageOptions = [10, 25, 50, 100];

/// Pure decode half of [loadStudentsRowsPerPage], split out for unit tests:
/// a stored size that is not (or no longer) a menu option — nothing stored
/// yet, or a size from a newer/older app version — means "no stored
/// choice", never an off-menu dropdown value.
int? decodeStudentsRowsPerPage(int? raw) {
  if (raw == null) return null;
  return kStudentsRowsPerPageOptions.contains(raw) ? raw : null;
}

/// The rows-per-page stored on this device, or null for the default.
Future<int?> loadStudentsRowsPerPage() async {
  final prefs = await SharedPreferences.getInstance();
  return decodeStudentsRowsPerPage(prefs.getInt(_kRowsPerPagePref));
}

/// Stores [rowsPerPage] as the number itself, never an item index.
Future<void> saveStudentsRowsPerPage(int rowsPerPage) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kRowsPerPagePref, rowsPerPage);
}

/// The class filter stored on this device (a class name or one of the
/// page's sentinels), or null for the default ("All").
Future<String?> loadStudentsClassFilter() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kClassFilterPref);
}

/// Stores [classFilter] verbatim — class name or sentinel.
Future<void> saveStudentsClassFilter(String classFilter) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kClassFilterPref, classFilter);
}
