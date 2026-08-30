// Issue #7 — when the Python host process dies mid-run, or is gone by the
// time the Run button's exec would be sent, the output panel has to say so.
// Before the fix a host crash left the run looking finished ("Done") with
// no error line, and a not-ready host threw a StateError out of the Run
// button's tap handler.
//
// This mounts the real `PracticeView` (run controls, editor, output panel)
// over the real `OutputService`; only `PyRunner` and its `RunHandle` are
// mocked, since a real host needs the bundled interpreter. The run is
// started by tapping the real Run button.

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
import 'package:mocktail/mocktail.dart';
import 'package:py_runner/py_runner.dart';

class _MockPyRunner extends Mock implements PyRunner {}

class _MockRunHandle extends Mock implements RunHandle {}

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> requestExercise() async {}

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

void main() {
  late _MockPyRunner runner;
  late _MockRunHandle handle;
  late StreamController<String> stdout;
  late StreamController<String> stderr;
  late StreamController<InputRequest> inputs;
  late Completer<RunResult> done;
  late OutputService output;
  late ChatService chat;

  setUp(() {
    runner = _MockPyRunner();
    handle = _MockRunHandle();
    stdout = StreamController<String>.broadcast();
    stderr = StreamController<String>.broadcast();
    inputs = StreamController<InputRequest>.broadcast();
    done = Completer<RunResult>();

    when(() => runner.start()).thenAnswer((_) async {});
    when(
      () => runner.run(
        any(),
        cwd: any(named: 'cwd'),
        timeout: any(named: 'timeout'),
      ),
    ).thenReturn(handle);
    when(() => handle.stdout).thenAnswer((_) => stdout.stream);
    when(() => handle.stderr).thenAnswer((_) => stderr.stream);
    when(() => handle.inputRequests).thenAnswer((_) => inputs.stream);
    when(() => handle.done).thenAnswer((_) => done.future);
    when(() => handle.cancel()).thenAnswer((_) async {});

    output = OutputService(pyRunner: runner);
    chat = ChatService();
  });

  tearDown(() async {
    chat.dispose();
    await stdout.close();
    await stderr.close();
    await inputs.close();
  });

  Widget buildApp() => ProviderScope(
    overrides: [
      tutorServiceProvider.overrideWith(() => _FakeTutorService()),
      outputServiceProvider.overrideWithValue(output),
      chatServiceProvider.overrideWithValue(chat),
      modeProvider.overrideWith((_) => SessionMode.practice),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PracticeView(showObjective: false)),
    ),
  );

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp());
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<void> tapRun(WidgetTester tester) async {
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a host that dies mid-run leaves an error line, not "Done"', (
    tester,
  ) async {
    // Created inside the test body so its completion is delivered on the
    // widget test's fake event loop (a setUp-created completer resolves on
    // the real one, which `pump` never drains).
    done = Completer<RunResult>();
    await mount(tester);
    await tapRun(tester);

    stdout.add('hello\n');
    await tester.pump();
    expect(find.textContaining('hello', findRichText: true), findsOneWidget);
    expect(find.textContaining('Running', findRichText: true), findsOneWidget);

    // What py_runner synthesises when the host process exits unexpectedly:
    // status error, no Python traceback.
    done.complete(
      const RunResult(
        status: RunStatus.error,
        duration: Duration.zero,
        exception: PyException(
          type: 'HostExited',
          message: 'host process exited unexpectedly',
          traceback: '',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(output.isRunning.value, isFalse);
    expect(
      find.textContaining(
        'host process exited unexpectedly',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('1 error', findRichText: true), findsOneWidget);
    expect(find.textContaining('Done', findRichText: true), findsNothing);

    await unmount(tester);
  });

  testWidgets('a host that is gone when the run is sent reports the error '
      'instead of throwing from the Run button', (tester) async {
    when(
      () => runner.run(
        any(),
        cwd: any(named: 'cwd'),
        timeout: any(named: 'timeout'),
      ),
    ).thenThrow(
      StateError(
        'PyRunner is not ready (status: crashed); call start() first.',
      ),
    );
    await mount(tester);

    await tapRun(tester);

    expect(tester.takeException(), isNull);
    expect(output.isRunning.value, isFalse);
    expect(
      find.textContaining('Python host error', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('not ready', findRichText: true),
      findsOneWidget,
    );

    await unmount(tester);
  });
}
