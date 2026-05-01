// Reference test for the Conductor — the brain that picks question types,
// computes progress deltas, adapts difficulty, and advances goals. The
// Conductor reads/writes through `DataService` (a `get_it` locator), so the
// test pattern is: register service mocks under the *interface* type, plumb
// real `ValueNotifier`s through stubbed getters so `notifier.value = x`
// writes work as in production, then exercise the public API and verify the
// observable side effects (`progress.upsert`, `chat.addSystemMessage`,
// `splash.showGoalReached`, `sound.*`).

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

  group('updateProgress — delta computation', () {
    test('correct on default (no question type set, easy, 0 hints) bumps by '
        'baseDelta(0.14) × typeMult(1.0) × diffMult(0.8) = 0.112', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      await c.updateProgress(AnswerQuality.correct);

      // Only the child upserts — no root upsert because selectedRootGoal is
      // null (parent recompute is gated on that).
      final captured = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      expect(captured, hasLength(1));
      expect(captured.single.goalID, 'child-1');
      expect(captured.single.progress, closeTo(0.112, 1e-9));
      expect(currentProgress.value, closeTo(0.112, 1e-9));
      verify(() => sound.correctAnswer()).called(1);
    });

    test('wrong delta clamps at 0.0 instead of going negative', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      await Conductor().updateProgress(AnswerQuality.wrong);

      final p = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .single as Progress;
      expect(p.progress, 0.0);
      verifyNever(() => sound.correctAnswer());
    });

    test('hints dampen a positive delta but cannot flip its sign', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor()
        ..hintProvided()
        ..hintProvided();
      await c.updateProgress(AnswerQuality.correct);

      // 0.14 × 1.0 × 0.8 = 0.112 ; hintPenalty = 0.02 × 2 = 0.04 → 0.072
      final p = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .single as Progress;
      expect(p.progress, closeTo(0.072, 1e-9));
    });

    test('hint counter resets after each updateProgress call', () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor()
        ..hintProvided()
        ..hintProvided();
      await c.updateProgress(AnswerQuality.correct); // 0.072 (with penalty)
      await c.updateProgress(AnswerQuality.correct); // 0.112 (no penalty)

      final captured = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      expect(captured[0].progress, closeTo(0.072, 1e-9));
      expect(captured[1].progress, closeTo(0.072 + 0.112, 1e-9));
    });
  });

  group('updateProgress — difficulty adaptation window', () {
    test('4 correct in a row bumps difficulty up and emits a system message',
        () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      for (var i = 0; i < 4; i++) {
        await c.updateProgress(AnswerQuality.correct);
      }

      // Exactly one "easy → medium" message after the 4th correct.
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

  group('updateProgress — parent recompute', () {
    test('upserts child first, then root with average of children\' '
        'pre-update progress (representative of read-back-from-Cosmos)',
        () async {
      selectedRoot.value = makeGoal('root-1');
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      when(() => goals.getChildrenOnce('root-1'))
          .thenAnswer((_) async => [makeGoal('child-1'), makeGoal('child-2')]);
      when(() => progress.getByGoalId('child-1')).thenAnswer(
        (_) async => Progress(goalID: 'child-1', progress: 0.4),
      );
      when(() => progress.getByGoalId('child-2')).thenAnswer(
        (_) async => Progress(goalID: 'child-2', progress: 0.0),
      );

      // partial: 0.07 × 1.0 × 0.8 = 0.056
      await Conductor().updateProgress(AnswerQuality.partial);

      final captured = verify(() => progress.upsert(captureAny<Progress>()))
          .captured
          .cast<Progress>();
      expect(captured, hasLength(2));
      expect(captured[0].goalID, 'child-1');
      expect(captured[0].progress, closeTo(0.056, 1e-9));
      expect(captured[1].goalID, 'root-1');
      // root avg = (child-1.read=0.4 + child-2.read=0.0) / 2 = 0.2
      expect(captured[1].progress, closeTo(0.2, 1e-9));
    });
  });

  group('updateProgress — goal completion', () {
    test('crossing 1.0 fires splash + goal-reached sound and clears '
        'selected goals (when the next-target search finds nothing)',
        () async {
      selectedRoot.value = makeGoal('root-1');
      selectedChild.value = makeGoal('child-1', title: 'Lussen');
      currentProgress.value = 0.95; // any positive delta crosses 1.0

      final followUp =
          await Conductor().updateProgress(AnswerQuality.correct);

      verify(
        () => splash.showGoalReached(
          goalTitle: 'Lussen',
          description: any<String>(named: 'description'),
        ),
      ).called(1);
      verify(() => sound.playGoalReached()).called(1);

      // Crossing the 1.0 milestone makes followUp deterministically false:
      // _rollFollowUpAllowance(false) returns false on both random branches.
      expect(followUp, isFalse);

      // _setTargetGoal cleared the selection and reset the progress notifier.
      expect(selectedChild.value, isNull);
      expect(selectedRoot.value, isNull);
      expect(currentProgress.value, 0.0);
    });
  });

  group('getNextQuestion', () {
    test('progress < 0.2 → guidingQuestion', () {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.1;

      final (type, difficulty) = Conductor().getNextQuestion();

      expect(type, ChatRequestType.guidingQuestion);
      expect(difficulty, QuestionDifficulty.easy);
    });

    test('no selected or preferred child → noResult', () {
      final (type, _) = Conductor().getNextQuestion();
      expect(type, ChatRequestType.noResult);
    });
  });

  group('guidingIsComplete', () {
    test('accumulates understanding, displays understanding/5 mid-flow, '
        'jumps to 0.2 and plays the chime when the running sum reaches 0.8',
        () async {
      selectedChild.value = makeGoal('child-1');
      currentProgress.value = 0.0;

      final c = Conductor();
      expect(await c.guidingIsComplete(0.5), isFalse);
      expect(currentProgress.value, closeTo(0.5 / 5, 1e-9));

      expect(await c.guidingIsComplete(0.4), isTrue);
      expect(currentProgress.value, closeTo(0.2, 1e-9));
      verify(() => sound.guidingComplete()).called(1);
    });
  });
}
