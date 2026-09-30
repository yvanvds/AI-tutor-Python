// Issue #211 — the warm-up and recheck pills in chat name the older subgoal
// in the app language: its English title when the goal has a translation,
// the Dutch title, without a notice, when it has none. The notice keeps the
// goal's id next to its Dutch title, so a translation that arrives on a poll
// and a language switch both re-render the pills already on screen. In
// Dutch nothing is fetched from `translations`.
//
// Mounted like chat_widget_test: the real `ChatWidget` and `ChatService`, a
// `TutorService` stand-in that does nothing on session start.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/translation/translation.dart';
import 'package:ai_tutor_python/services/translation/translation_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _testProfile = Profile(
  name: 'Test',
  topic: '',
  level: 1,
  xp: 0,
  xpNext: 500,
  streak: 0,
  role: Role.student,
);

final _printen = Goal(
  id: 's1',
  title: 'Printen',
  description: 'Tekst op het scherm zetten.',
  parentId: 'r1',
  order: 1000,
);

Map<String, dynamic> _english() => Translation.goal(
  language: 'en',
  goalId: 's1',
  title: 'Printing',
  description: 'Putting text on the screen.',
  sourceHash: goalSourceHash(_printen),
).toMap();

/// The notices as `TutorService` raises them: the Dutch title and the id.
ChatNotice _warmUp() => ChatNotice(
  ChatNoticeKind.warmUpReview,
  args: [_printen.title],
  goalId: _printen.id,
);

ChatNotice _recheck() => ChatNotice(
  ChatNoticeKind.recheck,
  args: [_printen.title],
  goalId: _printen.id,
);

/// Stands in for the Options language switch.
final _locale = StateProvider<Locale>((_) => const Locale('en'));

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
  late ChatService chat;
  late ProviderContainer container;

  setUp(() {
    store = InMemoryCosmos.partitioned('language', [_english()]);
    service = _RecordingTranslations(store);
    chat = ChatService();
    chat.addSystemNotice(_warmUp());
    chat.addSystemNotice(_recheck());
  });

  tearDown(() => chat.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  Future<void> mount(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _locale.overrideWith((_) => locale),
          appLocaleProvider.overrideWith((ref) => ref.watch(_locale)),
          translationServiceProvider.overrideWithValue(service),
          tutorServiceProvider.overrideWith(_FakeTutorService.new),
          chatServiceProvider.overrideWithValue(chat),
          profileProvider.overrideWithValue(_testProfile),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            locale: ref.watch(_locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ChatWidget()),
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(ChatWidget)),
    );
    await settle(tester);
  }

  /// Disposes the scope, and with it the `translations` poll.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  List<String> pills(WidgetTester tester) => tester
      .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
      .map((p) => p.text)
      .toList();

  const warmUpEn = 'Quick warm-up first: one review question on Printing.';
  const recheckEn =
      "In between: one check question on Printing, so you can show you've "
      'got it now.';

  testWidgets('English with a translation: both pills name the goal in '
      'English', (tester) async {
    await mount(tester, const Locale('en'));

    expect(pills(tester), containsAll([warmUpEn, recheckEn]));
    expect(pills(tester), everyElement(isNot(contains('Printen'))));

    await unmount(tester);
  });

  testWidgets('English without a translation: the Dutch title, without a '
      'notice, until a translation arrives on a later poll', (tester) async {
    store.docs.clear();
    await mount(tester, const Locale('en'));

    expect(
      pills(tester),
      containsAll([
        'Quick warm-up first: one review question on Printen.',
        "In between: one check question on Printen, so you can show you've "
            'got it now.',
      ]),
    );
    expect(find.textContaining('translat'), findsNothing);
    expect(find.textContaining('Dutch'), findsNothing);

    store.upsert(_english(), partitionKey: 'en');
    await tester.pump(kCosmosPollInterval);
    await settle(tester);

    expect(pills(tester), containsAll([warmUpEn, recheckEn]));

    await unmount(tester);
  });

  testWidgets('Dutch: the goal as written, and nothing fetched', (
    tester,
  ) async {
    await mount(tester, const Locale('nl'));

    expect(
      pills(tester),
      containsAll([
        'Eerst even opwarmen: één opfrisvraag over Printen.',
        'Tussendoor: één controlevraag over Printen, om te tonen dat je het '
            'nu kan.',
      ]),
    );
    expect(service.fetched, isEmpty);

    await unmount(tester);
  });

  testWidgets('a language switch re-renders the pills already on screen with '
      "the new language's title", (tester) async {
    await mount(tester, const Locale('nl'));
    expect(
      pills(tester),
      contains('Eerst even opwarmen: één opfrisvraag over Printen.'),
    );

    container.read(_locale.notifier).state = const Locale('en');
    await settle(tester);

    expect(pills(tester), containsAll([warmUpEn, recheckEn]));

    await unmount(tester);
  });
}
