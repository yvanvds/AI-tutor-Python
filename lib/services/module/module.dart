/// Top-level grouping of root goals. Wired into the data layer in v1 even
/// though only a single auto-bootstrapped "Python basics" module exists in
/// practice. Module-management UI is deferred — the Lesinhoud view groups
/// goals by `moduleId` so that adding more modules later doesn't require
/// re-shaping the editor.
class Module {
  Module({
    required this.id,
    required this.title,
    required this.order,
    this.updatedAt,
  });

  final String id;
  final String title;
  final int order;
  final DateTime? updatedAt;

  /// Stable id for the v1 default module. Bootstrapping is idempotent: if a
  /// doc with this id is missing, [ModuleService.ensureDefaultModule]
  /// upserts one.
  static const String defaultId = 'python-basics';

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': 'module',
    'title': title,
    'order': order,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory Module.fromCosmos(Map<String, dynamic> doc) {
    final raw = doc['updatedAt'];
    DateTime? parsedAt;
    if (raw is String && raw.isNotEmpty) parsedAt = DateTime.tryParse(raw);
    return Module(
      id: doc['id'] as String,
      title: (doc['title'] as String?) ?? '',
      order: (doc['order'] as int?) ?? 0,
      updatedAt: parsedAt,
    );
  }
}
