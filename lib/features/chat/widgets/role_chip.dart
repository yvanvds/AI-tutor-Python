import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

/// Optional tag shown above a tutor bubble. Set on `TextMessage.metadata['role']`
/// using the enum's `name` (e.g. `'uitleg'`).
enum TutorRole { uitleg, voorbeeld, denkvraag, goed }

TutorRole? tutorRoleFromMetadata(Map<String, dynamic>? metadata) {
  final raw = metadata?['role'];
  if (raw is! String) return null;
  for (final r in TutorRole.values) {
    if (r.name == raw) return r;
  }
  return null;
}

class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});

  final TutorRole role;

  @override
  Widget build(BuildContext context) {
    final s = _styleFor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s, vertical: 3),
      decoration: BoxDecoration(
        color: s.bg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 11, color: s.fg),
          const SizedBox(width: 4),
          Text(
            role.name,
            style: TextStyle(
              color: s.fg,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  _RoleStyle _styleFor(TutorRole role) {
    switch (role) {
      case TutorRole.uitleg:
        return _RoleStyle(
          bg: AppColors.accent3.withValues(alpha: 0.14),
          border: AppColors.accent3.withValues(alpha: 0.4),
          fg: AppColors.accent3,
          icon: Icons.lightbulb_outline,
        );
      case TutorRole.voorbeeld:
        return _RoleStyle(
          bg: AppColors.ink2,
          border: AppColors.ink3,
          fg: AppColors.fgMute,
          icon: Icons.code,
        );
      case TutorRole.denkvraag:
        return _RoleStyle(
          bg: AppColors.accent.withValues(alpha: 0.14),
          border: AppColors.accent.withValues(alpha: 0.4),
          fg: AppColors.accent,
          icon: Icons.help_outline,
        );
      case TutorRole.goed:
        return _RoleStyle(
          bg: AppColors.accent2.withValues(alpha: 0.16),
          border: AppColors.accent2.withValues(alpha: 0.5),
          fg: AppColors.accent2,
          icon: Icons.check,
        );
    }
  }
}

class _RoleStyle {
  const _RoleStyle({
    required this.bg,
    required this.border,
    required this.fg,
    required this.icon,
  });
  final Color bg;
  final Color border;
  final Color fg;
  final IconData icon;
}
