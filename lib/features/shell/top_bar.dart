import 'dart:math' as math;

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:ai_tutor_python/widgets/first_that_fits.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double topBarHeight = 64;

class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    final inSession = section == Section.session;

    return SizedBox(
      height: topBarHeight,
      child: Stack(
        children: [
          // Body row
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.ink0,
                border: Border(
                  bottom: BorderSide(color: AppColors.ink2, width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              child: _TopBarRow(
                greeting: const _Greeting(),
                // Outside Session the switcher fades out and then gives its
                // place back (#258): an invisible one that still took its
                // ~220 px squeezed the stat strip into an overflow.
                modes: AnimatedSwitcher(
                  duration: AppDurations.modeFade,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.center,
                    children: [
                      // On its way out it no longer takes a click.
                      for (final p in previous) IgnorePointer(child: p),
                      ?current,
                    ],
                  ),
                  child: inSession
                      ? const ModeSwitcher(key: ValueKey('modes'))
                      : const SizedBox.shrink(),
                ),
                stats: const StatStrip(),
              ),
            ),
          ),
          // 2px ambient progress line at the very top edge
          const Positioned(top: 0, left: 0, right: 0, child: AmbientProgress()),
        ],
      ),
    );
  }
}

/// Rounding slack when a width is compared with the room for it.
const double _tolerance = 1e-6;

enum _BarSlot { greeting, modes, stats }

/// Between the greeting, the mode switcher and the stat strip.
const double _barGap = AppSpacing.lg;

/// The top bar's row (#258): the greeting on the left, the mode switcher in
/// the middle and the stat strip on the right, and never wider than the bar.
///
/// The room goes first to what can give least:
///  1. The mode switcher takes its natural width. It is the one control up
///     here and does not shrink. Outside Session it is gone, and so is its
///     place.
///  2. The stat strip gets the room on its side of a centred switcher — or,
///     with no switcher, all the greeting does not need and at least half —
///     and shows the richest form of itself that fits ([FirstThatFits]).
///     When even its narrowest form needs more, it takes that from the
///     greeting's side and the switcher moves left to make way.
///  3. The greeting gets what is left, and ellipsizes.
///
/// A window too narrow for the switcher on its own clips the row rather than
/// paint past the bar.
class _TopBarRow
    extends SlottedMultiChildRenderObjectWidget<_BarSlot, RenderBox> {
  const _TopBarRow({
    required this.greeting,
    required this.modes,
    required this.stats,
  });

  final Widget greeting;
  final Widget modes;
  final Widget stats;

  @override
  Iterable<_BarSlot> get slots => _BarSlot.values;

  @override
  Widget childForSlot(_BarSlot slot) => switch (slot) {
    _BarSlot.greeting => greeting,
    _BarSlot.modes => modes,
    _BarSlot.stats => stats,
  };

  @override
  _RenderTopBarRow createRenderObject(BuildContext context) =>
      _RenderTopBarRow();
}

