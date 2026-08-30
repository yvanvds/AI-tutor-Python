// Issue #23 — guards the i18n sweep itself: English is the base language and
// Dutch must be a complete translation of it. `flutter gen-l10n` only warns
// about an untranslated key (the English text silently leaks into the Dutch
// UI), so the parity is asserted here, together with placeholder agreement
// (a `{title}` the translation forgot would render as literal text) and the
// sanity of the generated lookup table.

import 'dart:convert';
import 'dart:io';

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readArb(String name) {
  final file = File('lib/l10n/$name');
  if (!file.existsSync()) {
    throw StateError('${file.path} is missing (cwd: ${Directory.current})');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Message keys only — the `@key` metadata entries and `@@locale` are not
/// strings the UI shows.
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

final _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)[,}]');

Set<String> _placeholders(String message) =>
    _placeholder.allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  final en = _readArb('app_en.arb');
  final nl = _readArb('app_nl.arb');
  final enKeys = _messageKeys(en);
  final nlKeys = _messageKeys(nl);

  test('ARB files declare the locale they are named for', () {
    expect(en['@@locale'], 'en');
    expect(nl['@@locale'], 'nl');
  });

  test('every English key has a Dutch translation', () {
    expect(
      enKeys.difference(nlKeys),
      isEmpty,
      reason: 'keys in app_en.arb without a Dutch translation',
    );
  });

  test('Dutch has no keys the English base language lacks', () {
    expect(
      nlKeys.difference(enKeys),
      isEmpty,
      reason: 'keys in app_nl.arb that are not in app_en.arb',
    );
  });

  test('no message is empty in either language', () {
    for (final key in enKeys) {
      expect(en[key], isA<String>(), reason: key);
      expect((en[key] as String).trim(), isNotEmpty, reason: 'en/$key');
    }
    for (final key in nlKeys) {
      expect(nl[key], isA<String>(), reason: key);
      expect((nl[key] as String).trim(), isNotEmpty, reason: 'nl/$key');
    }
  });

  test(
    'each translation uses exactly the placeholders of its base message',
    () {
      for (final key in enKeys.intersection(nlKeys)) {
        expect(
          _placeholders(nl[key] as String),
          _placeholders(en[key] as String),
          reason: 'placeholder mismatch for $key',
        );
      }
    },
  );

  test('declared placeholders match the ones used in the English message', () {
    for (final key in enKeys) {
      final meta = en['@$key'];
      if (meta is! Map || meta['placeholders'] is! Map) continue;
      final declared = (meta['placeholders'] as Map).keys
          .cast<String>()
          .toSet();
      expect(
        _placeholders(en[key] as String),
        declared,
        reason: 'declared vs used placeholders differ for $key',
      );
    }
  });

  test('generated lookup covers exactly the supported locales', () {
    expect(
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
      {'en', 'nl'},
    );
    expect(lookupAppLocalizations(const Locale('en')).localeName, 'en');
    expect(lookupAppLocalizations(const Locale('nl')).localeName, 'nl');
  });

  test('the two languages actually differ (a copy-paste translation would '
      'pass the parity checks)', () {
    final l10nEn = lookupAppLocalizations(const Locale('en'));
    final l10nNl = lookupAppLocalizations(const Locale('nl'));
    expect(l10nEn.sidebar_section_map, isNot(l10nNl.sidebar_section_map));
    expect(l10nEn.options_page_title, isNot(l10nNl.options_page_title));
    expect(
      l10nEn.chat_notice_tutorUnreachable,
      isNot(l10nNl.chat_notice_tutorUnreachable),
    );
  });
}
