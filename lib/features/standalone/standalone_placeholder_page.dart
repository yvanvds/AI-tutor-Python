// What a build without a school configuration shows for now (#262). The
// local storage (#263) and the local profile (#264) replace it.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class StandalonePlaceholderPage extends StatelessWidget {
  const StandalonePlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      key: const ValueKey('standalone-placeholder'),
      appBar: AppBar(title: Text(l.standalone_placeholder_title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.standalone_placeholder_body,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.4),
          ),
        ),
      ),
    );
  }
}
