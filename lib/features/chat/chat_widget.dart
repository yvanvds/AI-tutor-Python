import 'package:ai_tutor_python/services/data_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_system_message/flyer_chat_system_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

class ChatWidget extends StatefulWidget {
  const ChatWidget({super.key});

  @override
  State<ChatWidget> createState() => _TutorState();
}

class _TutorState extends State<ChatWidget> {
  bool _didInit = false;

  @override
  void initState() {
    super.initState();

    // Run once after mount
    Future.microtask(() async {
      if (!mounted || _didInit) return;
      _didInit = true;
      DataService.tutor.initializeSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: DataService.tutor.isWorking,
      builder: (context, value, child) {
        return Column(
          children: [
            Expanded(
              child: Chat(
                theme: ChatTheme.fromThemeData(Theme.of(context)),
                chatController: DataService.chat.controller,
                currentUserId: 'You',
                onMessageSend: (text) async {
                  DataService.chat.addMessage(text);
                  await DataService.tutor.handleStudentMessage(text);
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
                      }) => FlyerChatTextMessage(
                        index: index,
                        message: message,
                        sentTextStyle: Theme.of(context).textTheme.bodyMedium!
                            .copyWith(
                              fontSize: 20,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                        receivedTextStyle: Theme.of(context)
                            .textTheme
                            .bodyMedium!
                            .copyWith(
                              fontSize: 20,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),

                  systemMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => FlyerChatSystemMessage(
                        message: message,
                        index: index,
                        backgroundColor: Theme.of(context).canvasColor,
                        textStyle: Theme.of(context).textTheme.bodyMedium!
                            .copyWith(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                ),
                resolveUser: (UserID id) async {
                  // Simple user resolver
                  return User(id: id, name: id == 'user1' ? 'You' : 'Tutor');
                },
              ),
            ),
            SizedBox(
              height: 36,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: DataService.tutor.isWorking.value
                      ? LoadingAnimationWidget.staggeredDotsWave(
                          key: const ValueKey('loader'),
                          color: Colors.blue,
                          size: 36,
                        )
                      : const SizedBox.shrink(key: ValueKey('no-loader')),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
