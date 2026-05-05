import 'package:ai_tutor_python/features/chat/mcq_options_widget.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_header.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_continue.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_mcq_disabled.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_thinking.dart';
import 'package:ai_tutor_python/features/chat/widgets/role_chip.dart';
import 'package:ai_tutor_python/features/chat/widgets/student_bubble.dart';
import 'package:ai_tutor_python/features/chat/widgets/tutor_bubble.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';

class ChatWidget extends ConsumerStatefulWidget {
  const ChatWidget({super.key});

  @override
  ConsumerState<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetState extends ConsumerState<ChatWidget> {
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
    return Column(
      children: [
        const ChatHeader(),
        Expanded(child: _ChatBody()),
      ],
    );
  }
}

class _ChatBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tutorState = ref.watch(tutorServiceProvider);
    final mcqPending = ref.watch(mcqPendingProvider);
    final streamState = ref.watch(streamStateProvider);
    final chat = ref.read(chatServiceProvider);

    return Chat(
      theme: ChatTheme.fromThemeData(Theme.of(context)).copyWith(
        colors: ChatColors.fromThemeData(Theme.of(context)).copyWith(
          surface: AppColors.ink1,
        ),
      ),
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
            return const ComposerThinking();
          } else if (tutorState == TutorState.hasFollowUp) {
            return const ComposerContinue();
          } else if (mcqPending) {
            return const ComposerMcqDisabled();
          } else {
            return const ComposerIdle();
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
        }) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: isSentByMe
              ? StudentBubble(
                  text: message.text,
                  createdAt: message.createdAt,
                )
              : TutorBubble(
                  text: message.text,
                  role: tutorRoleFromMetadata(message.metadata),
                  createdAt: message.createdAt,
                ),
        ),
        textStreamMessageBuilder: (
          context,
          message,
          index, {
          required bool isSentByMe,
          MessageGroupStatus? groupStatus,
        }) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.82,
              ),
              child: FlyerChatTextStreamMessage(
                index: index,
                message: message,
                streamState: streamState,
                mode: TextStreamMessageMode.instantMarkdown,
                receivedBackgroundColor: AppColors.ink1,
                borderRadius: BorderRadius.circular(AppRadius.bubble),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                receivedTextStyle: const TextStyle(
                  color: AppColors.fg,
                  fontSize: 14,
                  height: 1.55,
                ),
                loadingText: 'Tutor denkt na…',
              ),
            ),
          ),
        ),
        systemMessageBuilder: (
          context,
          message,
          index, {
          required bool isSentByMe,
          MessageGroupStatus? groupStatus,
        }) => Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: ChatSystemPill(text: message.text),
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
        return User(id: id, name: id == 'You' ? 'You' : 'Tutor');
      },
    );
  }
}
