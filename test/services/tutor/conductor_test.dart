// Tests for the mastery-streak Conductor. A subgoal is mastered when the
// student answers correctly `_streakNeeded` times in a row across at least
// `_distinctTypesNeeded` different question types. Mastery triggers a
// fast-forward diagnostic on the next subgoal.
//
// The Conductor talks to the rest of the app through `DataService` (a
// `get_it` locator), so each test registers service mocks under the
// interface type, plumbs real `ValueNotifier`s through stubbed getters, and
// verifies observable side effects (`progress.upsert`,
// `chat.addSystemMessage`, `splash.showGoalReached`, `sound.*`).

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/progress.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/sound/sound_service.dart';
import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/locator.dart';
import '../../helpers/mocks.dart';

class _FakeProgress extends Fake implements Progress {}

void main() {
  late MockGoalsService goals;
  late MockProgressService progress;
  late MockChatService chat;
  late MockSoundService sound;
  late MockSplashService splash;

  late ValueNotifier<Goal?> selectedRoot;
  late ValueNotifier<Goal?> selectedChild;
  late ValueNotifier<Goal?> preferredRoot;
  late ValueNotifier<Goal?> preferredChild;
  late ValueNotifier<double> currentProgress;

  Goal makeGoal(String id, {String? title, int order = 1000}) =>
      Goal(id: id, title: title ?? id, order: order);

  setUpAll(() {
    registerFallbackValue(_FakeProgress());
  });

  setUp(() {
    goals = MockGoalsService();
    progress = MockProgressService();
    chat = MockChatService();
    sound = MockSoundService();
    splash = MockSplashService();

    selectedRoot = ValueNotifier<Goal?>(null);
    selectedChild = ValueNotifier<Goal?>(null);
    preferredRoot = ValueNotifier<Goal?>(null);
    preferredChild = ValueNotifier<Goal?>(null);
    currentProgress = ValueNotifier<double>(0.0);

    when(() => goals.selectedRootGoal).thenReturn(selectedRoot);
    when(() => goals.selectedChildGoal).thenReturn(selectedChild);
    when(() => goals.preferredRootGoal).thenReturn(preferredRoot);
    when(() => goals.preferredChildGoal).thenReturn(preferredChild);
    when(() => progress.currentProgress).thenReturn(currentProgress);

    when(() => progress.upsert(any<Progress>())).thenAnswer((_) async {});
    when(() => progress.getAll()).thenAnswer((_) async => <Progress>[]);
    when(() => progress.getByGoalId(any<String>()))
        .thenAnswer((_) async => null);
    when(() => goals.getRootGoalsOnce()).thenAnswer((_) async => <Goal>[]);
    when(() => goals.getChildrenOnce(any<String>()))
        .thenAnswer((_) async => <Goal>[]);
    when(() => sound.correctAnswer()).thenAnswer((_) async {});
    when(() => sound.playGoalReached()).thenAnswer((_) async {});
    when(() => sound.guidingComplete()).thenAnswer((_) async {});

    registerMock<GoalsService>(goals);
    registerMock<ProgressService>(progress);
    registerMock<ChatService>(chat);
    registerMock<SoundService>(sound);
    registerMock<SplashService>(splash);
  });

  tearDown(() async {
    await resetLocator();
    selectedRoot.dispose();
    selectedChild.dispose();
    preferredRoot.dispose();
    preferredChild.dispose();
    currentProgress.dispose();
  });

  /// Drives the Conductor through guiding so practice can begin. The
  /// guiding phase completes once the running confidence sum reaches 0.8.
  Future<void> completeGuiding(Conductor c) async {
    c.getNextQuestion(); // sets _currentQuestionType to guidingQuestion
    await c.guidingIsComplete(0.8);
  }

  /// Records a correct answer for [type] on [c]. Caller is responsible for
  /// having selected a child goal first.
  Future<void> answerCorrect(Conductor c, ChatRequestType type) async {
    // Force the question-type record by advancing through getNextQuestion
    // until we hit [type]. A simpler approach: poke the field via a
    // round-trip — but the Conductor doesn't expose it, so we drive
    // updateProgress while pretending the just-issued question was [type].
    // The Conductor's updateProgress reads `_currentQuestionType` set by
    // getNextQuestion; we reach the desired type by calling getNextQuestion
    // until it returns it.
    var safety = 20;
    while (safety-- > 0) {
      final (got, _) = c.getNextQuestion();
      if (got == type) break;
    }
    await c.updateProgress(AnswerQuality.correct);
  }

  group('getNextQuestion', () {
    test('no selected or preferred child → noResult', () {
      final (type, _) = Conductor().getNextQuestion();
      expect(type, ChatRequestType.noResult);
    });

    test('fresh subgoal (no persisted progress) → guidingQuestion', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      final (type, difficulty) = c.getNextQuestion();
      expect(type, ChatRequestType.guidingQuestion);
      expect(difficulty, QuestionDifficulty.easy);
    });

    test('after guiding completes, picks from practice types and avoids '
        'back-to-back repeats', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      const practice = {
        ChatRequestType.mcQuestion,
        ChatRequestType.explainCodeQuestion,
        ChatRequestType.completeCodeQuestion,
        ChatRequestType.socraticQuestion,
        ChatRequestType.writeCodeQuestion,
      };

      final first = c.getNextQuestion().$1;
      expect(practice, contains(first));
      // Run a few more picks; none should ever repeat the immediately
      // previous type.
      var prev = first;
      for (var i = 0; i < 10; i++) {
        final next = c.getNextQuestion().$1;
        expect(practice, contains(next));
        expect(next, isNot(prev));
        prev = next;
      }
    });
  });

  group('guidingIsComplete', () {
    test('accumulates confidence; returning true once the running sum '
        'reaches 0.8 plays the chime and persists the post-guiding marker',
        () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      expect(await c.guidingIsComplete(0.5), isFalse);
      expect(await c.guidingIsComplete(0.4), isTrue);

      verify(() => sound.guidingComplete()).called(1);
      // Last upsert reflects the post-guiding marker (display = 0.05).
      final upserts = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      expect(upserts.last.goalID, 'child-1');
      expect(upserts.last.progress, closeTo(0.05, 1e-9));
      expect(currentProgress.value, closeTo(0.05, 1e-9));
    });
  });

  group('updateProgress — streak progression', () {
    test('a single correct answer after guiding bumps display to 1/3 and '
        'persists it', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);
      // Clear earlier captures.
      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>())).thenAnswer((_) async {});

      c.getNextQuestion(); // sets _currentQuestionType to a practice type
      await c.updateProgress(AnswerQuality.correct);

      final captured = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      expect(captured.single.goalID, 'child-1');
      expect(captured.single.progress, closeTo(1.0 / 3.0, 1e-9));
      expect(currentProgress.value, closeTo(1.0 / 3.0, 1e-9));
    });

    test('wrong answer resets the streak (display drops back to the '
        'guiding-done marker)', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct); // 1/3
      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>())).thenAnswer((_) async {});

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.wrong);

      final captured = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      expect(captured.single.progress, closeTo(0.05, 1e-9));
    });

    test('partial answer holds ground (no streak change, no upsert change)',
        () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct); // 1/3
      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>())).thenAnswer((_) async {});

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.partial);

      final captured = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      // Still 1/3 — partial neither advances nor resets.
      expect(captured.single.progress, closeTo(1.0 / 3.0, 1e-9));
    });
  });

  group('updateProgress — mastery', () {
    test('3 correct answers across 2 distinct question types triggers '
        'mastery: persists 1.0, fires goal-reached, and clears selection '
        'when no further subgoal is found', () async {
      selectedRoot.value = makeGoal('root-1');
      selectedChild.value = makeGoal('child-1', title: 'Variabelen');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      // Drive question types so the streak hits 2 distinct types.
      await answerCorrect(c, ChatRequestType.mcQuestion);
      await answerCorrect(c, ChatRequestType.explainCodeQuestion);
      // The 3rd correct can be on any type; reuse mc to confirm types-set
      // (already 2 distinct) is sufficient.
      await answerCorrect(c, ChatRequestType.mcQuestion);

      verify(
        () => splash.showGoalReached(
          goalTitle: 'Variabelen',
          description: any<String>(named: 'description'),
        ),
      ).called(1);
      verify(() => sound.playGoalReached()).called(1);

      // 1.0 was persisted for the child.
      final upserts = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      expect(
        upserts.any((p) => p.goalID == 'child-1' && p.progress == 1.0),
        isTrue,
      );

      // No further subgoal → selection cleared and notifier reset.
      expect(selectedChild.value, isNull);
      expect(selectedRoot.value, isNull);
      expect(currentProgress.value, 0.0);
    });

    test('3 corrects on a SINGLE type does not yet master (distinct-types '
        'requirement not met)', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      // Force the same question type three times.
      for (var i = 0; i < 3; i++) {
        await answerCorrect(c, ChatRequestType.mcQuestion);
      }

      verifyNever(
        () => splash.showGoalReached(
          goalTitle: any<String>(named: 'goalTitle'),
          description: any<String>(named: 'description'),
        ),
      );
    });

    test('once the streak reaches threshold without distinct-types, '
        'updateProgress denies the follow-up so the caller fetches a new '
        'exercise of a different type', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      Future<bool> correctOn(ChatRequestType type) async {
        var safety = 20;
        while (safety-- > 0) {
          final (got, _) = c.getNextQuestion();
          if (got == type) break;
        }
        return c.updateProgress(AnswerQuality.correct);
      }

      // Streak 1 and 2 on a single type may still allow follow-ups.
      await correctOn(ChatRequestType.mcQuestion);
      await correctOn(ChatRequestType.mcQuestion);
      // Streak 3 on a single type: mastery can't fire yet, so the follow-up
      // must be denied to force a new question type.
      final allowedAtThree = await correctOn(ChatRequestType.mcQuestion);
      expect(allowedAtThree, isFalse);
    });
  });

  group('updateProgress — fast-forward diagnostic', () {
    test('after mastery, getNextQuestion returns a writeCodeQuestion at '
        'medium for the new subgoal (the diagnostic)', () async {
      selectedRoot.value = makeGoal('root-1');
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      // After child-1 is mastered, advance to child-2 under the same root.
      when(() => goals.getRootGoalsOnce())
          .thenAnswer((_) async => [makeGoal('root-1')]);
      when(() => goals.getChildrenOnce('root-1')).thenAnswer(
        (_) async => [makeGoal('child-1'), makeGoal('child-2')],
      );
      when(() => progress.getAll()).thenAnswer(
        (_) async => [
          // child-1 is mastered (1.0); child-2 is fresh (0.0).
          Progress(goalID: 'child-1', progress: 1.0),
        ],
      );

      final c = Conductor();
      await completeGuiding(c);

      await answerCorrect(c, ChatRequestType.mcQuestion);
      await answerCorrect(c, ChatRequestType.explainCodeQuestion);
      await answerCorrect(c, ChatRequestType.mcQuestion);

      // After advancement, child-2 is the new active subgoal; the next
      // question must be a diagnostic.
      expect(selectedChild.value?.id, 'child-2');

      final (type, difficulty) = c.getNextQuestion();
      expect(type, ChatRequestType.writeCodeQuestion);
      expect(difficulty, QuestionDifficulty.medium);
    });

    test('correct diagnostic answer fast-forwards: marks the new subgoal '
        'mastered too and fires goal-reached again', () async {
      selectedRoot.value = makeGoal('root-1');
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      // Three child goals — the diagnostic on child-2 should fast-forward
      // to child-3.
      when(() => goals.getRootGoalsOnce())
          .thenAnswer((_) async => [makeGoal('root-1')]);
      when(() => goals.getChildrenOnce('root-1')).thenAnswer(
        (_) async => [
          makeGoal('child-1'),
          makeGoal('child-2'),
          makeGoal('child-3'),
        ],
      );
      // Track which children are mastered as the test progresses.
      final mastered = <String>{};
      when(() => progress.getAll()).thenAnswer(
        (_) async => mastered
            .map((id) => Progress(goalID: id, progress: 1.0))
            .toList(),
      );
      when(() => progress.upsert(any<Progress>())).thenAnswer((inv) async {
        final p = inv.positionalArguments.first as Progress;
        if (p.progress >= 1.0) mastered.add(p.goalID);
      });

      final c = Conductor();
      await completeGuiding(c);

      // Master child-1.
      await answerCorrect(c, ChatRequestType.mcQuestion);
      await answerCorrect(c, ChatRequestType.explainCodeQuestion);
      await answerCorrect(c, ChatRequestType.mcQuestion);
      expect(selectedChild.value?.id, 'child-2');

      // Diagnostic question on child-2.
      final (diag, _) = c.getNextQuestion();
      expect(diag, ChatRequestType.writeCodeQuestion);

      // Student aces it → child-2 is mastered without practice; advances
      // to child-3.
      await c.updateProgress(AnswerQuality.correct);

      expect(mastered, containsAll(['child-1', 'child-2']));
      expect(selectedChild.value?.id, 'child-3');

      // Two goal-reached events: one for child-1, one for child-2.
      verify(
        () => splash.showGoalReached(
          goalTitle: any<String>(named: 'goalTitle'),
          description: any<String>(named: 'description'),
        ),
      ).called(2);
    });

    test('wrong diagnostic answer cancels the fast-forward and falls back '
        'to guiding on the new subgoal', () async {
      selectedRoot.value = makeGoal('root-1');
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      when(() => goals.getRootGoalsOnce())
          .thenAnswer((_) async => [makeGoal('root-1')]);
      when(() => goals.getChildrenOnce('root-1')).thenAnswer(
        (_) async => [makeGoal('child-1'), makeGoal('child-2')],
      );
      when(() => progress.getAll()).thenAnswer(
        (_) async => [Progress(goalID: 'child-1', progress: 1.0)],
      );

      final c = Conductor();
      await completeGuiding(c);

      await answerCorrect(c, ChatRequestType.mcQuestion);
      await answerCorrect(c, ChatRequestType.explainCodeQuestion);
      await answerCorrect(c, ChatRequestType.mcQuestion);
      expect(selectedChild.value?.id, 'child-2');

      // Diagnostic.
      final (diag, _) = c.getNextQuestion();
      expect(diag, ChatRequestType.writeCodeQuestion);

      // Student gets it wrong — fall back to normal guiding flow.
      await c.updateProgress(AnswerQuality.wrong);

      // Next question on child-2 is a guidingQuestion, not another
      // diagnostic.
      final (next, _) = c.getNextQuestion();
      expect(next, ChatRequestType.guidingQuestion);
    });
  });

  group('updateProgress — difficulty adaptation window', () {
    test('4 correct in a row bumps difficulty up and emits a system message',
        () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      for (var i = 0; i < 4; i++) {
        c.getNextQuestion();
        await c.updateProgress(AnswerQuality.correct);
      }

      verify(
        () => chat.addSystemMessage(
          any<String>(
            that: predicate<String>(
              (s) =>
                  s.contains('Moeilijkheid') &&
                  s.contains('easy') &&
                  s.contains('medium'),
            ),
          ),
        ),
      ).called(1);
    });
  });

  group('parent recompute', () {
    test('a single-child correct upserts both child progress and the root '
        'average', () async {
      selectedRoot.value = makeGoal('root-1');
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      when(() => goals.getChildrenOnce('root-1')).thenAnswer(
        (_) async => [makeGoal('child-1'), makeGoal('child-2')],
      );
      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(goalID: 'child-1', progress: 1.0 / 3.0),
      );
      when(() => progress.getByGoalId('child-2')).thenAnswer(
        (_) async => Progress(goalID: 'child-2', progress: 0.0),
      );

      final c = Conductor();
      await completeGuiding(c);
      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>())).thenAnswer((_) async {});
      when(() => goals.getChildrenOnce('root-1')).thenAnswer(
        (_) async => [makeGoal('child-1'), makeGoal('child-2')],
      );
      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(goalID: 'child-1', progress: 1.0 / 3.0),
      );
      when(() => progress.getByGoalId('child-2')).thenAnswer(
        (_) async => Progress(goalID: 'child-2', progress: 0.0),
      );

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);

      final captured = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      // First write: child-1 at 1/3. Second: root average from re-read
      // values (1/3 and 0) = 1/6.
      expect(captured[0].goalID, 'child-1');
      expect(captured[0].progress, closeTo(1.0 / 3.0, 1e-9));
      expect(captured[1].goalID, 'root-1');
      expect(captured[1].progress, closeTo(1.0 / 6.0, 1e-9));
    });
  });

  group('setTarget — resume from persisted progress', () {
    test('persisted 0.66 recovers `_correctStreak = 2` and skips guiding so '
        'the next question comes from the practice pool', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.66;
      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(goalID: 'child-1', progress: 0.66),
      );
      // setTarget calls _setTargetGoal only if no preferredChildGoal *and*
      // it would clear selectedChild — give it a no-result root list so it
      // leaves the test's selection alone via the preferred path.
      preferredChild.value = makeGoal('child-1');
      preferredRoot.value = makeGoal('root-1');

      final c = Conductor();
      await c.setTarget();

      final (type, _) = c.getNextQuestion();
      expect(type, isNot(ChatRequestType.guidingQuestion));
    });
  });
}
