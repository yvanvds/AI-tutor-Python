import 'package:flutter/material.dart';

/// Who sent a message.
enum MessageRole { system, user, ai }

@immutable
class MessageEntry {
  final String id;
  final MessageRole role;
  final String text;
  final DateTime createdAt;

  const MessageEntry({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
  });

  MessageEntry copyWith({MessageRole? role, String? text}) => MessageEntry(
    id: id,
    role: role ?? this.role,
    text: text ?? this.text,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory MessageEntry.fromJson(Map<String, dynamic> json) => MessageEntry(
    id: json['id'] as String,
    role: MessageRole.values.firstWhere((r) => r.name == json['role']),
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
