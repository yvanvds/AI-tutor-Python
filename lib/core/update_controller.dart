/// The update check as state plus operations, with every side effect behind
/// a seam (#47).
///
/// Before this, the whole flow — fetch, compare, dialog, download, hash,
/// `Process.start` — lived inline in `AppShell.initState`, which had three
/// consequences worth naming, because they are what this file exists to fix:
///
/// - **Untestable.** Nothing could reach the orchestration without a real
///   network and a real installer, so the only thing any test did with it was
///   switch it off. A BOM shipped (#45) because nothing could catch it.
/// - **Unstoppable.** There was no gate on the build type, so a `flutter run`
///   checkout would download and silently install a release over the
///   developer's own machine the moment the manifest went ahead. See
///   [UpdateServices.autoCheck].
/// - **Invisible.** A failed check left nothing behind for the UI to show.
///   [UpdateState.phase] and [UpdateState.message] now carry the reason, and
///   the About panel renders it beside its **Check for updates** button
///   (#48).
///
/// The layering mirrors AccountManager's (`lib/src/update/`): this file holds
/// decision logic and no IO, `update_bootstrap.dart` holds the IO and is the
/// only place that touches the network, the disk or a process.
library;

import 'dart:io';

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the update check has got to. The shell's offer bar shows from
/// [available] onwards; the About panel renders [failed] with
/// [UpdateState.message] (#48).
enum UpdatePhase {
  /// Nothing has been asked yet.
  idle,

  /// A check is in flight.
  checking,

  /// The check came back and this build is the newest published one.
  upToDate,

  /// A newer release is published and waiting for the student to accept it.
  available,

  /// The student accepted; the installer is coming down.
  downloading,

  /// The installer is downloaded, verified, and being handed to Windows.
  applying,

  /// The check or the apply failed. The reason is on [UpdateState.message].
  failed,
}

/// Looks up the published release. Returns `null` when nothing is published,
/// throws [UpdateCheckException] when the check itself did not complete (#46).
typedef ReleaseFeed = Future<UpdateInfo?> Function();

/// Downloads [release]'s installer, reporting progress as a 0..1 fraction
/// where the server declared a content length.
typedef ReleaseDownloader = Future<File> Function(
  UpdateInfo release,
  void Function(double fraction) onProgress,
);

/// Checks a downloaded installer against the hash published beside it.
/// A `false` here is the one failure that must never reach [InstallerRunner].
typedef ReleaseVerifier = Future<bool> Function(
  File installer,
  String expectedSha256,
);

/// Hands the downloaded installer to Windows and ends this process so the
/// installer can replace the files underneath it. Returns only if the
/// handover failed — a successful one does not come back.
typedef InstallerRunner = Future<void> Function(File installer);

/// Parks a release's notes somewhere that outlives this process, so the build
/// the installer puts in its place can show them (#119). Called once, on the
/// way out, after the download has verified and before [InstallerRunner].
typedef ReleaseNotesStash = Future<void> Function(String version, String notes);

/// Where a diagnostic goes when nothing is shown on screen.
typedef UpdateLog = void Function(String message);

/// The seams the update layer is assembled from: production wiring in
/// `update_bootstrap.dart`, fakes in tests, and nothing in between that
/// reaches a real network, a real temp file or a real process.
class UpdateServices {
  const UpdateServices({
    required this.localVersion,
    required this.feed,
    required this.download,
    required this.verify,
    required this.run,
    this.stashNotes,
    this.autoCheck = true,
    this.log,
  });

  /// The running build's version — `kAppVersion` in production. An
  /// unparseable value means "cannot compare", and the controller declines to
  /// offer anything rather than guessing that everything published is newer.
  final String localVersion;

  /// Where the published release is looked up.
  final ReleaseFeed feed;

  /// How an accepted release is fetched.
  final ReleaseDownloader download;

  /// How a fetched installer is checked against its published hash.
  final ReleaseVerifier verify;

  /// How a verified installer is launched.
  final InstallerRunner run;

  /// Where a release's notes are left for the build that comes back (#119).
  ///
  /// Optional, and a failure here never stops an install: not being told what
  /// changed is a smaller loss than an update that refused to run because a
  /// preference file could not be written.
  final ReleaseNotesStash? stashNotes;

