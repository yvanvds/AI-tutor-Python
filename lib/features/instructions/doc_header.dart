import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class DocHeader extends StatelessWidget {
  const DocHeader({
    super.key,
    required this.selectedDocId,
    required this.onRename,
  });
  final String? selectedDocId;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final id = selectedDocId ?? l.instructions_docHeader_noDoc;
    return ListTile(
      title: Text(
        id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: IconButton(
        tooltip: l.instructions_docHeader_renameTooltip,
        onPressed: selectedDocId == null ? null : onRename,
        icon: const Icon(Icons.drive_file_rename_outline),
      ),
    );
  }
}
