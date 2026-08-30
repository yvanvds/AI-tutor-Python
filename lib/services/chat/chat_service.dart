import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';

class ChatService {
  ChatService({
    void Function(StreamState)? onStreamStateChanged,
    void Function(bool)? onMcqPendingChanged,
  })  : _onStreamStateChanged = onStreamStateChanged,
        _onMcqPendingChanged = onMcqPendingChanged;

  final ChatController controller = InMemoryChatController();
  final void Function(StreamState)? _onStreamStateChanged;
  final void Function(bool)? _onMcqPendingChanged;

  int _id = 0;
  TextStreamMessage? _activeStream;

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

  /// Insert a system pill. The text is not chosen here: the notice travels
  /// on the message metadata and `ChatWidget` localizes it when it renders
  /// (issue #23).
  void addSystemNotice(ChatNotice notice) {
    _id++;
    controller.insertMessage(
      SystemMessage(
        id: _id.toString(),
        text: '',
        authorId: 'system',
        metadata: {ChatNotice.metadataKey: notice.toJson()},
      ),
    );
  }

  /// Insert a clickable multiple-choice options block.
  void addMcqOptions(List<String> options) {
    _id++;
    controller.insertMessage(
      CustomMessage(
        id: _id.toString(),
        authorId: 'Teacher',
        createdAt: DateTime.now(),
        metadata: {
          'kind': 'mcq_options',
          'options': options,
          'selected': null,
        },
      ),
    );
    _onMcqPendingChanged?.call(true);
  }

  /// Mark an mcq-options message as answered so its buttons rebuild as
  /// disabled with the picked one highlighted.
  void markMcqAnswered(CustomMessage message, String picked) {
    controller.updateMessage(
      message,
      message.copyWith(
        metadata: {...?message.metadata, 'selected': picked},
      ),
    );
    _onMcqPendingChanged?.call(false);
  }

  /// Start a streaming tutor message. Finalize with [completeStream] or [failStream].
  void startStream() {
    _id++;
    final message = TextStreamMessage(
      id: _id.toString(),
      authorId: 'Teacher',
      streamId: 's${_id.toString()}',
      createdAt: DateTime.now(),
    );
    _activeStream = message;
    _onStreamStateChanged?.call(const StreamStateLoading());
    controller.insertMessage(message);
  }

  void updateStream(String accumulatedText) {
    if (_activeStream == null) return;
    _onStreamStateChanged?.call(StreamStateStreaming(accumulatedText));
  }

  /// Replace the active streaming placeholder with a finalised text message.
  void completeStream(String finalText) {
    final placeholder = _activeStream;
    _activeStream = null;
    _onStreamStateChanged?.call(const StreamStateLoading());
    if (placeholder == null) return;
    if (finalText.trim().isEmpty) {
      controller.removeMessage(placeholder);
      return;
    }
    controller.updateMessage(
      placeholder,
      TextMessage(
        id: placeholder.id,
        text: finalText,
        authorId: 'Teacher',
        createdAt: placeholder.createdAt,
      ),
    );
  }

  /// Tear down the active stream after a transport error.
  void failStream() {
    final placeholder = _activeStream;
    _activeStream = null;
    _onStreamStateChanged?.call(const StreamStateLoading());
    if (placeholder != null) {
      controller.removeMessage(placeholder);
    }
  }

  void clear() {
    _id = 0;
    _activeStream = null;
    _onStreamStateChanged?.call(const StreamStateLoading());
    _onMcqPendingChanged?.call(false);
    controller.setMessages([]);
  }

  void dispose() => controller.dispose();
}

final streamStateProvider = StateProvider<StreamState>(
  (_) => const StreamStateLoading(),
);

final mcqPendingProvider = StateProvider<bool>((_) => false);

final chatServiceProvider = Provider<ChatService>((ref) {
  final cs = ChatService(
    onStreamStateChanged: (s) =>
        ref.read(streamStateProvider.notifier).state = s,
    onMcqPendingChanged: (v) =>
        ref.read(mcqPendingProvider.notifier).state = v,
  );
  ref.onDispose(cs.dispose);
  return cs;
});
