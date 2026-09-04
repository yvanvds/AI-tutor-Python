// Issue #23 — the app renders in English and in Dutch, and the choice is
// wired the way `main.dart` wires it: `GoalsApp` sets `MaterialApp.locale`
// from `appLocaleProvider` (system locale unless the user overrode it).
//
// Two layers:
//   - `GoalsApp` itself, mounted signed-out so it lands on the sign-in page
//     — the real root widget, real locale resolution, real delegates.
//   - the shell chrome (sidebar + top bar) and the Options page, under each
//     locale and across a live switch through `LocaleService`, which is what
//     the language rows on the Options page call.
//
// Not driven through the full app: boot requires an Entra sign-in and a live
// Cosmos endpoint, and there is no integration_test harness in the repo (#28).

import 'package:ai_tutor_python/features/options/options_page.dart';
import 'package:ai_tutor_python/features/shell/shell_state.dart';
import 'package:ai_tutor_python/features/shell/sidebar.dart';
import 'package:ai_tutor_python/features/shell/top_bar.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/main.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:ai_tutor_python/services/config/locale_service.dart';
import 'package:ai_tutor_python/services/debug/debug_session_recorder.dart';
import 'package:ai_tutor_python/services/github/github_issue_service.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_cosmos.dart';

const _uid = 'u1';

const _identity = AccountIdentity(
  oid: _uid,
  displayName: 'Sam Student',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  isTeacher: false,
);

class _SignedInAuth extends AuthService {
  @override
  AccountIdentity? build() => _identity;
}

class _SignedOutAuth extends AuthService {
  @override
  AccountIdentity? build() => null;
}

const _teacher = Profile(
  name: 'Yvan',
  topic: 'Python',
  level: 1,
  xp: 0,
  xpNext: 500,
  streak: 3,
  role: Role.teacher,
);

Map<String, dynamic> _account() => {
  'id': _uid,
  'uid': _uid,
  'email': 'sam@example.com',
  'firstName': 'Sam',
  'lastName': 'Student',
  'targetGoal': 'Python',
  'mayUseGlobalKey': true,
  'calibration': {
    'difficulty': 'medium',
    'recentAnswers': const [],
    'recentQuestionTypes': const [],
  },
};

