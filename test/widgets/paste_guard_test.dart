// #334 — a student could paste a chatbot's answer into the answer field.
// Now a paste from outside the app does not reach the code editor (the
// answer of an exercise, Practice, and the Playground) or the chat composer:
// Ctrl+V, Shift+Insert and Paste in the right-click menu change nothing, a
// short neutral notice says so, and the attempt is noted for the
// oefening's record. Text the student copied inside the app — from the
// editor, the tutor's messages, a student message — pastes as before.
// Typing is untouched, and with `BlockExternalPaste: false` in the school's
// `config/global` every paste goes through.
//
// The real `Editor` (flutter_code_editor's `CodeField`), the real
// `ComposerIdle`, `TutorMarkdown` and `StudentBubble`; the system clipboard
// is a fake behind the platform channel, so what a test puts there came from
// outside the app. The end-to-end run in the real app is
// `integration_test/flows/paste_guard.dart`.

import 'package:ai_tutor_python/core/blocked_pastes.dart';
import 'package:ai_tutor_python/features/chat/widgets/composer_idle.dart';
import 'package:ai_tutor_python/features/chat/widgets/student_bubble.dart';
import 'package:ai_tutor_python/features/dashboard/editor.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/clipboard/in_app_clipboard.dart';
import 'package:ai_tutor_python/services/clipboard/paste_policy.dart';
import 'package:ai_tutor_python/services/code/code_service.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:ai_tutor_python/widgets/paste_guard.dart';
import 'package:ai_tutor_python/widgets/tutor_markdown.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart'
    show ComposerHeightNotifier;
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart' as provider;

const _chatbotAnswer = 'def som(a, b):\n    return a + b\n';
const _notice = "Pasting from outside the app isn't possible here.";

/// The system clipboard, behind the platform channel.
class _Clipboard {
  String? text;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'Clipboard.setData':
        text = (call.arguments as Map)['text'] as String?;
        return null;
      case 'Clipboard.getData':
        return text == null ? null : <String, Object?>{'text': text};
      case 'Clipboard.hasStrings':
        return <String, Object?>{'value': text?.isNotEmpty ?? false};
    }
    return null;
  }
}

/// The school's `config/global` as the app has it in memory.
class _Config extends GlobalConfigService {
  _Config(this.config);
  final GlobalConfig config;

  @override
  GlobalConfig? build() => config;
}

Finder get _editable => find.descendant(
  of: find.byType(CodeField),
  matching: find.byType(EditableText),
);

/// The idle composer as the chat hosts it: over the list, in a stack, under
/// the height report the list pads itself by.
Widget _composer() => provider.ChangeNotifierProvider(
  create: (_) => ComposerHeightNotifier(),
  child: const Stack(children: [ComposerIdle()]),
);

