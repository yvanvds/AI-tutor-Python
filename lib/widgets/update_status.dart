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
library;

import 'package:ai_tutor_python/core/update_controller.dart';
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
