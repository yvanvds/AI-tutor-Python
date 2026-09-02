// Unit tests for the persisted Students view options (#95): the
// SharedPreferences round trips and the decode tolerance that keeps a stale
// stored page size from feeding the dropdown an off-menu value.

import 'package:ai_tutor_python/features/account/students_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decodeStudentsRowsPerPage', () {
    test('passes every menu option through', () {
      for (final n in kStudentsRowsPerPageOptions) {
        expect(decodeStudentsRowsPerPage(n), n);
      }
    });

    test('nothing stored decodes to null', () {
      expect(decodeStudentsRowsPerPage(null), isNull);
    });

    test('an off-menu size decodes to null, not a guess', () {
      // A size from a newer/older app version, or a hypothetical stored
      // item index — DropdownButton asserts its value has a matching item,
      // so anything off-menu must fall back to the default instead.
      expect(decodeStudentsRowsPerPage(37), isNull);
      expect(decodeStudentsRowsPerPage(0), isNull);
      expect(decodeStudentsRowsPerPage(-10), isNull);
      expect(decodeStudentsRowsPerPage(2), isNull);
    });
  });

  group('load/saveStudentsRowsPerPage', () {
    test('round-trips through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      await saveStudentsRowsPerPage(50);
      expect(await loadStudentsRowsPerPage(), 50);

      // What hit the store is the NUMBER, not a dropdown item index.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('students_rows_per_page'), 50);
    });

    test('loads null when nothing was stored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadStudentsRowsPerPage(), isNull);
    });

    test('a stored off-menu size loads as null', () async {
      SharedPreferences.setMockInitialValues({'students_rows_per_page': 37});
      expect(await loadStudentsRowsPerPage(), isNull);
    });
  });

  group('load/saveStudentsClassFilter', () {
    test('round-trips a class name through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      await saveStudentsClassFilter('5A');
      expect(await loadStudentsClassFilter(), '5A');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('students_class_filter'), '5A');
    });

    test('round-trips the sentinels verbatim', () async {
      // '__all__' / '__none__' are safe stored values: real class names are
      // trimmed, non-empty teacher text and never collide with them.
      SharedPreferences.setMockInitialValues({});
      await saveStudentsClassFilter('__none__');
      expect(await loadStudentsClassFilter(), '__none__');
      await saveStudentsClassFilter('__all__');
      expect(await loadStudentsClassFilter(), '__all__');
    });

    test('loads null when nothing was stored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadStudentsClassFilter(), isNull);
    });

    test('a stored class that no longer exists still loads verbatim — the '
        'fallback to "All" is the page\'s in-build normalization, not the '
        'store\'s', () async {
      SharedPreferences.setMockInitialValues({
        'students_class_filter': 'deleted-class',
      });
      expect(await loadStudentsClassFilter(), 'deleted-class');
    });
  });
}
