import 'package:cloud_firestore/cloud_firestore.dart';

// Model class representing a Goal.
class Goal {
  final String id;
  final String title;
  final String? description;
  final String? parentId;
  final int order;
  final bool optional;
  final List<String> suggestions;

  // Constructor
  Goal({
    required this.id,
    required this.title,
    this.description,
    this.parentId,
    required this.order,
    this.optional = false,
    this.suggestions = const [],
  });

  // Create a Goal from a Firestore document.
  factory Goal.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return Goal(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'],
      parentId: d['parentId'],
      order: d['order'] ?? 0,
      optional: d['optional'] ?? false,
      suggestions: List<String>.from(d['suggestions'] ?? []),
    );
  }

  // Convert a Goal to a map for Firestore storage.
  Map<String, dynamic> toMap() => {
    'title': title,
    'description': description,
    'parentId': parentId,
    'order': order,
    'optional': optional,
    'suggestions': suggestions,
  };
}
