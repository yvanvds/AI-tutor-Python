import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  final chatService = ChatService();
  ref.onDispose(() {
    chatService.dispose();
  });
  return chatService;
});

class ChatService {
  final ChatController controller = InMemoryChatController();
  int _id = 0;

  void addMessage(String text) {
    _id++;
    controller.insertMessage(
      TextMessage(id: _id.toString(), text: text, authorId: 'You'),
    );
  }

  void addTutorMessage(String text) {
    _id++;
    controller.insertMessage(
      TextMessage(id: _id.toString(), text: text, authorId: 'Teacher'),
    );
  }

  void addSystemMessage(String text) {
    _id++;
    controller.insertMessage(
      SystemMessage(id: _id.toString(), text: text, authorId: 'system'),
    );
  }

  void clear() {
    _id = 0;
    controller.setMessages([]);
  }

  void dispose() => controller.dispose();

  Future<void> addSystem(String text) async {}
}
