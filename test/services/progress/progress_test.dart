// Round-trip tests for the `Progress` model. The Cosmos doc shape gained
// three optional fields (`difficulty`, `recentAnswers`, `lastSessionAt`) for
// per-(uid, goalId) calibration; legacy docs predate them and must still
// parse with sensible defaults.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/progress/concept_attribution.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'oid-123';

void main() {
  group('toMap', () {
    test('emits the new calibration fields with enum names and a fresh '
        'lastSessionAt timestamp', () {
      final before = DateTime.now().toUtc();
      final doc = Progress(
        goalID: 'g1',
        progress: 0.5,
        difficulty: QuestionDifficulty.medium,
        recentAnswers: const [
          AnswerQuality.wrong,
          AnswerQuality.partial,
          AnswerQuality.correct,
        ],
      ).toMap(uid: _uid);
      final after = DateTime.now().toUtc();

      expect(doc['id'], '${_uid}_g1');
      expect(doc['uid'], _uid);
      expect(doc['goalId'], 'g1');
      expect(doc['progress'], 0.5);
      expect(doc['difficulty'], 'medium');
      expect(doc['recentAnswers'], ['wrong', 'partial', 'correct']);

      final lastSessionAt = DateTime.parse(doc['lastSessionAt'] as String);
      expect(lastSessionAt.isBefore(before), isFalse);
      expect(lastSessionAt.isAfter(after), isFalse);
    });

    test('trims recentAnswers to the last 5 on write (oldest dropped)', () {
      final doc = Progress(
        goalID: 'g1',
        progress: 0.5,
        recentAnswers: const [
          AnswerQuality.wrong, // oldest, should be dropped
          AnswerQuality.partial,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.partial,
          AnswerQuality.correct, // newest
        ],
      ).toMap(uid: _uid);

      expect(
        doc['recentAnswers'],
        ['partial', 'correct', 'correct', 'partial', 'correct'],
      );
    });

    test('defaults serialise to easy + empty list', () {
      final doc =
          Progress(goalID: 'g1', progress: 0.0).toMap(uid: _uid);
      expect(doc['difficulty'], 'easy');
      expect(doc['recentAnswers'], <String>[]);
    });
  });

  group('fromCosmos', () {
    test('round-trips difficulty and recentAnswers via toMap → fromCosmos',
        () {
      final original = Progress(
        goalID: 'g1',
        progress: 0.4,
        difficulty: QuestionDifficulty.hard,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.partial,
        ],
      );
      final restored = Progress.fromCosmos(original.toMap(uid: _uid));

      expect(restored.goalID, 'g1');
      expect(restored.progress, 0.4);
      expect(restored.difficulty, QuestionDifficulty.hard);
      expect(restored.recentAnswers, [
        AnswerQuality.correct,
        AnswerQuality.correct,
        AnswerQuality.partial,
      ]);
      expect(restored.lastSessionAt, isNotNull);
    });

    test('legacy doc without the new fields defaults to easy + [] + null '
        'lastSessionAt', () {
      final restored = Progress.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.6,
        'updatedAt': '2025-01-02T03:04:05.000Z',
      });

      expect(restored.goalID, 'g1');
      expect(restored.progress, 0.6);
      expect(restored.difficulty, QuestionDifficulty.easy);
      expect(restored.recentAnswers, isEmpty);
      expect(restored.lastSessionAt, isNull);
    });

    test('unknown enum strings fall back: difficulty → easy, answers skipped',
        () {
      final restored = Progress.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.0,
        'difficulty': 'extreme',
        'recentAnswers': ['correct', 'bogus', 'wrong'],
      });

      expect(restored.difficulty, QuestionDifficulty.easy);
      expect(restored.recentAnswers,
          [AnswerQuality.correct, AnswerQuality.wrong]);
    });

    test('non-list recentAnswers in the doc parses as empty', () {
      final restored = Progress.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.0,
        'recentAnswers': 'not-a-list',
      });

      expect(restored.recentAnswers, isEmpty);
    });
  });

  group('recentConceptAttributions', () {
    test('round-trips through toMap/fromCosmos preserving concept, at, '
        'quality', () {
      final at = DateTime.utc(2026, 4, 15, 12, 30);
      final original = Progress(
        goalID: 'g1',
        progress: 0.4,
        recentConceptAttributions: [
          ConceptAttribution(
            concept: 'variables',
            at: at,
            quality: AnswerQuality.wrong,
          ),
          ConceptAttribution(
            concept: 'loops',
            at: at,
            quality: AnswerQuality.correct,
          ),
        ],
      );
      final restored = Progress.fromCosmos(original.toMap(uid: _uid));

      expect(restored.recentConceptAttributions, [
        ConceptAttribution(
          concept: 'variables',
          at: at,
          quality: AnswerQuality.wrong,
        ),
        ConceptAttribution(
          concept: 'loops',
          at: at,
          quality: AnswerQuality.correct,
        ),
      ]);
    });

    test('legacy doc without the field deserialises with empty list', () {
      final restored = Progress.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.5,
      });
      expect(restored.recentConceptAttributions, isEmpty);
    });

    test('toMap trims to last 20 entries (oldest dropped)', () {
      final at = DateTime.utc(2026, 4, 15, 12, 30);
      final attrs = [
        for (var i = 0; i < 25; i++)
          ConceptAttribution(
            concept: 'c$i',
            at: at,
            quality: AnswerQuality.wrong,
          ),
      ];
      final doc = Progress(
        goalID: 'g1',
        progress: 0.0,
        recentConceptAttributions: attrs,
      ).toMap(uid: _uid);

      final emitted = (doc['recentConceptAttributions'] as List)
          .cast<Map<String, dynamic>>();
      expect(emitted, hasLength(20));
      expect(emitted.first['concept'], 'c5');
      expect(emitted.last['concept'], 'c24');
    });

    test('non-list field in the doc parses as empty', () {
      final restored = Progress.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.0,
        'recentConceptAttributions': 'not-a-list',
      });
      expect(restored.recentConceptAttributions, isEmpty);
    });

    test('unknown quality string in a stored entry falls back to wrong', () {
      final restored = Progress.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.0,
        'recentConceptAttributions': [
          {
            'concept': 'variables',
            'at': '2026-04-15T12:30:00.000Z',
            'quality': 'bogus',
          },
        ],
      });
      expect(
        restored.recentConceptAttributions.single.quality,
        AnswerQuality.wrong,
      );
    });
  });
}
