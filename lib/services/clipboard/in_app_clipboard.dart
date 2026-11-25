import 'dart:collection';

import 'package:flutter/services.dart';

/// What the student copied inside the app (#334): from the editor of
/// Practice or the Playground, the output, the tutor's messages and
/// feedback, a quiz question, a question's ID. A paste into the answer, the
/// chat or the Playground goes through only when the clipboard holds
/// exactly one of these texts; see `PasteGuard`.
///
/// Kept in memory only, for as long as the app runs, and forgotten when the
/// student signs out. Never written anywhere.
///
/// One for the whole app rather than a provider: the places that copy are
/// widgets without a `ref` (the tutor's markdown, a question's ID tag) and
/// the editor's controller.
class InAppClipboard {
  InAppClipboard._();

  /// The app's one memory.
  static final InAppClipboard instance = InAppClipboard._();

  /// How many copies are kept; the oldest goes first. A student pastes what
  /// they copied a moment ago, not fifty copies back.
  static const int capacity = 50;

  final LinkedHashSet<String> _texts = LinkedHashSet<String>();

  /// Notes that the app put [text] on the clipboard. An empty text is no
  /// copy.
  void remember(String text) {
    final t = _normalize(text);
    if (t.isEmpty) return;
    // Copied again: the newest again.
    _texts
      ..remove(t)
      ..add(t);
    while (_texts.length > capacity) {
      _texts.remove(_texts.first);
    }
  }

  /// Whether [text] is exactly something the app copied.
  bool holds(String text) => _texts.contains(_normalize(text));

  /// Puts [text] on the clipboard as a copy made in the app: a copy button.
  Future<void> copy(String text) async {
    remember(text);
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Forgets every copy: the student signed out.
  void clear() => _texts.clear();

  /// Windows may hand a text back with `\r\n` where the app put `\n`; the
  /// same text either way.
  static String _normalize(String text) => text.replaceAll('\r\n', '\n');
}
