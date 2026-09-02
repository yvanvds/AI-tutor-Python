// Unit tests for the Students page bulk-selection helpers (#91): the
// tri-state header checkbox value and the filter-scoped toggle-all.

import 'package:ai_tutor_python/features/account/students_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectAllState', () {
    test('false when nothing is selected', () {
      expect(selectAllState({}, ['a', 'b']), isFalse);
    });

    test(
      'false for an empty filtered set, even with a selection elsewhere',
      () {
        expect(selectAllState({'x'}, []), isFalse);
      },
    );

    test('false when only rows outside the filtered set are selected', () {
      expect(selectAllState({'x'}, ['a', 'b']), isFalse);
    });

    test('null (indeterminate) when part of the filtered set is selected', () {
      expect(selectAllState({'a'}, ['a', 'b']), isNull);
    });

    test('true when every filtered row is selected', () {
      expect(selectAllState({'a', 'b'}, ['a', 'b']), isTrue);
      // Extra selections outside the filter do not break "all".
      expect(selectAllState({'a', 'b', 'x'}, ['a', 'b']), isTrue);
    });
  });

  group('toggleSelectAll', () {
    test('selects every filtered row from an empty selection', () {
      expect(toggleSelectAll({}, ['a', 'b']), {'a', 'b'});
    });

    test('completes a partial (indeterminate) selection', () {
      expect(toggleSelectAll({'a'}, ['a', 'b']), {'a', 'b'});
    });

    test('deselects the filtered rows when all of them are selected', () {
      expect(toggleSelectAll({'a', 'b'}, ['a', 'b']), isEmpty);
    });

    test('keeps selections outside the filtered set in both directions', () {
      // Selecting all of the filter keeps the off-filter uid.
      expect(toggleSelectAll({'x'}, ['a', 'b']), {'x', 'a', 'b'});
      // Deselecting all of the filter also keeps it.
      expect(toggleSelectAll({'x', 'a', 'b'}, ['a', 'b']), {'x'});
    });

    test('empty filtered set is a no-op', () {
      expect(toggleSelectAll({'x'}, []), {'x'});
    });
  });
}
