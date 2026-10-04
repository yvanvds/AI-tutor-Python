// The badges a student has earned (#220), as they sit on the account doc:
//
//   "badges": {
//     "effort":     {"tier": 2, "earnedAt": "2026-10-04T09:12:00.000Z"},
//     "helloWorld": {"tier": 1, "earnedAt": "2026-10-04T09:12:00.000Z"},
//     "expert:r1":  {"tier": 1, "earnedAt": "2026-10-05T10:40:00.000Z"}
//   }
//
// One entry per badge: the highest tier reached and when it was reached.
// What is earned is never taken away — not by a progress reset, not by a
// threshold that changes later: a merge only ever raises a tier.
//
// Room for #221 without a new shape: a badge the teacher hands out, or a
// medal of the class podium, is one more entry under an id of its own with
// `awardedBy` set (`teacher`, `podium`); the app's own rules leave it out.
// Fields this build does not know are kept as they are, on every entry and
// on the map.

import 'package:flutter/foundation.dart';

/// One badge on the account doc.
@immutable
class EarnedBadge {
  const EarnedBadge({
    required this.tier,
    this.earnedAt,
    this.awardedBy,
    this.extra = const {},
  });

  /// The highest tier reached: 1 for the first. A badge without tiers has
  /// only 1.
  final int tier;

  /// When [tier] was reached — the moment the app noticed, also for what
  /// the first start after #220 found in the history.
  final DateTime? earnedAt;

  /// Who gave it: `null` for the app's own rules. #221 sets `teacher` for a
  /// badge the teacher hands out and `podium` for the class podium.
  final String? awardedBy;

  /// Fields on the stored entry this build does not know, written back as
  /// they were.
  final Map<String, dynamic> extra;

  /// An entry as stored, or `null` when it is not one (no whole tier of at
  /// least 1).
  static EarnedBadge? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final tier = raw['tier'];
    if (tier is! num || tier.isNaN || tier.isInfinite) return null;
    final whole = tier.toInt();
    if (whole < 1) return null;
    final at = raw['earnedAt'];
    final by = raw['awardedBy'];
    return EarnedBadge(
      tier: whole,
      earnedAt: at is String ? DateTime.tryParse(at) : null,
      awardedBy: by is String && by.isNotEmpty ? by : null,
      extra: {
        for (final entry in raw.entries)
          if (!_known.contains(entry.key)) '${entry.key}': entry.value,
      },
    );
  }

  static const Set<String> _known = {'tier', 'earnedAt', 'awardedBy'};

  Map<String, dynamic> toJson() => {
    ...extra,
    'tier': tier,
    if (earnedAt != null) 'earnedAt': earnedAt!.toUtc().toIso8601String(),
    if (awardedBy != null) 'awardedBy': awardedBy,
  };

  @override
  bool operator ==(Object other) =>
      other is EarnedBadge &&
      other.tier == tier &&
      other.earnedAt == earnedAt &&
      other.awardedBy == awardedBy &&
      mapEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(tier, earnedAt, awardedBy);
}

/// The `badges` map of an account doc.
@immutable
class EarnedBadges {
  const EarnedBadges(this.byId);

  static const EarnedBadges none = EarnedBadges({});

  /// Per badge id, what is stored. Entries that are not a badge are left
  /// out here (and kept on the doc by [mergeBadgeTiers]).
  final Map<String, EarnedBadge> byId;

  /// The `badges` field of an account doc; `null` when the doc has none —
  /// the app never looked at this student's badges yet, so the first look
  /// sums up instead of announcing each one.
  static EarnedBadges? fromDoc(Map<String, dynamic> doc) {
    final raw = doc['badges'];
    if (raw is! Map) return null;
    return EarnedBadges({
      for (final entry in raw.entries)
        if (EarnedBadge.fromJson(entry.value) case final badge?)
          '${entry.key}': badge,
    });
  }

  /// The tier stored for [id]; 0 when it is not earned.
  int tierOf(String id) => byId[id]?.tier ?? 0;

  bool get isEmpty => byId.isEmpty;

  /// By value, so the account doc's 5 s poll only passes on a real change.
  @override
  bool operator ==(Object other) =>
      other is EarnedBadges && mapEquals(other.byId, byId);

  @override
  int get hashCode => Object.hashAllUnordered(
    byId.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

/// What merging the tiers the rules reached into a stored `badges` map
/// gives: the map to store, the badges that went up, and whether the doc
/// had no map yet.
@immutable
class BadgeAward {
  const BadgeAward({
    required this.badges,
    required this.raised,
    required this.first,
  });

  /// The `badges` map to store.
  final Map<String, dynamic> badges;

  /// Per badge whose tier went up, the new tier — what to announce.
  final Map<String, int> raised;

  /// The doc had no `badges` field: the first look at this student's
  /// badges, with everything the history already earned (#220: one summary
  /// instead of a notice per badge).
  final bool first;

  /// Whether the stored map has to be written: something went up, or there
  /// was no map yet.
  bool get changed => first || raised.isNotEmpty;
}

/// Merges [reached] (badge id → tier the rules reach now) into [stored], the
/// `badges` field as read from the account doc. A tier only ever goes up:
/// a badge stored higher than reached — a threshold changed, the history
/// was reset — keeps what it has, and so does every entry the rules do not
/// name (another build's, #221's). An entry that goes up gets [now] as its
/// `earnedAt`; its other fields stay.
BadgeAward mergeBadgeTiers(
  Object? stored,
  Map<String, int> reached, {
  required DateTime now,
}) {
  final first = stored is! Map;
  final out = <String, dynamic>{
    if (stored is Map)
      for (final entry in stored.entries) '${entry.key}': entry.value,
  };
  final raised = <String, int>{};
  for (final entry in reached.entries) {
    if (entry.value < 1) continue;
    final existing = EarnedBadge.fromJson(out[entry.key]);
    if (existing != null && existing.tier >= entry.value) continue;
    out[entry.key] = EarnedBadge(
      tier: entry.value,
      earnedAt: now.toUtc(),
      awardedBy: existing?.awardedBy,
      extra: existing?.extra ?? const {},
    ).toJson();
    raised[entry.key] = entry.value;
  }
  return BadgeAward(badges: out, raised: raised, first: first);
}
