// Issue #210 — the "Current goal" banner above the practice view shows the
// goal's title and description in the app language when the goal has a
// translation, and in Dutch, without a notice, when it has none. In Dutch
// nothing is fetched from `translations`, and a translation that arrives on
// a later poll takes the Dutch text's place.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/session/widgets/objective_banner.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goal_selection_notifier.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/localization.dart';

final _root = Goal(id: 'r1', title: 'Basis', order: 0);
final _printen = Goal(
  id: 's1',
  title: 'Printen',
  description: 'Tekst op het scherm zetten.',
  parentId: 'r1',
  order: 1,
);

Map<String, dynamic> _english() => Translation.goal(
  language: 'en',
  goalId: 's1',
  title: 'Printing',
  description: 'Putting text on the screen.',
  sourceHash: goalSourceHash(_printen),
).toMap();

class _PresetSelection extends GoalSelectionNotifier {
  @override
  GoalSelectionState build() =>
      GoalSelectionState(selectedRoot: _root, selectedChild: _printen);
}

/// The real service, recording every language it was asked to fetch.
class _RecordingTranslations extends TranslationService {
  _RecordingTranslations(InMemoryCosmos store)
    : super(container: store.container);

  final List<String> fetched = [];

  @override
  Future<List<Translation>> listLanguage(String language) {
    fetched.add(language);
    return super.listLanguage(language);
  }
}

void main() {
  late InMemoryCosmos store;
  late _RecordingTranslations service;

  setUp(() {
    store = InMemoryCosmos.partitioned('language', [_english()]);
    service = _RecordingTranslations(store);
  });

  Future<void> mount(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLocaleProvider.overrideWithValue(locale),
          translationServiceProvider.overrideWithValue(service),
          goalSelectionProvider.overrideWith(_PresetSelection.new),
          ambientProgressProvider.overrideWithValue(0.4),
        ],
        child: localizedTestApp(
          const Scaffold(body: Column(children: [ObjectiveBanner()])),
          locale: locale,
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('English with a translation: the goal in English', (
    tester,
  ) async {
    await mount(tester, const Locale('en'));

    expect(find.text('CURRENT GOAL'), findsOneWidget);
    expect(find.text('Printing'), findsOneWidget);
    expect(find.text('Putting text on the screen.'), findsOneWidget);
    expect(find.text('Printen'), findsNothing);
    expect(find.text('Tekst op het scherm zetten.'), findsNothing);
  });

  testWidgets('English without a translation: the goal in Dutch, without a '
      'notice, until a translation arrives on a later poll', (tester) async {
    store.docs.clear();
    await mount(tester, const Locale('en'));

    expect(find.text('Printen'), findsOneWidget);
    expect(find.text('Tekst op het scherm zetten.'), findsOneWidget);
    expect(find.textContaining('translat'), findsNothing);
    expect(find.textContaining('Dutch'), findsNothing);

    store.upsert(_english(), partitionKey: 'en');
    await tester.pump(kCosmosPollInterval);
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    expect(find.text('Printing'), findsOneWidget);
    expect(find.text('Putting text on the screen.'), findsOneWidget);
  });

  testWidgets('Dutch: the goal as written, and nothing fetched', (
    tester,
  ) async {
    await mount(tester, const Locale('nl'));

    expect(find.text('Printen'), findsOneWidget);
    expect(find.text('Tekst op het scherm zetten.'), findsOneWidget);
    expect(find.text('Printing'), findsNothing);
    expect(service.fetched, isEmpty);
  });
}
