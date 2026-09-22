// Issue #26 — the instructions editor (tutor system-prompt editor) is a
// developer tool and must not be reachable from the regular teacher UI. It is
// gated behind [developerToolsProvider] (kDebugMode in the shipping app).
//
// Issue #25 — the sidebar's bottom strip is an Options entry (a real section,
// routed like the others) plus sign-out. The former Settings popup and Debug
// icon buttons are gone: language moved into the Options page and the debug
// tools live in its developer-gated section.
//
// Issue #129 — the grade formula document is a section of its own, in the
// student group, so every signed-in user (a teacher included) can open it.
//
// Issue #151 — "My reports" is a second student-group section, next to the
// formula. Unlike the formula it is student-only: it lists the signed-in
// user's own published reports, and a teacher is never graded, so they get
// the class-wide "Reports" of #148 instead.
//
// This mounts the real Sidebar over the real providers, overriding only the
// derived profile and the developer-tools flag, so the assertions are about
// what a signed-in user actually sees in the navigation rail.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo (#28).

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
  xpNext: 500,
  streak: 0,
  role: Role.teacher,
);

const _student = Profile(
  name: 'Sam',
  topic: 'Python',
  level: 1,
  xp: 0,
  xpNext: 500,
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

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Sidebar)));

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

  testWidgets('bottom strip is Options + sign out for a student; the old '
      'Settings and Debug buttons are gone', (tester) async {
    await mount(tester, profile: _student, devTools: true);

    expect(find.byTooltip('Options'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.byTooltip('Debug'), findsNothing);
  });

  testWidgets('teacher also gets the Options entry', (tester) async {
    await mount(tester, profile: _teacher, devTools: false);

    expect(find.byTooltip('Options'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsNothing);
  });

  testWidgets('tapping Options routes to the options section and highlights '
      'it', (tester) async {
    await mount(tester, profile: _student, devTools: false);
    final container = containerOf(tester);
    expect(container.read(sectionProvider), Section.session);

    await tester.tap(find.byTooltip('Options'));
    await tester.pump();

    expect(container.read(sectionProvider), Section.options);
    // The active indicator is the accent bar; only one item carries it.
    final activeIcons = tester
        .widgetList<Icon>(find.byType(Icon))
        .where((i) => i.icon == Icons.settings_outlined)
        .toList();
    expect(activeIcons, hasLength(1));
    expect(activeIcons.single.color, isNot(equals(Colors.transparent)));

    await tester.tap(find.byTooltip('Session'));
    await tester.pump();
    expect(container.read(sectionProvider), Section.session);
  });

  testWidgets('student sees the grade formula entry and tapping it routes '
      'to the section', (tester) async {
    await mount(tester, profile: _student, devTools: false);
    final container = containerOf(tester);

    expect(find.byTooltip('Grade formula'), findsOneWidget);

    await tester.tap(find.byTooltip('Grade formula'));
    await tester.pump();

    expect(container.read(sectionProvider), Section.puntenformule);
    final icons = tester
        .widgetList<Icon>(find.byType(Icon))
        .where((i) => i.icon == Icons.calculate_outlined)
        .toList();
    expect(icons, hasLength(1));
    expect(icons.single.color, isNot(equals(Colors.transparent)));
  });

  testWidgets('teacher gets the grade formula entry in the student group, '
      'above the teacher header', (tester) async {
    await mount(tester, profile: _teacher, devTools: false);

    final entry = find.byTooltip('Grade formula');
    expect(entry, findsOneWidget);
    expect(
      tester.getTopLeft(entry).dy,
      lessThan(tester.getTopLeft(find.text('TEACHER')).dy),
    );
  });

  testWidgets('student sees the My reports entry and tapping it routes to '
      'the section', (tester) async {
    await mount(tester, profile: _student, devTools: false);
    final container = containerOf(tester);

    expect(find.byTooltip('My reports'), findsOneWidget);
    // The teacher's class-wide run is a different section, and a student has
    // no entry for it.
    expect(find.byTooltip('Reports'), findsNothing);

    await tester.tap(find.byTooltip('My reports'));
    await tester.pump();

    expect(container.read(sectionProvider), Section.myReports);
  });

  testWidgets('a teacher gets the class-wide Reports and not My reports', (
    tester,
  ) async {
    await mount(tester, profile: _teacher, devTools: false);

    expect(find.byTooltip('My reports'), findsNothing);
    final classWide = find.byTooltip('Reports');
    expect(classWide, findsOneWidget);
    expect(
      tester.getTopLeft(classWide).dy,
      greaterThan(tester.getTopLeft(find.text('TEACHER')).dy),
    );
  });

  test('Section.myReports is the one student-only section', () {
    expect(Section.values.where((s) => s.isStudentOnly), [Section.myReports]);
    expect(Section.myReports.isTeacherOnly, isFalse);
    expect(Section.myReports.isDeveloperOnly, isFalse);
    expect(Section.reports.isTeacherOnly, isTrue);
    expect(Section.reports.isStudentOnly, isFalse);
  });

  test('Section.puntenformule is reachable by students', () {
    expect(Section.puntenformule.isTeacherOnly, isFalse);
    expect(Section.puntenformule.isDeveloperOnly, isFalse);
  });

  test('Section.instructions is the only developer-only section', () {
    expect(Section.values.where((s) => s.isDeveloperOnly), [
      Section.instructions,
    ]);
    expect(Section.instructions.isTeacherOnly, isTrue);
  });

  test('Section.options is reachable by students', () {
    expect(Section.options.isTeacherOnly, isFalse);
    expect(Section.options.isDeveloperOnly, isFalse);
  });
}
