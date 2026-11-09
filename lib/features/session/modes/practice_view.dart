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
  const PracticeView({
    super.key,
    this.showObjective = true,
    this.showQuiz = true,
  });

  final bool showObjective;

  /// Whether a pending MCQ (`activeMcqProvider != null`) replaces the editor
  /// with [QuizView]. Playground hosts this view too and must keep showing
  /// the editor while a quiz is parked in Practice (#122).
  final bool showQuiz;

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

  /// The ask for an exercise this view made, while it is on its way.
  Future<void>? _asking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForAnExercise());
    // A session that starts while this view is on screen — the restart in
    // the chat header — brings its first exercise, as coming on screen
    // does (#286). The ask waits for the start (#284).
    ref.listenManual<int>(sessionStartsProvider, (_, _) => _askForAnExercise());
  }

  /// Asks for an exercise unless one is in flight for the subgoal the
  /// session is on, or this view's last ask is still on its way: a restart
  /// pressed twice, or in the frame this view mounted, asks once.
  void _askForAnExercise() {
    if (!mounted || _asking != null) return;
    final tutor = ref.read(tutorServiceProvider.notifier);
    if (tutor.hasInFlightExercise()) return;
    final ask = tutor.requestExercise();
    _asking = ask;
    ask.whenComplete(() {
      if (identical(_asking, ask)) _asking = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mcqActive = widget.showQuiz && ref.watch(activeMcqProvider) != null;

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
