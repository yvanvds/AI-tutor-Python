// End-to-end (#28, fixing #69): a teacher opens the Instructions editor and
// the document row they pick is actually highlighted.
//
// Why this has to run against the real app rather than the widget test next
// to it: the bug was not in a row or in a list, it was in how the *page*
// composes them. Every row here is a `ListTile` with an `onTap`, and
// `ListTile` paints its tile colour, its selected highlight and every ink
// splash into the nearest `Material` above it. The page's background used to
// be a coloured `Container`, i.e. a `ColoredBox`, which is painted in front of
// that Material and hid all three, while Flutter threw `ListTile background
// color or ink splashes may be invisible.` once per row per build.
//
// It also runs the page at the real window size in the real font, which the
// widget test cannot: in the square-glyph test font the two section buttons
// overflow their 280 px pane, an artefact that has nothing to do with the app.
//
// Run (all flows, one app process — see app_test.dart):
//   flutter test integration_test -d windows
// Run just this flow:
//   flutter test integration_test/flows/instructions_row_highlight.dart -d windows

import 'package:ai_tutor_python/features/instructions/doc_list.dart';
import 'package:ai_tutor_python/features/instructions/instructions_editor_page.dart';
import 'package:ai_tutor_python/features/instructions/sections_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../test/helpers/ink_surface.dart';
import '../harness/app_harness.dart';
import '../harness/seed.dart';

Map<String, dynamic> _instructionDoc(String id, Map<String, String> sections) =>
    {
      'id': id,
      'type': 'instruction',
      'sections': sections,
      'updatedAt': '2026-05-01T10:00:00Z',
    };

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Instructions: the selected document row can paint its '
      'highlight', (tester) async {
    final harness = AppHarness(identity: teacherIdentity);
    await harness.boot(tester);

    // Seeded here rather than in `seed.dart`: no other flow reads the
    // instructions container, and the tutor would pick these prompts up.
    harness.cosmos['instructions'].docs.addAll({
      'system_prompt': _instructionDoc('system_prompt', {
        'rules_and_style': 'Be brief.',
        'summary': 'Wrap up.',
      }),
      'exercise_prompt': _instructionDoc('exercise_prompt', {
        'intro': 'Ask one question.',
      }),
    });

    // The section is developer-gated, which an integration-test binary (a
    // debug build) satisfies — the same way a teacher on a dev build sees it.
    await tester.tap(find.byTooltip('Instructions'));
    await pumpUntilFound(tester, find.byType(InstructionsEditorPage));

    final docTile = find.descendant(
      of: find.byType(DocsList),
      matching: find.widgetWithText(ListTile, 'system_prompt'),
    );
    await pumpUntilFound(tester, docTile);

    // Picking a document is the interaction the highlight is for.
    await tester.tap(docTile);
    await tester.pump();
    await pumpUntilFound(tester, find.byType(SectionsList));

    final selected = tester.widget<ListTile>(docTile);
    expect(selected.selected, isTrue);

    // Nothing may stand between the row and the surface it paints on.
    // (Before the fix the app also threw the framework assertion here, once
    // per row per build, which fails this test on its own.)
    expect(
      firstSurfaceAbove(tester, docTile),
      isA<Material>(),
      reason:
          'an opaque box sits between the row and its Material, so the '
          'selected-document highlight is painted and then covered',
    );

    final sectionTile = find.descendant(
      of: find.byType(SectionsList),
      matching: find.widgetWithText(ListTile, 'rules_and_style'),
    );
    await pumpUntilFound(tester, sectionTile);
    expect(
      firstSurfaceAbove(tester, sectionTile),
      isA<Material>(),
      reason: 'the sections list paints on the page surface too',
    );

    await harness.dispose(tester);
  });
}
