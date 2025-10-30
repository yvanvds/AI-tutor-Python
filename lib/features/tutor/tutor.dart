import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_system_message/flyer_chat_system_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class Tutor extends ConsumerStatefulWidget {
  const Tutor({super.key});

  @override
  ConsumerState<Tutor> createState() => _TutorState();
}

class _TutorState extends ConsumerState<Tutor> {
  bool _didInit = false;

  @override
  void initState() {
    super.initState();

    // Run once after mount
    Future.microtask(() async {
      if (!mounted || _didInit) return;
      _didInit = true;
      final tutor = ref.read(tutorServiceProvider);
      await tutor.initializeSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatServiceProvider);

    return Chat(
      chatController: chat.controller,
      currentUserId: 'user1',
      onMessageSend: (text) {
        chat.addMessage(text);
      },
      builders: Builders(
        chatAnimatedListBuilder: (context, itemBuilder) {
          return ChatAnimatedListReversed(itemBuilder: itemBuilder);
        },
        textMessageBuilder:
            (
              context,
              message,
              index, {
              required bool isSentByMe,
              MessageGroupStatus? groupStatus,
            }) => FlyerChatTextMessage(message: message, index: index),

        systemMessageBuilder:
            (
              context,
              message,
              index, {
              required bool isSentByMe,
              MessageGroupStatus? groupStatus,
            }) => FlyerChatSystemMessage(message: message, index: index),
      ),
      resolveUser: (UserID id) async {
        // Simple user resolver
        return User(id: id, name: id == 'user1' ? 'You' : 'Tutor');
      },
    );
  }
}
