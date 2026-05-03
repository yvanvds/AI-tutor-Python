import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:py_runner/py_runner.dart';

class Output extends ConsumerStatefulWidget {
  const Output({super.key});

  @override
  ConsumerState<Output> createState() => _OutputState();
}

class _OutputState extends ConsumerState<Output> {
  final _scrollCtrl = ScrollController();
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  late final OutputService _output;

  @override
  void initState() {
    super.initState();
    _output = ref.read(outputServiceProvider);
    _output.lines.addListener(_onLinesChanged);
    _output.pendingInputRequest.addListener(_onInputRequestChanged);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final output = _output;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: output.isRunning,
            builder: (context, running, _) => Row(
              children: [
                Text(
                  running ? 'Running…' : 'Output',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                if (running)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ValueListenableBuilder<List<OutputLine>>(
              valueListenable: output.lines,
              builder: (context, lines, _) => Scrollbar(
                controller: _scrollCtrl,
                child: ListView.builder(
                  controller: _scrollCtrl,
                  itemCount: lines.length,
                  itemBuilder: (context, i) {
                    final line = lines[i];
                    final theme = Theme.of(context);
                    final Color? color;
                    if (line.isMeta) {
                      color = theme.hintColor;
                    } else if (line.isError) {
                      color = theme.colorScheme.error;
                    } else {
                      color = theme.textTheme.bodyMedium?.color;
                    }
                    return SelectableText(
                      line.text,
                      style: TextStyle(fontFamily: 'monospace', color: color),
                    );
                  },
                ),
              ),
            ),
          ),
          ValueListenableBuilder<InputRequest?>(
            valueListenable: output.pendingInputRequest,
            builder: (context, req, _) {
              if (req == null) return const SizedBox.shrink();
              return _buildInputRow(context, req);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, InputRequest req) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (req.prompt.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                req.prompt,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              focusNode: _inputFocus,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submitInput(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _submitInput,
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
