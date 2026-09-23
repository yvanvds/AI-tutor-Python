// #165: the screen a build below the school's minimum version gets instead
// of the app. Whether it shows is decided in `GoalsApp`
// (test/features/shell/update_required_gate_test.dart); this pins what it
// says, that it runs the launch check the shell would have run, that its one
// button is Update — or Check for updates when there is nothing to update to
// — and that there is no Later. The real root widget mounting it over a real
// release server is integration_test/flows/update_required.dart.

import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/core/update_required.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/widgets/update_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateInfo _release(String version) => UpdateInfo(
  version,
  Uri.parse('https://example.com/python_teacher_install.exe'),
  'abc123',
);

/// Records what the screen asked of the outside world.
class _Seams {
  _Seams({this.latest, this.autoCheck = true});

  final UpdateInfo? latest;
  final bool autoCheck;
  int feedCalls = 0;
  int downloadCalls = 0;
  final List<File> ran = <File>[];

  UpdateServices get services => UpdateServices(
    localVersion: '2.4.0+21',
    autoCheck: autoCheck,
    feed: () async {
      feedCalls++;
      return latest;
    },
    download: (release, onProgress) async {
      downloadCalls++;
      return File('does-not-need-to-exist.exe');
    },
    // A hash that never matches: the install is never reached from a test.
    verify: (file, expected) async => false,
    run: (file) async => ran.add(file),
    log: (_) {},
  );
}

const _requirement = UpdateRequirement(
  localVersion: '2.4.0+21',
  minimumVersion: '2.5.0',
);

final _title = find.byKey(const ValueKey('update-required-title'));
final _message = find.byKey(const ValueKey('update-required-message'));
final _status = find.byKey(const ValueKey('update-required-status'));
final _apply = find.byKey(const ValueKey('update-required-apply'));
final _check = find.byKey(const ValueKey('update-required-check'));

void main() {
  late ProviderContainer container;

  ProviderContainer containerFor(_Seams seams) {
    container = ProviderContainer(
      overrides: [updateServicesProvider.overrideWithValue(seams.services)],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget app(Locale locale) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const UpdateRequiredScreen(requirement: _requirement),
    ),
  );

  String text(WidgetTester tester, Finder finder) =>
      tester.widget<Text>(finder).data!;

  testWidgets('names both versions, runs the launch check itself, offers the '
      'release, and has no Later', (tester) async {
    final seams = _Seams(latest: _release('99.0.0+1'));
    containerFor(seams);

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pump(); // the post-frame start()
    await tester.pump(); // its answer

    expect(seams.feedCalls, 1, reason: 'the shell is not there to check');
    expect(text(tester, _title), 'Update required');
    expect(
      text(tester, _message),
      'This version of the app (2.4.0+21) is older than the version the '
      'school requires (2.5.0). Update to continue.',
    );
    expect(text(tester, _status), 'Version 99.0.0+1 is available.');
    expect(find.text('Update to 99.0.0+1'), findsOneWidget);
    expect(_apply, findsOneWidget);
    expect(_check, findsNothing);
    // The whole point: nothing here puts the screen away.
    expect(find.text('Later'), findsNothing);
    expect(find.byKey(const ValueKey('update-offer-later')), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('nothing is downloaded without a press; Update downloads, and '
      'a failed checksum leaves the button for another try', (tester) async {
    final seams = _Seams(latest: _release('99.0.0+1'));
    containerFor(seams);

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pump();
    await tester.pump();
    expect(seams.downloadCalls, 0);

    await tester.tap(_apply);
    await tester.pump();
    await tester.pump();

    expect(seams.downloadCalls, 1);
    expect(seams.ran, isEmpty, reason: 'an unverified installer was started');
    expect(text(tester, _status), contains('checksum'));
    expect(_apply, findsOneWidget);
    expect(tester.widget<FilledButton>(_apply).onPressed, isNotNull);
    expect(find.text('Later'), findsNothing);
  });

  testWidgets('with nothing published it offers a check instead, which runs '
      'on the button', (tester) async {
    final seams = _Seams(latest: null);
    containerFor(seams);

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pump();
    await tester.pump();

    expect(seams.feedCalls, 1);
    expect(_apply, findsNothing);
    expect(_check, findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);

    await tester.tap(_check);
    await tester.pump();
    await tester.pump();
    expect(seams.feedCalls, 2);
    expect(_check, findsOneWidget);
  });

  testWidgets('a build that does not check by itself still gets the button', (
    tester,
  ) async {
    final seams = _Seams(latest: _release('99.0.0+1'), autoCheck: false);
    containerFor(seams);

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pump();
    await tester.pump();

    expect(seams.feedCalls, 0, reason: 'a debug build never checks by itself');
    expect(text(tester, _status), 'No update check has run yet.');
    expect(_check, findsOneWidget);

    await tester.tap(_check);
    await tester.pump();
    await tester.pump();
    expect(seams.feedCalls, 1);
    expect(_apply, findsOneWidget);
    expect(find.text('Update to 99.0.0+1'), findsOneWidget);
  });

  testWidgets('is translated', (tester) async {
    final seams = _Seams(latest: _release('99.0.0+1'));
    containerFor(seams);

    await tester.pumpWidget(app(const Locale('nl')));
    await tester.pump();
    await tester.pump();

    expect(text(tester, _title), 'Update vereist');
    expect(
      text(tester, _message),
      'Deze versie van de app (2.4.0+21) is ouder dan de versie die de school '
      'vereist (2.5.0). Werk bij om verder te gaan.',
    );
    expect(find.text('Bijwerken naar 99.0.0+1'), findsOneWidget);
    expect(find.text('Later'), findsNothing);
  });
}
