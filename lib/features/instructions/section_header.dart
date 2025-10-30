import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.keyName,
    required this.onRename,
    required this.enabled,
    super.key,
  });

  final String? keyName;
  final VoidCallback onRename;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(
        keyName ?? 'No section selected',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: IconButton(
        tooltip: 'Rename section',
        onPressed: enabled ? onRename : null,
        icon: const Icon(Icons.drive_file_rename_outline),
      ),
    );
  }
}
