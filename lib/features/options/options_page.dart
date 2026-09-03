// Options panel (issue #25). One scrollable page reachable from the icon
// sidebar that gathers everything that used to be spread over the settings
// popup and the debug dialog:
//
//   - language (moved from the sidebar settings popup)
//   - appearance: light / dark / follow the system (#32)
//   - the AI model, on own-key and developer builds (#32) and for teachers
//     (#90)
//   - progress reset: everything, or one goal / subgoal
//   - export / import of progress to a JSON file (#32)
//   - the user's own OpenAI key (only when the account is not on the
//     bundled key)
//   - bug reports to GitHub, with a recent tutor turn's debug payload
//   - developer tools (former DebugDialog), behind [developerToolsProvider]
//   - about / version, with the manual update check (#48)

import 'dart:async';
import 'dart:convert';

import 'package:ai_tutor_python/core/chat_request_type.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:ai_tutor_python/services/config/model_preference.dart';
import 'package:ai_tutor_python/services/config/theme_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/debug/runner_diagnostics.dart';
import 'package:ai_tutor_python/services/github/github_device_flow.dart';
import 'package:ai_tutor_python/services/github/github_issue_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/progress/progress_archive.dart';
import 'package:ai_tutor_python/services/progress/progress_archive_io.dart';
import 'package:ai_tutor_python/services/progress/progress_reset.dart';
import 'package:ai_tutor_python/services/tutor/openai_connector.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/tutor/conductor.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/version.dart';
import 'package:ai_tutor_python/widgets/update_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OptionsPage extends ConsumerWidget {
  const OptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final devTools = ref.watch(developerToolsProvider);
    final isTeacher = ref.watch(isTeacherProvider);
    final usesOwnKey = ref.watch(
      accountServiceProvider.select((a) => a != null && !a.mayUseGlobalKey),
    );

    return Container(
      color: AppColors.ink0,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.xl,
            ),
            children: [
              Text(
                l.options_page_title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                l.options_page_subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xl),
              const _LanguageCard(),
              const SizedBox(height: AppSpacing.lg),
              const _ThemeCard(),
              // The model is a spending decision as much as a quality one, so
              // it is offered to whoever is paying: an own-key account, or a
              // developer build (#32) — and to a teacher on the school's key,
              // who answers for that spend and has no other way to see which
              // model the tutor is on (#90). A student on the school's key
              // still sees nothing.
              if (usesOwnKey || devTools || isTeacher) ...[
                const SizedBox(height: AppSpacing.lg),
                const _ModelCard(),
              ],
              const SizedBox(height: AppSpacing.lg),
              const _ProgressCard(),
              const SizedBox(height: AppSpacing.lg),
              const _TransferCard(),
              if (usesOwnKey) ...[
                const SizedBox(height: AppSpacing.lg),
                const _ApiKeyCard(),
              ],
              const SizedBox(height: AppSpacing.lg),
              const _BugReportCard(),
              if (devTools) ...[
                const SizedBox(height: AppSpacing.lg),
                const _DeveloperCard(),
              ],
              const SizedBox(height: AppSpacing.lg),
              const _AboutCard(),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // A Material (not a decorated Container) so the ListTile rows inside
    // paint their ink on the card surface.
    return Material(
      color: AppColors.ink1,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.cardLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lgPlus),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(subtitle!, style: text.bodySmall),
            ],
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Radio-style row shared by the language, appearance and model cards.
Widget _choiceRow({
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  return ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      size: 18,
      color: selected ? AppColors.accent : AppColors.fgMute,
    ),
    title: Text(label),
    onTap: onTap,
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

// ---------------------------------------------------------------------------
// Language
// ---------------------------------------------------------------------------

class _LanguageCard extends ConsumerWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(localeServiceProvider);

    Widget row(String label, Locale? value) => _choiceRow(
      label: label,
      selected: value == null
          ? current == null
          : current?.languageCode == value.languageCode,
      onTap: () => ref.read(localeServiceProvider.notifier).setLocale(value),
    );

    return _OptionsCard(
      title: l.options_language_title,
      subtitle: l.options_language_subtitle,
      child: Column(
        children: [
          row(l.settings_language_system, null),
          row(l.settings_language_english, const Locale('en')),
          row(l.settings_language_dutch, const Locale('nl')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance (#32)
// ---------------------------------------------------------------------------

/// Light / dark / follow-the-system.
///
/// Picking one swaps the palette behind the flat `AppColors` tokens and
/// remounts the shell (see `GoalsApp.build`), so the whole window — sidebar,
/// editor, syntax colours, chat — changes on the next frame.
class _ThemeCard extends ConsumerWidget {
  const _ThemeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(themeServiceProvider);

    Widget row(String label, AppThemeChoice value) => _choiceRow(
      label: label,
      selected: current == value,
      onTap: () => ref.read(themeServiceProvider.notifier).setChoice(value),
    );

    return _OptionsCard(
      title: l.options_theme_title,
      subtitle: l.options_theme_subtitle,
      child: Column(
        children: [
          row(l.options_theme_system, AppThemeChoice.system),
          row(l.options_theme_light, AppThemeChoice.light),
          row(l.options_theme_dark, AppThemeChoice.dark),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI model (#32)
// ---------------------------------------------------------------------------

/// Per-device model override on top of the school-wide `GlobalConfig.Model`.
/// See `services/config/model_preference.dart` for why it is per device and
/// who gets to see this card.
class _ModelCard extends ConsumerWidget {
  const _ModelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final current = ref.watch(modelPreferenceProvider);
    final global = ref.watch(globalConfigServiceProvider)?.model;
    final fallback = (global == null || global.isEmpty)
        ? OpenaiConnector.defaultModel
        : global;

    Widget row(String label, String? value) => _choiceRow(
      label: label,
      selected: current == value,
      onTap: () => ref.read(modelPreferenceProvider.notifier).setModel(value),
    );

    return _OptionsCard(
      title: l.options_model_title,
      subtitle: l.options_model_subtitle,
      child: Column(
        children: [
          row(l.options_model_followGlobal(fallback), null),
          for (final model in kSelectableModels) row(model, model),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Export / import progress (#32)
// ---------------------------------------------------------------------------

class _TransferCard extends ConsumerStatefulWidget {
  const _TransferCard();

  @override
  ConsumerState<_TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends ConsumerState<_TransferCard> {
  bool _busy = false;

  Future<void> _export() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final data = await ref.read(progressArchiveProvider).export();
      final stamp = DateTime.now().toUtc().toIso8601String().split('T').first;
      final path = await ref
          .read(progressArchiveIoProvider)
          .save(
            suggestedName: 'ai-tutor-progress-$stamp.json',
            contents: const JsonEncoder.withIndent('  ').convert(data),
          );
      if (!mounted || path == null) return;
      _snack(context, l.options_transfer_exported(path));
    } catch (e) {
      if (!mounted) return;
      _snack(context, l.options_transfer_exportFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final l = AppLocalizations.of(context);
    final ArchiveFile? file;
    try {
      file = await ref.read(progressArchiveIoProvider).open();
    } catch (e) {
      if (!mounted) return;
      _snack(context, l.options_transfer_importFailed(e.toString()));
      return;
    }
    if (file == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.options_transfer_import_dialog_title),
        content: Text(l.options_transfer_import_dialog_message(file!.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.options_dialog_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.options_transfer_import_dialog_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final decoded = jsonDecode(file.contents);
      if (decoded is! Map) {
        throw ProgressArchiveException('The file does not contain JSON data.');
      }
      final summary = await ref
          .read(progressArchiveProvider)
          .import(decoded.cast<String, dynamic>());
      if (!mounted) return;
      _snack(
        context,
        l.options_transfer_imported(
          summary.goals,
          summary.samples,
          summary.beliefs,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _snack(context, l.options_transfer_importFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _OptionsCard(
      title: l.options_transfer_title,
      subtitle: l.options_transfer_subtitle,
      child: Wrap(
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.s,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: Text(l.options_transfer_export_button),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.file_upload_outlined, size: 18),
            label: Text(l.options_transfer_import_button),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

class _ProgressCard extends ConsumerStatefulWidget {
  const _ProgressCard();

  @override
  ConsumerState<_ProgressCard> createState() => _ProgressCardState();
}

class _ProgressCardState extends ConsumerState<_ProgressCard> {
  bool _busy = false;

  Future<void> _resetAll() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.options_progress_resetAll_dialog_title),
        content: Text(l.options_progress_resetAll_dialog_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.options_dialog_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.options_progress_resetAll_dialog_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(progressResetProvider).resetAll();
      if (!mounted) return;
      _snack(context, l.options_progress_resetAll_done);
    } catch (e) {
      if (!mounted) return;
      _snack(context, l.options_progress_resetFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetOne() async {
    final l = AppLocalizations.of(context);
    final goals = ref.read(goalsServiceProvider);
    final picked = await showDialog<Goal>(
      context: context,
      builder: (_) => _GoalPickerDialog(load: goals.getAllGoalsOnce),
    );
    if (picked == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.options_progress_resetGoal_confirm_title(picked.title)),
        content: Text(
          picked.parentId == null
              ? l.options_progress_resetGoal_confirm_message_root
              : l.options_progress_resetGoal_confirm_message_subgoal,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.options_dialog_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.options_progress_resetGoal_confirm_button),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(progressResetProvider).resetGoal(picked);
      if (!mounted) return;
      _snack(context, l.options_progress_resetGoal_done(picked.title));
    } catch (e) {
      if (!mounted) return;
      _snack(context, l.options_progress_resetFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return _OptionsCard(
      title: l.options_progress_title,
      subtitle: l.options_progress_subtitle,
      child: Wrap(
        spacing: AppSpacing.s,
        runSpacing: AppSpacing.s,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : _resetOne,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: Text(l.options_progress_resetGoal_button),
          ),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _resetAll,
            icon: const Icon(Icons.delete_forever, size: 18),
            label: Text(l.options_progress_resetAll_button),
          ),
        ],
      ),
    );
  }
}

/// Lists root goals with their subgoals indented beneath them; tapping a row
/// returns that goal.
class _GoalPickerDialog extends StatelessWidget {
  const _GoalPickerDialog({required this.load});

  final Future<List<Goal>> Function() load;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.options_progress_resetGoal_dialog_title),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.options_progress_resetGoal_dialog_message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.m),
            Expanded(
              child: FutureBuilder<List<Goal>>(
                future: load(),
                builder: (ctx, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text(
                        l.options_progress_resetGoal_dialog_loadError(
                          snap.error.toString(),
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snap.data!;
                  final roots = all.where((g) => g.parentId == null).toList()
                    ..sort((a, b) => a.order.compareTo(b.order));
                  if (roots.isEmpty) {
                    return Center(
                      child: Text(l.options_progress_resetGoal_dialog_empty),
                    );
                  }
                  final rows = <Widget>[];
                  for (final root in roots) {
                    rows.add(
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.flag_outlined, size: 18),
                        title: Text(root.title),
                        onTap: () => Navigator.of(ctx).pop(root),
                      ),
                    );
                    final children =
                        all.where((g) => g.parentId == root.id).toList()
                          ..sort((a, b) => a.order.compareTo(b.order));
                    for (final child in children) {
                      rows.add(
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(
                            left: AppSpacing.xxxl,
                            right: AppSpacing.lg,
                          ),
                          leading: const Icon(
                            Icons.subdirectory_arrow_right,
                            size: 16,
                          ),
                          title: Text(child.title),
                          onTap: () => Navigator.of(ctx).pop(child),
                        ),
                      );
                    }
                  }
                  return ListView(children: rows);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.options_dialog_cancel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// OpenAI key
// ---------------------------------------------------------------------------

class _ApiKeyCard extends ConsumerWidget {
  const _ApiKeyCard();

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final key = await showDialog<String>(
      context: context,
      builder: (_) => _SecretInputDialog(
        title: l.options_apiKey_dialog_title,
        fieldLabel: l.options_apiKey_dialog_field,
        hint: 'sk-...',
        confirmLabel: l.options_apiKey_dialog_save,
      ),
    );
    if (key == null || key.isEmpty || !context.mounted) return;
    await ref.read(localApiKeyStorageProvider.notifier).saveKey(key);
    if (!context.mounted) return;
    _snack(context, l.options_apiKey_saved);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.options_apiKey_remove_dialog_title),
        content: Text(l.options_apiKey_remove_dialog_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.options_dialog_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.options_apiKey_remove_dialog_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(localApiKeyStorageProvider.notifier).clearKey();
    if (!context.mounted) return;
    _snack(context, l.options_apiKey_removed);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hasKey = ref.watch(localApiKeyStorageProvider);
    return _OptionsCard(
      title: l.options_apiKey_title,
      subtitle: l.options_apiKey_subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasKey
                ? l.options_apiKey_status_present
                : l.options_apiKey_status_missing,
          ),
          const SizedBox(height: AppSpacing.m),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              OutlinedButton.icon(
                onPressed: () => _change(context, ref),
                icon: const Icon(Icons.key, size: 18),
                label: Text(l.options_apiKey_change_button),
              ),
              FilledButton.tonalIcon(
                onPressed: hasKey ? () => _remove(context, ref) : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(l.options_apiKey_remove_button),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Obscured single-line input with paste + reveal, returning the trimmed
/// text (or null on cancel).
class _SecretInputDialog extends StatefulWidget {
  const _SecretInputDialog({
    required this.title,
    required this.fieldLabel,
    required this.confirmLabel,
    this.hint,
  });

  final String title;
  final String fieldLabel;
  final String confirmLabel;
  final String? hint;

  @override
  State<_SecretInputDialog> createState() => _SecretInputDialogState();
}

class _SecretInputDialogState extends State<_SecretInputDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                hintText: widget.hint,
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _obscure
                          ? l.auth_localKey_tooltip_showKey
                          : l.auth_localKey_tooltip_hideKey,
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    IconButton(
                      tooltip: l.auth_localKey_tooltip_paste,
                      icon: const Icon(Icons.paste),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        final pasted = data?.text ?? '';
                        if (pasted.isNotEmpty) _controller.text = pasted.trim();
                      },
                    ),
                  ],
                ),
              ),
              onSubmitted: (_) =>
                  Navigator.of(context).pop(_controller.text.trim()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.options_dialog_cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bug reports
// ---------------------------------------------------------------------------

/// Filing a GitHub issue from inside the app, and the GitHub sign-in that
/// makes it possible.
///
/// Sign-in is the OAuth **device flow** (#57): a dialog shows a short code,
/// the student approves it in a browser, and the app polls until GitHub hands
/// over a token. It replaced a personal access token the student had to
/// create and paste (#25) — see `services/github/github_device_flow.dart` for
/// why, and for the scope the app asks for.
///
/// The code lives in a **dialog**, not inline in the card, and the reason is
/// not cosmetic: this card sits in a lazily-built `ListView`, so scrolling it
/// past the fold disposes its state — which, while a sign-in is running,
/// would silently abandon the code the student is at that moment typing into
/// a browser. A modal route is outside the list and holds the scroll still
/// while it is up. (It also matches the old paste-a-token dialog it replaces,
/// and the rest of this panel.)
///
/// A build compiled without an OAuth client id cannot run the flow at all.
/// That is a legitimate state (a fork that has not registered an OAuth app),
/// so the card says so plainly and hides the button, rather than offering a
/// sign-in that could only fail.
class _BugReportCard extends ConsumerStatefulWidget {
  const _BugReportCard();

  @override
  ConsumerState<_BugReportCard> createState() => _BugReportCardState();
}

class _BugReportCardState extends ConsumerState<_BugReportCard> {
  String? _loginToken;
  Future<String>? _login;
  bool _busy = false;

  /// Set by the dialog's Cancel button; the polling loop reads it between
  /// polls, so a cancel takes effect within one interval.
  bool _cancelled = false;

  Future<String> _loginFor(String token) {
    if (_loginToken != token || _login == null) {
      _loginToken = token;
      _login = ref.read(githubIssueServiceProvider).loginFor(token);
    }
    return _login!;
  }

  Future<void> _connect() async {
    final l = AppLocalizations.of(context);
    final flow = ref.read(gitHubDeviceFlowProvider);
    setState(() {
      _busy = true;
      _cancelled = false;
    });

    NavigatorState? navigator;
    bool dialogOpen = false;
    // Idempotent: the dialog is closed on whichever path finishes first, and
    // the later ones must not pop a route that is no longer ours.
    void closeCodeDialog() {
      if (!dialogOpen) return;
      dialogOpen = false;
      if (navigator?.mounted ?? false) navigator!.pop();
    }

    try {
      final grant = await flow.requestCode();
      if (!mounted) return;

      navigator = Navigator.of(context);
      dialogOpen = true;
      // Deliberately not awaited: the dialog is up *while* the polling runs,
      // and it is this method that takes it down again.
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _DeviceCodeDialog(
            grant: grant,
            onOpenBrowser: () => _openBrowser(grant),
            onCopyCode: () => _copyCode(grant),
            onCancel: () {
              _cancelled = true;
              closeCodeDialog();
            },
          ),
        ),
      );

      final token = await flow.pollForToken(
        grant,
        isCancelled: () => _cancelled || !mounted,
      );
      final login = await ref.read(githubIssueServiceProvider).loginFor(token);
      _loginToken = token;
      _login = Future.value(login);
      await ref.read(githubTokenStorageProvider.notifier).saveToken(token);
      closeCodeDialog();
      if (!mounted) return;
      _snack(context, l.options_bugReport_github_connectedAs(login));
    } on DeviceFlowException catch (e) {
      closeCodeDialog();
      if (!mounted) return;
      switch (e.reason) {
        // The student pressed Cancel; they know what happened.
        case DeviceFlowFailure.cancelled:
          break;
        case DeviceFlowFailure.expired:
          _snack(context, l.options_bugReport_github_device_expired);
        case DeviceFlowFailure.denied:
          _snack(context, l.options_bugReport_github_device_denied);
        case DeviceFlowFailure.notConfigured:
          _snack(context, l.options_bugReport_github_notConfigured);
        case DeviceFlowFailure.failed:
          _snack(context, l.options_bugReport_github_connectFailed(e.message));
      }
    } catch (e) {
      closeCodeDialog();
      if (!mounted) return;
      _snack(context, l.options_bugReport_github_connectFailed(e.toString()));
    } finally {
      closeCodeDialog();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hands the verification URL to the operating system, and reports back
  /// what the dialog should say about it — a snackbar would come up *behind*
  /// the modal barrier, which is exactly where a message about the dialog
  /// must not be.
  Future<String?> _openBrowser(DeviceCodeGrant grant) async {
    final l = AppLocalizations.of(context);
    bool launched;
    try {
      launched = await ref.read(browserLauncherProvider)(grant.verificationUri);
    } catch (_) {
      launched = false;
    }
    if (launched) return null;
    return l.options_bugReport_github_device_browserFailed(
      grant.verificationUri.toString(),
    );
  }

  Future<String?> _copyCode(DeviceCodeGrant grant) async {
    final l = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: grant.userCode));
    return l.options_bugReport_github_device_codeCopied;
  }

  Future<void> _disconnect() async {
    await ref.read(githubTokenStorageProvider.notifier).clearToken();
    if (!mounted) return;
    setState(() {
      _loginToken = null;
      _login = null;
    });
  }

  Future<void> _report(String token) async {
    final l = AppLocalizations.of(context);
    final turns = ref.read(debugServiceProvider).buffer;
    // Read before the dialog, so the async gaps below never touch `ref`.
    final pyRunner = ref.read(pyRunnerProvider);
    final issues = ref.read(githubIssueServiceProvider);
    final draft = await showDialog<_BugReportDraft>(
      context: context,
      builder: (_) => _BugReportDialog(turns: turns),
    );
    if (draft == null || !mounted) return;

    setState(() => _busy = true);
    try {
      // Always attached, with no dropdown: the turn payload describes the
      // tutor, and "it didn't run" is a question about the runner (#74).
      final runner = await RunnerDiagnostics.collect(pyRunner);
      final url = await issues.createIssue(
        token: token,
        title: draft.title,
        body: buildBugReportBody(
          description: draft.description,
          appVersion: kAppVersion,
          runner: runner,
          turn: draft.turn?.toJson(),
        ),
      );
      if (!mounted) return;
      _snack(context, l.options_bugReport_posted(url.toString()));
    } catch (e) {
      if (!mounted) return;
      _snack(context, l.options_bugReport_postFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final token = ref.watch(githubTokenStorageProvider);
    final configured = ref.watch(gitHubDeviceFlowProvider).isConfigured;

    final Widget status;
    if (token != null) {
      status = FutureBuilder<String>(
        future: _loginFor(token),
        builder: (_, snap) {
          if (snap.hasError) {
            return Text(
              l.options_bugReport_github_connectFailed(snap.error.toString()),
            );
          }
          return Text(l.options_bugReport_github_connectedAs(snap.data ?? '…'));
        },
      );
    } else if (!configured) {
      // Honest rather than silent: a build with no OAuth app cannot sign in,
      // and a disabled button with no explanation would read as a bug.
      status = Text(
        l.options_bugReport_github_notConfigured,
        key: const ValueKey('github-not-configured'),
      );
    } else {
      status = Text(l.options_bugReport_github_notConnected);
    }

    return _OptionsCard(
      title: l.options_bugReport_title,
      subtitle: l.options_bugReport_subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          status,
          const SizedBox(height: AppSpacing.m),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              if (token == null) ...[
                if (configured)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: const Icon(Icons.link, size: 18),
                    label: Text(l.options_bugReport_github_connect_button),
                  ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _report(token),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: Text(l.options_bugReport_report_button),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _disconnect,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: Text(l.options_bugReport_github_disconnect_button),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The waiting half of the device flow: the code to type, where to type it,
/// and the three things a student can do about it.
///
/// The code is a [SelectableText] in a monospaced face — it is eight
/// characters that have to be transcribed exactly, and `WDJB-MJHT` in a
/// proportional font is how an `I` becomes an `l`.
///
/// It is dismissed by whoever started the flow, never by the barrier: closing
/// it has to also stop the polling, and a tap outside would leave the two
/// disagreeing about whether a sign-in is still running.
class _DeviceCodeDialog extends StatefulWidget {
  const _DeviceCodeDialog({
    required this.grant,
    required this.onOpenBrowser,
    required this.onCopyCode,
    required this.onCancel,
  });

  final DeviceCodeGrant grant;

  /// Each returns the line to show inside the dialog, or `null` for "nothing
  /// to say".
  final Future<String?> Function() onOpenBrowser;
  final Future<String?> Function() onCopyCode;

  final VoidCallback onCancel;

  @override
  State<_DeviceCodeDialog> createState() => _DeviceCodeDialogState();
}

class _DeviceCodeDialogState extends State<_DeviceCodeDialog> {
  String? _notice;

  Future<void> _run(Future<String?> Function() action) async {
    final notice = await action();
    if (!mounted) return;
    setState(() => _notice = notice);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final notice = _notice;
    return AlertDialog(
      key: const ValueKey('github-device-dialog'),
      title: Text(l.options_bugReport_github_connect_button),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.options_bugReport_github_device_explainer(kBugReportRepo),
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.m),
            SelectableText(
              widget.grant.userCode,
              key: const ValueKey('github-device-code'),
              style: text.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l.options_bugReport_github_device_instruction(
                widget.grant.verificationUri.toString(),
              ),
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: Text(
                    l.options_bugReport_github_device_waiting,
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
            if (notice != null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                notice,
                key: const ValueKey('github-device-notice'),
                style: text.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel,
          child: Text(l.options_bugReport_github_device_cancel),
        ),
        OutlinedButton.icon(
          onPressed: () => _run(widget.onCopyCode),
          icon: const Icon(Icons.copy, size: 18),
          label: Text(l.options_bugReport_github_device_copyCode),
        ),
        FilledButton.icon(
          onPressed: () => _run(widget.onOpenBrowser),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(l.options_bugReport_github_device_openBrowser),
        ),
      ],
    );
  }
}

class _BugReportDraft {
  const _BugReportDraft({
    required this.title,
    required this.description,
    this.turn,
  });
  final String title;
  final String description;
  final TurnRecord? turn;
}

class _BugReportDialog extends StatefulWidget {
  const _BugReportDialog({required this.turns});

  final List<TurnRecord> turns;

  @override
  State<_BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<_BugReportDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  TurnRecord? _turn;
  bool _titleMissing = false;

  @override
  void initState() {
    super.initState();
    _turn = widget.turns.isEmpty ? null : widget.turns.last;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleMissing = true);
      return;
    }
    Navigator.of(context).pop(
      _BugReportDraft(
        title: title,
        description: _description.text,
        turn: _turn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final newestFirst = widget.turns.reversed.toList(growable: false);
    return AlertDialog(
      title: Text(l.options_bugReport_dialog_title),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.options_bugReport_dialog_titleField,
                border: const OutlineInputBorder(),
                errorText: _titleMissing
                    ? l.options_bugReport_dialog_titleRequired
                    : null,
              ),
              onChanged: (_) {
                if (_titleMissing) setState(() => _titleMissing = false);
              },
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              controller: _description,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: l.options_bugReport_dialog_descriptionField,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            DropdownButtonFormField<TurnRecord?>(
              initialValue: _turn,
              decoration: InputDecoration(
                labelText: l.options_bugReport_dialog_turnField,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<TurnRecord?>(
                  value: null,
                  child: Text(l.options_bugReport_dialog_turnNone),
                ),
                for (final t in newestFirst)
                  DropdownMenuItem<TurnRecord?>(
                    value: t,
                    child: Text(
                      l.options_bugReport_dialog_turnLabel(
                        t.turnId,
                        t.requestType,
                      ),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _turn = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.options_dialog_cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l.options_bugReport_dialog_submit),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Developer tools (former DebugDialog)
// ---------------------------------------------------------------------------

class _DeveloperCard extends ConsumerStatefulWidget {
  const _DeveloperCard();

  @override
  ConsumerState<_DeveloperCard> createState() => _DeveloperCardState();
}

class _DeveloperCardState extends ConsumerState<_DeveloperCard> {
  QuestionDifficulty _difficulty = QuestionDifficulty.medium;

  static const List<(ChatRequestType, String)> _questionTypes = [
    (ChatRequestType.socraticQuestion, 'Socratic'),
    (ChatRequestType.mcQuestion, 'Multiple choice'),
    (ChatRequestType.explainCodeQuestion, 'Explain code'),
    (ChatRequestType.completeCodeQuestion, 'Complete code'),
    (ChatRequestType.writeCodeQuestion, 'Write code'),
  ];

  Future<void> _triggerQuestion(ChatRequestType type) async {
    // Ad-hoc plan for debug-fired questions: no LO targeting, just the
    // chosen difficulty. Jump to the session so the question is visible.
    ref.read(sectionProvider.notifier).state = Section.session;
    final plan = QuestionPlan(
      type: type,
      difficulty: _difficulty,
      targetLOs: const [],
      reason: const TurnSelectionReason(
        candidateLOs: [],
        chosenReason: 'options panel',
        notchDropFired: false,
      ),
    );
    await ref
        .read(tutorServiceProvider.notifier)
        .queryTutor(type: type, plan: plan);
  }

  void _triggerLevelUp() {
    ref.read(sectionProvider.notifier).state = Section.session;
    ref
        .read(levelUpControllerProvider.notifier)
        .push(
          const LevelUpEvent(
            newLevel: 5,
            xpAwarded: 20,
            conceptName: 'elif-ladder',
          ),
        );
  }

  Future<void> _copyAllTurns(List<TurnRecord> turns) async {
    final l = AppLocalizations.of(context);
    final encoded = const JsonEncoder.withIndent('  ')
        .convert(turns.map((t) => t.toJson()).toList(growable: false));
    await Clipboard.setData(ClipboardData(text: encoded));
    if (!mounted) return;
    _snack(context, l.options_developer_recentTurns_copied(turns.length));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final recorder = ref.read(debugServiceProvider);
    return _OptionsCard(
      title: l.options_developer_title,
      subtitle: l.options_developer_subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _triggerLevelUp,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(l.options_developer_levelUp_button),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.s),
          Text(
            l.options_developer_triggerQuestion_title,
            style: text.titleSmall,
          ),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Text(l.options_developer_difficulty_label),
              const SizedBox(width: AppSpacing.m),
              DropdownButton<QuestionDifficulty>(
                value: _difficulty,
                onChanged: (v) {
                  if (v != null) setState(() => _difficulty = v);
                },
                items: QuestionDifficulty.values
                    .map((d) => DropdownMenuItem(value: d, child: Text(d.name)))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.s,
            children: [
              for (final (type, label) in _questionTypes)
                OutlinedButton(
                  onPressed: () => _triggerQuestion(type),
                  child: Text(label),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.s),
          Row(
            children: [
              Expanded(
                child: Text(
                  l.options_developer_recentTurns_title,
                  style: text.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: recorder.buffer.isEmpty
                    ? null
                    : () => _copyAllTurns(recorder.buffer),
                icon: const Icon(Icons.copy_all, size: 18),
                label: Text(l.options_developer_recentTurns_copyAll),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            height: 240,
            child: _RecentTurnsList(turns: recorder.buffer),
          ),
        ],
      ),
    );
  }
}

class _RecentTurnsList extends StatelessWidget {
  const _RecentTurnsList({required this.turns});

  final List<TurnRecord> turns;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (turns.isEmpty) {
      return Center(child: Text(l.options_developer_recentTurns_empty));
    }
    final reversed = turns.reversed.toList(growable: false);
    return ListView.separated(
      itemCount: reversed.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final t = reversed[i];
        final p = t.persisted;
        final fallback = p?.hadFallback == true;
        final reason = p?.selectionReason;
        final isFu = p?.isFollowUp == true;
        final hasFu = t.followUp != null;
        final events = p?.signalEvents ?? const <TurnSignalEvent>[];
        final eventsLabel = events
            .map((e) => '${e.kind.name}/${e.severity.name}')
            .join(', ');
        return ListTile(
          dense: true,
          tileColor: fallback
              ? Theme.of(ctx).colorScheme.errorContainer.withValues(alpha: 0.4)
              : null,
          title: Row(
            children: [
              if (isFu)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'FU d=${p?.chainDepth ?? 0}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  '#${t.turnId}  ${t.requestType}'
                  '${p == null ? '' : '  → ${p.overallQuality.name}'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          subtitle: Text(
            [
              if (reason != null) reason.chosenReason,
              if (reason?.notchDropFired == true) 'notch-dropped',
              if (p != null) 'targets: ${p.targetLOIds.join(", ")}',
              if (p != null)
                'cal: ${p.calibrationBefore.name}→${p.calibrationAfter.name}',
              if (fallback) 'FALLBACK',
              if (hasFu) 'followUp: "${t.followUp!.question}"',
              if (events.isNotEmpty) 'events: $eventsLabel',
            ].whereType<String>().join(' · '),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _showTurnDetail(ctx, t),
        );
      },
    );
  }

  void _showTurnDetail(BuildContext ctx, TurnRecord t) {
    final l = AppLocalizations.of(ctx);
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(l.options_developer_turnDetail_title(t.turnId)),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(t.toJson()),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.options_developer_turnDetail_close),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// About
// ---------------------------------------------------------------------------

/// The running build's version and the only place the update check can be
/// *asked* for (#48).
///
/// The shell's offer bar reacts to a check; the check itself, and the reason
/// one failed, are read here on demand. That split is what lets a failed
/// check stay silent — the news has somewhere to sit without going looking
/// for the student. It also has to work on a build that never checks by
/// itself: `autoCheck` is `kReleaseMode` (#47), so on a `flutter run`
/// checkout this button is the *only* way the feature runs at all.
class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final update = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final release = update.release;

    return _OptionsCard(
      title: l.options_about_title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.appTitle, style: text.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(l.options_about_version(kAppVersion), style: text.bodySmall),
          const SizedBox(height: AppSpacing.m),
          Text(
            updateStatusText(l, update),
            key: const ValueKey('about-update-status'),
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.s,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('about-update-check'),
                onPressed: update.busy ? null : controller.check,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l.update_action_check),
              ),
              // Offered only when there is genuinely something to apply. With
              // the shell's Update button this is the whole consent gate: no
              // other code path reaches `apply()`.
              if (release != null)
                FilledButton.icon(
                  key: const ValueKey('about-update-apply'),
                  onPressed: update.busy ? null : controller.apply,
                  icon: const Icon(Icons.system_update_alt_outlined, size: 18),
                  label: Text(l.update_action_applyVersion(release.version)),
                ),
            ],
          ),
          if (update.phase == UpdatePhase.downloading) ...[
            const SizedBox(height: AppSpacing.m),
            UpdateProgressBar(
              key: const ValueKey('about-update-progress'),
              progress: update.progress,
            ),
          ],
        ],
      ),
    );
  }
}
