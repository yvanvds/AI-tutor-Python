import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

class McqOptionsWidget extends StatelessWidget {
  const McqOptionsWidget({super.key, required this.message});

  final CustomMessage message;

  @override
  Widget build(BuildContext context) {
    final metadata = message.metadata ?? const {};
    final options = (metadata['options'] as List?)?.cast<String>() ?? const [];
    final selected = metadata['selected'] as String?;
    final answered = selected != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in options)
            _OptionButton(
              label: option,
              isSelected: option == selected,
              isDisabled: answered,
              onTap: () => _onTap(option),
            ),
        ],
      ),
    );
  }

  void _onTap(String picked) {
    if (DataService.tutor.state.value != TutorState.idle) return;
    DataService.chat.markMcqAnswered(message, picked);
    DataService.chat.addMessage(picked);
    DataService.tutor.handleStudentMessage(picked);
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 18,
    );

    if (isSelected) {
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          disabledBackgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledForegroundColor: colors.onPrimary,
          textStyle: textStyle,
        ),
        child: Text(label),
      );
    }

    return OutlinedButton(
      onPressed: isDisabled ? null : onTap,
      style: OutlinedButton.styleFrom(textStyle: textStyle),
      child: Text(label),
    );
  }
}
