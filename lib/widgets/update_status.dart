/// The places an update is visible, and the one sentence they share (#48).
///
/// Before this the update announced itself: a `barrierDismissible: false`
/// dialog with a single OK button, and closing it started a ~250 MB download
/// and an unconditional install. A student mid-lesson on a metered connection
/// could not say "not now", saw no progress, and then watched the app vanish
/// when the installer launched.
///
/// What replaces it is deliberately not a dialog. [UpdateOfferBar] is a strip
/// of chrome at the top of the shell with **Update** and **Later**: it waits
/// instead of interrupting, and `apply()` is reachable only from a button a
/// person pressed. The same state is rendered again in Options → About, where
/// a check can also be *asked* for — including on a debug build, which never
/// checks by itself (#47).
///
/// [UpdateCheckFailedNotice] takes the same strip for the opposite news
/// (#124): the launch's own check did not complete. Until then that failure
/// was a `debugPrint` and a line in About that nobody opens, and students
/// behind a TLS-inspecting school filter sat two releases behind without a
/// hint. It says where the reason is and has one button, which closes it.
///
/// [UpdateRequiredScreen] is the one place the update is not optional (#165):
/// what a build below the minimum version the school has set on
/// `config/global` gets instead of the app. A student who took **Later** on
/// every launch kept writing with a build that did not know the fields
/// later builds added, and every write erased them again; the strip's third
/// option was exactly the problem there, so this screen has **Update** or
/// **Check for updates**, and no way past.
library;

import 'dart:async';

import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_required.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One sentence for wherever the update flow has got to.
///
/// The phases the app can describe itself get a translated sentence; only
/// [UpdatePhase.failed] falls back to `UpdateState.message`, because the
/// reason a check or a download failed is a server's words, not the app's.
String updateStatusText(AppLocalizations l, UpdateState state) {
  final version = state.release?.version ?? '';
  return switch (state.phase) {
    UpdatePhase.idle => l.update_status_idle,
    UpdatePhase.checking => l.update_status_checking,
    UpdatePhase.upToDate => l.update_status_upToDate,
    UpdatePhase.available => l.update_status_available(version),
    UpdatePhase.downloading => l.update_status_downloading(version),
    UpdatePhase.applying => l.update_status_applying(version),
    UpdatePhase.failed => l.update_status_failed(state.message),
  };
}

/// A determinate bar once the download's size is known, an indeterminate one
/// until then.
///
/// `progress == 0` means the server sent no `Content-Length`, not that
/// nothing has arrived — a bar frozen at 0% reads as a hang, a moving one
/// reads as work.
class UpdateProgressBar extends StatelessWidget {
  const UpdateProgressBar({super.key, required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    value: progress > 0 ? progress : null,
    minHeight: 4,
    backgroundColor: AppColors.ink3,
    color: AppColors.accent,
  );
}

/// The strip that offers a newer release, and then shows it arriving.
///
/// Two buttons and no third: **Update** applies it, **Later** puts the bar
/// away until the next launch or the next manual check. There is deliberately
/// no "always update" — the consent is per update, because the cost of
/// getting it wrong is the app closing in the middle of an exercise.
/// The strip that says the launch's own update check failed (#124).
///
/// Thinner than [UpdateOfferBar] and with nothing to accept: the reason is
/// a server's or a network's words and belongs in About, where the same
/// state renders it in full beside **Check for updates**. Only a check the
/// app ran by itself gets this — see [UpdateState.checkFailed] — and closing
/// it is for the session.
class UpdateCheckFailedNotice extends ConsumerWidget {
  const UpdateCheckFailedNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final controller = ref.read(updateControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    return Material(
      key: const ValueKey('update-check-failed'),
      color: AppColors.ink2,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: AppColors.fgMute, size: 18),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Text(
                l.update_notice_checkFailed,
                key: const ValueKey('update-check-failed-message'),
                style: text.bodySmall,
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            IconButton(
              key: const ValueKey('update-check-failed-dismiss'),
              tooltip: l.update_notice_dismiss,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: controller.dismissNotice,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class UpdateOfferBar extends ConsumerWidget {
  const UpdateOfferBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final text = Theme.of(context).textTheme;

    return Material(
      key: const ValueKey('update-offer'),
      color: AppColors.ink2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.s,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.system_update_alt_outlined,
                  color: AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Text(
                    updateStatusText(l, state),
                    key: const ValueKey('update-offer-message'),
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                FilledButton(
                  key: const ValueKey('update-offer-apply'),
                  onPressed: state.busy ? null : controller.apply,
                  child: Text(l.update_action_apply),
                ),
                const SizedBox(width: AppSpacing.s),
                TextButton(
                  key: const ValueKey('update-offer-later'),
                  onPressed: state.busy ? null : controller.dismiss,
                  child: Text(l.update_action_later),
                ),
              ],
            ),
          ),
          if (state.phase == UpdatePhase.downloading)
            UpdateProgressBar(
              key: const ValueKey('update-offer-progress'),
              progress: state.progress,
            ),
        ],
      ),
    );
  }
}

/// The screen a build below the school's minimum version gets instead of the
/// app (#165). Mounted by `GoalsApp` in front of `AppShell`, so there is no
/// shell behind it, no session, and nothing that writes a student document.
///
/// Deliberately not the offer bar with **Later** removed: the bar is chrome
/// on top of a working app, and here there is no app to work. It says why in
/// the student's terms — the version running and the version required — and
/// then gives the one way forward: **Update to …** when a release is on
/// offer, **Check for updates** when none is (a check that failed, a debug
/// build that never checks by itself, nothing published yet), with the
/// download's progress and the check's outcome in the same sentence the
/// offer bar uses. `apply()` is still reached only from the button.
///
/// The shell's launch check (`AppShell.initState`) never runs while this
/// stands in for the shell, so it runs from here instead — the same call,
/// under the same rules (#47): nothing on a build that does not check by
/// itself, and never an install without a press.
class UpdateRequiredScreen extends ConsumerStatefulWidget {
  const UpdateRequiredScreen({super.key, required this.requirement});

  final UpdateRequirement requirement;

  @override
  ConsumerState<UpdateRequiredScreen> createState() =>
      _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends ConsumerState<UpdateRequiredScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(updateControllerProvider.notifier).start());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final text = Theme.of(context).textTheme;
    final release = state.release;

    return Scaffold(
      key: const ValueKey('update-required'),
      backgroundColor: AppColors.ink0,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.system_update_alt_outlined,
                  color: AppColors.accent,
                  size: 40,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  l.update_required_title,
                  key: const ValueKey('update-required-title'),
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.m),
                Text(
                  l.update_required_message(
                    widget.requirement.localVersion,
                    widget.requirement.minimumVersion,
                  ),
                  key: const ValueKey('update-required-message'),
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  updateStatusText(l, state),
                  key: const ValueKey('update-required-status'),
                  style: text.bodySmall?.copyWith(color: AppColors.fgMute),
                  textAlign: TextAlign.center,
                ),
                if (state.phase == UpdatePhase.downloading) ...[
                  const SizedBox(height: AppSpacing.m),
                  UpdateProgressBar(
                    key: const ValueKey('update-required-progress'),
                    progress: state.progress,
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: release != null
                      ? FilledButton(
                          key: const ValueKey('update-required-apply'),
                          onPressed: state.busy ? null : controller.apply,
                          child: Text(
                            l.update_action_applyVersion(release.version),
                          ),
                        )
                      : FilledButton(
                          key: const ValueKey('update-required-check'),
                          onPressed: state.busy ? null : controller.check,
                          child: Text(l.update_action_check),
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
