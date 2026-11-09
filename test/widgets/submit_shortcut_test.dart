// Issue #300 — the key hints on the Run button and below the chat composer
// said `⌘↵`, the Mac shortcut, in an app that ships on Windows only. The
// hint now comes from one place (`submitShortcutLabel`) and names the key
// of the platform: `Ctrl+↵` on Windows, `⌘↵` on a Mac.
//
// The label on its own, then the real `RunControls` and the real idle
// composer (inside the real `ChatWidget`, which hosts it) under a target
// platform override. Ctrl+Enter running the code is
// `test/features/session/editor_run_shortcut_test.dart`; the end-to-end run
// is `integration_test/flows/run_shortcut.dart`.

import 'package:ai_tutor_python/features/chat/chat_widget.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/session/widgets/run_controls.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/chat/chat_service.dart';
import 'package:ai_tutor_python/services/output/output_service.dart';
import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:ai_tutor_python/widgets/submit_shortcut.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:py_runner/py_runner.dart';

import '../helpers/localization.dart';

class _FakeTutorService extends TutorService {
  @override
  TutorState build() => TutorState.idle;

  @override
  Future<void> initializeSession({bool force = false}) async {}
}

const _profile = Profile(
  name: 'Test',
  topic: '',
  level: 1,
  xp: 0,
  xpNext: 500,
  streak: 0,
  role: Role.student,
);

/// What the hint should read on the platform the variant set.
String _expected() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘↵' : 'Ctrl+↵';

final _windowsAndMac = TargetPlatformVariant({
  TargetPlatform.windows,
  TargetPlatform.macOS,
});

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('submitShortcutLabel', () {
    test('is Ctrl+↵ on Windows and Linux', () {
      expect(submitShortcutLabel(TargetPlatform.windows), 'Ctrl+↵');
      expect(submitShortcutLabel(TargetPlatform.linux), 'Ctrl+↵');
    });

    test('is ⌘↵ on a Mac', () {
      expect(submitShortcutLabel(TargetPlatform.macOS), '⌘↵');
    });

    testWidgets('follows the running platform', (tester) async {
      expect(submitShortcutLabel(), _expected());
    }, variant: _windowsAndMac);
  });

  late ChatService chat;
  late ProviderContainer pc;

  setUp(() {
    chat = ChatService();
    // One message, so the empty-list placeholder (and its timer) is not
    // mounted.
    chat.addTutorMessage('hi');
    pc = ProviderContainer(
      overrides: [
        tutorServiceProvider.overrideWith(() => _FakeTutorService()),
        chatServiceProvider.overrideWithValue(chat),
        profileProvider.overrideWithValue(_profile),
        modeProvider.overrideWith((_) => SessionMode.practice),
        outputServiceProvider.overrideWithValue(
          OutputService(
            pyRunner: PyRunner(locator: const InstallerPyHostLocator()),
            localizations: testLocalizations(),
          ),
        ),
      ],
    );
  });

  tearDown(() {
    pc.dispose();
    chat.dispose();
  });

  Future<void> mount(WidgetTester tester, Widget body) async {
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
          home: Scaffold(body: body),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the Run button names the key of the platform', (tester) async {
    await mount(tester, const RunControls());

    final hint = tester.widget<Text>(
      find.byKey(const Key('run-shortcut-hint')),
    );
    expect(hint.data, _expected());
    if (defaultTargetPlatform == TargetPlatform.windows) {
      expect(find.text('⌘↵'), findsNothing);
    }
  }, variant: _windowsAndMac);

  testWidgets('the composer names the key of the platform for send', (
    tester,
  ) async {
    await mount(tester, const ChatWidget());

    expect(
      find.descendant(
        of: find.byType(ComposerIdle),
        matching: find.text(_expected()),
      ),
      findsOneWidget,
    );
    if (defaultTargetPlatform == TargetPlatform.windows) {
      expect(find.text('⌘↵'), findsNothing);
    }

    // Unmount before the invariant checks: the chat list's animations would
    // otherwise still be ticking.
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: _windowsAndMac);
}
