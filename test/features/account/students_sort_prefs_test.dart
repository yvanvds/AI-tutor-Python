// Unit tests for the persisted Students sort choice (#92): the
// SharedPreferences round trip and the decode tolerance that keeps a stale
// or foreign stored value from misfiring as a wrong-column sort.

import 'package:ai_tutor_python/features/account/students_sort.dart';
import 'package:ai_tutor_python/features/account/students_sort_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decodeStudentsSortChoice', () {
    test('maps every key name back onto its key', () {
      for (final key in StudentsSortKey.values) {
        expect(decodeStudentsSortChoice(key.name, false), (
          key: key,
          ascending: false,
        ));
      }
    });

    test('nothing stored decodes to null', () {
      expect(decodeStudentsSortChoice(null, null), isNull);
      expect(decodeStudentsSortChoice(null, true), isNull);
    });

    test('an unrecognized name decodes to null, not a guess', () {
      // A key renamed/removed in another app version, or a raw column index
      // from a hypothetical index-based scheme — both must fall back to
      // storage order instead of sorting by the wrong column.
      expect(decodeStudentsSortChoice('lastSeen', true), isNull);
      expect(decodeStudentsSortChoice('5', true), isNull);
      expect(decodeStudentsSortChoice('', true), isNull);
    });

    test('a missing direction defaults to ascending', () {
      expect(decodeStudentsSortChoice('email', null), (
        key: StudentsSortKey.email,
        ascending: true,
      ));
    });
  });

  group('load/saveStudentsSortChoice', () {
    test('round-trips key and direction through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      await saveStudentsSortChoice((
        key: StudentsSortKey.progress,
        ascending: false,
      ));
      expect(await loadStudentsSortChoice(), (
        key: StudentsSortKey.progress,
        ascending: false,
      ));

      // What hit the store is the enum NAME, not a column index — the #91
      // column shift is exactly what an index would not have survived.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('students_sort_key'), 'progress');
      expect(prefs.getBool('students_sort_ascending'), false);
    });

    test('loads null when nothing was stored', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await loadStudentsSortChoice(), isNull);
    });

    test('saving null clears a stored choice', () async {
      SharedPreferences.setMockInitialValues({});
      await saveStudentsSortChoice((
        key: StudentsSortKey.name,
        ascending: true,
      ));
      await saveStudentsSortChoice(null);
      expect(await loadStudentsSortChoice(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('students_sort_key'), isNull);
      expect(prefs.getBool('students_sort_ascending'), isNull);
    });

    test('a stored value from a newer/older version loads as null', () async {
      SharedPreferences.setMockInitialValues({
        'students_sort_key': 'someFutureKey',
        'students_sort_ascending': false,
      });
      expect(await loadStudentsSortChoice(), isNull);
    });
  });
}
