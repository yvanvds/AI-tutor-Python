import 'package:flutter/material.dart';

/// A single code page/version in the timeline.
@immutable
class CodeEntry {
  final String id;
  final String code; // the full code for this page
  final int firstMessageIndex; // index into the global messages list

  const CodeEntry({
    required this.id,
    required this.code,
    required this.firstMessageIndex,
  });

  CodeEntry copyWith({String? code, int? firstMessageIndex}) => CodeEntry(
    id: id,
    code: code ?? this.code,
    firstMessageIndex: firstMessageIndex ?? this.firstMessageIndex,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'firstMessageIndex': firstMessageIndex,
  };

  factory CodeEntry.fromJson(Map<String, dynamic> json) => CodeEntry(
    id: json['id'] as String,
    code: json['code'] as String,
    firstMessageIndex: json['firstMessageIndex'] as int,
  );
}
