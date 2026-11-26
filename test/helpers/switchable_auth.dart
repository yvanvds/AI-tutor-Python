// A sign-in a test switches on and off (#345): the providers that poll the
// database stop at a sign-out and start again at the next sign-in, and a
// test of that signs a student out and back in without a browser.
//
//     authServiceProvider.overrideWith(SwitchableAuth.new)
//     ...
//     await container.read(authServiceProvider.notifier).signOut();

import 'package:ai_tutor_python/services/auth/auth_service.dart';

/// The student a [SwitchableAuth] signs in.
const AccountIdentity kSwitchableIdentity = AccountIdentity(
  oid: 'oid-switch',
  displayName: 'Test Student',
  email: 'test.student@example.com',
  firstName: 'Test',
  lastName: 'Student',
  isTeacher: false,
);

/// Signed in from the start, unless [signedIn] is `false`; [signIn] and
/// [signOut] flip it.
class SwitchableAuth extends AuthService {
  SwitchableAuth({this.signedIn = true});

  final bool signedIn;

  @override
  AccountIdentity? build() => signedIn ? kSwitchableIdentity : null;

  @override
  Future<void> tryAcquireTokenSilent() async {}

  @override
  Future<void> signIn() async => state = kSwitchableIdentity;

  @override
  Future<void> signOut() async => state = null;
}
