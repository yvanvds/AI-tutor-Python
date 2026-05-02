import 'package:ai_tutor_python/features/chat/composer_continue_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_mcq_wait_widget.dart';
import 'package:ai_tutor_python/features/chat/composer_wait_widget.dart';
import 'package:ai_tutor_python/features/chat/mcq_options_widget.dart';
import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/multi_value_listenable_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flyer_chat_system_message/flyer_chat_system_message.dart';
import 'package:flyer_chat_text_message/flyer_chat_text_message.dart';
import 'package:flyer_chat_text_stream_message/flyer_chat_text_stream_message.dart';

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
    return MultiValueListenableBuilder(
      listenables: [DataService.tutor.state, DataService.chat.mcqPending],
      builder: (context, _) {
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
                  composerBuilder: (context) {
                    if (DataService.tutor.state.value == TutorState.working) {
                      return const ComposerWaitWidget();
                    } else if (DataService.tutor.state.value ==
                        TutorState.hasFollowUp) {
                      return const ComposerContinueWidget();
                    } else if (DataService.chat.mcqPending.value) {
                      return const ComposerMcqWaitWidget();
                    } else {
                      return const Composer();
                    }
                  },
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

                  textStreamMessageBuilder:
                      (
                        context,
                        message,
                        index, {
                        required bool isSentByMe,
                        MessageGroupStatus? groupStatus,
                      }) => ValueListenableBuilder<StreamState>(
                        valueListenable: DataService.chat.streamState,
                        builder: (context, streamState, _) =>
                            FlyerChatTextStreamMessage(
                              index: index,
                              message: message,
                              streamState: streamState,
                              mode: TextStreamMessageMode.instantMarkdown,
                              receivedTextStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium!
                                  .copyWith(
                                    fontSize: 20,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                              loadingText: 'Aan het denken...',
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

                  customMessageBuilder:
                      (
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
                  // Simple user resolver
                  return User(id: id, name: id == 'user1' ? 'You' : 'Tutor');
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
