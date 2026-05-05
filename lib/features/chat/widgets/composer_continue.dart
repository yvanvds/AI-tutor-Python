import 'package:ai_tutor_python/features/chat/widgets/composer_chrome.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/theme/app_theme.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Accent-tinted bar shown when the tutor has more to say. Pressing the
/// button (or `Enter`) advances to the queued follow-up.
class ComposerContinue extends ConsumerStatefulWidget {
  const ComposerContinue({super.key});

  @override
  ConsumerState<ComposerContinue> createState() => _ComposerContinueState();
}

class _ComposerContinueState extends ConsumerState<ComposerContinue> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _go() {
    ref.read(tutorServiceProvider.notifier).moveToFollowUp();
  }

  @override
  Widget build(BuildContext context) {
    return ComposerChrome(
      background: AppColors.accent.withValues(alpha: 0.06),
      topBorder: AppColors.accent.withValues(alpha: 0.3),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _go,
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Klaar voor het volgende stuk?',
                  style: TextStyle(
                    color: AppColors.fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              _GoButton(onTap: _go),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoButton extends StatefulWidget {
  const _GoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_GoButton> createState() => _GoButtonState();
}

class _GoButtonState extends State<_GoButton> {
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
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
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
              const Text(
                'Ga verder',
                style: TextStyle(
                  color: AppColors.ink0,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text('↵', style: AppMono.kbd(color: AppColors.ink0)),
            ],
          ),
        ),
      ),
    );
  }
}
