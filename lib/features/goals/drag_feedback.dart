import 'package:flutter/material.dart';

Widget DragFeedback(BuildContext context, String title) {
  return Material(
    elevation: 6,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: const BoxConstraints(maxWidth: 320),
      color: Theme.of(context).colorScheme.surface,
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}
