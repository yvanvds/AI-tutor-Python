import 'dart:ui';

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/progression/level_up_controller.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-screen "Level X" celebration. Listens to [levelUpControllerProvider];
/// when non-null, fades in a blurred backdrop and pops a centred card.
/// Tapping outside the card or the "Keep learning →" button dismisses.
class LevelUpOverlay extends ConsumerWidget {
  const LevelUpOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(levelUpControllerProvider);

    return AnimatedSwitcher(
      duration: AppDurations.levelUpPopup,
      switchInCurve: AppCurves.levelUp,
      switchOutCurve: AppCurves.layout,
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: event == null
          ? const SizedBox.shrink(key: ValueKey('empty'))
          : _LevelUpScrim(
              key: const ValueKey('shown'),
              event: event,
              onDismiss: () =>
                  ref.read(levelUpControllerProvider.notifier).dismiss(),
            ),
    );
  }
}

class _LevelUpScrim extends StatelessWidget {
  const _LevelUpScrim({
    super.key,
    required this.event,
    required this.onDismiss,
  });

  final LevelUpEvent event;
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
            child: GestureDetector(
              onTap: () {},
              child: _LevelUpCard(event: event, onDismiss: onDismiss),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelUpCard extends StatefulWidget {
  const _LevelUpCard({required this.event, required this.onDismiss});

  final LevelUpEvent event;
  final VoidCallback onDismiss;

  @override
  State<_LevelUpCard> createState() => _LevelUpCardState();
}

class _LevelUpCardState extends State<_LevelUpCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppDurations.levelUpPopup,
  )..forward();

  late final Animation<double> _scale = Tween(
    begin: 0.92,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _ctrl, curve: AppCurves.levelUp));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return ScaleTransition(
      scale: _scale,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.all(AppSpacing.xxl),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Caption(xpAwarded: e.xpAwarded),
            const SizedBox(height: AppSpacing.s),
            _LevelNumber(level: e.newLevel),
            const SizedBox(height: AppSpacing.m),
            _Subtitle(conceptName: e.conceptName),
            const SizedBox(height: AppSpacing.xl),
            _ContinueButton(onTap: widget.onDismiss),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.xpAwarded});
  final int xpAwarded;

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).levelUp_caption(xpAwarded),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.accent2,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _LevelNumber extends StatelessWidget {
  const _LevelNumber({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context).levelUp_level(level),
      textAlign: TextAlign.center,
      style: AppMono.tnum(
        size: 64,
        weight: FontWeight.w800,
        color: AppColors.fg,
      ).copyWith(height: 1.0, letterSpacing: -2),
    );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.conceptName});
  final String conceptName;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final concept = conceptName.trim();
    final text = concept.isEmpty
        ? l.levelUp_subtitle_generic
        : l.levelUp_subtitle_concept(concept);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.fgMute, fontSize: 14, height: 1.5),
    );
  }
}

class _ContinueButton extends StatefulWidget {
  const _ContinueButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).levelUp_button_continue,
                style: TextStyle(
                  color: AppColors.ink0,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward, size: 16, color: AppColors.ink0),
            ],
          ),
        ),
      ),
    );
  }
}
