import 'package:ai_tutor_python/data/ai/ai_response_provider.dart';
import 'package:ai_tutor_python/data/code/code_provider.dart';
import 'package:ai_tutor_python/data/session/code_timeline_provider.dart';
import 'package:ai_tutor_python/data/session/message_entry.dart';
import 'package:ai_tutor_python/features/dashboard/controllers.dart';
import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/dashboard/editor_controller.dart';
import 'package:ai_tutor_python/features/dashboard/output.dart';
import 'package:ai_tutor_python/features/dashboard/output_controller.dart';
import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:multi_split_view/multi_split_view.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  final _editorCtrl = EditorController();
  final _outputCtrl = OutputController(); // set when Editor is ready

  // Outer: left (editor+controllers+output)  | right (tutor)
  final MultiSplitViewController _outerCtrl = MultiSplitViewController(
    areas: [
      // Left stack (editor/controllers/output)
      Area(flex: 3, min: 1, data: 'left'),
      // Right column (exercises)
      Area(flex: 1, min: 1, data: 'right'),
    ],
  );

  // Inner (vertical): editor | controllers(fixed 40px) | output
  final MultiSplitViewController _innerCtrl = MultiSplitViewController(
    areas: [
      // Controllers bar (fixed height, non-resizable)
      Area(size: 48, min: 48, max: 48, data: 'controllers'),
      // Editor
      Area(flex: 6, min: 2, data: 'editor'),
      // Output
      Area(flex: 2, min: 2, data: 'output'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MultiSplitView(
      axis: Axis.horizontal,
      controller: _outerCtrl,
      builder: (context, area) {
        switch (area.data) {
          case 'left':
            return MultiSplitView(
              axis: Axis.vertical,
              controller: _innerCtrl,
              builder: (context, area) {
                switch (area.data) {
                  case 'editor':
                    return Editor(controller: _editorCtrl);
                  case 'controllers':
                    return Material(
                      // keep it visible and themed
                      color: Theme.of(context).colorScheme.surface,
                      child: Row(
                        children: [
                          Expanded(
                            child: Controllers(
                              onRunPressed: () async {
                                final code = await _editorCtrl.getCode();
                                await _outputCtrl.run(code);
                              },
                              onStopPressed: () async {
                                await _outputCtrl.stop();
                              },
                              onHintPressed: () async {
                                final tutor = ref.read(tutorServiceProvider);

                                final code = await _editorCtrl.getCode();
                                await tutor.requestHint(code);
                              },
                              onSubmitPressed: () async {
                                final tutor = ref.read(tutorServiceProvider);
                                final timeline = ref.read(
                                  codeTimelineProvider.notifier,
                                );

                                // 1) Get current editor code
                                final code = await _editorCtrl.getCode();

                                // 2) Update the *last* code page in the timeline with student edits
                                timeline.updateLastCode(code);

                                // 3) Keep editor/chat in sync (active page did not change, but code did)
                                await _syncUIWithActiveCode(ref);

                                // 4) Send to tutor
                                await tutor.submitCode(code);
                              },
                              onExercisePressed: () async {
                                final tutor = ref.read(tutorServiceProvider);
                                await tutor.requestExercise();
                              },
                              onPreviousPressed: () async {
                                final timeline = ref.read(
                                  codeTimelineProvider.notifier,
                                );
                                timeline.goPrev();
                                await _syncUIWithActiveCode(ref);
                              },

                              onNextPressed: () async {
                                final timeline = ref.read(
                                  codeTimelineProvider.notifier,
                                );
                                timeline.goNext();
                                await _syncUIWithActiveCode(ref);
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  case 'output':
                    return Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox.expand(
                        child: Output(controller: _outputCtrl),
                      ),
                    );
                  default:
                    return const SizedBox.shrink();
                }
              },
            );
          case 'right':
            return ChatWidget();
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }

  Future<void> _syncUIWithActiveCode(WidgetRef ref) async {
    final timeline = ref.read(codeTimelineProvider.notifier);
    final active = timeline.activeCode;
    final msgs = timeline.activeMessages;

    // Update editor content
    String code = active?.code ?? '# Write your Python code here\n';
    ref.read(codeProvider.notifier).state = code;

    // Rebuild chat from the page’s messages
    final chat = ref.read(chatServiceProvider);
    chat.clear();
    for (final m in msgs) {
      switch (m.role) {
        case MessageRole.system:
          chat.addSystemMessage(m.text);
          break;
        case MessageRole.user:
          chat.addMessage(m.text);
          break;
        case MessageRole.ai:
          chat.addTutorMessage(m.text);
          break;
      }
    }
  }
}
