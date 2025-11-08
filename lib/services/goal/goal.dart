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
  final List<String> knownConcepts;

  // Constructor
  Goal({
    required this.id,
    required this.title,
    this.description,
    this.parentId,
    required this.order,
    this.optional = false,
    this.suggestions = const [],
    this.knownConcepts = const [],
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
      knownConcepts: List<String>.from(d['knownConcepts'] ?? []),
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
    'knownConcepts': knownConcepts,
  };

  factory Goal.fromMap({
    required String id,
    required Map<String, dynamic> map,
  }) {
    return Goal(
      id: id,
      title: map['title'] ?? '',
      description: map['description'],
      parentId: map['parentId'],
      order: map['order'] ?? 0,
      optional: map['optional'] ?? false,
      suggestions: List<String>.from(map['suggestions'] ?? []),
      knownConcepts: List<String>.from(map['knownConcepts'] ?? []),
    );
  }

  static List<Goal> fromFirebase(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map((data) {
      return Goal.fromMap(id: data.id, map: data.data());
    }).toList();
  }

  factory Goal.fromFirebaseDocument(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return Goal.fromMap(id: snapshot.id, map: snapshot.data()!);
  }
}
