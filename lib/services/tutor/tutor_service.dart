import 'package:ai_tutor_python/data/goal/goal_providers.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tutorServiceProvider = Provider<TutorService>((ref) {
  final service = TutorService(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

class TutorService {
  final Ref ref;
  TutorService({required this.ref});

  void initializeSession() {
    final chat = ref.read(chatServiceProvider);
    chat.addSystemMessage("Welcome to your tutoring session!");

    final goalsAsync = ref.watch(rootGoalsProvider.future);
    goalsAsync.then((goals) {
      if (goals.isNotEmpty) {
        for (final goal in goals) {
          chat.addSystemMessage(goal.title);
        }
      } else {
        chat.addTutorMessage("It seems you have no learning goals set.");
      }
    });
  }

  void dispose() {}
}
