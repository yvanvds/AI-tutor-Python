// Issue #271 — the chat stays open next to a quiz now, so the tutor can be
// busy answering a question while the quiz waits. A pick then would not be
// graded (the grading call cannot go out while the tutor works) and would
// hang on screen; the options take no pick until the tutor is done.
//
// This mounts the real `QuizView` over a tutor whose state the test sets,
// and records the picks that reach it.

import 'package:ai_tutor_python/features/session/modes/quiz_view.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/tutor/active_mcq.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTutorService extends TutorService {
  final List<String> picks = [];

  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> initializeSession({bool force = false}) async {}

  @override
  Future<void> submitMcqAnswer(String picked) async => picks.add(picked);

  void setState(TutorState next) => state = next;
}

const _quiz = ActiveMcq(
  prompt: 'Wat drukt print(1 + 1) af?',
  code: 'print(1 + 1)',
  options: ['2', '11'],
);

void main() {
  late _FakeTutorService tutor;
  late ProviderContainer pc;

  setUp(() {
    tutor = _FakeTutorService();
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(() => tutor),
        activeMcqProvider.overrideWith((_) => _quiz),
      ],
    );
    pc.read(tutorServiceProvider);
  });

  tearDown(() => pc.dispose());

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: QuizView()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('while the tutor answers a question the options take no pick; '
      'once it is done they do', (tester) async {
    tutor.setState(TutorState.working);
    await mount(tester);

    await tester.tap(find.text('11'));
    await tester.pump();
    expect(tutor.picks, isEmpty, reason: 'a pick that cannot be graded');

    tutor.setState(TutorState.idle);
    await tester.pump();
    await tester.tap(find.text('11'));
    await tester.pump();
    expect(tutor.picks, ['11']);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
