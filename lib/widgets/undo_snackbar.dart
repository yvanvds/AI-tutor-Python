import 'package:flutter/material.dart';

void showUndoSnackBar(
  ScaffoldMessengerState messenger, {
  required String message,
  required VoidCallback onUndo,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
        duration: const Duration(seconds: 5),
      ),
    );
}
