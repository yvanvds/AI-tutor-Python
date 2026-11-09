import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ctrl+Enter — Cmd+Enter on a Mac — sends off what the focused field holds:
/// the chat composer sends the message, the code editor runs the code
/// (#300). Plain Enter stays a new line in both.
///
/// Both keys are bound on every platform, so the shortcut works whichever
/// one the student reaches for; the hint ([submitShortcutLabel]) names the
/// one of the platform. A held-down shortcut does not repeat: a quick
/// program would otherwise run again and again.
const List<ShortcutActivator> submitShortcutActivators = [
  SingleActivator(
    LogicalKeyboardKey.enter,
    control: true,
    includeRepeats: false,
  ),
  SingleActivator(LogicalKeyboardKey.enter, meta: true, includeRepeats: false),
];

/// [submitShortcutActivators], each bound to [onSubmit], for a
/// [CallbackShortcuts] around the field.
Map<ShortcutActivator, VoidCallback> submitShortcutBindings(
  VoidCallback onSubmit,
) => {for (final activator in submitShortcutActivators) activator: onSubmit};

/// The key hint for the submit shortcut on [platform] (the running platform
/// when left out): `⌘↵` on a Mac, `Ctrl+↵` everywhere else. The app ships on
/// Windows, where a `⌘` key does not exist (#300).
String submitShortcutLabel([TargetPlatform? platform]) {
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.macOS:
    case TargetPlatform.iOS:
      return '⌘↵';
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      return 'Ctrl+↵';
  }
}
