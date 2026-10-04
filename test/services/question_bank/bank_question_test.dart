// Issue #185 — the question bank's model: what a generated question is
// stored as, and what the next reader (#186, the Questions page) gets back.
// And #216: the short ID the student sees and the teacher looks up.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/question_bank/bank_question.dart';
import 'package:ai_tutor_python/services/tutor/responses/answer.dart';
import 'package:ai_tutor_python/services/tutor/responses/chat_response.dart';
import 'package:ai_tutor_python/services/tutor/responses/complete_code.dart';
import 'package:ai_tutor_python/services/tutor/responses/multiple_choice.dart';
import 'package:ai_tutor_python/services/tutor/responses/socratic_question.dart';
import 'package:flutter_test/flutter_test.dart';

final _at = DateTime.utc(2026, 9, 24, 8, 30);

BankQuestion? _bank(ChatResponse response, {String subgoalId = 's1'}) =>
    BankQuestion.fromResponse(
      response,
      subgoalId: subgoalId,
      rootGoalId: 'r1',
      targetLOIds: const ['lo-print'],
      difficulty: QuestionDifficulty.hard,
      language: 'nl',
      model: 'gpt-5-mini',
      createdByUid: 'u1',
      createdAt: _at,
    );

MultipleChoice _mcq({
  String prompt = 'Wat drukt dit af?',
  String code = "print('Python')",
  List<String> options = const ['Python', "'Python'", 'Error'],
  Object? correct = 'A',
}) => MultipleChoice.fromMap({
  'type': 'multiple_choice',
  'prompt': prompt,
  'code': code,
  'options': [
    for (final o in options) {'option': o},
  ],
  'correct': ?correct,
});

