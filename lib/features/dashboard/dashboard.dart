import 'package:ai_tutor_python/data/ai/ai_response_provider.dart';
import 'package:ai_tutor_python/data/code/code_provider.dart';
import 'package:ai_tutor_python/features/dashboard/controllers.dart';
import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/dashboard/editor_controller.dart';
import 'package:ai_tutor_python/features/dashboard/output.dart';
import 'package:ai_tutor_python/features/dashboard/output_controller.dart';
import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/services/chat_service.dart';
import 'package:ai_tutor_python/services/timeline/timeline.dart';
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
                                // final timeline = ref.read(timeLineProvider);

                                // 1) Get current editor code
                                final code = await _editorCtrl.getCode();

                                // 2) Update the *last* code page in the timeline with student edits
                                // timeline.updateCurrentCode(code);

                                // 3) Send to tutor
                                await tutor.submitCode(code);
                              },
                              onExercisePressed: () async {
                                final tutor = ref.read(tutorServiceProvider);
                                await tutor.requestExercise();
                              },
                              onPreviousPressed: () async {
                                // final timeline = ref.read(timeLineProvider);
                                // timeline.goPrev();
                              },

                              onNextPressed: () async {
                                // final timeline = ref.read(timeLineProvider);
                                // timeline.goNext();
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
}
