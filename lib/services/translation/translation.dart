// A translation of Dutch source text (#206): a lesson from `content`, or the
// title and description of a goal from `goals`, in one other language.
//
// Translations live in their own container, `translations`, partitioned on
// `/language` (see `CosmosPaths.translations`), never inside the `content`
// or `goals` doc they translate: an upsert replaces a whole doc, so every
// writer that does not know about a translations field would wipe it, and
// every student would fetch every language on every poll.
//
// Dutch ([kSourceLanguage]) is the source language. It has no docs here: it
// stays in `content` and `goals`.
//
// A translation is stale when the Dutch text changed after it was made. That
// is decided by a hash of the Dutch text ([sourceHash], see
// [translationSourceHash]), not by a timestamp: `goals` docs have no
// `updatedAt`, and `Content.toMap` renews `updatedAt` on every save, whether
// anything changed or not.

import 'dart:convert';

import 'package:ai_tutor_python/services/content/content.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// The language lessons and goals are written in. Its text is in `content`
/// and `goals`; nothing is stored in or fetched from `translations` for it.
const String kSourceLanguage = 'nl';

/// What a [Translation] translates. The name is the doc id prefix and the
/// stored `kind`.
enum TranslationKind {
  /// A lesson: a `content` doc's `title` and `body`.
  content,

  /// A goal or subgoal: a `goals` doc's `title` and `description`.
  goal,
}

@immutable
class Translation {
  const Translation({
    required this.language,
    required this.kind,
    required this.refId,
    required this.title,
    required this.text,
    required this.sourceHash,
    this.updatedAt,
  });

  /// The translation of the lesson [contentId] (a `content` doc id).
  const Translation.content({
    required String language,
    required String contentId,
    required String title,
    required String body,
    required String sourceHash,
    DateTime? updatedAt,
  }) : this(
         language: language,
         kind: TranslationKind.content,
         refId: contentId,
         title: title,
         text: body,
         sourceHash: sourceHash,
         updatedAt: updatedAt,
       );

  /// The translation of the goal [goalId]'s title and description.
  const Translation.goal({
    required String language,
    required String goalId,
    required String title,
    required String description,
    required String sourceHash,
    DateTime? updatedAt,
  }) : this(
         language: language,
         kind: TranslationKind.goal,
         refId: goalId,
         title: title,
         text: description,
         sourceHash: sourceHash,
         updatedAt: updatedAt,
       );

  /// Language code (`en`, …): the partition key. Never [kSourceLanguage].
  final String language;

  final TranslationKind kind;

  /// The id of the translated doc: a `content` id or a goal id.
  final String refId;

  final String title;

  /// The lesson's HTML body fragment (as in `Content.body`) for
  /// [TranslationKind.content]; the goal's description for
  /// [TranslationKind.goal]. Stored as `body` or `description`.
  final String text;

  /// [translationSourceHash] of the Dutch text this was translated from.
  final String sourceHash;

  final DateTime? updatedAt;

  /// Doc id. Prefixed with the kind because a lesson's id equals its
  /// subgoal's id: without the prefix the two would collide.
  String get id => docId(kind, refId);

  static String docId(TranslationKind kind, String refId) =>
      '${kind.name}_$refId';

  static String contentDocId(String contentId) =>
      docId(TranslationKind.content, contentId);

  static String goalDocId(String goalId) => docId(TranslationKind.goal, goalId);

  /// Whether the Dutch text has changed since this was translated from it:
  /// [currentSourceHash] is the hash of the Dutch text as it is now.
  bool isStaleFor(String currentSourceHash) => sourceHash != currentSourceHash;

  Translation copyWith({
    String? title,
    String? text,
    String? sourceHash,
    DateTime? updatedAt,
  }) => Translation(
    language: language,
    kind: kind,
    refId: refId,
    title: title ?? this.title,
    text: text ?? this.text,
    sourceHash: sourceHash ?? this.sourceHash,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'language': language,
    'kind': kind.name,
    'refId': refId,
    'title': title,
    _textField(kind): text,
    'sourceHash': sourceHash,
    if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
  };

  /// The translation in [doc], or `null` when it is not one this build can
  /// read (no language, an unknown kind, no id to translate).
  static Translation? tryFromCosmos(Map<String, dynamic> doc) {
    final language = doc['language'];
    if (language is! String || language.isEmpty) return null;
    final kind = switch (doc['kind']) {
      'content' => TranslationKind.content,
      'goal' => TranslationKind.goal,
      _ => null,
    };
    if (kind == null) return null;
    final refId = doc['refId'];
    if (refId is! String || refId.isEmpty) return null;
    final rawAt = doc['updatedAt'];
    return Translation(
      language: language,
      kind: kind,
      refId: refId,
      title: _string(doc['title']),
      text: _string(doc[_textField(kind)]),
      sourceHash: _string(doc['sourceHash']),
      updatedAt: rawAt is String ? DateTime.tryParse(rawAt) : null,
    );
  }

  static String _textField(TranslationKind kind) => switch (kind) {
    TranslationKind.content => 'body',
    TranslationKind.goal => 'description',
  };

  static String _string(Object? raw) => raw is String ? raw : '';

  @override
  bool operator ==(Object other) =>
      other is Translation &&
      other.language == language &&
      other.kind == kind &&
      other.refId == refId &&
      other.title == title &&
      other.text == text &&
      other.sourceHash == sourceHash &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(language, kind, refId, title, text, sourceHash, updatedAt);

  @override
  String toString() => 'Translation($language, $id)';
}

/// The hash a translation's `sourceHash` holds: of the Dutch [title] and
/// [text] (a lesson's `body`, a goal's `description`) it was translated from.
///
/// SHA-256 of the UTF-8 bytes of `title + "\u0000" + text`, with `\r\n` and
/// `\r` first turned into `\n` in both, as 64 lowercase hex digits. Kept this
/// plain on purpose, so tooling outside the app (#209) can compute the same
/// value — in Python:
///
///     def norm(s): return s.replace('\r\n', '\n').replace('\r', '\n')
///     hashlib.sha256((norm(title) + '\0' + norm(text)).encode('utf-8'))
///         .hexdigest()
String translationSourceHash(String title, String text) =>
    sha256.convert(utf8.encode('${_lf(title)}\u0000${_lf(text)}')).toString();

/// [translationSourceHash] of a lesson's Dutch text.
String contentSourceHash(Content content) =>
    translationSourceHash(content.title, content.body);

/// [translationSourceHash] of a goal's Dutch title and description (an
/// absent description counts as empty).
String goalSourceHash(Goal goal) =>
    translationSourceHash(goal.title, goal.description ?? '');

String _lf(String s) => s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
