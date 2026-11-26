// #264: the stand-alone start, through `GoalsApp` as `main()` mounts it.
//
// First start: the welcome screen. A name makes the local profile and its
// account doc (`mayUseGlobalKey: false`), so the key screen follows, with the
// stand-alone text. A second start with that profile skips the welcome. The
// whole way into the shell, on local storage, is the `standalone_start`
// integration flow.

import 'dart:convert';

import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/features/auth/local_key_gate_screen.dart';
import 'package:ai_tutor_python/features/auth/sign_in_page.dart';
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

const _standaloneKeyText =
    "The tutor uses OpenAI's AI. For that you need your own key.\n\n"
    'Make one at platform.openai.com/api-keys and paste it below. You pay '
    'OpenAI for what you use.\n\nThe key stays on this pc only.';

void main() {
  late InMemoryCosmosClient cosmos;
  late MemorySchoolFileStore schoolStore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cosmos = InMemoryCosmosClient()..install();
    schoolStore = MemorySchoolFileStore();
  });

  /// Like `main()`: the container reads the stored profile before the first
  /// frame.
  Future<ProviderContainer> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        appModeProvider.overrideWithValue(const StandaloneMode()),
        systemLocaleProvider.overrideWithValue(const Locale('en', 'US')),
        schoolFileStoreProvider.overrideWithValue(schoolStore),
        schoolFilePickerProvider.overrideWithValue(
          () async => exampleSchoolFile(),
        ),
      ],
    );
    await container.read(authServiceProvider.notifier).tryAcquireTokenSilent();
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const GoalsApp()),
    );
    await tester.pump();
    return container;
  }

  /// Unmounts and disposes the container, which stops its account and
  /// config polls.
  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }

  testWidgets('first start: welcome, then the key screen with the '
      'stand-alone text', (tester) async {
    final container = await start(tester);

    expect(find.byType(StandaloneWelcomePage), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);

    // No first name, no profile.
    await tester.tap(find.byKey(const ValueKey('standalone-welcome-start')));
    await tester.pump();
    expect(find.text('Enter your first name.'), findsOneWidget);
    expect(container.read(authServiceProvider), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('standalone-welcome-first-name')),
      'Alex',
    );
    await tester.tap(find.byKey(const ValueKey('standalone-welcome-start')));
    await tester.pumpAndSettle();

    expect(find.byType(LocalKeyGateScreen), findsOneWidget);
    expect(find.text(_standaloneKeyText), findsOneWidget);
    expect(find.byType(StandaloneWelcomePage), findsNothing);

    final identity = container.read(authServiceProvider)!;
    expect(identity.firstName, 'Alex');
    expect(identity.isTeacher, isFalse);
    final account = cosmos['accounts'][identity.oid]!;
    expect(account['firstName'], 'Alex');
    expect(account['lastName'], '');
    expect(account['email'], '');
    expect(account['mayUseGlobalKey'], isFalse);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString('standalone.local_profile_v1')!);
    expect(stored['uid'], identity.oid);

    await unmount(tester, container);
  });

  testWidgets('the language picked on the welcome screen applies at once', (
    tester,
  ) async {
    final container = await start(tester);

    await tester.tap(find.text('Nederlands'));
    await tester.pumpAndSettle();

    expect(find.text('Welkom'), findsOneWidget);
    expect(find.text('Voornaam'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_locale'), 'nl');

    await unmount(tester, container);
  });

  testWidgets('a second start skips the welcome screen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'standalone.local_profile_v1': jsonEncode({
        'uid': 'local-1',
        'firstName': 'Alex',
        'lastName': '',
      }),
    });
    cosmos['accounts'].upsert({
      'id': 'local-1',
      'uid': 'local-1',
      'firstName': 'Alex',
      'lastName': '',
      'email': '',
      'mayUseGlobalKey': false,
    });

    final container = await start(tester);
    await tester.pumpAndSettle();

    expect(find.byType(StandaloneWelcomePage), findsNothing);
    expect(find.byType(LocalKeyGateScreen), findsOneWidget);

    await unmount(tester, container);
  });

  // #307: whoever went on without a school by mistake finds the way back on
  // the key screen.
  testWidgets('the key screen offers to import the school file', (
    tester,
  ) async {
    final container = await start(tester);
    await tester.enterText(
      find.byKey(const ValueKey('standalone-welcome-first-name')),
      'Alex',
    );
    await tester.tap(find.byKey(const ValueKey('standalone-welcome-start')));
    await tester.pumpAndSettle();
    expect(find.byType(LocalKeyGateScreen), findsOneWidget);

    await tester.tap(
      find.text('At a school? Import the school file your teacher gives you.'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The school file of Example School is saved. Close the app and '
        'start it again to sign in.',
      ),
      findsOneWidget,
    );
    expect(schoolStore.stored?.schoolName, 'Example School');

    await unmount(tester, container);
  });
}
