import 'package:flutter/material.dart';

class DocHeader extends StatelessWidget {
  const DocHeader({required this.selectedDocId, required this.onRename});
  final String? selectedDocId;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final id = selectedDocId ?? 'No document selected';
    return ListTile(
      title: Text(
        id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: IconButton(
        tooltip: 'Rename document',
        onPressed: selectedDocId == null ? null : onRename,
        icon: const Icon(Icons.drive_file_rename_outline),
      ),
    );
  }
}
