import 'package:ai_tutor_python/services/instructions/instruction.dart';
import 'package:flutter/material.dart';

class DocsList extends StatelessWidget {
  const DocsList({
    super.key,
    required this.docs,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Instruction> docs;
  final String? selectedId;
  final ValueChanged<Instruction?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const ListTile(
          title: Text(
            'Documents',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i];
              final selected = d.id == selectedId;
              return ListTile(
                title: Text(d.id, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: selected,
                onTap: () => onSelect(d),
              );
            },
          ),
        ),
      ],
    );
  }
}
