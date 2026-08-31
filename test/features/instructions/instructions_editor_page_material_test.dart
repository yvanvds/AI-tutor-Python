// Issue #69 — `ListTile background color or ink splashes may be invisible.`
//
// The instructions editor painted its background with a coloured `Container`,
// i.e. a `ColoredBox`. `ListTile` paints its tile colour, its selected
// highlight and its ink splashes into the nearest `Material` *above* it, so
// that ColoredBox sat in front of them and hid all three: picking a document
// or a section looked exactly like not picking one, and Flutter reported the
// assertion once per row per build. Same defect as #68 one page over.
//
// Mounting the page at all needed the seam this issue added:
// `InstructionsService` used to resolve the process-wide
// `CosmosPaths.instructions()` handle, so there was no way to give it data in
// a widget test. It now takes the `container:` override every other
// Cosmos-backed service here has.
//
// The end-to-end half — a teacher opening Instructions in the real shell —
// lives in `integration_test/flows/instructions_row_highlight.dart`.

import 'package:ai_tutor_python/features/instructions/doc_list.dart';
import 'package:ai_tutor_python/features/instructions/instructions_editor_page.dart';
import 'package:ai_tutor_python/features/instructions/sections_list.dart';
import 'package:ai_tutor_python/services/instructions/instructions_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/ink_surface.dart';
import '../../helpers/localization.dart';

Map<String, dynamic> _instructionDoc(String id, Map<String, String> sections) =>
    {
      'id': id,
      'type': 'instruction',
      'sections': sections,
      'updatedAt': '2026-05-01T10:00:00Z',
    };

/// Takes whatever the framework reported during the last frame and asserts it
/// was not the ink one, leaving the binding clean for the next frame.
///
/// Not a plain `expect(tester.takeException(), isNull)` like the goals-page
/// twin: the two section buttons ("Add section", "Delete") sit in a 280 px
/// pane and fit there in the real font, but not in the square-glyph test font,
/// so every laid-out frame of this page in a widget test also reports a
/// `RenderFlex overflowed`. Naming the error this test is about keeps that
/// artefact from failing the run; the real layout is checked in the
/// integration flow, which runs the real font at the real window size.
///
/// The binding holds one error per frame and the overflow usually wins the
/// race, so this is the belt to the surface walk's braces: the assertion that
/// actually pins the regression is [firstSurfaceAbove].
void expectNoInkError(WidgetTester tester) {
  final Object? error = tester.takeException();
  expect(
    error?.toString() ?? '',
    isNot(
      contains(
        'ListTile background color or ink splashes may be '
        'invisible',
      ),
    ),
    reason: 'an instructions row cannot paint its tile colour or ink',
  );
}

void main() {
  testWidgets('the instructions rows paint their ink on a Material, not '
      'behind the page background', (tester) async {
    final instructions = InMemoryCosmos([
      _instructionDoc('system_prompt', {
        'rules_and_style': 'Be brief.',
        'summary': 'Wrap up.',
      }),
      _instructionDoc('exercise_prompt', {'intro': 'Ask one question.'}),
    ]);
    final container = ProviderContainer(
      overrides: [
        instructionsServiceProvider.overrideWith(
          () => InstructionsService(container: instructions.container),
        ),
      ],
    );
    tester.view.physicalSize = const Size(1900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: localizedTestApp(const Scaffold(body: InstructionsEditorPage())),
      ),
    );
    // Drained after every frame — the binding holds one error at a time, and
    // an undrained one fails the test at teardown. The docs poll lands on the
    // second frame; before the fix that frame reported the ink error once per
    // row.
    expectNoInkError(tester);
    await tester.pump();
    expectNoInkError(tester);
    await tester.pump();
    expectNoInkError(tester);

    // Scoped to the list: once the document is selected, the header pane
    // shows its id on a `ListTile` of its own.
    final docTile = find.descendant(
      of: find.byType(DocsList),
      matching: find.widgetWithText(ListTile, 'system_prompt'),
    );
    expect(docTile, findsOneWidget);
    // …and nothing may stand between the row and the surface it paints on.
    expect(
      firstSurfaceAbove(tester, docTile),
      isA<Material>(),
      reason:
          'an opaque box sits between the row and its Material, so the '
          'row highlight and ink are painted and then covered',
    );

    // Selecting a document is the interaction the highlight is for: it fills
    // the sections pane, whose rows are `ListTile`s on the same surface.
    await tester.tap(docTile);
    await tester.pump();
    expectNoInkError(tester);

    final selectedDoc = tester.widget<ListTile>(docTile);
    expect(selectedDoc.selected, isTrue);

    final sectionTile = find.descendant(
      of: find.byType(SectionsList),
      matching: find.widgetWithText(ListTile, 'rules_and_style'),
    );
    expect(sectionTile, findsOneWidget);
    expect(
      firstSurfaceAbove(tester, sectionTile),
      isA<Material>(),
      reason: 'the sections list paints on the page surface too',
    );

    // Unmounting cancels the docs polling timer.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