  /// Whether a launch checks by itself.
  ///
  /// `kReleaseMode` in production (see `updateAutoCheckProvider`): a debug
  /// checkout is something being developed against, not an install to update,
  /// and leaving this on means every `flutter run` and every integration-test
  /// boot reaches out — and, worse, installs a release build over the
  /// developer's machine. [check] still runs when asked, which is what
  /// About's **Check for updates** button calls (#48).
  final bool autoCheck;

  /// Where failures are written. Defaults to [debugPrint].
  final UpdateLog? log;
}

/// What the shell and the About panel render from.
@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.release,
    this.message = '',
    this.progress = 0,
    this.dismissed = false,
  });

  final UpdatePhase phase;

  /// The newer release on offer, or `null` when there is none.
  final UpdateInfo? release;

  /// The last thing worth telling a user who asks — including the reason a
  /// check or an apply failed. Never pushed at anybody from here.
  final String message;

  /// Download progress as a 0..1 fraction while [phase] is
  /// [UpdatePhase.downloading]. Stays 0 while the server declared no content
  /// length, which the bar renders as indeterminate rather than as 0% (#48).
  final double progress;

  /// Whether the student has put this session's offer away with **Later**.
  ///
  /// Deliberately not persisted: it silences the bar for as long as the app
  /// is open, and the next launch asks again. "Skip this version" forever is
  /// a setting nobody revisits, and an un-updated install is the failure it
  /// produces.
  final bool dismissed;

  /// Whether the shell should be showing the offer bar.
  ///
  /// Covers the whole accepted run, not just the moment before it: the bar is
  /// where the progress and the outcome are rendered, so it has to stay while
  /// the installer comes down and after an apply that failed. A *check* that
  /// failed clears [release] and so shows nothing — that news waits in About.
  bool get isOffering =>
      !dismissed &&
      release != null &&
      (phase == UpdatePhase.available ||
          phase == UpdatePhase.downloading ||
          phase == UpdatePhase.applying ||
          phase == UpdatePhase.failed);

  /// Whether an operation is in flight, so a button can disable itself.
  bool get busy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.applying;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateInfo? release,
    bool clearRelease = false,
    String? message,
    double? progress,
    bool? dismissed,
  }) => UpdateState(
    phase: phase ?? this.phase,
    release: clearRelease ? null : (release ?? this.release),
    message: message ?? this.message,
    progress: progress ?? this.progress,
    dismissed: dismissed ?? this.dismissed,
  );
}

/// The update state and the operations that move it.
///
/// Nothing here touches the network, the disk or a process: every effect goes
/// through [UpdateServices], so a test drives the whole flow — including the
/// hash mismatch and the failed check — with three closures.
class UpdateController extends Notifier<UpdateState> {
  bool _disposed = false;

  @override
  UpdateState build() {
    ref.onDispose(() => _disposed = true);
    return const UpdateState();
  }

  UpdateServices get _services => ref.read(updateServicesProvider);

  void _log(String text) => (_services.log ?? debugPrint)(text);

  /// Riverpod throws when a notifier's state is written after its container
  /// is gone. The check runs unawaited from the shell's first frame, so a
  /// window closed (or a test torn down) mid-request lands exactly there.
  void _set(UpdateState next) {
    if (_disposed) return;
    state = next;
  }

  /// What the shell fires from its first frame. Checks only on a build that
  /// checks by itself; never throws, never blocks anything on screen.
  Future<void> start() async {
    if (!_services.autoCheck) return;
    await check();
  }

