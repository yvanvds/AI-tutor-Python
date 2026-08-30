import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// Resolver for services that take an `AppLocalizations Function()` because
/// they have no `BuildContext` (e.g. `OutputService`). Mirrors what
/// `appLocalizationsProvider` hands them in the app.
AppLocalizations Function() testLocalizations([
  Locale locale = const Locale('en'),
]) =>
    () => lookupAppLocalizations(locale);

/// Wraps a widget in a `MaterialApp` with the same localization delegates
/// the production app uses. Use this from widget tests that mount screens
/// reading from `AppLocalizations.of(context)`.
Widget localizedTestApp(Widget child, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}
