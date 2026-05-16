import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the sidebar settings popup at the given build context. Currently
/// exposes a single setting — language — with three states: follow system,
/// English, or Dutch.
Future<void> showSettingsMenu(BuildContext context, WidgetRef ref) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final button = context.findRenderObject() as RenderBox?;
  if (overlay == null || button == null) return;

  final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
  final bottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  final position = RelativeRect.fromLTRB(
    bottomRight.dx + 8,
    topLeft.dy,
    overlay.size.width - bottomRight.dx - 8,
    overlay.size.height - bottomRight.dy,
  );

  final l = AppLocalizations.of(context);
  final current = ref.read(localeServiceProvider);

  await showMenu<_LanguageChoice>(
    context: context,
    position: position,
    items: [
      PopupMenuItem<_LanguageChoice>(
        enabled: false,
        height: 32,
        child: Text(
          l.settings_language_label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      _languageItem(_LanguageChoice.system, l.settings_language_system, current),
      _languageItem(_LanguageChoice.en, l.settings_language_english, current),
      _languageItem(_LanguageChoice.nl, l.settings_language_dutch, current),
    ],
  ).then((choice) {
    if (choice == null) return;
    switch (choice) {
      case _LanguageChoice.system:
        ref.read(localeServiceProvider.notifier).setLocale(null);
      case _LanguageChoice.en:
        ref.read(localeServiceProvider.notifier).setLocale(const Locale('en'));
      case _LanguageChoice.nl:
        ref.read(localeServiceProvider.notifier).setLocale(const Locale('nl'));
    }
  });
}

enum _LanguageChoice { system, en, nl }

PopupMenuItem<_LanguageChoice> _languageItem(
  _LanguageChoice choice,
  String label,
  Locale? currentOverride,
) {
  final selected = switch (choice) {
    _LanguageChoice.system => currentOverride == null,
    _LanguageChoice.en => currentOverride?.languageCode == 'en',
    _LanguageChoice.nl => currentOverride?.languageCode == 'nl',
  };
  return PopupMenuItem<_LanguageChoice>(
    value: choice,
    child: Row(
      children: [
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}
