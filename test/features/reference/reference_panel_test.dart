// #323 — a student who no longer knows how a function is called or what it
// does had to search the whole course. The reference panel lists every
// function and class of the course from the bundled reference. These mount
// the real panel on the real asset bundle and drive it as a student does:
// the groups to browse, a search by name or by a word of the explanation,
// the item with how it is written, its explanation, its example and the
// lesson that explains it, in the app language; Escape and the cross close
// it. Where it sits next to the exercise is in
// test/features/session/reference_panel_session_test.dart.

import 'package:ai_tutor_python/features/reference/reference_panel.dart';
import 'package:ai_tutor_python/features/reference/reference_panel_state.dart';
import 'package:ai_tutor_python/services/translation/localized_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localization.dart';

/// The lessons in the app: only the one about print.
LocalizedContent? _lesson(String contentId) => contentId == 'uitvoer-print'
    ? const LocalizedContent(
        contentId: 'uitvoer-print',
        language: 'en',
        title: 'Output with print',
        body: '<p>print</p>',
      )
    : null;

Finder _item(String key) => find.byKey(ValueKey('reference-item-$key'));
Finder _group(String id) => find.byKey(ValueKey('reference-group-$id'));
final _search = find.byKey(const Key('reference-search'));

void main() {
  late ProviderContainer pc;

  setUp(() {
    pc = ProviderContainer(
      overrides: [
        localizedContentProvider.overrideWith((ref, id) => _lesson(id)),
      ],
    );
    pc.read(referencePanelOpenProvider.notifier).open();
  });

  tearDown(() => pc.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double width = referencePanelMinWidth,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: pc,
        child: localizedTestApp(
          Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(width: width, child: const ReferencePanel()),
            ),
          ),
          locale: locale,
        ),
      ),
    );
    // The bundled file is read through the test's asset bundle.
    for (var i = 0; i < 20 && _group('builtins').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(
      _group('builtins'),
      findsOneWidget,
      reason: 'the reference never loaded',
    );
  }

  testWidgets('it opens with the keyboard in the search field and every group '
      'closed', (tester) async {
    await mount(tester);

    expect(find.text('Reference'), findsOneWidget);
    final field = tester.widget<EditableText>(
      find.descendant(of: _search, matching: find.byType(EditableText)),
    );
    expect(field.focusNode.hasFocus, isTrue);
    for (final id in [
      'builtins',
      'str',
      'list',
      'dict',
      'turtle',
      'turtle.Turtle',
      'math',
      'random',
      'matplotlib.pyplot',
      'numpy',
    ]) {
      expect(_group(id), findsOneWidget, reason: id);
    }
    expect(find.text('Built-in functions'), findsOneWidget);
    expect(_item('builtins.print'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a group opens to its items: how each is written, what it '
      'does, an example, and a link to the lesson that explains it', (
    tester,
  ) async {
    await mount(tester);

    await tester.tap(_group('builtins'));
    await tester.pump();

    final print = _item('builtins.print');
    expect(print, findsOneWidget);
    Finder inPrint(Finder f) => find.descendant(of: print, matching: f);
    expect(
      inPrint(find.text("print(value, ..., sep=' ', end='\\n')")),
      findsOneWidget,
    );
    expect(
      inPrint(find.textContaining('Shows one or more values on the screen')),
      findsOneWidget,
    );
    expect(inPrint(find.textContaining('print("x =", 3)')), findsOneWidget);
    expect(inPrint(find.text('Lesson: Output with print')), findsOneWidget);
    // A lesson that is not in the app gets no link.
    expect(
      find.descendant(
        of: _item('builtins.input'),
        matching: find.textContaining('Lesson:'),
      ),
      findsNothing,
    );

    // A module's group starts with how the course imports it.
    await tester.tap(_group('builtins'));
    await tester.pump();
    await tester.tap(_group('matplotlib.pyplot'));
    await tester.pump();
    expect(find.text('import matplotlib.pyplot as plt'), findsOneWidget);
    expect(find.text('plt.plot(x, y, label=..., color=...)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search finds a name, or a word of the explanation, and says '
      'which group each hit is from', (tester) async {
    await mount(tester);

    await tester.enterText(_search, 'randint');
    await tester.pump();
    expect(_item('random.randint'), findsOneWidget);
    expect(
      find.descendant(
        of: _item('random.randint'),
        matching: find.text('random'),
      ),
      findsOneWidget,
    );
    expect(find.text('random.randint(a, b)'), findsOneWidget);
    expect(_group('builtins'), findsNothing);

    await tester.enterText(_search, 'square root');
    await tester.pump();
    expect(_item('math.sqrt'), findsOneWidget);
    expect(_item('numpy.sqrt'), findsOneWidget);

    await tester.enterText(_search, 'zzz');
    await tester.pump();
    expect(find.text('Nothing found for "zzz".'), findsOneWidget);

    // The cross in the field empties it: back to the groups.
    await tester.tap(find.byKey(const Key('reference-search-clear')));
    await tester.pump();
    expect(_group('builtins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Dutch: the panel, the groups, the explanations and the '
      'search', (tester) async {
    await mount(tester, locale: const Locale('nl'));

    expect(find.text('Naslag'), findsOneWidget);
    expect(find.text('Ingebouwde functies'), findsOneWidget);

    await tester.enterText(_search, 'wortel');
    await tester.pump();
    expect(_item('math.sqrt'), findsOneWidget);
    expect(find.text('De vierkantswortel √x.'), findsOneWidget);

    await tester.enterText(_search, 'zzz');
    await tester.pump();
    expect(find.text('Niets gevonden voor "zzz".'), findsOneWidget);
  });

  testWidgets('Escape and the cross close it', (tester) async {
    await mount(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(pc.read(referencePanelOpenProvider), isFalse);

    pc.read(referencePanelOpenProvider.notifier).open();
    await tester.pump();
    await tester.tap(find.byKey(const Key('reference-close')));
    await tester.pump();
    expect(pc.read(referencePanelOpenProvider), isFalse);
  });

  testWidgets('at its narrowest every group and every item lays out without '
      'an overflow', (tester) async {
    // A window tall enough for the whole list: every item is laid out.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 30000);
    addTearDown(tester.view.reset);
    await mount(tester);
    // Last first: opening a group pushes the ones below it down.
    for (final id in [
      'numpy',
      'matplotlib.pyplot',
      'random',
      'math',
      'turtle.Turtle',
      'turtle',
      'dict',
      'list',
      'str',
      'builtins',
    ]) {
      await tester.tap(_group(id));
      await tester.pump();
    }
    expect(_item('builtins.print'), findsOneWidget);
    expect(_item('numpy.pi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
