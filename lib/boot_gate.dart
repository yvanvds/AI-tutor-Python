import 'dart:async';
import 'package:ai_tutor_python/core/firestore_safety.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

class BootGate extends StatefulWidget {
  const BootGate({super.key, required this.child});
  final Widget child;

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  bool _checked = false;

  bool get _shiftDown {
    return HardwareKeyboard.instance.isShiftPressed;
  }

  @override
  void initState() {
    super.initState();
    // Wait one frame so the window is focused, then check keys.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Short delay gives the window time to grab focus on desktop.
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted || _checked) return;
      _checked = true;

      if (_shiftDown) {
        _showSafeModeDialog();
      }
    });
  }

  Future<void> _showSafeModeDialog() async {
    final ctx = context;
    if (!mounted) return;

    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Safe Mode'),
          content: const Text(
            'You started the app with Shift held.\n\n'
            'Use this to recover from permission or cache issues.\n\n'
            'The application will close after you choose an option below.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Continue without reset
              },
              child: const Text('Don\'t Reset'),
            ),
            FilledButton(
              onPressed: () async {
                // Run your hard reset
                await resetAuthAndCacheAndExit();

                if (context.mounted) {
                  Navigator.of(context).pop(); // close dialog
                  // After signOut, your auth StreamBuilder will show SignInPage automatically.
                  // If you want to be explicit:
                  // appNavigatorKey.currentState?.pushAndRemoveUntil(
                  //   MaterialPageRoute(builder: (_) => const SignInPage()),
                  //   (r) => false,
                  // );
                }
              },
              child: const Text('Reset & Exit'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Just render the rest of your app normally.
    return widget.child;
  }
}
