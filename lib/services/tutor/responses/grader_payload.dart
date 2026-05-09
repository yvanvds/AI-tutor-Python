// Shared parsing of the grader's `loSignals` + `followUp` fields per
// `docs/LLM_CONTRACT.md`. The conductor consumes typed signals; the
// individual feedback response models reuse this helper so the contract
// stays in one place.

import 'package:ai_tutor_python/services/tutor/belief_math.dart';

class LoSignal {
  final String subgoalId;
  final String loId;
  final LoSignalKind kind;
  final LoSignalStrength strength;
  const LoSignal({
    required this.subgoalId,
    required this.loId,
    required this.kind,
    required this.strength,
  });

  Map<String, dynamic> toJson() => {
        'subgoalId': subgoalId,
        'loId': loId,
        'signal': kind.name,
        'strength': strength.name,
      };
}

class FollowUp {
  /// Text the conductor would show the student verbatim. Out of scope for
  /// the current step — recorded on the turn record but not acted on.
  final String question;
  final String? rationale;
  const FollowUp({required this.question, this.rationale});

  Map<String, dynamic> toJson() => {
        'question': question,
        if (rationale != null) 'rationale': rationale,
      };

  static FollowUp? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final q = raw['question'];
    if (q is! String || q.isEmpty) return null;
    final r = raw['rationale'];
    return FollowUp(
      question: q,
      rationale: r is String && r.isNotEmpty ? r : null,
    );
  }
}

/// Parses an `loSignals` array into typed values. Drops malformed entries
/// silently — they're logged at the conductor by the validation step.
List<LoSignal> parseLoSignals(Object? raw) {
  if (raw is! List) return const [];
  final out = <LoSignal>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final m = entry.cast<String, dynamic>();
    final subgoalId = m['subgoalId'];
    final loId = m['loId'];
    if (subgoalId is! String || loId is! String) continue;
    final signal = m['signal'];
    final strength = m['strength'];
    final kind = _parseKind(signal);
    final str = _parseStrength(strength);
    if (kind == null || str == null) continue;
    out.add(LoSignal(
      subgoalId: subgoalId,
      loId: loId,
      kind: kind,
      strength: str,
    ));
  }
  return out;
}

LoSignalKind? _parseKind(Object? raw) {
  if (raw is! String) return null;
  for (final k in LoSignalKind.values) {
    if (k.name == raw) return k;
  }
  return null;
}

LoSignalStrength? _parseStrength(Object? raw) {
  if (raw is! String) return null;
  for (final s in LoSignalStrength.values) {
    if (s.name == raw) return s;
  }
  return null;
}
