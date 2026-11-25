// The reference panel (#323): every function and class the course uses,
// searchable, next to the exercise.
//
// Three things live here, so the session view (the layout), the panel and
// the buttons that open it agree on one source of truth:
//
//   - [referencePanelOpenProvider] — whether the student opened it. It shows
//     in Practice and the Playground, beside the editor or the quiz; in the
//     theory view it waits and comes back with the exercise. Not stored: a
//     new launch starts with it closed.
//   - [pythonReferenceProvider] — the bundled reference, the same file the
//     editor's dropdown after a dot reads (#322).
//   - [referencePlacement] — where the panel goes: over the chat, exactly as
//     wide as it, so the editor keeps its width at every window size
//     (#335); in a column of its own beside the editor only where there is
//     no chat, in the Playground.

import 'dart:math' as math;

import 'package:ai_tutor_python/services/code/python_reference.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the reference panel is open.
class ReferencePanelNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void open() => state = true;

  void close() => state = false;

  void toggle() => state = !state;
}

final referencePanelOpenProvider =
    NotifierProvider<ReferencePanelNotifier, bool>(ReferencePanelNotifier.new);

/// The bundled reference, read once per process by [PythonReference.load].
final pythonReferenceProvider = FutureProvider<PythonReference>(
  (ref) => PythonReference.load(),
);

/// The panel's width when the window has room for it.
const double referencePanelWidth = 340;

/// The narrowest the panel is laid out at in a column of its own: a search
/// field, a signature and a short example still fit on a line.
const double referencePanelMinWidth = 260;

/// What the exercise keeps next to a panel in a column of its own (the
/// Playground): the row above the editor whole, and a line of code. With
/// less, the panel lies over the right of the exercise instead.
const double referenceExerciseMinWidth = 360;

/// Where the reference panel goes in a session area.
@immutable
class ReferencePlacement {
  const ReferencePlacement({required this.width, required this.beside});

  final double width;

  /// In a column of its own beside the exercise, which gives up the room —
  /// only where there is no chat (the Playground). When false it lies over
  /// the chat, exactly as wide as it — or, next to a chat too narrow for it
  /// or in a Playground too small for the column, over the right of the
  /// exercise.
  final bool beside;

  @override
  bool operator ==(Object other) =>
      other is ReferencePlacement &&
      other.width == width &&
      other.beside == beside;

  @override
  int get hashCode => Object.hash(width, beside);

  @override
  String toString() =>
      'ReferencePlacement(${beside ? 'beside' : 'over'}, $width)';
}

/// Where the panel goes in a session area [sessionWidth] wide next to a chat
/// panel [chatWidth] wide, where a [chatWidth] of zero is no chat (the
/// Playground): over the chat, exactly as wide as it, when the chat is at
/// least [referencePanelMinWidth]; with no chat, beside the exercise, at
/// most [referencePanelWidth], when that leaves the exercise
/// [referenceExerciseMinWidth] and the panel [referencePanelMinWidth];
/// otherwise over the right of the exercise.
///
/// In Practice — the editor and the quiz — the panel so lies over the chat
/// in every window down to about 600 px: over the 460 px chat, and in the
/// 700 px window of #259 over the half-width one. The editor never gives up
/// room to it (#335): a column of its own between the exercise and the chat
/// left the editor 360 to 700 px on the student laptops. In the Playground
/// at the 1280 px window the app opens in, the column is 340 px and the
/// exercise keeps 868.
ReferencePlacement referencePlacement({
  required double sessionWidth,
  required double chatWidth,
}) {
  if (chatWidth >= referencePanelMinWidth) {
    return ReferencePlacement(width: chatWidth, beside: false);
  }
  final room = sessionWidth - referenceExerciseMinWidth;
  if (chatWidth <= 0 && room >= referencePanelMinWidth) {
    return ReferencePlacement(
      width: math.min(referencePanelWidth, room),
      beside: true,
    );
  }
  return ReferencePlacement(
    width: math.max(0, math.min(referencePanelWidth, sessionWidth)),
    beside: false,
  );
}