Finder get _composerField => find.descendant(
  of: find.byType(ComposerIdle),
  matching: find.byType(TextField),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late _Clipboard clipboard;
  late ProviderContainer pc;

  setUp(() {
    clipboard = _Clipboard();
    InAppClipboard.instance.clear();
  });
  tearDown(InAppClipboard.instance.clear);

  /// [body] in the app's localized shell, over the fake clipboard; the
  /// school's config says [blockExternalPaste], or there is none.
  Future<void> mount(
    WidgetTester tester,
    Widget body, {
    SessionMode mode = SessionMode.practice,
    bool? blockExternalPaste,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      clipboard.handle,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    pc = ProviderContainer(
      overrides: [
        modeProvider.overrideWith((_) => mode),
        if (blockExternalPaste != null)
          globalConfigServiceProvider.overrideWith(
            () => _Config(
              GlobalConfig(
                model: 'gpt-5-mini',
                apiKey: '',
                blockExternalPaste: blockExternalPaste,
              ),
            ),
          ),
      ],
    );
    addTearDown(pc.dispose);
    // The app keeps the config alive (the update gate watches it).
    if (blockExternalPaste != null) pc.read(globalConfigServiceProvider);
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

  /// Lets the clipboard reads and the paste behind them run.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Lets the editor's debounces and the notice's timer run out, then
  /// unmounts.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await settle(tester);
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) =>
      chord(tester, LogicalKeyboardKey.controlLeft, key);

  Future<void> shiftInsert(WidgetTester tester) =>
      chord(tester, LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.insert);

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.startGesture(
      tester.getCenter(finder),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await settle(tester);
  }

  /// The editor of [mode], focused with the caret at the end of [text].
  Future<CodeService> editor(
    WidgetTester tester, {
    SessionMode mode = SessionMode.practice,
    String text = 'x = 1\n',
    bool? blockExternalPaste,
  }) async {
    await mount(
      tester,
      const Editor(),
      mode: mode,
      blockExternalPaste: blockExternalPaste,
    );
    final code = pc.read(codeServiceProvider(mode));
    code.setText(text);
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    code.controller.selection = TextSelection.collapsed(offset: text.length);
    await tester.pump();
    return code;
  }

  BlockedPastes noted() => pc.read(blockedPasteLedgerProvider).pending;

  group('the code editor', () {
    testWidgets('Ctrl+V and Shift+Insert with text from outside the app change '
        'nothing, say so, and are noted with their characters', (tester) async {
      final code = await editor(tester);
      clipboard.text = _chatbotAnswer;

      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'x = 1\n');
      expect(find.byKey(pasteBlockedNoticeKey), findsOneWidget);
      expect(find.text(_notice), findsOneWidget);

      await shiftInsert(tester);
      expect(code.getText(), 'x = 1\n');
      expect(
        noted(),
        BlockedPastes(count: 2, chars: 2 * _chatbotAnswer.length),
      );

      // A text with Windows line ends counts its characters as the student
      // sees them.
      pc.read(blockedPasteLedgerProvider).clear();
      clipboard.text = 'a\r\nb';
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(noted(), const BlockedPastes(count: 1, chars: 3));

      await finish(tester);
    });

    testWidgets('Paste in the right-click menu with text from outside the app '
        'changes nothing and says so; the menu keeps cut, copy and select '
        'all', (tester) async {
      final code = await editor(tester);
      clipboard.text = _chatbotAnswer;
      code.controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );
      await tester.pump();

      await rightClick(tester, find.byType(CodeField));
      for (final item in ['Cut', 'Copy', 'Paste', 'Select all']) {
        expect(find.text(item), findsOneWidget, reason: item);
      }
      await tester.tap(find.text('Paste'));
      await settle(tester);

      expect(code.getText(), 'x = 1\n');
      expect(find.text(_notice), findsOneWidget);
      expect(find.text('Select all'), findsNothing, reason: 'menu closed');
      expect(noted().count, 1);

      await finish(tester);
    });

    testWidgets('what was copied or cut in the editor — Ctrl+C, Ctrl+X, the '
        "menu's Copy — pastes as before, and says nothing", (tester) async {
      final code = await editor(tester, text: 'som = 1 + 2\n');
      final controller = code.controller;

      // Ctrl+C on `som`, then Ctrl+V at the end.
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await ctrl(tester, LogicalKeyboardKey.keyC);
      expect(clipboard.text, 'som');
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'som = 1 + 2\nsom');

      // Ctrl+X moves `1 + 2` to the end.
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      await ctrl(tester, LogicalKeyboardKey.keyX);
      expect(code.getText(), 'som = \nsom');
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'som = \nsom1 + 2');

      // Copy in the right-click menu, pasted with Shift+Insert.
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();
      await rightClick(tester, find.byType(CodeField));
      await tester.tap(find.text('Copy'));
      await settle(tester);
      expect(clipboard.text, 'som =');
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await shiftInsert(tester);
      expect(code.getText(), 'som = \nsom1 + 2som =');

      expect(find.text(_notice), findsNothing);
      expect(noted(), BlockedPastes.none);
      await finish(tester);
    });

    testWidgets('in the Playground too: Ctrl+V from outside is blocked, text '
        "copied from the tutor's message pastes", (tester) async {
      final code = await editor(tester, mode: SessionMode.playground);
      clipboard.text = _chatbotAnswer;
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'x = 1\n');
      expect(find.text(_notice), findsOneWidget);

      // A copy made in the app, as the tutor's message makes one.
      await InAppClipboard.instance.copy('print(x)');
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'x = 1\nprint(x)');
      expect(noted().count, 1);

      await finish(tester);
    });

    testWidgets('typing works as before, also after a blocked paste', (
      tester,
    ) async {
      final code = await editor(tester, text: '');
      clipboard.text = _chatbotAnswer;
      await ctrl(tester, LogicalKeyboardKey.keyV);

      const typed = 'naam = 1';
      for (var k = 1; k <= typed.length; k++) {
        await tester.enterText(_editable, typed.substring(0, k));
        await tester.pump();
      }
      expect(code.getText(), typed);

      await finish(tester);
    });

    testWidgets('with BlockExternalPaste false every paste goes through, '
        'and nothing is noted', (tester) async {
      final code = await editor(tester, blockExternalPaste: false);
      clipboard.text = 'y = 2';

      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'x = 1\ny = 2');

      await rightClick(tester, find.byType(CodeField));
      await tester.tap(find.text('Paste'));
      await settle(tester);
      expect(code.getText(), 'x = 1\ny = 2y = 2');

      expect(find.text(_notice), findsNothing);
      expect(noted(), BlockedPastes.none);
      await finish(tester);
    });

    testWidgets('with the switch on in config/global, as without one, the '
        'paste is blocked', (tester) async {
      final code = await editor(tester, blockExternalPaste: true);
      clipboard.text = 'y = 2';
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'x = 1\n');
      expect(noted().count, 1);
      await finish(tester);
    });

    testWidgets('an empty clipboard pastes nothing and says nothing', (
      tester,
    ) async {
      final code = await editor(tester);
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(code.getText(), 'x = 1\n');
      expect(find.text(_notice), findsNothing);
      expect(noted(), BlockedPastes.none);
      await finish(tester);
    });
  });

  group('the chat composer', () {
    Future<TextEditingController> composer(WidgetTester tester) async {
      await mount(tester, _composer());
      await tester.tap(_composerField);
      await tester.pump();
      return tester.widget<TextField>(_composerField).controller!;
    }

    testWidgets('Ctrl+V, Shift+Insert and Paste in the menu with text from '
        'outside the app change nothing and say so', (tester) async {
      final field = await composer(tester);
      clipboard.text = 'Het antwoord is 42.';

      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(field.text, isEmpty);
      expect(find.text(_notice), findsOneWidget);

      await shiftInsert(tester);
      expect(field.text, isEmpty);

      await rightClick(tester, _composerField);
      expect(find.text('Paste'), findsOneWidget);
      await tester.tap(find.text('Paste'));
      await settle(tester);
      expect(field.text, isEmpty);

      expect(noted(), const BlockedPastes(count: 3, chars: 3 * 19));
      await finish(tester);
    });

    testWidgets('text copied in the app pastes, from the menu too; typing '
        'works as before', (tester) async {
      final field = await composer(tester);
      await tester.enterText(_composerField, 'Waarom ');
      await tester.pump();
      expect(field.text, 'Waarom ');

      await InAppClipboard.instance.copy('#3fa91c');
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(field.text, 'Waarom #3fa91c');

      await rightClick(tester, _composerField);
      await tester.tap(find.text('Paste'));
      await settle(tester);
      expect(field.text, 'Waarom #3fa91c#3fa91c');

      // What is typed in the composer and copied there pastes too.
      field.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await ctrl(tester, LogicalKeyboardKey.keyC);
      expect(clipboard.text, 'Waarom');
      expect(InAppClipboard.instance.holds('Waarom'), isTrue);

      expect(find.text(_notice), findsNothing);
      expect(noted(), BlockedPastes.none);
      await finish(tester);
    });

    testWidgets('with BlockExternalPaste false a paste from outside goes '
        'through', (tester) async {
      await mount(tester, _composer(), blockExternalPaste: false);
      await tester.tap(_composerField);
      await tester.pump();
      clipboard.text = 'van buiten';
      await ctrl(tester, LogicalKeyboardKey.keyV);
      expect(
        tester.widget<TextField>(_composerField).controller!.text,
        'van buiten',
      );
      expect(noted(), BlockedPastes.none);
      await finish(tester);
    });
  });

  group('a copy in the app is remembered', () {
    testWidgets("from the tutor's text: Ctrl+C and Copy in its menu", (
      tester,
    ) async {
      const tutorText = 'Gebruik return in plaats van print.';
      await mount(tester, const TutorMarkdown(tutorText));

      // A double click selects a word; Ctrl+C copies it.
      final at =
          tester.getTopLeft(find.byType(TutorMarkdown)) + const Offset(20, 10);
      final gesture = await tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.down(at);
      await gesture.up();
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyC);
      final word = clipboard.text;
      expect(word, isNotNull);
      expect(word, isNotEmpty);
      expect(InAppClipboard.instance.holds(word!), isTrue);

      // Select all and Copy from the right-click menu.
      await ctrl(tester, LogicalKeyboardKey.keyA);
      await rightClick(tester, find.byType(TutorMarkdown));
      await tester.tap(find.text('Copy'));
      await settle(tester);
      expect(clipboard.text, tutorText);
      expect(InAppClipboard.instance.holds(tutorText), isTrue);

      await finish(tester);
    });

    testWidgets("from a student's own message", (tester) async {
      const message = 'Ik snap de lus niet.';
      await mount(tester, const StudentBubble(text: message));
      await tester.tap(find.byType(SelectableText));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyA);
      await ctrl(tester, LogicalKeyboardKey.keyC);
      expect(clipboard.text, message);
      expect(InAppClipboard.instance.holds(message), isTrue);

      // And from its menu.
      InAppClipboard.instance.clear();
      clipboard.text = null;
      await rightClick(tester, find.byType(SelectableText));
      await tester.tap(find.text('Copy'));
      await settle(tester);
      expect(clipboard.text, message);
      expect(InAppClipboard.instance.holds(message), isTrue);

      await finish(tester);
    });
  });
}
