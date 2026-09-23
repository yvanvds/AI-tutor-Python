/// The school's minimum client version, and whether this build meets it
/// (#165).
///
/// The in-app update is offered, not imposed (#48), and a student who takes
/// **Later** on every launch keeps running whatever build they have. That
/// build's `toMap`s do not know the fields later builds added, and Cosmos
/// treats an upsert as a whole-document replacement — so every write from
/// such a client silently erases those fields again. That is how
/// `highestPositiveDifficulty` (#103) vanished from three of one student's
/// belief docs within two minutes of being restored by hand, written by her
/// own running session from a laptop still on a build from before the field
/// existed; and how "which docs carry the ratchet" turned out to split by
/// student, not by date. The updater cannot prevent it — declining an update
/// is legitimate — so the *server* says which builds may still write:
/// `config/global` carries a `MinimumVersion`, and a build below it gets
/// `UpdateRequiredScreen` instead of the app, with nothing to dismiss.
///
/// The gate sits in `GoalsApp`, in front of `AppShell`, because the shell is
/// what starts the session: the chat widget's mount calls
/// `TutorService.initializeSession`, and every belief, progress, snapshot
/// and turn write follows from there. Nothing above the shell writes a
/// student document, so a build that never mounts it never writes one.
///
/// [UpdateRequirementController] answers in three states, and the first
/// matters as much as the other two: *unknown* until the config's first
/// answer — a launch waits for it the way it already waits for the account
/// doc, rather than mounting the shell on a `null` that only means "not
/// read yet" — then *required* or *not*, following every later poll of the
/// config service, so a minimum raised during a lesson takes effect within
/// one poll interval on every app that is open.
library;

import 'package:ai_tutor_python/core/update_bootstrap.dart';
import 'package:ai_tutor_python/core/update_controller.dart';
import 'package:ai_tutor_python/core/update_info.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:ai_tutor_python/services/config/global_config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// This build is older than the school's minimum: what is running and what
/// is required, for the screen that has to say so.
@immutable
class UpdateRequirement {
  const UpdateRequirement({
    required this.localVersion,
    required this.minimumVersion,
  });

  /// The running build's version (`kAppVersion` in production).
  final String localVersion;

  /// `MinimumVersion` on `config/global`, as written there.
  final String minimumVersion;

  @override
  bool operator ==(Object other) =>
      other is UpdateRequirement &&
      other.localVersion == localVersion &&
      other.minimumVersion == minimumVersion;

  @override
  int get hashCode => Object.hash(localVersion, minimumVersion);

  @override
  String toString() =>
      'UpdateRequirement(running $localVersion, minimum $minimumVersion)';
}

/// Whether [localVersion] is below [minimumVersion]: the requirement when it
/// is, `null` when it is not — or when nothing can be said.
///
/// Fails open on purpose. No minimum (or a blank one) means no requirement,
/// and a minimum that does not parse means the same: a typo in the Cosmos
/// portal must not lock a whole school out of the app, so it is logged and
/// ignored, and the teacher finds it in the log rather than the students on
/// their screens. An unparseable *local* version gets the stance the update
/// check takes (`UpdateController`): it cannot be compared, so nothing is
/// concluded from it.
///
/// Equal is enough. `2.5.0` as the minimum admits `2.5.0+22`, the way the
/// update check counts a build number only to order two builds of the same
/// version; `2.5.0+23` as the minimum does not.
UpdateRequirement? evaluateUpdateRequirement({
  required String localVersion,
  required String? minimumVersion,
  UpdateLog? log,
}) {
  final String minimum = minimumVersion?.trim() ?? '';
  if (minimum.isEmpty) return null;
  try {
    if (!isNewer(minimum, localVersion)) return null;
  } on FormatException catch (e) {
    (log ?? debugPrint)(
      'Update: the minimum version "$minimum" and this build\'s '
      '"$localVersion" cannot be compared, so the minimum is not enforced: '
      '$e',
    );
    return null;
  }
  return UpdateRequirement(localVersion: localVersion, minimumVersion: minimum);
}

/// Where this build stands against `config/global`'s `MinimumVersion`.
///
/// `AsyncLoading` until the config has answered once — with a doc or
/// without — then `AsyncData(null)` (no requirement) or `AsyncData(req)`,
/// re-evaluated on every value the config service publishes afterwards.
///
/// The first answer is its own read (`GlobalConfigService.getConfig`) rather
/// than the service's polled state, because that state is `null` both before
/// the first poll and for a school that has no config doc at all, and the
/// gate has to tell the two apart: the first is "wait", the second is "go".
/// A read that fails is logged and treated as "go" — a Cosmos blip is not an
/// old client, and the poll listener corrects the answer within one
/// interval if there was a minimum after all.
class UpdateRequirementController extends AsyncNotifier<UpdateRequirement?> {
  @override
  Future<UpdateRequirement?> build() async {
    final String local = ref.watch(appVersionProvider);

    // Every later poll: a minimum the teacher raises while the app is open
    // gates it on the next tick, and one lowered again lets it back in.
    ref.listen<GlobalConfig?>(globalConfigServiceProvider, (_, config) {
      state = AsyncData(
        evaluateUpdateRequirement(
          localVersion: local,
          minimumVersion: config?.minimumVersion,
        ),
      );
    });

    GlobalConfig? config;
    try {
      config = await ref.read(globalConfigServiceProvider.notifier).getConfig();
    } on Object catch (e) {
      debugPrint(
        'Update: could not read the minimum version, so it is not enforced '
        'until the next poll: $e',
      );
    }
    return evaluateUpdateRequirement(
      localVersion: local,
      minimumVersion: config?.minimumVersion,
    );
  }
}

/// See [UpdateRequirementController]. `GoalsApp` watches it in front of the
/// shell; nothing else needs to.
final updateRequirementProvider =
    AsyncNotifierProvider<UpdateRequirementController, UpdateRequirement?>(
      UpdateRequirementController.new,
    );
