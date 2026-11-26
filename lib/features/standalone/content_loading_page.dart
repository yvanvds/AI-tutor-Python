// What the stand-alone app shows while it opens its local storage and loads
// the content it ships with (#346, part of #261). The first start writes
// every lesson and exercise to the pc, which takes a while: the window
// paints this page first and keeps it up to date, so the student sees that
// something happens and how far it is. A later start passes it in a moment.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How far the content is: [written] of [total] docs.
typedef ContentLoadProgress = ({int written, int total});

class ContentLoadingPage extends StatelessWidget {
  const ContentLoadingPage({super.key, required this.progress, this.error});

  /// `null` until there is something to write: a start with the content
  /// already on the pc never counts.
  final ValueListenable<ContentLoadProgress?> progress;

  /// Why the start failed, when it did.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = this.error;
    return Scaffold(
      key: const ValueKey('content-loading'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: error != null
                ? Text(
                    l.contentLoading_failed(error),
                    key: const ValueKey('content-loading-error'),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      height: 1.4,
                    ),
                  )
                : ValueListenableBuilder<ContentLoadProgress?>(
                    valueListenable: progress,
                    builder: (context, p, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.contentLoading_title,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 16),
                        LinearProgressIndicator(
                          key: const ValueKey('content-loading-bar'),
                          value: p == null || p.total == 0
                              ? null
                              : p.written / p.total,
                        ),
                        if (p != null && p.total > 0) ...[
                          const SizedBox(height: 12),
                          Text(
                            l.contentLoading_count(p.written, p.total),
                            key: const ValueKey('content-loading-count'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.contentLoading_hint,
                            style: const TextStyle(height: 1.4),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
