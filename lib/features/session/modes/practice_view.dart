import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/features/session/widgets/output_panel.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:multi_split_view/multi_split_view.dart';

/// Oefenen — objective + run controls + editor (resizable) + output (resizable).
class PracticeView extends ConsumerStatefulWidget {
  const PracticeView({super.key, this.showObjective = true});

  final bool showObjective;

  @override
  ConsumerState<PracticeView> createState() => _PracticeViewState();
}

class _PracticeViewState extends ConsumerState<PracticeView> {
  final MultiSplitViewController _ctrl = MultiSplitViewController(
    areas: [
      Area(flex: 6, min: 2, data: 'editor'),
      Area(size: 200, min: 120, data: 'output'),
    ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tutor = ref.read(tutorServiceProvider.notifier);
      if (!tutor.hasInFlightExercise()) {
        tutor.requestExercise();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mcqActive = ref.watch(activeMcqProvider) != null;

    return Container(
      color: AppColors.ink0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showObjective) const ObjectiveBanner(),
          if (!mcqActive) ...[const RunControls(), const _ThinDivider()],
          Expanded(
            child: mcqActive
                ? const QuizView()
                : MultiSplitView(
                    axis: Axis.vertical,
                    controller: _ctrl,
                    builder: (context, area) {
                      switch (area.data) {
                        case 'editor':
                          return const Editor();
                        case 'output':
                          return const OutputPanel();
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppColors.ink2);
  }
}
