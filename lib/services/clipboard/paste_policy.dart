import 'package:ai_tutor_python/core/blocked_pastes.dart';
import 'package:ai_tutor_python/services/config/global_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The blocked pastes of the oefening in progress (#334): noted by
/// `PasteGuard`, taken onto the turn record by the tutor.
final blockedPasteLedgerProvider = Provider<BlockedPasteLedger>(
  (ref) => BlockedPasteLedger(),
);

/// Whether a paste from outside the app is blocked (#334): on unless the
/// school's `config/global` says `BlockExternalPaste: false`. On too while
/// the config has not come in, and where the app has none (a test).
bool externalPasteBlocked(GlobalConfig? config) =>
    config?.blockExternalPaste ?? true;
