import 'package:ai_tutor_python/data/account/account_repository.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// A sign-in page that toggles into a register mode on first Register click.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> with TickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  final _signInFocus = FocusNode(debugLabel: 'signInBtn');
  final _registerFocus = FocusNode(debugLabel: 'registerBtn');

  bool _busy = false;
  String? _error;

  /// Controls whether we’re in “register” UI mode (shows name fields, emphasizes Register)
  bool _registerMode = false;

  Future<void> _signIn() async {
    if (_registerMode) {
      // Flip back to sign-in mode instead of submitting.
      setState(() {
        _registerMode = false;
        _error = null;
      });
      // Move focus to the Sign in button.
      FocusScope.of(context).requestFocus(_signInFocus);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Login failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    if (!_registerMode) {
      // First click just turns on register mode and focuses the button.
      setState(() {
        _registerMode = true;
        _error = null;
      });
      FocusScope.of(context).requestFocus(_registerFocus);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    // Require names on registration
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() {
        _busy = false;
        _error = 'Please enter your first name and last name to register.';
      });
      return;
    }

    try {
      final auth = FirebaseAuth.instance;
      final cred = await auth.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      await cred.user?.updateDisplayName('$first $last');

      final repo = AccountRepository(FirebaseFirestore.instance, auth);
      await repo.upsertAccount(
        uid: cred.user!.uid,
        firstName: first,
        lastName: last,
        email: _email.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? 'Register failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _signInFocus.dispose();
    _registerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Button visual states
    final activeButtonPadding = const EdgeInsets.symmetric(vertical: 16);
    final inactiveButtonPadding = const EdgeInsets.symmetric(vertical: 12);

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                ),
                // Animated appearance of first/last name when in register mode.
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    children: [
                      const SizedBox(height: 12),
                      TextField(
                        controller: _firstName,
                        decoration: const InputDecoration(
                          labelText: 'First name',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _lastName,
                        decoration: const InputDecoration(
                          labelText: 'Last name',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                    ],
                  ),
                  crossFadeState: _registerMode
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 220),
                  sizeCurve: Curves.easeInOut,
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                // Buttons with animated emphasis swap
                Row(
                  children: [
                    // Sign in button (active when !_registerMode)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        padding: _registerMode
                            ? inactiveButtonPadding
                            : activeButtonPadding,
                        child: _registerMode
                            ? OutlinedButton(
                                focusNode: _signInFocus,
                                onPressed: _busy ? null : _signIn,
                                child: const Text('Sign in'),
                              )
                            : FilledButton(
                                focusNode: _signInFocus,
                                onPressed: _busy ? null : _signIn,
                                child: _busy
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Sign in'),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Register button (active when _registerMode)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeInOut,
                        padding: _registerMode
                            ? activeButtonPadding
                            : inactiveButtonPadding,
                        child: _registerMode
                            ? FilledButton.tonal(
                                // tonal variant for visual contrast; still "active"
                                focusNode: _registerFocus,
                                onPressed: _busy ? null : _register,
                                child: _busy
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Register'),
                              )
                            : TextButton(
                                focusNode: _registerFocus,
                                onPressed: _busy ? null : _register,
                                child: const Text('Register'),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
