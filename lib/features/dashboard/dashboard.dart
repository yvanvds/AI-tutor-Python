import 'package:ai_tutor_python/features/dashboard/controllers.dart';
import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/dashboard/output.dart';
import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:flutter/material.dart';
import 'package:multi_split_view/multi_split_view.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
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
                    return Editor();
                  case 'controllers':
                    return Material(
                      // keep it visible and themed
                      color: Theme.of(context).colorScheme.surface,
                      child: Row(
                        children: [
                          Expanded(
                            child: Controllers(
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
                      child: SizedBox.expand(child: Output()),
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