void main() {
  group('fromResponse', () {
    test('a multiple-choice question is stored with what it was asked for, '
        'its payload as the UI renders it and the key as option text', () {
      final q = _bank(_mcq(correct: 'B'))!;

      expect(q.id, startsWith('s1_'));
      expect(q.id.length, 's1_'.length + 32);
      expect(q.subgoalId, 's1');
      expect(q.rootGoalId, 'r1');
      expect(q.targetLOIds, ['lo-print']);
      expect(q.questionType, ChatRequestType.mcQuestion);
      expect(q.difficulty, QuestionDifficulty.hard);
      expect(q.language, 'nl');
      expect(q.model, 'gpt-5-mini');
      expect(q.createdByUid, 'u1');
      expect(q.createdAt, _at);
      expect(q.payload, {
        'type': 'multiple_choice',
        'prompt': 'Wat drukt dit af?',
        'code': "print('Python')",
        'options': [
          {'option': 'Python'},
          {'option': "'Python'"},
          {'option': 'Error'},
        ],
        'correct': "'Python'",
      });
      expect(q.correctOption, "'Python'");
      expect(q.askedCount, 0);
      expect(q.isActive, isTrue);
      expect(q.hiddenBy, isNull);
      expect(q.keptByTeacher, isFalse);
      // Nothing of the teacher's: no hide, no review stamp, no note (#215).
      expect(
        q.toMap().keys,
        isNot(
          anyOf(
            contains('hiddenBy'),
            contains('hiddenAt'),
            contains('keptByTeacher'),
            contains('reviewedAt'),
            contains('teacherNote'),
          ),
        ),
      );
    });

    test('the question type is what the model returned', () {
      expect(
        _bank(
          CompleteCode(type: 'complete_code', prompt: 'p', code: 'x = ___'),
        )!.questionType,
        ChatRequestType.completeCodeQuestion,
      );
      expect(
        _bank(SocraticQuestion(type: 'socratic_question', prompt: 'Waarom?'))!
            .questionType,
        ChatRequestType.socraticQuestion,
      );
    });

    test('anything that is not a question is not stored', () {
      expect(_bank(Answer(type: 'answer', prompt: 'Goed zo.')), isNull);
    });

    test('a multiple-choice question without a usable key has none', () {
      expect(
        _bank(_mcq(correct: null))!.payload.containsKey('correct'),
        isFalse,
      );
      expect(_bank(_mcq(correct: 'Z'))!.correctOption, isNull);
    });
  });

  group('dedupe id', () {
    test('the same question is the same id, however its options are ordered '
        'and whatever the prompt says', () {
      final a = _bank(_mcq())!;
      final b = _bank(
        _mcq(
          prompt: 'Welke uitvoer geeft deze code?',
          options: const ['Error', 'Python', "'Python'"],
        ),
      )!;
      expect(b.id, a.id);
    });

    test('other options or other code are another question', () {
      final a = _bank(_mcq())!;
      expect(
        _bank(_mcq(options: const ['Python', 'python', 'Error']))!.id,
        isNot(a.id),
      );
      expect(_bank(_mcq(code: "print('Py')"))!.id, isNot(a.id));
    });

    test('the same question on another subgoal is another doc', () {
      expect(
        _bank(_mcq(), subgoalId: 's2')!.id,
        isNot(_bank(_mcq(), subgoalId: 's1')!.id),
      );
    });

    test('without options the prompt is the question: the same starter code '
        'asked for two things is two questions', () {
      CompleteCode cc(String prompt) => CompleteCode(
        type: 'complete_code',
        prompt: prompt,
        code: 'print(___)',
      );
      final greet = _bank(cc('Toon een groet.'))!;
      expect(_bank(cc('Toon je naam.'))!.id, isNot(greet.id));
      // Whitespace is not a different question.
      expect(_bank(cc('Toon  een\ngroet.'))!.id, greet.id);
    });
  });

  group('Cosmos round trip', () {
    test('every field survives toMap / tryFromCosmos', () {
      final q = _bank(_mcq())!;
      final stored = {
        ...q.toMap(),
        'askedCount': 5,
        'answeredCount': 4,
        'correctCount': 1,
        'lastAskedAt': '2026-09-24T09:00:00.000Z',
        'optionFeedback': [
          {'option': 'Error', 'text': 'Nee, dit werkt.', 'quality': 'wrong'},
        ],
        'status': 'hidden',
        'hiddenBy': 'auto',
        'hiddenAt': '2026-09-24T10:00:00.000Z',
        'keptByTeacher': true,
        // Cosmos system fields, a field of a newer build, and the review
        // stamp and note of a doc from before #215 are ignored.
        '_etag': '"0"',
        'futureField': true,
        'teacherNote': 'Te makkelijk',
        'reviewedAt': '2026-09-24T10:00:00.000Z',
      };
      final back = BankQuestion.tryFromCosmos(stored)!;

      expect(back.toMap(), {
        ...q.toMap(),
        'askedCount': 5,
        'answeredCount': 4,
        'correctCount': 1,
        'lastAskedAt': '2026-09-24T09:00:00.000Z',
        'optionFeedback': [
          {'option': 'Error', 'text': 'Nee, dit werkt.', 'quality': 'wrong'},
        ],
        'status': 'hidden',
        'hiddenBy': 'auto',
        'hiddenAt': '2026-09-24T10:00:00.000Z',
        'keptByTeacher': true,
      });
      expect(back.shareCorrect, 0.25);
      expect(back.isActive, isFalse);
      expect(back.isAutoHidden, isTrue);
      expect(back.hiddenAt, DateTime.utc(2026, 9, 24, 10));
      expect(back.keptByTeacher, isTrue);
      expect(back.feedbackFor('Error')!.quality, AnswerQuality.wrong);
      expect(back.feedbackFor('Python'), isNull);
    });

    test('a question hidden before #215 carries no hiddenBy: the teacher hid '
        'it', () {
      final q = BankQuestion.tryFromCosmos({
        ..._bank(_mcq())!.toMap(),
        'status': 'hidden',
      })!;
      expect(q.isActive, isFalse);
      expect(q.hiddenBy, isNull);
      expect(q.isAutoHidden, isFalse);
      expect(
        BankQuestion.tryFromCosmos({
          ..._bank(_mcq())!.toMap(),
          'status': 'hidden',
          'hiddenBy': 'teacher',
        })!.isAutoHidden,
        isFalse,
      );
    });

    test('a doc a reader cannot use is skipped, not guessed at', () {
      final good = _bank(_mcq())!.toMap();
      expect(
        BankQuestion.tryFromCosmos({...good, 'questionType': 'x'}),
        isNull,
      );
      expect(
        BankQuestion.tryFromCosmos({...good}..remove('subgoalId')),
        isNull,
      );
      expect(BankQuestion.tryFromCosmos({...good}..remove('payload')), isNull);
    });
  });

  group('toChatResponse (#186 serves a bank question through the same '
      'handler as a fresh one)', () {
    test('multiple choice comes back with its key as text — also when an '
        'option is itself a letter', () {
      final q = _bank(_mcq(options: const ['B', 'A', 'C'], correct: 'A'))!;
      // "A" is the first option, whose text is "B".
      expect(q.correctOption, 'B');

      final response = q.toChatResponse()! as MultipleChoice;
      expect(response.options, ['B', 'A', 'C']);
      expect(response.correct, 'B');
      expect(response.prompt, 'Wat drukt dit af?');
      expect(response.code, "print('Python')");
    });

    test('the other types come back through the response factory', () {
      final q = _bank(
        CompleteCode(
          type: 'complete_code',
          prompt: 'Vul aan.',
          code: 'x = ___',
        ),
      )!;
      final response = q.toChatResponse()! as CompleteCode;
      expect(response.prompt, 'Vul aan.');
      expect(response.code, 'x = ___');
    });
  });

  group('graderDisagreesWithKey', () {
    BankQuestion withFeedback(List<Map<String, String>> feedback) =>
        BankQuestion.tryFromCosmos({
          ..._bank(_mcq())!.toMap(),
          'optionFeedback': feedback,
        })!;

    test('the key graded correct and another option wrong agree', () {
      expect(
        withFeedback([
          {'option': 'Python', 'text': 'Juist.', 'quality': 'correct'},
          {'option': 'Error', 'text': 'Nee.', 'quality': 'wrong'},
        ]).graderDisagreesWithKey,
        isFalse,
      );
    });

    test('a grading that called the key wrong disagrees (#198), even when '
        'every pick was graded as the key says', () {
      final q = BankQuestion.tryFromCosmos({
        ..._bank(_mcq())!.toMap(),
        'optionFeedback': [
          {'option': 'Error', 'text': 'Nee.', 'quality': 'wrong'},
        ],
        'keyDisputedCount': 2,
        'keyDisputedAt': '2026-09-24T10:00:00.000Z',
      })!;
      expect(q.keyDisputedCount, 2);
      expect(q.keyDisputedAt, DateTime.utc(2026, 9, 24, 10));
      expect(q.graderDisagreesWithKey, isTrue);
      // Written back as read; a question never disputed carries neither.
      expect(q.toMap()['keyDisputedCount'], 2);
      expect(q.toMap()['keyDisputedAt'], '2026-09-24T10:00:00.000Z');
      final plain = _bank(_mcq())!;
      expect(plain.keyDisputedCount, 0);
      expect(plain.toMap().containsKey('keyDisputedCount'), isFalse);
      expect(plain.toMap().containsKey('keyDisputedAt'), isFalse);
    });

    test('another option graded correct, or the key graded less, disagree', () {
      expect(
        withFeedback([
          {'option': 'Error', 'text': 'Juist.', 'quality': 'correct'},
        ]).graderDisagreesWithKey,
        isTrue,
      );
      expect(
        withFeedback([
          {'option': 'Python', 'text': 'Bijna.', 'quality': 'partial'},
        ]).graderDisagreesWithKey,
        isTrue,
      );
    });
  });

  group('short ID (#216)', () {
    test('is # and the first six characters of the content hash — of a doc '
        'id or of the hash alone, the same on every subgoal', () {
      final q = _bank(_mcq())!;
      final hash = q.id.substring('s1_'.length);
      expect(q.shortId, '#${hash.substring(0, 6)}');
      expect(BankQuestion.shortIdOf(q.id), q.shortId);
      expect(BankQuestion.shortIdOf(hash), q.shortId);
      expect(_bank(_mcq(), subgoalId: 'other_subgoal')!.shortId, q.shortId);
      expect(BankQuestion.contentHashOf(_mcq()), hash);
      expect(
        BankQuestion.contentHashOf(Answer(type: 'answer', prompt: 'Ja.')),
        isNull,
      );
    });

    test('a lookup takes the short ID with or without #, in capitals, a '
        'longer piece of the hash, or the whole doc id', () {
      const id = 's1_3fa91c0b5e7d4a2f9c8b1e6d0a4f7c2e';
      bool finds(String typed) {
        final query = BankQuestion.idQueryOf(typed);
        return query != null && BankQuestion.matchesIdQuery(id, query);
      }

      expect(finds('3fa91c'), isTrue);
      expect(finds('#3fa91c'), isTrue);
      expect(finds('  #3FA91C '), isTrue);
      expect(finds('3fa91c0b5e'), isTrue);
      expect(finds('3fa91c0b5e7d4a2f9c8b1e6d0a4f7c2e'), isTrue);
      expect(finds(id), isTrue);
      expect(finds('S1_3FA91C0B5E7D4A2F9C8B1E6D0A4F7C2E'), isTrue);

      expect(finds('3fa91d'), isFalse);
      expect(finds('s2_3fa91c0b5e7d4a2f9c8b1e6d0a4f7c2e'), isFalse);
      expect(finds('a91c0b'), isFalse, reason: 'the start of the hash only');
      expect(BankQuestion.matchesIdQuery('s1_3fa91c', 's1'), isFalse);
    });

    test('what cannot be an ID is no query: too short, not hex, empty', () {
      expect(BankQuestion.idQueryOf('3fa91'), isNull);
      expect(BankQuestion.idQueryOf('#xyz123'), isNull);
      expect(BankQuestion.idQueryOf(''), isNull);
      expect(BankQuestion.idQueryOf('#'), isNull);
      expect(BankQuestion.idQueryOf('s1_'), isNull);
      expect(BankQuestion.idQueryOf('#3FA91C'), '3fa91c');
    });
  });
}
