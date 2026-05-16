import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Formats [ts] in the user's local timezone using a locale-aware short
/// date + time pattern. The locale is resolved from [context] — i.e. whichever
/// locale `MaterialApp` resolved through `localizationsDelegates`.
///
/// Examples (US local time, given the same instant):
///   en  → `5/16/2026 14:30`
///   nl  → `16-5-2026 14:30`
String formatTs(DateTime ts, BuildContext context) {
  final localeTag = Localizations.localeOf(context).toLanguageTag();
  final dt = ts.toLocal();
  return DateFormat.yMd(localeTag).add_Hm().format(dt);
}
