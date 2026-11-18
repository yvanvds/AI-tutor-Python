// The first screen of the stand-alone mode (#264, part of #261): a name, a
// language and one sentence about the app. Saving makes the local profile
// and its account doc; `GoalsApp` then moves on to the key screen.
//
// A page of its own, so the first-start choice of #307 can put itself in
// front of it.

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/auth/local_profile.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StandaloneWelcomePage extends ConsumerStatefulWidget {
  const StandaloneWelcomePage({super.key});

  @override
  ConsumerState<StandaloneWelcomePage> createState() =>
      _StandaloneWelcomePageState();
}

class _StandaloneWelcomePageState extends ConsumerState<StandaloneWelcomePage> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    final first = _firstName.text.trim();
    if (first.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.standalone_welcome_firstNameRequired)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = LocalProfile.create(
        firstName: first,
        lastName: _lastName.text,
      );
      // The account doc first, so the app finds it on its first read instead
      // of one poll later. `mayUseGlobalKey` starts false: the key screen
      // asks for the user's own key.
      await ref
          .read(accountServiceProvider.notifier)
          .upsertAccount(
            uid: profile.uid,
            firstName: profile.firstName,
            lastName: profile.lastName,
            email: '',
          );
      await ref.read(authServiceProvider.notifier).useLocalProfile(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.standalone_welcome_failed(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final language = ref.watch(appLocaleProvider).languageCode;
    return Scaffold(
      key: const ValueKey('standalone-welcome'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                l.standalone_welcome_title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                l.standalone_welcome_intro,
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 24),
              TextField(
                key: const ValueKey('standalone-welcome-first-name'),
                controller: _firstName,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l.standalone_welcome_firstName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('standalone-welcome-last-name'),
                controller: _lastName,
                onSubmitted: (_) => _saving ? null : _start(),
                decoration: InputDecoration(
                  labelText: l.standalone_welcome_lastName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Text(l.standalone_welcome_language),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'nl',
                    label: Text(l.settings_language_dutch),
                  ),
                  ButtonSegment(
                    value: 'en',
                    label: Text(l.settings_language_english),
                  ),
                ],
                selected: {language},
                showSelectedIcon: false,
                onSelectionChanged: (s) => ref
                    .read(localeServiceProvider.notifier)
                    .setLocale(Locale(s.single)),
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const ValueKey('standalone-welcome-start'),
                  onPressed: _saving ? null : _start,
                  child: Text(l.standalone_welcome_start),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
