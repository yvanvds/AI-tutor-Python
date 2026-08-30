import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/playground/playground_file_store.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Playground mode. Reuses [PracticeView] under a small header strip,
/// without the share-with-tutor link from RunControls. The header carries
/// the save / open file browser for the student's own code (issue #19).
class PlaygroundView extends ConsumerWidget {
  const PlaygroundView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(playgroundFileProvider);

    return Container(
      color: AppColors.ink0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.s,
            ),
            decoration: const BoxDecoration(
              color: AppColors.ink1,
              border: Border(
                bottom: BorderSide(color: AppColors.ink2, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.ink2,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    l.session_playground_pill,
                    style: const TextStyle(
                      color: AppColors.fgMute,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(
                    l.session_playground_subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.fgMute,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                if (current != null) ...[
                  Text(
                    '${current.name}${PlaygroundFileStore.extension}',
                    style: AppMono.code(color: AppColors.fg, size: 12),
                  ),
                  const SizedBox(width: AppSpacing.m),
                ],
                _HeaderButton(
                  tooltip: l.session_playground_open_tooltip,
                  icon: Icons.folder_open_outlined,
                  label: l.session_playground_open_button,
                  onTap: () => _PlaygroundFiles(context, ref).open(),
                ),
                const SizedBox(width: AppSpacing.xxs),
                _HeaderButton(
                  tooltip: l.session_playground_save_tooltip,
                  icon: Icons.save_outlined,
                  label: l.session_playground_save_button,
                  onTap: () => _PlaygroundFiles(context, ref).save(),
                ),
              ],
            ),
          ),
          const Expanded(child: PracticeView(showObjective: false)),
        ],
      ),
    );
  }
}

/// The save / open / delete flows, bound to the widget that triggered them.
class _PlaygroundFiles {
  _PlaygroundFiles(this.context, this.ref);

  final BuildContext context;
  final WidgetRef ref;

  AppLocalizations get _l => AppLocalizations.of(context);
  PlaygroundFileStore get _store => ref.read(playgroundFileStoreProvider);
  CodeService get _code =>
      ref.read(codeServiceProvider(SessionMode.playground));

  void _snack(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> save() async {
    final current = ref.read(playgroundFileProvider);
    final name = await _askName(initial: current?.name ?? '');
    if (name == null || !context.mounted) return;

    if (name != current?.name && await _store.exists(name)) {
      if (!context.mounted) return;
      final ok = await _confirm(
        title: _l.session_playground_overwriteDialog_title(name),
        message: _l.session_playground_overwriteDialog_message,
        confirmLabel: _l.session_playground_overwriteDialog_confirm,
      );
      if (!ok) return;
    }

    final text = _code.getText();
    try {
      await _store.save(name, text);
    } catch (e) {
      _snack(_l.session_playground_snack_saveFailed(e.toString()));
      return;
    }
    ref.read(playgroundFileProvider.notifier).state = PlaygroundFile(
      name: name,
      content: text,
    );
    _snack(_l.session_playground_snack_saved(name));
  }

  Future<void> open() async {
    final name = await _pickFile();
    if (name == null || !context.mounted) return;

    if (_isDirty()) {
      final ok = await _confirm(
        title: _l.session_playground_discardDialog_title,
        message: _l.session_playground_discardDialog_message,
        confirmLabel: _l.session_playground_discardDialog_confirm,
      );
      if (!ok) return;
    }

    final String text;
    try {
      text = await _store.load(name);
    } catch (e) {
      _snack(_l.session_playground_snack_openFailed(e.toString()));
      return;
    }
    _code.setText(text);
    ref.read(playgroundFileProvider.notifier).state = PlaygroundFile(
      name: name,
      content: text,
    );
  }

  /// Whether the buffer holds work that would be lost by replacing it: any
  /// edit since the last save / load, or — when nothing was ever saved —
  /// anything beyond the starter comment.
  bool _isDirty() {
    final text = _code.getText();
    final current = ref.read(playgroundFileProvider);
    if (current != null) return text != current.content;
    final trimmed = text.trim();
    return trimmed.isNotEmpty && trimmed != CodeService.starterText.trim();
  }

  Future<String?> _askName({required String initial}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _SaveNameDialog(initial: initial),
    );
  }

  Future<String?> _pickFile() {
    return showDialog<String>(
      context: context,
      builder: (_) => _OpenFileDialog(store: _store),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.session_playground_dialog_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return ok == true && context.mounted;
  }
}

class _SaveNameDialog extends StatefulWidget {
  const _SaveNameDialog({required this.initial});
  final String initial;

  @override
  State<_SaveNameDialog> createState() => _SaveNameDialogState();
}

class _SaveNameDialogState extends State<_SaveNameDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );
  bool _invalid = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = PlaygroundFileStore.normalizeName(_ctrl.text);
    if (name == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.session_playground_saveDialog_title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: PlaygroundFileStore.maxNameLength,
          decoration: InputDecoration(
            labelText: l.session_playground_saveDialog_nameLabel,
            suffixText: PlaygroundFileStore.extension,
            errorText: _invalid
                ? l.session_playground_saveDialog_invalidName
                : null,
          ),
          onChanged: (_) {
            if (_invalid) setState(() => _invalid = false);
          },
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.session_playground_dialog_cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l.session_playground_saveDialog_confirm),
        ),
      ],
    );
  }
}

class _OpenFileDialog extends StatefulWidget {
  const _OpenFileDialog({required this.store});
  final PlaygroundFileStore store;

  @override
  State<_OpenFileDialog> createState() => _OpenFileDialogState();
}

class _OpenFileDialogState extends State<_OpenFileDialog> {
  late Future<List<String>> _names = widget.store.list();

  Future<void> _delete(String name) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.session_playground_deleteDialog_title(name)),
        content: Text(l.session_playground_deleteDialog_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.session_playground_dialog_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.session_playground_deleteDialog_confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.delete(name);
    if (!mounted) return;
    final refreshed = widget.store.list();
    setState(() {
      _names = refreshed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.session_playground_openDialog_title),
      content: SizedBox(
        width: 400,
        height: 320,
        child: FutureBuilder<List<String>>(
          future: _names,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                l.session_playground_snack_openFailed(
                  snapshot.error.toString(),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final names = snapshot.data!;
            if (names.isEmpty) {
              return Center(child: Text(l.session_playground_openDialog_empty));
            }
            return ListView.builder(
              itemCount: names.length,
              itemBuilder: (context, i) {
                final name = names[i];
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text('$name${PlaygroundFileStore.extension}'),
                  onTap: () => Navigator.of(context).pop(name),
                  trailing: IconButton(
                    tooltip: l.session_playground_openDialog_delete_tooltip,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(name),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.session_playground_dialog_cancel),
        ),
      ],
    );
  }
}

class _HeaderButton extends StatefulWidget {
  const _HeaderButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_HeaderButton> createState() => _HeaderButtonState();
}

class _HeaderButtonState extends State<_HeaderButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final fg = _hovering ? AppColors.fg : AppColors.fgMute;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppDurations.hover,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: _hovering ? AppColors.ink2 : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.inputSmall),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: fg),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
