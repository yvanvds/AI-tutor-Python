// Backup of a subtree for restore later.
class SubtreeBackup {
  SubtreeBackup(this.nodes);

  /// Each entry: id + full raw data map (including parentId, order, etc.)
  final List<(String id, Map<String, dynamic> data)> nodes;
}
