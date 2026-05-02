// 5.2 — Pure helpers driving the teacher overview dot + drawer summary. The
// thresholds here are the ones the spec calls out (≥0.5 weighted-wrong over
// ≥3 answers); pinning them down so silent drift later is loud.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/services/progress/concept_attribution.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/teacher_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isStruggling', () {
    test('returns false with fewer than the minimum number of samples', () {
      expect(isStruggling(const []), isFalse);
      expect(
        isStruggling(const [AnswerQuality.wrong, AnswerQuality.wrong]),
        isFalse,
      );
    });

    test('returns true when weighted-wrong average meets the threshold', () {
      // 3 wrongs over 3 → 1.0 weighted-wrong
      expect(
        isStruggling(const [
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.wrong,
        ]),
        isTrue,
      );
      // 2 wrongs + 1 partial over 3 → (1+1+0.5)/3 = 0.83
      expect(
        isStruggling(const [
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.partial,
        ]),
        isTrue,
      );
    });

    test('returns false when weighted-wrong average is below the threshold',
        () {
      // 1 wrong + 1 partial + 1 correct over 3 → (1+0.5+0)/3 = 0.5 → tie
      // is true (≥). Step down: 1 wrong + 2 correct → 1/3 → false.
      expect(
        isStruggling(const [
          AnswerQuality.wrong,
          AnswerQuality.correct,
          AnswerQuality.correct,
        ]),
        isFalse,
      );
    });
  });

  group('mostRecentlyActive', () {
    test('returns null when input is empty', () {
      expect(mostRecentlyActive(const []), isNull);
    });

    test('picks the doc with the largest lastSessionAt', () {
      final older = Progress(
        goalID: 'g1',
        progress: 0.5,
        lastSessionAt: DateTime.utc(2026, 4, 1),
      );
      final newer = Progress(
        goalID: 'g2',
        progress: 0.8,
        lastSessionAt: DateTime.utc(2026, 4, 10),
      );
      expect(mostRecentlyActive([older, newer]), same(newer));
      expect(mostRecentlyActive([newer, older]), same(newer));
    });

    test('falls back to updatedAt when lastSessionAt is missing', () {
      final older = Progress(
        goalID: 'g1',
        progress: 0.5,
        updatedAt: DateTime.utc(2026, 4, 1),
      );
      final newer = Progress(
        goalID: 'g2',
        progress: 0.8,
        updatedAt: DateTime.utc(2026, 4, 10),
      );
      expect(mostRecentlyActive([older, newer])!.goalID, 'g2');
    });
  });

  group('computeStudentStatus', () {
    Progress mk({
      required String id,
      required List<AnswerQuality> answers,
      required DateTime when,
    }) {
      return Progress(
        goalID: id,
        progress: 0.5,
        lastSessionAt: when,
        recentAnswers: answers,
      );
    }

    test('idle when there is no progress data at all', () {
      expect(
        computeStudentStatus(progress: const []),
        StudentStatus.idle,
      );
    });

    test('struggling when the most-recently-active doc has bad answers', () {
      final now = DateTime.utc(2026, 4, 10);
      final docs = [
        mk(
          id: 'g1',
          when: now.subtract(const Duration(hours: 2)),
          answers: const [
            AnswerQuality.wrong,
            AnswerQuality.wrong,
            AnswerQuality.wrong,
          ],
        ),
      ];
      expect(
        computeStudentStatus(progress: docs, now: now),
        StudentStatus.struggling,
      );
    });

    test('active when there is recent activity and the answers are fine', () {
      final now = DateTime.utc(2026, 4, 10);
      final docs = [
        mk(
          id: 'g1',
          when: now.subtract(const Duration(hours: 2)),
          answers: const [
            AnswerQuality.correct,
            AnswerQuality.correct,
            AnswerQuality.correct,
          ],
        ),
      ];
      expect(
        computeStudentStatus(progress: docs, now: now),
        StudentStatus.active,
      );
    });

    test('idle when the latest activity is outside the recent window', () {
      final now = DateTime.utc(2026, 4, 30);
      final docs = [
        mk(
          id: 'g1',
          when: now.subtract(const Duration(days: 14)),
          answers: const [
            AnswerQuality.correct,
            AnswerQuality.correct,
            AnswerQuality.correct,
          ],
        ),
      ];
      expect(
        computeStudentStatus(progress: docs, now: now),
        StudentStatus.idle,
      );
    });
  });

  group('rankConceptAttributions', () {
    test('returns an empty list for empty input', () {
      expect(rankConceptAttributions(const []), isEmpty);
    });

    test('counts and sorts descending by count, then ascending by name', () {
      final at = DateTime.utc(2026, 4, 1);
      final attributions = [
        ConceptAttribution(concept: 'variabelen', at: at, quality: AnswerQuality.wrong),
        ConceptAttribution(concept: 'printen', at: at, quality: AnswerQuality.wrong),
        ConceptAttribution(concept: 'variabelen', at: at, quality: AnswerQuality.partial),
        ConceptAttribution(concept: 'variabelen', at: at, quality: AnswerQuality.wrong),
        ConceptAttribution(concept: 'lussen', at: at, quality: AnswerQuality.wrong),
      ];
      final ranked = rankConceptAttributions(attributions);
      expect(ranked.first.key, 'variabelen');
      expect(ranked.first.value, 3);
      // 'lussen' and 'printen' both have count 1 → alphabetical fallback.
      expect(ranked[1].key, 'lussen');
      expect(ranked[2].key, 'printen');
    });
  });
}
