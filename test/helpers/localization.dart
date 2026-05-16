import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

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
