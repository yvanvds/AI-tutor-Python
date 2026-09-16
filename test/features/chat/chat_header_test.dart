// Issue #131 — the chat header offers "Hide chat" in the theory view only:
// in practice the tutor's questions live in the panel, so there is nothing
// to fold. Tapping it flips the remembered choice; the restart button is
// still there either way.

import 'package:ai_tutor_python/features/chat/widgets/chat_header.dart';
import 'package:ai_tutor_python/features/session/chat_panel_state.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/localization.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _profile = Profile(
  name: 'Sam',
  topic: 'loops',
  level: 1,
  xp: 0,
  xpNext: 500,
  streak: 0,
  role: Role.student,
);

void main() {
  late ProviderContainer pc;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(() => _FakeTutorService()),
        profileProvider.overrideWithValue(_profile),
      ],
    );
  });

  tearDown(() => pc.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: localizedTestApp(
          const Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 460, child: ChatHeader()),
            ),
          ),
          locale: locale,
        ),
      ),
    );
  }

  testWidgets('explain offers Hide chat next to Restart session', (
    tester,
  ) async {
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    await mount(tester);

    expect(find.byTooltip('Hide chat'), findsOneWidget);
    expect(find.byTooltip('Restart session'), findsOneWidget);
  });

  testWidgets('practice has no Hide chat; Restart session stays', (
    tester,
  ) async {
    pc.read(modeProvider.notifier).state = SessionMode.practice;
    await mount(tester);

    expect(find.byTooltip('Hide chat'), findsNothing);
    expect(find.byTooltip('Restart session'), findsOneWidget);
  });

  testWidgets('the button follows a mode change while mounted', (tester) async {
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    await mount(tester);
    expect(find.byTooltip('Hide chat'), findsOneWidget);

    pc.read(modeProvider.notifier).state = SessionMode.practice;
    await tester.pump();
    expect(find.byTooltip('Hide chat'), findsNothing);

    pc.read(modeProvider.notifier).state = SessionMode.explain;
    await tester.pump();
    expect(find.byTooltip('Hide chat'), findsOneWidget);
  });

  testWidgets('tapping Hide chat folds the panel and remembers it', (
    tester,
  ) async {
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    await mount(tester);
    expect(pc.read(chatCollapsedProvider), isNull, reason: 'no choice yet');

    await tester.tap(find.byTooltip('Hide chat'));
    await tester.pump();

    expect(pc.read(chatCollapsedProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kChatCollapsedPrefsKey), isTrue);
  });

  testWidgets('Dutch: Verberg chat', (tester) async {
    pc.read(modeProvider.notifier).state = SessionMode.explain;
    await mount(tester, locale: const Locale('nl'));

    expect(find.byTooltip('Verberg chat'), findsOneWidget);
    expect(find.byTooltip('Sessie herstarten'), findsOneWidget);
  });
}
