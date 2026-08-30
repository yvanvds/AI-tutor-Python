import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:py_runner/py_runner.dart';

enum _OutputUiState { idle, running, ok, error }

class OutputPanel extends ConsumerStatefulWidget {
  const OutputPanel({super.key});

  @override
  ConsumerState<OutputPanel> createState() => _OutputPanelState();
}

class _OutputPanelState extends ConsumerState<OutputPanel>
    with SingleTickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  late final OutputService _output;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _output = ref.read(outputServiceProvider);
    _output.lines.addListener(_onLinesChanged);
    _output.pendingInputRequest.addListener(_onInputRequestChanged);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  void _onLinesChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  void _onInputRequestChanged() {
    if (_output.pendingInputRequest.value != null) {
      _inputCtrl.clear();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _inputFocus.requestFocus(),
      );
    }
  }

  void _submitInput() {
    _output.submitInput(_inputCtrl.text);
    _inputCtrl.clear();
  }

  @override
  void dispose() {
    _output.lines.removeListener(_onLinesChanged);
    _output.pendingInputRequest.removeListener(_onInputRequestChanged);
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _pulse.dispose();
    super.dispose();
  }

  _OutputUiState _resolveState(bool running, List<OutputLine> lines) {
    if (running) return _OutputUiState.running;
    if (lines.isEmpty) return _OutputUiState.idle;
    final hasError = lines.any((l) => l.isError);
    return hasError ? _OutputUiState.error : _OutputUiState.ok;
  }

  String _stateLabel(_OutputUiState s, List<OutputLine> lines) {
    final l = AppLocalizations.of(context);
    switch (s) {
      case _OutputUiState.idle:
        return l.session_output_state_idle;
      case _OutputUiState.running:
        return l.session_output_state_running;
      case _OutputUiState.ok:
        return l.session_output_state_ok;
      case _OutputUiState.error:
        final errors = lines.where((l) => l.isError).length;
        return l.session_output_state_error_count(errors);
    }
  }

  Color _dotColor(_OutputUiState s) {
    switch (s) {
      case _OutputUiState.idle:
        return AppColors.fgFaint;
      case _OutputUiState.running:
        return AppColors.accent;
      case _OutputUiState.ok:
        return AppColors.accent2;
      case _OutputUiState.error:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border(top: BorderSide(color: AppColors.ink2, width: 1)),
      ),
      child: ValueListenableBuilder<bool>(
        valueListenable: _output.isRunning,
        builder: (context, running, _) {
          return ValueListenableBuilder<List<OutputLine>>(
            valueListenable: _output.lines,
            builder: (context, lines, _) {
              final state = _resolveState(running, lines);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    state: state,
                    dotColor: _dotColor(state),
                    label: _stateLabel(state, lines),
                    pulse: _pulse,
                  ),
                  Expanded(
                    child: _Body(
                      state: state,
                      lines: lines,
                      scroll: _scrollCtrl,
                    ),
                  ),
                  ValueListenableBuilder<InputRequest?>(
                    valueListenable: _output.pendingInputRequest,
                    builder: (context, req, _) {
                      if (req == null) return const SizedBox.shrink();
                      return _InputRow(
                        request: req,
                        controller: _inputCtrl,
                        focusNode: _inputFocus,
                        onSubmit: _submitInput,
                      );
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.dotColor,
    required this.label,
    required this.pulse,
  });

  final _OutputUiState state;
  final Color dotColor;
  final String label;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.ink2)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final opacity = state == _OutputUiState.running
                  ? 0.5 + 0.5 * pulse.value
                  : 1.0;
              return Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor.withValues(alpha: opacity),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          const SizedBox(width: AppSpacing.s),
          Text(
            AppLocalizations.of(context).session_output_header_label,
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '· $label',
            style: TextStyle(color: AppColors.fgMute, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.lines, required this.scroll});

  final _OutputUiState state;
  final List<OutputLine> lines;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    if (state == _OutputUiState.idle) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            AppLocalizations.of(context).session_output_emptyState_runHint,
            style: TextStyle(color: AppColors.fgFaint, fontSize: 12.5),
          ),
        ),
      );
    }

    // All lines live in one `SelectableText.rich` (one styled span per line)
    // rather than one `SelectableText` per line: a selection can only span a
    // single selectable, so per-line widgets made it impossible to highlight
    // a stack trace or a table and ask the tutor about it (#17).
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.s,
      ),
      child: Scrollbar(
        controller: scroll,
        child: SingleChildScrollView(
          controller: scroll,
          child: SizedBox(
            width: double.infinity,
            child: SelectableText.rich(
              TextSpan(
                children: [
                  for (var i = 0; i < lines.length; i++)
                    TextSpan(
                      text: i == lines.length - 1
                          ? lines[i].text
                          : '${lines[i].text}\n',
                      style: AppMono.output(color: _lineColor(lines[i])),
                    ),
                ],
              ),
              style: AppMono.output(),
            ),
          ),
        ),
      ),
    );
  }

  static Color _lineColor(OutputLine line) {
    if (line.isError) return AppColors.danger;
    if (line.isMeta) return AppColors.fgFaint;
    return AppColors.fg;
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.request,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  final InputRequest request;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.s,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.ink2)),
      ),
      child: Row(
        children: [
          if (request.prompt.isNotEmpty) ...[
            Text(
              request.prompt,
              style: AppMono.output(color: AppColors.fgMute),
            ),
            const SizedBox(width: AppSpacing.s),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: AppMono.output(),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.s,
                  vertical: AppSpacing.xs,
                ),
                filled: true,
                fillColor: AppColors.ink2,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(AppRadius.inputSmall),
                  ),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          IconButton(
            icon: const Icon(Icons.send_rounded, size: 18),
            color: AppColors.accent,
            onPressed: onSubmit,
          ),
        ],
      ),
    );
  }
}
