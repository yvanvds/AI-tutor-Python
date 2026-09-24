import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const double sidebarWidth = 72;

/// The 44 px touch target of one rail entry, and the margin around it.
///
/// 48 until #185: the Questions entry took the one entry of slack #156 had
/// put back, and 44 — with the logo's gaps below trimmed — buys it back. The
/// entry stays square: its highlight is inset to the same 44 px across.
const double _itemHeight = 44;
const double _itemMargin = 1;

/// The highlight's inset from the rail's edges, so it is as wide as it is
/// tall.
const double _itemInset = (sidebarWidth - _itemHeight) / 2;

/// The vertical room one rail entry takes — its touch target plus margin.
///
/// Exported so a test can state the rail's invariant (#156) in entries
/// rather than in re-derived pixels: at the window the Windows runner
/// creates (1280x720) the rail must still fit, with a whole entry of slack
/// for the next feature that wants one.
const double sidebarItemExtent = _itemHeight + 2 * _itemMargin;

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  // Everyone gets the grade formula (#129): it is written for students,
  // and a teacher reads the same document the students do.
  //
  // "My reports" (#151) sits right after it — the formula explains the
  // number, this is where the number arrives. Unlike the formula it is
  // `isStudentOnly`: it lists the signed-in user's own published reports, so
  // a teacher would get an empty page next to the class-wide `reports` entry
  // they actually want. That mirror rule stands on its own merits: the rail
  // no longer depends on it to fit a 720 px window (#156).
  static const _studentSections = [
    Section.session,
    Section.map,
    Section.puntenformule,
    Section.myReports,
  ];

  static const _teacherSections = [
    Section.goals,
    Section.lessonContent,
    // Next to the lesson content: the questions asked about it (#185).
    Section.questions,
    Section.instructions,
    Section.students,
    Section.milestones,
    Section.reports,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final selected = ref.watch(sectionProvider);
    final devTools = ref.watch(developerToolsProvider);
    final studentSections = _studentSections.where(
      (s) => !profile.isTeacher || !s.isStudentOnly,
    );
    final teacherSections = _teacherSections.where(
      (s) => devTools || !s.isDeveloperOnly,
    );

    return Container(
      width: sidebarWidth,
      color: AppColors.ink1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.m),
          const _Logo(),
          const SizedBox(height: AppSpacing.lg),
          // The destinations scroll; Options and sign-out stay pinned to the
          // bottom (#156). Before this they sat in this Column under a
          // `Spacer()`, which has no room to give: the rail grew a section
          // per feature — #25, #26, #99, #129, #148 — until a teacher's had
          // 31 px left at the 720 px window the Windows runner creates, less
          // than the one entry #151 then added, and the tenth entry clipped
          // the sign-out off the bottom behind a RenderFlex overflow.
          //
          // The scroll view is the safety net for a window shorter than the
          // rail — a laptop minus its taskbar, a half-height window, the
          // update bar above the shell — and not a licence to stop fitting:
          // the item margin and the pre-header gap below are tightened by
          // the 28 px that puts a whole entry of slack back at 720 px, so
          // every entry stays reachable *without* scrolling there. That is
          // what the flows tapping `find.byTooltip('Reports')` with no
          // `ensureVisible` rely on, and what the two height tests in
          // `test/features/shell/sidebar_test.dart` and the `sidebar_rail`
          // flow now hold to.
          Expanded(
            child: SingleChildScrollView(
              key: const Key('sidebar-destinations'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...studentSections.map(
                    (s) => _SidebarItem(
                      section: s,
                      icon: _iconFor(s),
                      active: selected == s,
                      onTap: () => ref.read(sectionProvider.notifier).state = s,
                    ),
                  ),
                  if (profile.isTeacher) ...[
                    const SizedBox(height: AppSpacing.s),
                    _SidebarHeader(
                      label: AppLocalizations.of(context).sidebar_teacherHeader,
                    ),
                    const SizedBox(height: AppSpacing.s),
                    ...teacherSections.map(
                      (s) => _SidebarItem(
                        section: s,
                        icon: _iconFor(s),
                        active: selected == s,
                        onTap: () =>
                            ref.read(sectionProvider.notifier).state = s,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Options panel (issue #25): settings, progress reset, API key,
          // bug reports and — behind the developer gate — the debug tools.
          _SidebarItem(
            section: Section.options,
            icon: _iconFor(Section.options),
            active: selected == Section.options,
            onTap: () =>
                ref.read(sectionProvider.notifier).state = Section.options,
          ),
          _SidebarIconButton(
            tooltip: AppLocalizations.of(context).sidebar_signOut_tooltip,
            icon: Icons.logout,
            onTap: () => ref.read(authServiceProvider.notifier).signOut(),
          ),
          const SizedBox(height: AppSpacing.m),
        ],
      ),
    );
  }

  static IconData _iconFor(Section s) {
    switch (s) {
      case Section.session:
        return Icons.terminal_outlined;
      case Section.map:
        return Icons.insights_outlined;
      case Section.puntenformule:
        return Icons.calculate_outlined;
      case Section.myReports:
        return Icons.workspace_premium_outlined;
      case Section.goals:
        return Icons.flag_outlined;
      case Section.lessonContent:
        return Icons.menu_book_outlined;
      case Section.questions:
        return Icons.quiz_outlined;
      case Section.instructions:
        return Icons.integration_instructions_outlined;
      case Section.students:
        return Icons.people_outline;
      case Section.milestones:
        return Icons.event_available_outlined;
      case Section.reports:
        return Icons.assignment_outlined;
      case Section.options:
        return Icons.settings_outlined;
    }
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.accent, AppColors.accent2],
          ),
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
        ),
        child: Icon(
          Icons.auto_awesome_outlined,
          color: AppColors.ink0,
          size: 22,
        ),
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: Text(
        label.toUpperCase(),
        textAlign: TextAlign.center,
        // One line, always (#156): a translation long enough to wrap used to
        // add a line's height to the rail behind everyone's back.
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.fgFaint,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.section,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final Section section;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tinted = widget.active
        ? AppColors.ink2
        : (_hovering
              ? AppColors.ink2.withValues(alpha: 0.6)
              : Colors.transparent);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: widget.section.label(context),
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            height: _itemHeight,
            margin: const EdgeInsets.symmetric(vertical: _itemMargin),
            child: Stack(
              children: [
                if (widget.active)
                  Positioned(
                    left: 0,
                    top: 8,
                    bottom: 8,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: _itemInset),
                  decoration: BoxDecoration(
                    color: tinted,
                    borderRadius: BorderRadius.circular(AppRadius.inputLarge),
                  ),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: widget.active ? AppColors.fg : AppColors.fgMute,
                    ),
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

class _SidebarIconButton extends StatelessWidget {
  const _SidebarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: AppColors.fgFaint),
        onPressed: onTap,
        splashRadius: 18,
      ),
    );
  }
}
