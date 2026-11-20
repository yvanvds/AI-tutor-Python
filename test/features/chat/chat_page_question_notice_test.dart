// #324 — a message typed next to the theory page while a question waits
// for its answer in the chat went out as a question about the page, and
// the chat says it did not count as the answer: plain text, not the faint
// italic pill, with a button that takes the student back to the question —
// the practice view. Other notices stay pills without a button.
//
// Mounted like chat_goal_notice_test: the real `ChatWidget` and
// `ChatService`, a `TutorService` stand-in that does nothing on session
// start.

import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_action_notice.dart';
import 'package:ai_tutor_python/features/chat/widgets/chat_system_pill.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_notice.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late ChatService chat;
  late ProviderContainer container;

  setUp(() {
    chat = ChatService();
    chat.addTutorMessage('Wat drukt deze code af?');
    chat.addMessage('Het drukt 7 af.');
    chat.addTutorMessage('Op deze pagina gaat het over print.');
    chat.addSystemNotice(
      const ChatNotice(ChatNoticeKind.pageQuestionNotAnAnswer),
    );
    chat.addSystemNotice(const ChatNotice(ChatNoticeKind.submitViaEditor));
  });

  tearDown(() => chat.dispose());

  Future<void> mount(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tutorServiceProvider.overrideWith(_FakeTutorService.new),
          chatServiceProvider.overrideWithValue(chat),
          profileProvider.overrideWithValue(_testProfile),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ChatWidget()),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(ChatWidget)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('the notice says the message did not count, and its button '
      'goes to the question in practice', (tester) async {
    await mount(tester, const Locale('nl'));
    expect(container.read(modeProvider), SessionMode.explain);

    expect(find.byType(ChatActionNotice), findsOneWidget);
    expect(
      find.text(
        'Dit was een vraag over de uitleg, dus het telt niet als antwoord '
        'op je oefening. Antwoord bij de vraag zelf.',
      ),
      findsOneWidget,
    );
    // Not one of the faint pills.
    expect(
      tester
          .widgetList<ChatSystemPill>(find.byType(ChatSystemPill))
          .map((p) => p.text),
      [
        'Pas je code aan in de editor links en druk op Run om je oplossing '
            'in te sturen.',
      ],
    );

    // The chat wraps every message in a double-tap detector, so a tap in
    // one wins the gesture arena only once the double-tap window is over.
    await tester.tap(find.text('Naar de vraag'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    expect(container.read(modeProvider), SessionMode.practice);
  });

  testWidgets('in English', (tester) async {
    await mount(tester, const Locale('en'));

    expect(
      find.text(
        'This was a question about the explanation, so it does not count as '
        'an answer to your exercise. Answer at the question itself.',
      ),
      findsOneWidget,
    );
    expect(find.text('Go to the question'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatActionNotice),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
      findsOneWidget,
    );
  });
}
