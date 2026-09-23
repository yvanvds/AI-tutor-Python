// #165: `GoalsApp` puts a build below the school's minimum version in front
// of the update screen instead of the shell — and waits for the config's
// answer before deciding, rather than mounting the shell (and with it the
// session) on a `null` that only means "not read yet".
//
// The root widget the way app_locale_switch_test.dart mounts it: signed in,
// the account and config docs in an in-memory Cosmos installed process-wide,
// the release feed off. The shell never builds here, so nothing heavier than
// the account service runs; the other half — a build that meets the minimum
// getting the shell, and a minimum lowered again letting it back in — is
// driven through the real app in integration_test/flows/update_required.dart.

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/features/shell/app_shell.dart';
import 'package:ai_tutor_python/main.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/config/app_locale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

Map<String, dynamic> _config({String? minimum}) => {
  'id': 'global',
  'type': 'config',
  'Model': 'gpt-4o',
  'ApiKey': '',
  if (minimum != null) 'MinimumVersion': minimum,
};

final _screen = find.byKey(const ValueKey('update-required'));
final _message = find.byKey(const ValueKey('update-required-message'));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app() => ProviderScope(
    overrides: [
      authServiceProvider.overrideWith(_SignedInAuth.new),
      systemLocaleProvider.overrideWithValue(const Locale('en', 'US')),
      appVersionProvider.overrideWithValue('2.5.0+22'),
      // Feed off: no network, and no launch check — the screen's own
      // `start()` returns without a request, as on any debug build.
      updateFeedUrlProvider.overrideWithValue(null),
    ],
    child: const GoalsApp(),
  );

  testWidgets('a build below the minimum waits for the answer, then gets the '
      'update screen and never the shell', (tester) async {
    InMemoryCosmosClient({
      'accounts': InMemoryCosmos([_account()]),
      'config': InMemoryCosmos([_config(minimum: '9.0.0')]),
    }).install();
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(app());

    // First frame: nothing has answered yet — the same spinner the account
    // doc gets, not the shell.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(_screen, findsNothing);

    for (var i = 0; i < 5 && _screen.evaluate().isEmpty; i++) {
      await tester.pump();
    }

    expect(_screen, findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Later'), findsNothing);
    final message = tester.widget<Text>(_message).data!;
    expect(message, contains('2.5.0+22'));
    expect(message, contains('9.0.0'));
    expect(find.text('Check for updates'), findsOneWidget);

    // Unmount so the polls stop with the scope.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
