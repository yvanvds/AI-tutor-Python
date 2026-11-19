// #307: the first start without a decided mode, through `FirstStartApp` as
// `main()` mounts it. "I have a file from my school" picks the file, stores
// it and goes on to the school's sign-in; "Continue without a school" goes on
// to the stand-alone welcome (#264). A refused file says why and changes
// nothing. The real app, end to end, is the `app_mode` integration flow.

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/features/auth/sign_in_page.dart';
import 'package:ai_tutor_python/features/school/first_start_page.dart';
import 'package:ai_tutor_python/features/standalone/standalone_welcome_page.dart';
import 'package:ai_tutor_python/main.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';
import '../../helpers/memory_school_file_store.dart';

void main() {
  late MemorySchoolFileStore store;
  late String? fileToPick;
  late List<AppMode> booted;
  late List<ProviderContainer> containers;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    InMemoryCosmosClient().install();
    store = MemorySchoolFileStore();
    fileToPick = null;
    booted = [];
    containers = [];
  });

  /// Like `main()` with nothing decided: the choice, then [bootApp]'s part
  /// that matters here — the mode, and the stored sign-in or profile.
  Future<void> start(WidgetTester tester, {Locale? locale}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final locales = [
      systemLocaleProvider.overrideWithValue(locale ?? const Locale('en')),
    ];
    final choice = ProviderContainer(
      overrides: [
        ...locales,
        schoolFileStoreProvider.overrideWithValue(store),
        schoolFilePickerProvider.overrideWithValue(() async => fileToPick),
      ],
    );
    containers.add(choice);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: choice,
        child: FirstStartApp(
          boot: (mode) async {
            booted.add(mode);
            final app = ProviderContainer(
              overrides: [...locales, appModeProvider.overrideWithValue(mode)],
            );
            containers.add(app);
            await app
                .read(authServiceProvider.notifier)
                .tryAcquireTokenSilent();
            return app;
          },
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final c in containers) {
      c.dispose();
    }
  }

  testWidgets('the choice is asked; nothing is picked for the user', (
    tester,
  ) async {
    await start(tester);

    expect(find.byType(FirstStartPage), findsOneWidget);
    expect(find.text('How do you want to use the app?'), findsOneWidget);
    expect(find.text('I have a file from my school'), findsOneWidget);
    expect(find.text('Continue without a school'), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
    expect(find.byType(StandaloneWelcomePage), findsNothing);
    expect(booted, isEmpty);

    await unmount(tester);
  });

  testWidgets('a school file: stored, then the sign-in of that school', (
    tester,
  ) async {
    fileToPick = exampleSchoolFile();
    await start(tester);

    await tester.tap(find.byKey(const ValueKey('first-start-school')));
    await tester.pumpAndSettle();

    expect(find.byType(SignInPage), findsOneWidget);
    expect(find.byType(FirstStartPage), findsNothing);
    final school = parseSchoolFile(exampleSchoolFile());
    expect(booted, [SchoolMode(school)]);
    expect(store.stored, school);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('standalone.start_without_school_v1'), isNull);

    await unmount(tester);
  });

  testWidgets('without a school: remembered, then the stand-alone welcome', (
    tester,
  ) async {
    await start(tester);

    await tester.tap(find.byKey(const ValueKey('first-start-without-school')));
    await tester.pumpAndSettle();

    expect(find.byType(StandaloneWelcomePage), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);
    expect(booted, [const StandaloneMode()]);
    expect(store.stored, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('standalone.start_without_school_v1'), isTrue);

    await unmount(tester);
  });

  testWidgets('a cancelled file dialog leaves the choice as it was', (
    tester,
  ) async {
    await start(tester);

    await tester.tap(find.byKey(const ValueKey('first-start-school')));
    await tester.pumpAndSettle();

    expect(find.byType(FirstStartPage), findsOneWidget);
    expect(find.byKey(const ValueKey('first-start-error')), findsNothing);
    expect(booted, isEmpty);

    await unmount(tester);
  });

  for (final (name, file, message) in [
    ('not a school file', '{"account": {}}', 'This is not a school file. '),
    (
      'a newer format',
      exampleSchoolFile(formatVersion: 2),
      'This school file is for a newer version of the app. ',
    ),
    (
      'a missing field',
      '{"formatVersion": 1, "schoolName": "Example School"}',
      'This school file is incomplete or invalid (tenantId). ',
    ),
    (
      'a key in the file',
      exampleSchoolFile(extra: {'databaseKey': 'abc'}),
      'This file contains a key or password (databaseKey). ',
    ),
  ]) {
    testWidgets('$name: a clear message, and nothing changes', (tester) async {
      fileToPick = file;
      await start(tester);

      await tester.tap(find.byKey(const ValueKey('first-start-school')));
      await tester.pumpAndSettle();

      final error = tester.widget<Text>(
        find.byKey(const ValueKey('first-start-error')),
      );
      expect(error.data, startsWith(message));
      expect(error.data, endsWith('Nothing has changed.'));
      expect(find.byType(FirstStartPage), findsOneWidget);
      expect(booted, isEmpty);
      expect(store.stored, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);

      // The right file next: on to the sign-in.
      fileToPick = exampleSchoolFile();
      await tester.tap(find.byKey(const ValueKey('first-start-school')));
      await tester.pumpAndSettle();
      expect(find.byType(SignInPage), findsOneWidget);

      await unmount(tester);
    });
  }

  testWidgets('in Dutch', (tester) async {
    fileToPick = exampleSchoolFile(formatVersion: 3);
    await start(tester, locale: const Locale('nl'));

    expect(find.text('Hoe wil je de app gebruiken?'), findsOneWidget);
    expect(find.text('Ik heb een bestand van mijn school'), findsOneWidget);
    expect(find.text('Zonder school verder'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('first-start-school')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Er is niets veranderd.'), findsOneWidget);

    await unmount(tester);
  });
}
