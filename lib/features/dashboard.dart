import 'package:ai_tutor_python/features/controllers.dart';
import 'package:ai_tutor_python/features/editor.dart';
import 'package:ai_tutor_python/features/editor_controller.dart';
import 'package:ai_tutor_python/features/output.dart';
import 'package:ai_tutor_python/features/output_controller.dart';
import 'package:ai_tutor_python/features/tutor/tutor.dart';
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
      Area(size: 40, min: 40, max: 40, data: 'controllers'),
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
                            ),
                          ),
                        ],
                      ),
                    );
                  case 'output':
                    return Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Output(controller: _outputCtrl),
                    );
                  default:
                    return const SizedBox.shrink();
                }
              },
            );
          case 'right':
            return Tutor();
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}
