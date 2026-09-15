// #124: the strip the shell puts up when the launch's own update check did
// not complete. The state that decides *whether* it shows is pinned in
// `test/core/update_controller_test.dart`; this pins what it says, in both
// languages, and that its one button closes it. The real shell mounting it
// over a real failed check is `integration_test/flows/update_check_failed_notice.dart`.

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/widgets/update_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        updateServicesProvider.overrideWithValue(
          UpdateServices(
            localVersion: '2.1.0+18',
            feed: () async => throw UpdateCheckException(
              'request failed: HandshakeException: CERTIFICATE_VERIFY_FAILED',
            ),
            download: (_, _) async => throw StateError('not reached'),
            verify: (_, _) async => true,
            run: (_) async => throw StateError('not reached'),
            log: (_) {},
          ),
        ),
      ],
    );
  });
  tearDown(() => container.dispose());

  /// The notice the way the shell shows it: only while the state asks for
  /// it, so tapping close can be seen to take it away.
  Widget app(Locale locale) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            final failed = ref.watch(
              updateControllerProvider.select((s) => s.checkFailed),
            );
            return failed
                ? const UpdateCheckFailedNotice()
                : const SizedBox.shrink();
          },
        ),
      ),
    ),
  );

  final notice = find.byKey(const ValueKey('update-check-failed'));
  final message = find.byKey(const ValueKey('update-check-failed-message'));
  final close = find.byKey(const ValueKey('update-check-failed-dismiss'));

  testWidgets('says where the reason is, and closes', (tester) async {
    await tester.pumpWidget(app(const Locale('en')));
    expect(notice, findsNothing, reason: 'shown before anything failed');

    await container.read(updateControllerProvider.notifier).start();
    await tester.pump();

    expect(notice, findsOneWidget);
    expect(
      tester.widget<Text>(message).data,
      'Checking for updates did not succeed — see Options → About.',
    );
    expect(find.byType(AlertDialog), findsNothing);
    // The failure's own words are for About, not for a strip of chrome.
    expect(find.textContaining('CERTIFICATE_VERIFY_FAILED'), findsNothing);

    await tester.tap(close);
    await tester.pump();

    expect(notice, findsNothing);
    final state = container.read(updateControllerProvider);
    expect(state.noticeDismissed, isTrue);
    expect(
      state.phase,
      UpdatePhase.failed,
      reason: 'closing changed the state',
    );
  });

  testWidgets('is translated', (tester) async {
    await tester.pumpWidget(app(const Locale('nl')));
    await container.read(updateControllerProvider.notifier).start();
    await tester.pump();

    expect(
      tester.widget<Text>(message).data,
      'Controleren op updates is mislukt — zie Opties → Over.',
    );
    expect(find.byTooltip('Sluiten'), findsOneWidget);
  });
}
