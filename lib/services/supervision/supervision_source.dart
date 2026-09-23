// The seam through which the tutor learns whether a student is working
// under classroom supervision (#100).
//
// The signal comes from Anchor (plinklabs/Anchor): a teacher starts a focus
// session per class, each enrolled laptop enforces an allowlist and raises
// alerts on escape attempts. The tutor asks one question per graded turn —
// "was *this* student in an active session with a clean alert record at
// *this* moment?" — and never keeps a toggle of its own, so nobody can
// forget to switch supervision off before the evening's homework.
//
// Anchor is not wired up yet. [NoSupervisionSource] is the production
// binding until it is: every turn is `home`, which makes the supervised
// weight factor inert without any migration, and it says so through
// [SupervisionSource.isWired], so nothing downstream reads "all home" as a
// finding about a student (#160). The Anchor-backed source lands as its own
// change and only has to replace [supervisionSourceProvider].

import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class SupervisionSource {
  /// Whether a real registry stands behind this source (#160).
  ///
  /// While it is `false` every turn is `home` by construction, so a
  /// supervised/home split is not a measurement and nothing may present it
  /// as one: the grade justification prompt leaves the split out and does
  /// not ask the model to name it. The Anchor-backed source answers `true`,
  /// and the split is back without anyone having to remember it.
  bool get isWired;

  /// Provenance of evidence produced by [uid] at [at].
  ///
  /// Implementations answer per student, not per class hour: a session with
  /// an alert on record for [uid] degrades only [uid]'s answer. A failure to
  /// reach the session registry must resolve to
  /// [EvidenceProvenance.home] — the fail-safe direction is "no extra
  /// weight", never "assume supervised".
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  });
}

/// No supervision registry: every turn is home work.
class NoSupervisionSource implements SupervisionSource {
  const NoSupervisionSource();

  @override
  bool get isWired => false;

  @override
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  }) async => EvidenceProvenance.home;
}

/// The registry the tutor consults when integrating a graded answer.
/// Override it to plug in Anchor (or a fake in tests).
final supervisionSourceProvider = Provider<SupervisionSource>(
  (_) => const NoSupervisionSource(),
);
