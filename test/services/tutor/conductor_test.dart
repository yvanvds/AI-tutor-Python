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
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/progress/concept_attribution.dart';
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

class _FakeGoal extends Fake implements Goal {}

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
    registerFallbackValue(_FakeGoal());
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

    when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});
    when(() => progress.getAll()).thenAnswer((_) async => <Progress>[]);
    when(() => progress.getByGoalId(any<String>()))
        .thenAnswer((_) async => null);
    when(() => goals.getRootGoalsOnce()).thenAnswer((_) async => <Goal>[]);
    when(() => goals.getChildrenOnce(any<String>()))
        .thenAnswer((_) async => <Goal>[]);
    when(() => goals.getKnownConceptsInScope(any<Goal>()))
        .thenAnswer((_) async => <String>[]);
    when(() => sound.correctAnswer()).thenAnswer((_) async {});
    when(() => sound.playGoalReached()).thenAnswer((_) async {});
    when(() => sound.guidingComplete()).thenAnswer((_) async {});

    registerMock<GoalsService>(goals);
    registerMock<ProgressService>(progress);
    registerMock<ChatService>(chat);
    registerMock<SoundService>(sound);
    registerMock<SplashService>(splash);
    registerMock<DebugSessionRecorder>(DebugSessionRecorder());
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
      final upserts = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
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
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      c.getNextQuestion(); // sets _currentQuestionType to a practice type
      await c.updateProgress(AnswerQuality.correct);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
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
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.wrong);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
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
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.partial);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
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
      final upserts = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
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
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((inv) async {
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
    test('4 corrects on a single type (no mastery, so the active subgoal '
        'never resets) bumps difficulty up and emits a system message',
        () async {
      // Staying on one question type keeps `_typesInStreak` size = 1, so
      // mastery never fires, the goal never advances, and `_difficulty` /
      // `_answerHistory` keep accumulating across the four answers.
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await completeGuiding(c);

      for (var i = 0; i < 4; i++) {
        await answerCorrect(c, ChatRequestType.mcQuestion);
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
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});
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

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
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

  group('setTarget — adaptive warm-up', () {
    /// Stubs `progress.getByGoalId('child-1')` to return a doc that sets
    /// the conductor up for warm-up evaluation, and selects child-1 as the
    /// preferred goal so `setTarget` skips `_setTargetGoal()`.
    void stubResumeOnChild1({
      required double persistedProgress,
      required List<AnswerQuality> recentAnswers,
      required Duration sessionAge,
      QuestionDifficulty difficulty = QuestionDifficulty.easy,
    }) {
      selectedChild.value = makeGoal('child-1');
      preferredChild.value = makeGoal('child-1');
      preferredRoot.value = makeGoal('root-1');
      currentProgress.value = persistedProgress;
      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(
          goalID: 'child-1',
          progress: persistedProgress,
          difficulty: difficulty,
          recentAnswers: recentAnswers,
          lastSessionAt: DateTime.now().toUtc().subtract(sessionAge),
        ),
      );
    }

    test('progress < 0.5 → no warm-up, even with a populated history and a '
        'stale lastSessionAt', () async {
      stubResumeOnChild1(
        persistedProgress: 0.3,
        recentAnswers: const [
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.partial,
        ],
        sessionAge: const Duration(days: 30),
      );

      final c = Conductor();
      await c.setTarget();

      expect(c.isInWarmup, isFalse);
    });

    test('recent session (≤ 12h) → no warm-up regardless of history', () async {
      stubResumeOnChild1(
        persistedProgress: 0.66,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
        ],
        sessionAge: const Duration(hours: 1),
      );

      final c = Conductor();
      await c.setTarget();

      expect(c.isInWarmup, isFalse);
    });

    test('success ratio ≥ 0.8 → 1 warm-up question; correct answer leaves '
        'progress unchanged, the next correct answer increments it normally',
        () async {
      // Persisted 2/3 → recovered streak = 2. A non-warm-up correct would
      // push streak → 3 (display 1.0); a warm-up correct must hold at 2/3.
      stubResumeOnChild1(
        persistedProgress: 2.0 / 3.0,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.partial, // ratio = 4.5/5 = 0.9 → 1 question
        ],
        sessionAge: const Duration(days: 1),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      // Warm-up correct: streak unchanged, progress stays at 2/3.
      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);
      expect(c.isInWarmup, isFalse);

      var captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      expect(captured.last.progress, closeTo(2.0 / 3.0, 1e-9));

      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      // Normal correct: streak hits 3 (display = 1.0).
      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);

      captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      expect(captured.last.progress, closeTo(1.0, 1e-9));
    });

    test('success ratio in [0.5, 0.8) → 2 warm-up questions', () async {
      stubResumeOnChild1(
        persistedProgress: 2.0 / 3.0,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.wrong,
          AnswerQuality.wrong, // ratio = 3/5 = 0.6 → 2 questions
        ],
        sessionAge: const Duration(days: 1),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);
      expect(c.isInWarmup, isTrue);

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);
      expect(c.isInWarmup, isFalse);
    });

    test('success ratio < 0.5 → 3 warm-up questions', () async {
      stubResumeOnChild1(
        persistedProgress: 2.0 / 3.0,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.partial, // ratio = 1.5/5 = 0.3 → 3 questions
        ],
        sessionAge: const Duration(days: 1),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      for (var i = 0; i < 3; i++) {
        c.getNextQuestion();
        await c.updateProgress(AnswerQuality.correct);
        if (i < 2) expect(c.isInWarmup, isTrue);
      }
      expect(c.isInWarmup, isFalse);
    });

    test('history length < 2 → defaults to 1 warm-up question', () async {
      stubResumeOnChild1(
        persistedProgress: 0.66,
        recentAnswers: const [AnswerQuality.correct],
        sessionAge: const Duration(days: 1),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);
      expect(c.isInWarmup, isFalse);
    });

    test('stale session (>14 days) adds +1 to the warm-up count', () async {
      // Ratio = 0.9 → base 1; stale → 2 total.
      stubResumeOnChild1(
        persistedProgress: 2.0 / 3.0,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.partial,
        ],
        sessionAge: const Duration(days: 30),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);
      expect(c.isInWarmup, isTrue); // bonus question still pending

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);
      expect(c.isInWarmup, isFalse);
    });

    test('stale-session bonus is capped at 3 (low ratio + stale stays at 3, '
        'not 4)', () async {
      stubResumeOnChild1(
        persistedProgress: 2.0 / 3.0,
        recentAnswers: const [
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.wrong,
          AnswerQuality.wrong, // ratio 0 → base 3
        ],
        sessionAge: const Duration(days: 30),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      // Three answers exhaust warm-up; a fourth should not.
      for (var i = 0; i < 3; i++) {
        c.getNextQuestion();
        await c.updateProgress(AnswerQuality.correct);
      }
      expect(c.isInWarmup, isFalse);
    });

    test('correct warm-up answer leaves progress unchanged but appends to '
        'recentAnswers and runs difficulty adaptation', () async {
      stubResumeOnChild1(
        persistedProgress: 2.0 / 3.0,
        difficulty: QuestionDifficulty.easy,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
        ],
        sessionAge: const Duration(days: 1),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final upsert = captured.firstWhere((p) => p.goalID == 'child-1');

      // Streak suppressed → progress stays at 2/3.
      expect(upsert.progress, closeTo(2.0 / 3.0, 1e-9));
      // History grew to 5, all corrects → bumps difficulty to medium.
      expect(upsert.recentAnswers, hasLength(5));
      expect(
        upsert.recentAnswers.every((q) => q == AnswerQuality.correct),
        isTrue,
      );
      expect(upsert.difficulty, QuestionDifficulty.medium);
    });

    test('wrong warm-up answer applies the normal negative delta (display '
        'drops to the guiding-done marker)', () async {
      stubResumeOnChild1(
        persistedProgress: 2.0 / 3.0,
        recentAnswers: const [
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.correct,
          AnswerQuality.partial,
        ],
        sessionAge: const Duration(days: 1),
      );

      final c = Conductor();
      await c.setTarget();
      expect(c.isInWarmup, isTrue);

      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.wrong);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final upsert = captured.firstWhere((p) => p.goalID == 'child-1');
      // Streak reset → display drops to the guiding-done marker.
      expect(upsert.progress, closeTo(0.05, 1e-9));
    });

    test('a freshly-advanced subgoal (no persisted progress) does not enter '
        'warm-up', () async {
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
      // child-2 has no persisted doc — getByGoalId default returns null.

      final c = Conductor();
      await completeGuiding(c);
      await answerCorrect(c, ChatRequestType.mcQuestion);
      await answerCorrect(c, ChatRequestType.explainCodeQuestion);
      await answerCorrect(c, ChatRequestType.mcQuestion);

      expect(selectedChild.value?.id, 'child-2');
      expect(c.isInWarmup, isFalse);
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

    test('persisted difficulty + recentAnswers survive a fresh Conductor: '
        'one more correct on a 4-correct medium window pushes to hard, and '
        'the upserted Progress carries the trimmed window forward',
        () async {
      // Simulate a relaunch on a subgoal that was already calibrated to
      // medium with four corrects in the window.
      selectedChild.value = makeGoal('child-1');
      preferredChild.value = makeGoal('child-1');
      preferredRoot.value = makeGoal('root-1');
      currentProgress.value = 0.05;

      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(
          goalID: 'child-1',
          progress: 0.05,
          difficulty: QuestionDifficulty.medium,
          recentAnswers: const [
            AnswerQuality.correct,
            AnswerQuality.correct,
            AnswerQuality.correct,
            AnswerQuality.correct,
          ],
        ),
      );

      final c = Conductor();
      await c.setTarget();

      // Difficulty is recovered, so the next practice question is medium.
      final (_, difficultyBefore) = c.getNextQuestion();
      expect(difficultyBefore, QuestionDifficulty.medium);

      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});
      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(
          goalID: 'child-1',
          progress: 0.05,
          difficulty: QuestionDifficulty.medium,
          recentAnswers: const [
            AnswerQuality.correct,
            AnswerQuality.correct,
            AnswerQuality.correct,
            AnswerQuality.correct,
          ],
        ),
      );

      // One more correct: window becomes 5 corrects → bump to hard.
      await c.updateProgress(AnswerQuality.correct);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final childUpsert =
          captured.firstWhere((p) => p.goalID == 'child-1');
      expect(childUpsert.difficulty, QuestionDifficulty.hard);
      expect(childUpsert.recentAnswers, hasLength(5));
      expect(
        childUpsert.recentAnswers.every((q) => q == AnswerQuality.correct),
        isTrue,
      );
    });
  });

  group('recordConceptAttributions', () {
    /// Sets up a conductor where child-1 is the active subgoal under
    /// root-2; root-1 has earlier knownConcepts and root-2 has its own
    /// in-progress set.
    Future<Conductor> setupForAttributions({
      List<ConceptAttribution> existing = const [],
    }) async {
      selectedRoot.value = makeGoal('root-2', order: 2000);
      selectedChild.value = makeGoal('child-1');
      preferredRoot.value = makeGoal('root-2', order: 2000);
      preferredChild.value = makeGoal('child-1');
      currentProgress.value = 0.05;

      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(
          goalID: 'child-1',
          progress: 0.05,
          recentConceptAttributions: existing,
        ),
      );
      when(() => goals.getKnownConceptsInScope(any<Goal>())).thenAnswer(
        (_) async => ['variables', 'loops', 'conditionals'],
      );

      final c = Conductor();
      await c.setTarget();
      // Seed `_lastQuality` so attributions inherit a real value.
      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.wrong);
      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});
      return c;
    }

    test('null/empty input is a no-op (no upsert call)', () async {
      final c = await setupForAttributions();

      await c.recordConceptAttributions(null);
      await c.recordConceptAttributions(const []);

      verifyNever(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')));
    });

    test('valid concepts are appended with at + last quality and persisted',
        () async {
      final c = await setupForAttributions();

      await c.recordConceptAttributions(const ['variables', 'loops']);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final upsert = captured.firstWhere((p) => p.goalID == 'child-1');
      expect(upsert.recentConceptAttributions, hasLength(2));
      expect(
        upsert.recentConceptAttributions.map((a) => a.concept).toList(),
        ['variables', 'loops'],
      );
      // Quality matches the most recent updateProgress (wrong).
      expect(
        upsert.recentConceptAttributions
            .every((a) => a.quality == AnswerQuality.wrong),
        isTrue,
      );
      // `at` is recent.
      final now = DateTime.now().toUtc();
      for (final attr in upsert.recentConceptAttributions) {
        expect(now.difference(attr.at).inSeconds.abs(), lessThan(5));
      }
    });

    test('tags not in the validation set are dropped, accepted ones persist',
        () async {
      final c = await setupForAttributions();

      await c.recordConceptAttributions(
        const ['variables', 'definitely-not-a-concept', 'conditionals'],
      );

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final upsert = captured.firstWhere((p) => p.goalID == 'child-1');
      expect(
        upsert.recentConceptAttributions.map((a) => a.concept).toList(),
        ['variables', 'conditionals'],
      );
    });

    test('all-invalid input is a no-op (no upsert)', () async {
      final c = await setupForAttributions();

      await c.recordConceptAttributions(const ['nonsense']);

      verifyNever(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')));
    });

    test('trims to last 20 entries (oldest dropped)', () async {
      // Pre-seed 18 attributions; record 5 more → expect last 20.
      final at = DateTime.utc(2026, 4, 1);
      final existing = [
        for (var i = 0; i < 18; i++)
          ConceptAttribution(
            concept: 'old-$i',
            at: at,
            quality: AnswerQuality.partial,
          ),
      ];
      final c = await setupForAttributions(existing: existing);
      when(() => goals.getKnownConceptsInScope(any<Goal>())).thenAnswer(
        (_) async => ['n0', 'n1', 'n2', 'n3', 'n4'],
      );

      await c.recordConceptAttributions(
        const ['n0', 'n1', 'n2', 'n3', 'n4'],
      );

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final upsert = captured.firstWhere((p) => p.goalID == 'child-1');
      expect(upsert.recentConceptAttributions, hasLength(20));
      // Oldest 3 of the seeded 18 should have been trimmed.
      expect(
        upsert.recentConceptAttributions.first.concept,
        'old-3',
      );
      expect(upsert.recentConceptAttributions.last.concept, 'n4');
    });

    test('attribution carries the latest updateProgress quality (correct)',
        () async {
      final c = await setupForAttributions();
      // Override _lastQuality from the setup's wrong → correct.
      c.getNextQuestion();
      await c.updateProgress(AnswerQuality.correct);
      clearInteractions(progress);
      when(() => progress.upsert(any<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory'))).thenAnswer((_) async {});

      await c.recordConceptAttributions(const ['variables']);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final upsert = captured.firstWhere((p) => p.goalID == 'child-1');
      expect(
        upsert.recentConceptAttributions.single.quality,
        AnswerQuality.correct,
      );
    });

    test('persisted attributions survive a fresh Conductor on resume', () async {
      // Persisted state already has two attributions from a prior session.
      final at = DateTime.utc(2026, 4, 1);
      final existing = [
        ConceptAttribution(
          concept: 'variables',
          at: at,
          quality: AnswerQuality.wrong,
        ),
        ConceptAttribution(
          concept: 'loops',
          at: at,
          quality: AnswerQuality.partial,
        ),
      ];
      final c = await setupForAttributions(existing: existing);

      await c.recordConceptAttributions(const ['conditionals']);

      final captured = verify(() => progress.upsert(captureAny<Progress>(), quality: any(named: 'quality'), isWarmUp: any(named: 'isWarmUp'), recordHistory: any(named: 'recordHistory')))
          .captured
          .cast<Progress>();
      final upsert = captured.firstWhere((p) => p.goalID == 'child-1');
      expect(
        upsert.recentConceptAttributions.map((a) => a.concept).toList(),
        ['variables', 'loops', 'conditionals'],
      );
    });
  });
}
