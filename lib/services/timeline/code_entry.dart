import 'package:ai_tutor_python/services/timeline/message_entry.dart';

class CodeEntry {
  String code;
  final List<MessageEntry> messages = [];

  CodeEntry({required this.code});

  void addMessage(MessageEntry message) {
    messages.add(message);
  }
}