  /// Asks the feed whether a newer release is published.
  ///
  /// Never throws: a failed check is logged, parked on [UpdateState.message]
  /// for the About panel, and leaves the app exactly as it was (#46).
  ///
  /// This never installs anything. Reaching [apply] takes a separate call
  /// that only a user action makes.
  Future<void> check() async {
    if (state.busy) return;
    final services = _services;

    _set(
      state.copyWith(
        phase: UpdatePhase.checking,
        message: '',
        clearRelease: true,
        progress: 0,
        // Asking again is asking to be told: a check the student started
        // themselves must be allowed to put the bar back.
        dismissed: false,
      ),
    );
    try {
      final latest = await services.feed();
      if (latest == null) {
        _set(
          state.copyWith(
            phase: UpdatePhase.upToDate,
            clearRelease: true,
            message: 'No release has been published yet.',
          ),
        );
        return;
      }

      final bool newer;
      try {
        newer = isNewer(latest.version, services.localVersion);
      } on FormatException catch (e) {
        // An unreadable local version is the dangerous one: treat it as
        // "cannot compare" rather than "anything published is newer", which
        // would install a release over an unknown build.
        _log('Update: cannot compare versions: $e');
        _set(
          state.copyWith(
            phase: UpdatePhase.failed,
            clearRelease: true,
            message:
                'This build reports version "${services.localVersion}" and the '
                'published one reports "${latest.version}", which cannot be '
                'compared.',
          ),
        );
        return;
      }

      if (newer) {
        _log(
          'Update: ${latest.version} available (running '
          '${services.localVersion}).',
        );
        _set(
          state.copyWith(
            phase: UpdatePhase.available,
            release: latest,
            message: 'Version ${latest.version} is available.',
          ),
        );
      } else {
        _set(
          state.copyWith(
            phase: UpdatePhase.upToDate,
            clearRelease: true,
            message: 'Version ${services.localVersion} is the newest one.',
          ),
        );
      }
    } on Object catch (e, stack) {
      // The silent path: no dialog, no banner, no stall — just a log and a
      // reason on the state for whoever opens the About panel (#46/#48).
      _log('Update: check failed: $e\n$stack');
      _set(
        state.copyWith(
          phase: UpdatePhase.failed,
          clearRelease: true,
          message: 'The update check did not succeed: $e',
        ),
      );
    }
  }

  /// Downloads the offered installer, verifies it against the hash published
  /// with the release, and hands it to Windows.
  ///
  /// Only ever reached from a user action. Nothing in [start] or [check]
  /// calls this and no timer can: an update that installs itself while a
  /// student is mid-exercise is the failure mode the seam exists to rule out.
  /// A call with nothing on offer is a no-op, so a stray invocation cannot
  /// install anything either.
  Future<void> apply() async {
    final release = state.release;
    if (release == null || state.busy) return;
    final services = _services;

    _set(
      state.copyWith(
        phase: UpdatePhase.downloading,
        progress: 0,
        message: 'Version ${release.version} is downloading…',
      ),
    );
    try {
      final installer = await services.download(
        release,
        (fraction) => _set(state.copyWith(progress: fraction.clamp(0.0, 1.0))),
      );
      if (!await services.verify(installer, release.sha256)) {
        // Never hand an unverified binary to `Process.start`: a mismatch is a
        // corrupted or substituted download, not a slow one.
        _log('Update: installer for ${release.version} failed its sha256.');
        _set(
          state.copyWith(
            phase: UpdatePhase.failed,
            message:
                'The downloaded installer for version ${release.version} did '
                'not match its published checksum, so it was not started.',
          ),
        );
        return;
      }

      _set(
        state.copyWith(
          phase: UpdatePhase.applying,
          progress: 1,
          message:
              'The installer is starting. The app closes itself and comes '
              'back as version ${release.version}.',
        ),
      );

      // The last thing done before the process is handed to the installer:
      // `run` does not come back, so anything the next build needs has to be
      // on disk by now (#119). Guarded on its own — an unwritable preference
      // store must not turn a working update into a failed one.
      final stash = services.stashNotes;
      if (stash != null) {
        try {
          await stash(release.version, release.notes);
        } on Object catch (e) {
          _log('Update: release notes for ${release.version} not stashed: $e');
        }
      }

      await services.run(installer);

      // Reached only when the handover failed to take the process with it.
      _log(
        'Update: installer downloaded but did not start '
        '(${installer.path}).',
      );
      _set(
        state.copyWith(
          phase: UpdatePhase.failed,
          message:
              'The installer was downloaded to ${installer.path} but did not '
              'start. Run it by hand.',
        ),
      );
    } on Object catch (e, stack) {
      _log('Update: applying failed: $e\n$stack');
      _set(
        state.copyWith(
          phase: UpdatePhase.failed,
          message: 'Updating did not succeed: $e',
        ),
      );
    }
  }

  /// Puts the offer bar away for this session (#48).
  ///
  /// The release stays on the state, so About still shows it and can still
  /// apply it: dismissing an offer is "not now", not "not this version". A
  /// dismissal during a download would leave an install running with nothing
  /// on screen, so it is refused while [UpdateState.busy].
  void dismiss() {
    if (state.busy) return;
    _set(state.copyWith(dismissed: true));
  }
}

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
