// #286 — a session that starts while the practice view is on screen brings
// its first exercise. The restart in the chat header changes neither the
// section nor the mode, so no new practice view mounts to ask for it; the
// one on screen asks when the start says it has begun
// (`sessionStartsProvider`), as it does when it comes on screen.
//
// The real `PracticeView` over a tutor that counts the asks and answers
// them when the test says so. The end-to-end run is
// `integration_test/flows/restart_in_practice.dart`.

import 'dart:async';

import 'package:ai_tutor_python/features/session/modes/practice_view.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:py_runner/py_runner.dart';

import '../../helpers/localization.dart';

class _CountingTutor extends TutorService {
  /// One per ask, in order; the ask is done when its completer is.
  final List<Completer<void>> asks = [];

  /// Whether an exercise is in flight for the subgoal the session is on.
  bool inFlight = false;

  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> requestExercise() {
    final ask = Completer<void>();
    asks.add(ask);
    return ask.future;
  }

  @override
  bool hasInFlightExercise() => inFlight;

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

void main() {
  late OutputService output;
  late ChatService chat;
  late _CountingTutor tutor;
  late ProviderContainer pc;

  setUp(() {
    output = OutputService(
      pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
      localizations: testLocalizations(),
    );
    chat = ChatService();
    tutor = _CountingTutor();
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(() => tutor),
        outputServiceProvider.overrideWithValue(output),
        chatServiceProvider.overrideWithValue(chat),
        modeProvider.overrideWith((_) => SessionMode.practice),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: PracticeView(showObjective: false)),
        ),
      ),
    );
    await tester.pump();
  }

  /// A session starts, as [TutorService.initializeSession] says it does.
  void sessionStarts() => pc.read(sessionStartsProvider.notifier).state++;

  testWidgets('a session that starts while it is on screen brings an '
      'exercise', (tester) async {
    await mount(tester);
    expect(tutor.asks, hasLength(1), reason: 'coming on screen asks');
    tutor.asks.last.complete();
    await tester.pump();

    sessionStarts();
    await tester.pump();
    expect(tutor.asks, hasLength(2), reason: 'the start brought nothing');
    tutor.asks.last.complete();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a restart pressed twice asks once', (tester) async {
    await mount(tester);
    tutor.asks.last.complete();
    await tester.pump();

    sessionStarts();
    sessionStarts();
    await tester.pump();
    expect(tutor.asks, hasLength(2));

    // Once it is done, the next start asks again.
    tutor.asks.last.complete();
    await tester.pump();
    sessionStarts();
    await tester.pump();
    expect(tutor.asks, hasLength(3));
    tutor.asks.last.complete();
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a start with an exercise in flight for its subgoal asks '
      'nothing', (tester) async {
    await mount(tester);
    tutor.asks.last.complete();
    await tester.pump();

    tutor.inFlight = true;
    sessionStarts();
    await tester.pump();
    expect(tutor.asks, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
