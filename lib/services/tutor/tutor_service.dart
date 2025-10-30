import 'package:ai_tutor_python/data/account/account_providers.dart';
import 'package:ai_tutor_python/data/goal/goal.dart';
import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/data/instructions/instruction.dart';
import 'package:ai_tutor_python/data/progress/progress.dart';
import 'package:ai_tutor_python/data/progress/progress_providers.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/instruction_generator.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/tutor/question_formatter.dart';
import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tutorServiceProvider = Provider<TutorService>((ref) {
  final service = TutorService(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

enum ChatRequestType {
  generateExercise,
  submitCode,
  mcqAnswer,
  requestHint,
  studentQuestion,
  status,
}

class TutorService {
  final Ref ref;
  TutorService({required this.ref});

  Goal? _currentRootGoal;
  Goal? _currentChildGoal;

  InstructionGenerator get _instructionGenerator =>
      InstructionGenerator(ref: ref);

  final OpenaiConnector _connector = OpenaiConnector();

  // ---- Public API -----------------------------------------------------------

  Future<void> initializeSession() async {
    final chat = ref.read(chatServiceProvider);

    chat.clear();
    // Resolve name & target using stable snapshots
    final userName = await _getUserFirstName();
    final hasTarget = await _setTargetGoal(); // selects providers inside

    if (!hasTarget) {
      chat.addSystemMessage(
        "There are no goals available to work on. Have fun!",
      );
      return;
    }

    chat.addSystemMessage(
      "Hello $userName, your current goal is '${_currentChildGoal?.title}' (under root '${_currentRootGoal?.title}'). Let's get started!",
    );

    queryTutor(type: ChatRequestType.generateExercise, newSession: true);
  }

  /// Computes and selects the next target goal/subgoal.
  /// Returns true if a selection was made, false otherwise.
  Future<bool> _setTargetGoal() async {
    // Clear previous selection
    ref.read(selectedRootGoalProviderNotifier.notifier).select(null);
    ref.read(selectedChildGoalProviderNotifier.notifier).select(null);

    // Take stable snapshots
    final roots = await ref.read(rootGoalsProviderFuture.future); // List<Goal>
    final progressList = await ref.read(
      progressListProviderFuture.future,
    ); // List<Progress>

    double progressFor(Goal g) {
      final p = progressList.firstWhereOrNull((x) => x.goalID == g.id);
      return p?.progress ?? 0.0;
    }

    for (final root in roots) {
      if (progressFor(root) < 1.0) {
        // Load children for this root on demand (family provider)
        final subgoals = await ref.read(
          childGoalsByParentProviderFuture(root.id).future,
        );

        // Pick first incomplete subgoal (if any)
        final targetChild = subgoals.firstWhereOrNull(
          (g) => progressFor(g) < 1.0,
        );

        if (targetChild != null) {
          ref.read(selectedRootGoalProviderNotifier.notifier).select(root.id);
          ref
              .read(selectedChildGoalProviderNotifier.notifier)
              .select(targetChild.id);
          _currentRootGoal = root;
          _currentChildGoal = targetChild;
          return true;
        }
        // else: all children complete -> try next root
      }
    }

    // Nothing to select
    return false;
  }

  Future<void> queryTutor({
    required ChatRequestType type,
    String? code,
    String? question,
    bool? newSession,
  }) async {
    switch (type) {
      case ChatRequestType.generateExercise:
        if (newSession != null && newSession == true) {
          final instructions = await _instructionGenerator.generateInstructions(
            _currentRootGoal!,
            _currentChildGoal!,
          );
          final progress = await _getCurrentProgress();
          final result = await _connector.startSession(
            input: QuestionFormatter.generateExcercise(progress),
            instructions: instructions,
          );
          print(result);
        } else {
          final progress = await _getCurrentProgress();
          final result = await _connector.continueSession(
            input: QuestionFormatter.generateExcercise(progress),
          );
          print(result);
        }
        break;

      case ChatRequestType.submitCode:
        if (code == null) return;
        final progress = await _getCurrentProgress();
        final result = await _connector.continueSession(
          input: QuestionFormatter.submitCode(code, progress),
        );
        print(result);
        break;

      case ChatRequestType.mcqAnswer:
        if (question == null) return;
        final progress = await _getCurrentProgress();
        final result = await _connector.continueSession(
          input: QuestionFormatter.answerMcq(question, progress),
        );
        print(result);
        break;

      case ChatRequestType.requestHint:
        if (code == null) return;
        final progress = await _getCurrentProgress();
        final result = await _connector.continueSession(
          input: QuestionFormatter.askHint(code, progress),
        );
        print(result);
        break;

      case ChatRequestType.studentQuestion:
        if (question == null) return;
        final progress = await _getCurrentProgress();
        final result = await _connector.continueSession(
          input: QuestionFormatter.studentQuestion(question, progress, code),
        );
        print(result);
        break;

      case ChatRequestType.status:
        final result = await _connector.continueSession(
          input: QuestionFormatter.checkStatus(),
        );
        print(result);
        break;
    }
  }

  void dispose() {}

  // ---- Private helpers ------------------------------------------------------

  Future<String> _getUserFirstName() async {
    final acc = await ref.read(myAccountProviderFuture.future);
    return acc?.firstName ?? 'Student';
  }

  Future<double> _getCurrentProgress() async {
    final progress = await ref.read(
      progressByGoalProviderFuture(_currentChildGoal?.id ?? '').future,
    );

    if (progress == null) {
      return 0.0;
    } else {
      return progress.progress;
    }
  }

  Future<void> _updateProgress(double newProgress) async {
    if (_currentChildGoal == null) return;

    // 1) Upsert child
    await ref.read(
      upsertProgressProviderFuture(
        Progress(goalID: _currentChildGoal!.id, progress: newProgress),
      ).future,
    );

    if (_currentRootGoal == null) return;

    // 2) Read child goals under the current root (provider names are examples)
    final children = await ref.read(
      childGoalsByParentProviderFuture(_currentRootGoal!.id).future,
    );

    // 3) Sum each child’s progress (missing -> 0.0)
    double sum = 0.0;
    for (final g in children) {
      final p = await ref.read(
        progressByGoalProviderFuture(g.id).future,
      ); // Progress?
      sum += (p?.progress ?? 0.0);
    }
    final rootAvg = sum / children.length;

    // 4) Upsert root
    await ref.read(
      upsertProgressProviderFuture(
        Progress(goalID: _currentRootGoal!.id, progress: rootAvg),
      ).future,
    );
  }
}
