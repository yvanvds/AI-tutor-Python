import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:flutter/material.dart';

class Output extends StatefulWidget {
  const Output({super.key});

  @override
  State<Output> createState() => _OutputState();
}

class _OutputState extends State<Output> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    DataService.output.lines.addListener(_onLinesChanged);
  }

  void _onLinesChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    DataService.output.lines.removeListener(_onLinesChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            valueListenable: DataService.output.isRunning,
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
              valueListenable: DataService.output.lines,
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
        ],
      ),
    );
  }
}
