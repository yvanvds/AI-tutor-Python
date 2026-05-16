import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
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
    final l = AppLocalizations.of(context);
    return ListTile(
      title: Text(
        keyName ?? l.instructions_sectionHeader_noSection,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      trailing: IconButton(
        tooltip: l.instructions_sectionHeader_renameTooltip,
        onPressed: enabled ? onRename : null,
        icon: const Icon(Icons.drive_file_rename_outline),
      ),
    );
  }
}
