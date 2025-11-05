/// Who sent a message.
enum MessageRole { system, user, ai }

class MessageEntry {
  final MessageRole role;
  final String text;

  const MessageEntry({required this.role, required this.text});
}
