// Issue #26 — the instructions editor (tutor system-prompt editor) is a
// developer tool and must not be reachable from the regular teacher UI. It is
// gated behind [developerToolsProvider] (kDebugMode in the shipping app).
//
// This mounts the real Sidebar over the real providers, overriding only the
// derived profile and the developer-tools flag, so the assertions are about
// what a signed-in teacher actually sees in the navigation rail.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo.

import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/localization.dart';

const _teacher = Profile(
  name: 'Yvan',
  topic: 'Python',
  level: 1,
  xp: 0,
  xpNext: 1500,
  streak: 0,
  role: Role.teacher,
);

const _student = Profile(
  name: 'Sam',
  topic: 'Python',
  level: 1,
  xp: 0,
  xpNext: 1500,
  streak: 0,
  role: Role.student,
);

void main() {
  Widget buildApp({required Profile profile, required bool devTools}) =>
      ProviderScope(
        overrides: [
          profileProvider.overrideWithValue(profile),
          developerToolsProvider.overrideWithValue(devTools),
        ],
        child: localizedTestApp(
          const Scaffold(body: Row(children: [Sidebar()])),
        ),
      );

  Future<void> mount(
    WidgetTester tester, {
    required Profile profile,
    required bool devTools,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildApp(profile: profile, devTools: devTools));
    await tester.pump();
  }

  testWidgets('teacher without developer tools does not see the instructions '
      'entry but keeps the other teacher sections', (tester) async {
    await mount(tester, profile: _teacher, devTools: false);

    expect(find.byTooltip('Instructions'), findsNothing);
    expect(find.byTooltip('Goals'), findsOneWidget);
    expect(find.byTooltip('Lesson content'), findsOneWidget);
    expect(find.byTooltip('Students'), findsOneWidget);
    expect(find.byTooltip('Debug'), findsNothing);
  });

  testWidgets('teacher with developer tools sees the instructions entry', (
    tester,
  ) async {
    await mount(tester, profile: _teacher, devTools: true);

    expect(find.byTooltip('Instructions'), findsOneWidget);
  });

  testWidgets('student never sees the instructions entry, even with developer '
      'tools', (tester) async {
    await mount(tester, profile: _student, devTools: true);

    expect(find.byTooltip('Instructions'), findsNothing);
    expect(find.byTooltip('Goals'), findsNothing);
  });

  test('Section.instructions is the only developer-only section', () {
    expect(Section.values.where((s) => s.isDeveloperOnly), [
      Section.instructions,
    ]);
    expect(Section.instructions.isTeacherOnly, isTrue);
  });
}
