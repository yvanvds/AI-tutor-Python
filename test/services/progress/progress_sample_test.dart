// Round-trip tests for the `ProgressSample` model — one row of the
// `progress_history` Cosmos container. Optional fields (`quality`) must
// survive being absent in legacy/derived docs; enum-name strings must
// round-trip; the doc id must be unique enough across rapid writes that
// two same-instant samples don't collide.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/progress/progress_sample.dart';
import 'package:flutter_test/flutter_test.dart';

const _uid = 'oid-123';

void main() {
  group('toMap', () {
    test('emits all required fields with enum names and ISO timestamp', () {
      final at = DateTime.utc(2026, 4, 15, 12, 30);
      final doc = ProgressSample(
        goalID: 'g1',
        progress: 0.4,
        difficulty: QuestionDifficulty.medium,
        quality: AnswerQuality.partial,
        isWarmUp: true,
        at: at,
      ).toMap(uid: _uid);

      expect(doc['uid'], _uid);
      expect(doc['goalId'], 'g1');
      expect(doc['progress'], 0.4);
      expect(doc['difficulty'], 'medium');
      expect(doc['quality'], 'partial');
      expect(doc['isWarmUp'], true);
      expect(doc['at'], at.toIso8601String());
      expect(doc['id'], isA<String>());
      expect((doc['id'] as String).startsWith(at.toIso8601String()), isTrue);
    });

    test('omits quality when null (not set on every progress change)', () {
      final doc = ProgressSample(
        goalID: 'g1',
        progress: 0.0,
        difficulty: QuestionDifficulty.easy,
        at: DateTime.utc(2026, 4, 15),
      ).toMap(uid: _uid);

      expect(doc.containsKey('quality'), isFalse);
    });

    test('two samples with the same instant get distinct ids', () {
      final at = DateTime.utc(2026, 4, 15, 12, 30);
      final a = ProgressSample(
        goalID: 'g1',
        progress: 0.0,
        difficulty: QuestionDifficulty.easy,
        at: at,
      ).toMap(uid: _uid);
      final b = ProgressSample(
        goalID: 'g1',
        progress: 0.1,
        difficulty: QuestionDifficulty.easy,
        at: at,
      ).toMap(uid: _uid);
      expect(a['id'], isNot(equals(b['id'])));
    });
  });

  group('fromCosmos', () {
    test('round-trips through toMap → fromCosmos', () {
      final at = DateTime.utc(2026, 4, 15, 12, 30);
      final original = ProgressSample(
        goalID: 'g1',
        progress: 0.6,
        difficulty: QuestionDifficulty.hard,
        quality: AnswerQuality.correct,
        isWarmUp: false,
        at: at,
      );
      final restored = ProgressSample.fromCosmos(original.toMap(uid: _uid));

      expect(restored.goalID, 'g1');
      expect(restored.progress, 0.6);
      expect(restored.difficulty, QuestionDifficulty.hard);
      expect(restored.quality, AnswerQuality.correct);
      expect(restored.isWarmUp, false);
      expect(restored.at, at);
    });

    test('legacy / derived doc without quality parses with quality = null',
        () {
      final restored = ProgressSample.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.5,
        'difficulty': 'easy',
        'isWarmUp': false,
        'at': '2026-04-15T12:30:00.000Z',
      });
      expect(restored.quality, isNull);
    });

    test('unknown enum strings fall back: difficulty → easy, quality → null',
        () {
      final restored = ProgressSample.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.0,
        'difficulty': 'extreme',
        'quality': 'bogus',
        'isWarmUp': true,
        'at': '2026-04-15T12:30:00.000Z',
      });
      expect(restored.difficulty, QuestionDifficulty.easy);
      expect(restored.quality, isNull);
      expect(restored.isWarmUp, true);
    });

    test('missing isWarmUp defaults to false', () {
      final restored = ProgressSample.fromCosmos(<String, dynamic>{
        'goalId': 'g1',
        'progress': 0.0,
        'difficulty': 'easy',
        'at': '2026-04-15T12:30:00.000Z',
      });
      expect(restored.isWarmUp, false);
    });
  });
}