class _RenderTopBarRow extends RenderBox
    with SlottedContainerRenderObjectMixin<_BarSlot, RenderBox> {
  RenderBox get _greeting => childForSlot(_BarSlot.greeting)!;
  RenderBox get _modes => childForSlot(_BarSlot.modes)!;
  RenderBox get _stats => childForSlot(_BarSlot.stats)!;

  bool _clipped = false;
  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  double _gaps(double modesWidth) => modesWidth > 0 ? 2 * _barGap : _barGap;

  @override
  double computeMinIntrinsicWidth(double height) {
    final modes = _modes.getMaxIntrinsicWidth(height);
    return modes + _stats.getMinIntrinsicWidth(height) + _gaps(modes);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final modes = _modes.getMaxIntrinsicWidth(height);
    return _greeting.getMaxIntrinsicWidth(height) +
        modes +
        _stats.getMaxIntrinsicWidth(height) +
        _gaps(modes);
  }

  @override
  double computeMinIntrinsicHeight(double width) => children.fold(
    0,
    (most, c) => math.max(most, c.getMinIntrinsicHeight(double.infinity)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => children.fold(
    0,
    (most, c) => math.max(most, c.getMaxIntrinsicHeight(double.infinity)),
  );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : getMaxIntrinsicWidth(double.infinity),
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : getMaxIntrinsicHeight(double.infinity),
        ),
      );

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : getMaxIntrinsicWidth(constraints.maxHeight);
    final maxHeight = constraints.maxHeight;
    BoxConstraints upTo(double maxWidth) =>
        BoxConstraints(maxWidth: math.max(0, maxWidth), maxHeight: maxHeight);

    // 1. The switcher, as wide as it is.
    final modes = _modes..layout(upTo(double.infinity), parentUsesSize: true);
    final modesWidth = modes.size.width;
    final withModes = modesWidth > 0;

    // 2. The strip: its side of the switcher, or what its narrowest form
    //    needs beyond that — never the switcher's own room.
    final stats = _stats;
    final statsLeast = stats.getMinIntrinsicWidth(maxHeight);
    final statsMost = width - modesWidth - _gaps(modesWidth);
    final statsShare = withModes
        ? (width - modesWidth) / 2 - _barGap
        : math.max(
            statsMost / 2,
            statsMost - _greeting.getMaxIntrinsicWidth(maxHeight),
          );
    stats.layout(
      upTo(
        statsLeast <= statsShare ? statsShare : math.min(statsLeast, statsMost),
      ),
      parentUsesSize: true,
    );
    final statsX = width - stats.size.width;

    // 3. The switcher centred, unless the strip needs some of that.
    final modesX = withModes
        ? math.max(
            0.0,
            math.min((width - modesWidth) / 2, statsX - _barGap - modesWidth),
          )
        : 0.0;

    // 4. The greeting in what is left.
    final greeting = _greeting
      ..layout(
        upTo((withModes ? modesX : statsX) - _barGap),
        parentUsesSize: true,
      );

    final height = constraints.hasBoundedHeight
        ? maxHeight
        : children.fold(0.0, (most, c) => math.max(most, c.size.height));
    size = constraints.constrain(Size(width, height));
    void place(RenderBox child, double x) =>
        (child.parentData! as BoxParentData).offset = Offset(
          x,
          (size.height - child.size.height) / 2,
        );
    place(greeting, 0);
    place(modes, modesX);
    place(stats, statsX);
    _clipped = modesX + modesWidth > size.width + _tolerance;
  }

  void _paintChildren(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        offset + (child.parentData! as BoxParentData).offset,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_clipped) {
      _clip.layer = null;
      _paintChildren(context, offset);
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintChildren,
      oldLayer: _clip.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final offset = (child.parentData! as BoxParentData).offset;
      final hit = result.addWithPaintOffset(
        offset: offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final section = ref.watch(sectionProvider);
    final l = AppLocalizations.of(context);

    final subline = section == Section.session
        ? (profile.topic.isEmpty
              ? l.topBar_subline_default
              : l.topBar_subline_withTopic(profile.topic))
        : section.label(context);

    final name = profile.name.isEmpty ? '...' : profile.name;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.topBar_greeting(name),
          style: TextStyle(
            color: AppColors.fg,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          subline,
          style: TextStyle(
            color: AppColors.fgMute,
            fontSize: 12.5,
            fontWeight: FontWeight.w400,
            height: 1.3,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class ModeSwitcher extends ConsumerWidget {
  const ModeSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(modeProvider);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in SessionMode.values)
            _ModeButton(
              mode: m,
              active: m == mode,
              onTap: () => ref.read(modeProvider.notifier).state = m,
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatefulWidget {
  const _ModeButton({
    required this.mode,
    required this.active,
    required this.onTap,
  });

  final SessionMode mode;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ModeButton> createState() => _ModeButtonState();
}

class _ModeButtonState extends State<_ModeButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? AppColors.ink3
        : (_hovering ? AppColors.ink2 : Colors.transparent);
    final fg = widget.active ? AppColors.fg : AppColors.fgMute;

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
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            widget.mode.label(context),
            style: TextStyle(
              color: fg,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// How much the stat strip spells out, richest first (#258).
///
/// With less room the strip drops one detail at a time: first the word
/// "days" after the streak, then the XP count in the level pill. What is
/// dropped stays in the chip's tooltip. The strip shows the first density
/// that fits; the top bar makes room for the last one.
enum StatStripDensity {
  full,
  noDaysWord,
  noXpCount;

  bool get daysWord => index < noDaysWord.index;
  bool get xpCount => index < noXpCount.index;
}

class StatStrip extends ConsumerWidget {
  const StatStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    return FirstThatFits(
      children: [
        for (final density in StatStripDensity.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StreakChip(streak: p.streak, withWord: density.daysWord),
              const SizedBox(width: AppSpacing.s),
              _XpPill(
                level: p.level,
                xp: p.xp,
                xpNext: p.xpNext,
                withCount: density.xpCount,
              ),
            ],
          ),
      ],
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak, required this.withWord});
  final int streak;

  /// The word "days" after the number; without it, it is in the tooltip.
  final bool withWord;

  @override
  Widget build(BuildContext context) {
    final word = AppLocalizations.of(context).topBar_streak_days;
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.ink1,
        border: Border.all(color: AppColors.ink2),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 14,
            color: AppColors.accent,
          ),
          const SizedBox(width: 4),
          Text('$streak', style: AppMono.tnum(size: 12.5, color: AppColors.fg)),
          if (withWord) ...[
            const SizedBox(width: 4),
            Text(
              word,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.fgMute,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
    return withWord ? chip : Tooltip(message: '$streak $word', child: chip);
  }
}

/// The level pill's width with its XP count, and without it. A floor, not a
/// fixed width: a longer level or count widens the pill instead of running
/// out of it.
const double _xpPillWidth = 152;
const double _xpPillCompactWidth = 80;

class _XpPill extends StatelessWidget {
  const _XpPill({
    required this.level,
    required this.xp,
    required this.xpNext,
    required this.withCount,
  });

  final int level;
  final int xp;
  final int xpNext;

  /// The "xp / next" count right of the level; without it, it is in the
  /// tooltip.
  final bool withCount;

  @override
  Widget build(BuildContext context) {
    final fraction = xpNext <= 0 ? 0.0 : (xp / xpNext).clamp(0.0, 1.0);
    final count = '$xp / $xpNext';
    final pill = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: withCount ? _xpPillWidth : _xpPillCompactWidth,
      ),
      child: IntrinsicWidth(
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.ink1,
            border: Border.all(color: AppColors.ink2),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    AppLocalizations.of(context).topBar_xp_level(level),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.fg,
                    ),
                  ),
                  if (withCount) ...[
                    const SizedBox(width: AppSpacing.s),
                    const Spacer(),
                    Text(
                      count,
                      style: AppMono.tnum(
                        size: 10.5,
                        weight: FontWeight.w500,
                        color: AppColors.fgMute,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  height: 3,
                  // Positioned, so the bar has no width of its own to give
                  // the pill's IntrinsicWidth: it spans what the text needs.
                  // (A fraction of 0 has none to give either: 0 / 0.)
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: AppColors.ink2)),
                      Positioned.fill(
                        child: AnimatedFractionallySizedBox(
                          duration: AppDurations.progressFill,
                          curve: AppCurves.layout,
                          widthFactor: fraction,
                          alignment: Alignment.centerLeft,
                          child: ColoredBox(color: AppColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return withCount ? pill : Tooltip(message: count, child: pill);
  }
}

class AmbientProgress extends ConsumerWidget {
  const AmbientProgress({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(ambientProgressProvider).clamp(0.0, 1.0);
    return SizedBox(
      height: 2,
      child: Stack(
        children: [
          Container(color: AppColors.ink2),
          AnimatedFractionallySizedBox(
            duration: AppDurations.progressFill,
            curve: AppCurves.layout,
            widthFactor: progress,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
