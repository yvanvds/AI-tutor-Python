import 'package:ai_tutor_python/features/chat/composer_continue_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_mcq_wait_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_wait_widget.dart';
import 'package:ai_tutor_python/features/chat/mcq_options_widget.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flyer_chat_system_message/flyer_chat_system_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';

class ChatWidget extends ConsumerStatefulWidget {
  const ChatWidget({super.key});

  @override
  ConsumerState<ChatWidget> createState() => _TutorState();
}

class _TutorState extends ConsumerState<ChatWidget> {
  bool _didInit = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted || _didInit) return;
      _didInit = true;
      ref.read(tutorServiceProvider.notifier).initializeSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tutorState = ref.watch(tutorServiceProvider);
    final mcqPending = ref.watch(mcqPendingProvider);
    final streamState = ref.watch(streamStateProvider);
    final chat = ref.read(chatServiceProvider);

    return Column(
      children: [
        Expanded(
          child: Chat(
            theme: ChatTheme.fromThemeData(Theme.of(context)),
            chatController: chat.controller,
            currentUserId: 'You',
            onMessageSend: (text) async {
              chat.addMessage(text);
              await ref
                  .read(tutorServiceProvider.notifier)
                  .handleStudentMessage(text);
            },
            builders: Builders(
              composerBuilder: (context) {
                if (tutorState == TutorState.working) {
                  return const ComposerWaitWidget();
                } else if (tutorState == TutorState.hasFollowUp) {
                  return const ComposerContinueWidget();
                } else if (mcqPending) {
                  return const ComposerMcqWaitWidget();
                } else {
                  return const Composer();
                }
              },
              chatAnimatedListBuilder: (context, itemBuilder) {
                return ChatAnimatedListReversed(itemBuilder: itemBuilder);
              },
              textMessageBuilder: (
                context,
                message,
                index, {
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) => FlyerChatTextMessage(
                index: index,
                message: message,
                sentTextStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
                receivedTextStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),

              textStreamMessageBuilder: (
                context,
                message,
                index, {
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) => FlyerChatTextStreamMessage(
                index: index,
                message: message,
                streamState: streamState,
                mode: TextStreamMessageMode.instantMarkdown,
                receivedTextStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium!.copyWith(
                  fontSize: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                loadingText: 'Aan het denken...',
              ),

              systemMessageBuilder: (
                context,
                message,
                index, {
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) => FlyerChatSystemMessage(
                message: message,
                index: index,
                backgroundColor: Theme.of(context).canvasColor,
                textStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),

              customMessageBuilder: (
                context,
                message,
                index, {
                required bool isSentByMe,
                MessageGroupStatus? groupStatus,
              }) {
                if (message.metadata?['kind'] == 'mcq_options') {
                  return McqOptionsWidget(message: message);
                }
                return const SizedBox.shrink();
              },
            ),
            resolveUser: (UserID id) async {
              return User(id: id, name: id == 'user1' ? 'You' : 'Tutor');
            },
          ),
        ),
      ],
    );
  }
}
