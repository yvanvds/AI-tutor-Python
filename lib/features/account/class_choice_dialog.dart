// The class of a student, chosen from the class list (#218).
//
// Until #218 this was a free-text field: the teacher typed the class for
// every new student, and a typo ("6 WEWI") made an extra class in the
// filters of the Students and Reports pages. Now the choice is one of the
// classes on the Classes page, or "no class". The same dialog serves one
// student (the class cell) and a selection (the bulk assignment, #91).
//
// The dialog pops the chosen class name, `''` for no class — the same value
// `AccountService.setClassName` takes — or nothing when it is cancelled.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';

class ClassChoiceDialog extends StatefulWidget {
  const ClassChoiceDialog({super.key, required this.classNames, this.initial});

  /// The classes in the class list, in the order to offer them.
  final List<String> classNames;

  /// The class the student has now — `''` for none — or `null` when there is
  /// no current class to show (a bulk assignment): then nothing is chosen
  /// yet and Save waits for a choice.
  ///
  /// A class that is not in [classNames] (a name typed before the class list
  /// existed) is offered as it is, marked, so opening the dialog never
  /// changes it by itself.
  final String? initial;

  @override
  State<ClassChoiceDialog> createState() => _ClassChoiceDialogState();
}

class _ClassChoiceDialogState extends State<ClassChoiceDialog> {
  late String? _choice = widget.initial;

  /// The student's current class when the list does not have it.
  String? get _unlistedInitial {
    final initial = widget.initial;
    if (initial == null || initial.isEmpty) return null;
    return widget.classNames.contains(initial) ? null : initial;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final unlisted = _unlistedInitial;
    final choice = _choice;
    return AlertDialog(
      title: Text(l.accounts_class_dialog_title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              key: const Key('class-choice'),
              isExpanded: true,
              value: choice,
              hint: Text(l.accounts_class_choice_hint),
              onChanged: (v) => setState(() => _choice = v),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(l.accounts_class_choice_none),
                ),
                for (final name in widget.classNames)
                  DropdownMenuItem(value: name, child: Text(name)),
                if (unlisted != null)
                  DropdownMenuItem(
                    value: unlisted,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            unlisted,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: AppColors.accent2,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (choice != null && choice == unlisted) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.accounts_class_choice_unlisted,
                key: const Key('class-choice-unlisted'),
                style: TextStyle(color: AppColors.accent2, fontSize: 12),
              ),
            ],
            if (widget.classNames.isEmpty) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                l.accounts_class_choice_noClasses,
                style: TextStyle(color: AppColors.fgFaint, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.accounts_class_dialog_cancel),
        ),
        FilledButton(
          key: const Key('class-choice-save'),
          onPressed: choice == null
              ? null
              : () => Navigator.pop(context, choice),
          child: Text(l.accounts_class_dialog_save),
        ),
      ],
    );
  }
}
