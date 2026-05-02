import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';

class ChatService {
  final ChatController controller = InMemoryChatController();
  int _id = 0;

  /// Active stream state for the in-flight tutor message. Read by the
  /// chat widget's [TextStreamMessage] builder. Only one tutor stream is
  /// ever active at a time (the tutor service serialises requests).
  final ValueNotifier<StreamState> streamState =
      ValueNotifier<StreamState>(const StreamStateLoading());

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

  void addSystemMessage(String text) {
    _id++;
    controller.insertMessage(
      SystemMessage(id: _id.toString(), text: text, authorId: 'system'),
    );
  }

  /// Insert a clickable multiple-choice options block. The chat widget renders
  /// it as a row of buttons; tapping one routes through the same path as
  /// keyboard input.
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
  }

  /// Mark an mcq-options message as answered so its buttons rebuild as
  /// disabled with the picked one highlighted. Persisted on the controller
  /// so it survives scroll-induced rebuilds.
  void markMcqAnswered(CustomMessage message, String picked) {
    controller.updateMessage(
      message,
      message.copyWith(
        metadata: {...?message.metadata, 'selected': picked},
      ),
    );
  }

  /// Start a streaming tutor message. Inserts a [TextStreamMessage] in the
  /// loading state. Subsequent text deltas are passed via [updateStream];
  /// finalize with [completeStream] (which swaps the placeholder for a
  /// regular [TextMessage]) or [failStream].
  void startStream() {
    _id++;
    final streamId = 's${_id.toString()}';
    final message = TextStreamMessage(
      id: _id.toString(),
      authorId: 'Teacher',
      streamId: streamId,
      createdAt: DateTime.now(),
    );
    _activeStream = message;
    streamState.value = const StreamStateLoading();
    controller.insertMessage(message);
  }

  void updateStream(String accumulatedText) {
    if (_activeStream == null) return;
    streamState.value = StreamStateStreaming(accumulatedText);
  }

  /// Replace the active streaming placeholder with a finalised text message.
  /// If the stream produced no visible text, the placeholder is removed.
  void completeStream(String finalText) {
    final placeholder = _activeStream;
    _activeStream = null;
    streamState.value = const StreamStateLoading();
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

  /// Tear down the active stream after a transport error. The partial text
  /// (if any) is dropped — callers typically follow up with
  /// [addSystemMessage] to surface the failure.
  void failStream() {
    final placeholder = _activeStream;
    _activeStream = null;
    streamState.value = const StreamStateLoading();
    if (placeholder != null) {
      controller.removeMessage(placeholder);
    }
  }

  void clear() {
    _id = 0;
    _activeStream = null;
    streamState.value = const StreamStateLoading();
    controller.setMessages([]);
  }

  void dispose() {
    streamState.dispose();
    controller.dispose();
  }
}
