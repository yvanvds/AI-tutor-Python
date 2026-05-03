import 'package:ai_tutor_python/services/tutor/responses/suspected_concepts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSuspectedConcepts', () {
    test('returns null for null input', () {
      expect(parseSuspectedConcepts(null), isNull);
    });

    test('returns null for non-list input', () {
      expect(parseSuspectedConcepts('not a list'), isNull);
      expect(parseSuspectedConcepts(42), isNull);
      expect(parseSuspectedConcepts({'key': 'value'}), isNull);
    });

    test('returns null for empty list', () {
      expect(parseSuspectedConcepts([]), isNull);
    });

    test('returns trimmed strings from a valid list', () {
      expect(
        parseSuspectedConcepts(['  loops  ', 'variables']),
        ['loops', 'variables'],
      );
    });

    test('drops empty and whitespace-only entries', () {
      expect(parseSuspectedConcepts(['', '   ', 'functions']), ['functions']);
    });

    test('drops non-string entries', () {
      expect(parseSuspectedConcepts([42, null, 'lists']), ['lists']);
    });

    test('returns null when all entries are non-string or empty', () {
      expect(parseSuspectedConcepts([42, '', '   ']), isNull);
    });
  });
}