/// Mirrors `GoalsApp`'s wiring for a page under test: the locale comes from
/// `appLocaleProvider`, so `LocaleService.setLocale` re-renders the tree.
class _LocalizedHost extends ConsumerWidget {
  const _LocalizedHost({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      locale: ref.watch(appLocaleProvider),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  group('GoalsApp (main.dart)', () {
    Widget app(Locale system) => ProviderScope(
      overrides: [
        authServiceProvider.overrideWith(_SignedOutAuth.new),
        systemLocaleProvider.overrideWithValue(system),
      ],
      child: const GoalsApp(),
    );

    testWidgets('starts in Dutch on a Dutch system', (tester) async {
      await setViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(app(const Locale('nl', 'BE')));
      await tester.pump();

      expect(find.text('Aanmelden met schoolaccount'), findsOneWidget);
      expect(find.text('Sign in with school account'), findsNothing);
      expect(
        Localizations.localeOf(tester.element(find.byType(Scaffold))),
        const Locale('nl'),
      );
      await unmount(tester);
    });

    testWidgets('starts in English on any other system', (tester) async {
      await setViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(app(const Locale('fr', 'BE')));
      await tester.pump();

      expect(find.text('Sign in with school account'), findsOneWidget);
      expect(find.text('Aanmelden met schoolaccount'), findsNothing);
      await unmount(tester);
    });

    testWidgets('a stored language override beats the system locale', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'app_locale': 'en'});
      await setViewport(tester, const Size(1200, 800));
      await tester.pumpWidget(app(const Locale('nl', 'NL')));
      await tester.pump(); // LocaleService hydration
      await tester.pump();

      expect(find.text('Sign in with school account'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('shell chrome', () {
    setUp(() {
      // The test font (Ahem) renders every glyph as a full-em square, which
      // overflows the top bar's fixed-width XP pill that real fonts fit
      // comfortably. Scale text down so layout, not localization, is not
      // what fails here; the assertions below match on text content only.
      TestWidgetsFlutterBinding
              .instance
              .platformDispatcher
              .textScaleFactorTestValue =
          0.7;
    });
    tearDown(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher
          .clearTextScaleFactorTestValue();
    });

    Widget shell(Locale system) => ProviderScope(
      overrides: [
        profileProvider.overrideWithValue(_teacher),
        developerToolsProvider.overrideWithValue(false),
        systemLocaleProvider.overrideWithValue(system),
      ],
      child: const _LocalizedHost(
        child: Row(
          children: [
            Sidebar(),
            Expanded(child: Column(children: [TopBar()])),
          ],
        ),
      ),
    );

    testWidgets('renders in English', (tester) async {
      await setViewport(tester, const Size(1400, 900));
      await tester.pumpWidget(shell(const Locale('en', 'US')));
      await tester.pump();

      expect(find.byTooltip('Learning path'), findsOneWidget);
      expect(find.byTooltip('Goals'), findsOneWidget);
      expect(find.byTooltip('Students'), findsOneWidget);
      expect(find.byTooltip('Options'), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsOneWidget);
      expect(find.text('TEACHER'), findsOneWidget);
      expect(find.text('Hi Yvan,'), findsOneWidget);
      expect(find.text("let's get started with Python"), findsOneWidget);
      expect(find.text('Explain'), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('days'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('renders in Dutch', (tester) async {
      await setViewport(tester, const Size(1400, 900));
      await tester.pumpWidget(shell(const Locale('nl', 'BE')));
      await tester.pump();

      expect(find.byTooltip('Leerpad'), findsOneWidget);
      expect(find.byTooltip('Doelen'), findsOneWidget);
      expect(find.byTooltip('Studenten'), findsOneWidget);
      expect(find.byTooltip('Opties'), findsOneWidget);
      expect(find.byTooltip('Afmelden'), findsOneWidget);
      expect(find.text('DOCENT'), findsOneWidget);
      expect(find.text('Hoi Yvan,'), findsOneWidget);
      expect(find.text('aan de slag met Python'), findsOneWidget);
      expect(find.text('Uitleg'), findsOneWidget);
      expect(find.text('Oefenen'), findsOneWidget);
      expect(find.text('dagen'), findsOneWidget);
      // Nothing English leaked.
      expect(find.byTooltip('Learning path'), findsNothing);
      expect(find.text('Hi Yvan,'), findsNothing);
      await unmount(tester);
    });

    testWidgets('switching the language re-renders the chrome in place', (
      tester,
    ) async {
      await setViewport(tester, const Size(1400, 900));
      await tester.pumpWidget(shell(const Locale('en', 'US')));
      await tester.pump();
      expect(find.text('Hi Yvan,'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Sidebar)),
      );
      await container
          .read(localeServiceProvider.notifier)
          .setLocale(const Locale('nl'));
      await tester.pump();

      expect(find.text('Hoi Yvan,'), findsOneWidget);
      expect(find.text('Hi Yvan,'), findsNothing);
      expect(find.byTooltip('Leerpad'), findsOneWidget);

      await container.read(localeServiceProvider.notifier).setLocale(null);
      await tester.pump();
      expect(find.text('Hi Yvan,'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('Options page', () {
    late InMemoryCosmos accounts;

    setUp(() {
      accounts = InMemoryCosmos([_account()]);
    });

    Widget options(Locale system) => ProviderScope(
      overrides: [
        authServiceProvider.overrideWith(_SignedInAuth.new),
        accountServiceProvider.overrideWith(
          () => AccountService(container: accounts.container),
        ),
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: InMemoryCosmos([]).container),
        ),
        githubIssueServiceProvider.overrideWithValue(
          GitHubIssueService(
            client: MockClient((_) async => http.Response('{}', 404)),
          ),
        ),
        debugServiceProvider.overrideWithValue(DebugSessionRecorder()),
        developerToolsProvider.overrideWithValue(false),
        systemLocaleProvider.overrideWithValue(system),
      ],
      child: const _LocalizedHost(child: OptionsPage()),
    );

    Future<void> mount(WidgetTester tester, Locale system) async {
      await setViewport(tester, const Size(1400, 2400));
      await tester.pumpWidget(options(system));
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('renders in English', (tester) async {
      await mount(tester, const Locale('en', 'US'));

      expect(find.text('Options'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Reset all progress'), findsOneWidget);
      expect(find.text('Bug reports'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('renders in Dutch', (tester) async {
      await mount(tester, const Locale('nl', 'BE'));

      expect(find.text('Opties'), findsOneWidget);
      expect(find.text('Taal'), findsOneWidget);
      expect(find.text('Voortgang'), findsOneWidget);
      expect(find.text('Alle voortgang wissen'), findsOneWidget);
      expect(find.text('Bugmeldingen'), findsOneWidget);
      expect(find.text('Over'), findsOneWidget);
      expect(find.text('Systeem'), findsOneWidget);
      expect(find.text('Options'), findsNothing);
      await unmount(tester);
    });

    testWidgets('the language rows switch the whole page and persist the '
        'choice', (tester) async {
      await mount(tester, const Locale('en', 'US'));
      expect(find.text('Options'), findsOneWidget);

      await tester.tap(find.text('Nederlands'));
      await tester.pumpAndSettle();
      expect(find.text('Opties'), findsOneWidget);
      expect(find.text('Options'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getString('app_locale'),
        'nl',
      );

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(find.text('Options'), findsOneWidget);

      // "System" on an English system is English again; the stored override
      // is gone.
      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(find.text('Options'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).containsKey('app_locale'),
        isFalse,
      );
      await unmount(tester);
    });
  });
}
