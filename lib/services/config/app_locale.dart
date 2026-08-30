import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The locale the UI runs in (issue #23): the user's override from the
/// Options page when set, else the operating-system locale when the app has
/// a translation for it, else English.
Locale resolveAppLocale(Locale? override, Locale system) {
  if (override != null) return override;
  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == system.languageCode) return supported;
  }
  return const Locale('en');
}

/// Operating-system locale. Split out so tests can override it.
final systemLocaleProvider = Provider<Locale>(
  (_) => WidgetsBinding.instance.platformDispatcher.locale,
);

/// Effective app locale — what `MaterialApp.locale` is set to.
final appLocaleProvider = Provider<Locale>(
  (ref) => resolveAppLocale(
    ref.watch(localeServiceProvider),
    ref.watch(systemLocaleProvider),
  ),
);

/// `AppLocalizations` for [appLocaleProvider], for the rare service-side
/// string that has no widget to be resolved in (the editor template a
/// write-code exercise starts with, the browser page shown after sign-in).
/// Chat-bound text goes through `ChatNotice` instead and is resolved in the
/// widget tree.
final appLocalizationsProvider = Provider<AppLocalizations>(
  (ref) => lookupAppLocalizations(ref.watch(appLocaleProvider)),
);
