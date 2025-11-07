import 'package:ai_tutor_python/services/data_service.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:flutter/material.dart';

class ParentField extends StatelessWidget {
  const ParentField({super.key, required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    // Only roots in the parent dropdown
    final rootsAsync = DataService.goals.streamRoots!;

    Widget result;
    result = StreamBuilder<List<Goal>>(
      stream: rootsAsync,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 56,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          return Text('Failed to load parents: ${snapshot.error}');
        }
        final roots = snapshot.data ?? [];
        final items = <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('(no parent)'),
          ),
          ...roots.map(
            (g) => DropdownMenuItem<String?>(value: g.id, child: Text(g.title)),
          ),
        ];
        return DropdownButtonFormField<String?>(
          initialValue: goal.parentId, // may be null
          items: items,
          onChanged: (newParent) async {
            if (newParent == goal.parentId) return;
            await DataService.goals.reparent(goal.id, newParent);
          },
          decoration: const InputDecoration(
            labelText: 'Parent',
            border: OutlineInputBorder(),
          ),
        );
      },
    );

    return result;
  }
}
