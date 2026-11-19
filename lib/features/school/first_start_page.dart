// The first-start choice (#307, part of #261): with a school file, or
// without a school. Shown only when the start decided nothing
// (lib/core/app_start.dart) — never to a student whose install already has a
// school. Nothing is picked for the user: a wrong click must not leave a
// student practising on their own without noticing.
//
// "I have a file from my school" picks the file, checks and stores it, and
// the app goes on in that school's mode (sign-in). "Continue without a
// school" is remembered and goes on to the stand-alone welcome (#264).

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/app_start.dart';
import 'package:ai_tutor_python/features/school/school_file_actions.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirstStartPage extends ConsumerStatefulWidget {
  const FirstStartPage({super.key, required this.onChosen});

  /// Called once with the mode the user chose; the app starts in it.
  final Future<void> Function(AppMode mode) onChosen;

  @override
  ConsumerState<FirstStartPage> createState() => _FirstStartPageState();
}

class _FirstStartPageState extends ConsumerState<FirstStartPage> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<AppMode?> Function() choose) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final mode = await choose();
    if (!mounted) return;
    if (mode == null) {
      setState(() => _busy = false);
      return;
    }
    await widget.onChosen(mode);
  }

  Future<AppMode?> _withSchoolFile() async {
    final result = await pickAndImportSchoolFile(ref);
    switch (result) {
      case SchoolFileImported(:final school):
        return SchoolMode(school);
      case SchoolFileCancelled():
        return null;
      case SchoolFileRefused(:final error):
        if (mounted) {
          setState(
            () => _error = schoolFileProblemText(
              AppLocalizations.of(context),
              error,
            ),
          );
        }
        return null;
    }
  }

  Future<AppMode?> _withoutSchool() async {
    await chooseWithoutSchool(await SharedPreferences.getInstance());
    return const StandaloneMode();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      key: const ValueKey('first-start'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(l.firstStart_title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 12),
              Text(l.firstStart_intro, style: const TextStyle(height: 1.4)),
              const SizedBox(height: 24),
              _Choice(
                key: const ValueKey('first-start-school'),
                icon: Icons.school_outlined,
                title: l.firstStart_school,
                hint: l.firstStart_schoolHint,
                onTap: _busy ? null : () => _run(_withSchoolFile),
              ),
              const SizedBox(height: 12),
              _Choice(
                key: const ValueKey('first-start-without-school'),
                icon: Icons.person_outline,
                title: l.firstStart_without,
                hint: l.firstStart_withoutHint,
                onTap: _busy ? null : () => _run(_withoutSchool),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const ValueKey('first-start-error'),
                  style: TextStyle(color: theme.colorScheme.error, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(hint),
        trailing: const Icon(Icons.chevron_right),
        enabled: onTap != null,
        onTap: onTap,
      ),
    );
  }
}
