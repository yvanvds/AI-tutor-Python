/// Authored explanation block for a subgoal. Lives in the `content` Cosmos
/// container (single-partition, `/type = "content"`). Rendered by
/// `explain_view.dart` (inside a WebView styled by `assets/lesson/lesson.css`)
/// and edited in the teacher's "Lesinhoud" view.
///
/// `body` is an HTML body fragment — what goes inside `<body class="lesson">`,
/// not a full document. The WebView host wraps it at render time. Lesson
/// HTML must not contain navigation CTAs ("try it yourself" etc.); those are
/// Flutter chrome around the canvas.
class Content {
  Content({
    required this.id,
    required this.title,
    required this.body,
    this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final DateTime? updatedAt;

  Content copyWith({String? title, String? body}) {
    return Content(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': 'content',
    'title': title,
    'body': body,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };

  factory Content.fromCosmos(Map<String, dynamic> doc) {
    final raw = doc['updatedAt'];
    DateTime? parsedAt;
    if (raw is String && raw.isNotEmpty) parsedAt = DateTime.tryParse(raw);
    return Content(
      id: doc['id'] as String,
      title: (doc['title'] as String?) ?? '',
      body: (doc['body'] as String?) ?? '',
      updatedAt: parsedAt,
    );
  }
}
