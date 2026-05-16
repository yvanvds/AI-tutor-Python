import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ParentField extends ConsumerStatefulWidget {
  const ParentField({super.key, required this.goal});
  final Goal goal;

  @override
  ConsumerState<ParentField> createState() => _ParentFieldState();
}

class _ParentFieldState extends ConsumerState<ParentField> {
  late final Stream<List<Goal>> _rootsStream;

  @override
  void initState() {
    super.initState();
    _rootsStream = ref.read(goalsServiceProvider).streamRoots!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Goal>>(
      stream: _rootsStream,
      builder: (context, snapshot) {
        final l = AppLocalizations.of(context);
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          return Text(
              l.goals_parentField_loadFailed(snapshot.error.toString()));
        }
        final roots = snapshot.data ?? [];
        final items = <DropdownMenuItem<String?>>[
          DropdownMenuItem<String?>(
            value: null,
            child: Text(l.goals_parentField_noParent),
          ),
          ...roots.map(
            (g) =>
                DropdownMenuItem<String?>(value: g.id, child: Text(g.title)),
          ),
        ];
        return DropdownButtonFormField<String?>(
          initialValue: widget.goal.parentId,
          items: items,
          onChanged: (newParent) async {
            if (newParent == widget.goal.parentId) return;
            await ref.read(goalsServiceProvider).reparent(
              widget.goal.id,
              newParent,
            );
          },
          decoration: InputDecoration(
            labelText: l.goals_parentField_label,
            border: const OutlineInputBorder(),
          ),
        );
      },
    );
  }
}
