/// The "What's new" card the app shows once, on the first launch after it
/// updated itself (#119).
///
/// Built on `LevelUpOverlay`'s shape — same blurred scrim, same pop-in, same
/// "tap outside or press the button" dismissal — because it is stacked in the
/// same place in the shell and should not read as a different kind of thing.
/// The one deliberate difference is that nothing times it away: the goal
/// splash hides itself after 10 s, but this appears on the very first frame
/// of a launch, when a student may well be looking at their keyboard.
///
/// **English only, by decision on the issue.** The release notes themselves
/// are whatever was typed on the GitHub release and are not translated, so
/// translating the two words of chrome around them would only make the card
/// read as half-localized. Nothing here goes through `AppLocalizations`.
///
/// The notes are Markdown by origin (a GitHub release body) and are rendered
/// as plain text, so what a release is written as is what a student reads.
/// Keep release bodies plain — short lines, `-` bullets — when cutting a
/// release with `tooling/build_release.ps1`.
library;

import 'dart:ui';

import 'package:ai_tutor_python/core/whats_new_controller.dart';
import 'package:ai_tutor_python/core/whats_new_store.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WhatsNewOverlay extends ConsumerWidget {
  const WhatsNewOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(whatsNewControllerProvider);

    return AnimatedSwitcher(
      duration: AppDurations.levelUpPopup,
      switchInCurve: AppCurves.levelUp,
      switchOutCurve: AppCurves.layout,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: notes == null
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : _WhatsNewScrim(
              key: const ValueKey('whats-new-overlay'),
              notes: notes,
              onDismiss: () =>
                  ref.read(whatsNewControllerProvider.notifier).dismiss(),
            ),
    );
  }
}

class _WhatsNewScrim extends StatelessWidget {
  const _WhatsNewScrim({
    super.key,
    required this.notes,
    required this.onDismiss,
  });

  final ReleaseNotes notes;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: AppColors.ink0.withValues(alpha: 0.8)),
            ),
          ),
          Center(
            // Swallows the tap so clicking inside the card does not dismiss
            // it — a student scrolling the notes is not asking to close them.
            child: GestureDetector(
              onTap: () {},
              child: _WhatsNewCard(notes: notes, onDismiss: onDismiss),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard({required this.notes, required this.onDismiss});

  final ReleaseNotes notes;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      margin: const EdgeInsets.all(AppSpacing.xxl),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.modal),
        boxShadow: [
          BoxShadow(
            blurRadius: 32,
            spreadRadius: 4,
            offset: const Offset(0, 12),
            color: Colors.black.withValues(alpha: 0.35),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UPDATED',
            key: const ValueKey('whats-new-caption'),
            style: TextStyle(
              color: AppColors.accent2,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            "What's new in ${notes.version}",
            key: const ValueKey('whats-new-title'),
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Bounded and scrollable: a release body has no length limit, and a
          // card that grows past the window would put its own button offscreen.
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Text(
                notes.notes.trim(),
                key: const ValueKey('whats-new-notes'),
                style: TextStyle(
                  color: AppColors.fgMute,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Align(
            alignment: Alignment.centerRight,
            child: _GotItButton(onTap: onDismiss),
          ),
        ],
      ),
    );
  }
}

class _GotItButton extends StatefulWidget {
  const _GotItButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_GotItButton> createState() => _GotItButtonState();
}

class _GotItButtonState extends State<_GotItButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        key: const ValueKey('whats-new-dismiss'),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.hover,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: _hovering
                ? Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.06),
                    AppColors.accent,
                  )
                : AppColors.accent,
            borderRadius: BorderRadius.circular(AppRadius.inputLarge),
          ),
          child: Text(
            'Got it',
            style: TextStyle(
              color: AppColors.ink0,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
