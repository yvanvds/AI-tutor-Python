import 'package:flutter/material.dart';

class SectionsList extends StatelessWidget {
  const SectionsList({
    required this.sections,
    required this.selectedKey,
    required this.onSelect,
  });

  final Map<String, String> sections;
  final String? selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final keys = sections.keys.toList()..sort();
    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (context, i) {
        final k = keys[i];
        final selected = k == selectedKey;
        return ListTile(
          title: Text(k, maxLines: 1, overflow: TextOverflow.ellipsis),
          selected: selected,
          onTap: () => onSelect(k),
        );
      },
    );
  }
}
