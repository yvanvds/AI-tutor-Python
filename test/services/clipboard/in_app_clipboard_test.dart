// #334 — what the student copied inside the app: the texts a paste into the
// answer, the chat or the Playground lets through.

import 'package:ai_tutor_python/services/clipboard/in_app_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final clipboard = InAppClipboard.instance;
  setUp(clipboard.clear);
  tearDown(clipboard.clear);

  test('holds exactly what was copied: not a part of it, not more', () {
    clipboard.remember('print(som)');
    expect(clipboard.holds('print(som)'), isTrue);
    expect(clipboard.holds('print'), isFalse);
    expect(clipboard.holds('print(som)\n'), isFalse);
    expect(clipboard.holds('PRINT(SOM)'), isFalse);
  });

  test('a text with Windows line ends is the same text', () {
    clipboard.remember('a = 1\nprint(a)');
    expect(clipboard.holds('a = 1\r\nprint(a)'), isTrue);
    clipboard.remember('b = 2\r\nprint(b)');
    expect(clipboard.holds('b = 2\nprint(b)'), isTrue);
  });

  test('an empty copy is no copy', () {
    clipboard.remember('');
    expect(clipboard.holds(''), isFalse);
  });

  test('keeps the newest copies; one copied again is the newest again', () {
    for (var i = 0; i < InAppClipboard.capacity; i++) {
      clipboard.remember('copy $i');
    }
    clipboard.remember('copy 0');
    clipboard.remember('one more');
    expect(clipboard.holds('copy 0'), isTrue, reason: 'copied again');
    expect(clipboard.holds('copy 1'), isFalse, reason: 'the oldest went');
    expect(clipboard.holds('copy 2'), isTrue);
    expect(clipboard.holds('one more'), isTrue);
  });

  test('clear forgets every copy: the student signed out', () {
    clipboard.remember('x = 1');
    clipboard.clear();
    expect(clipboard.holds('x = 1'), isFalse);
  });

  testWidgets('copy puts the text on the clipboard and remembers it', (
    tester,
  ) async {
    final set = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          set.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await clipboard.copy('#3fa91c');
    expect(set, ['#3fa91c']);
    expect(clipboard.holds('#3fa91c'), isTrue);
  });
}
