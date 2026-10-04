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
// #221 adds two kinds of entry in the same shape, each under an id of its
// own with `awardedBy` set; the app's own rules leave them out:
//
//   "podium:<subgoalId>":  {"tier": 3, "earnedAt": "…", "awardedBy": "podium",
//                           "place": 1, "className": "6EWI"}
//   "teacher:helpingHand": {"tier": 1, "earnedAt": "…", "awardedBy": "teacher",
//                           "count": 2, "seen": 1}
//
// A medal of the class podium is written by the student's own app, from the
// podium docs (`class_podium.dart`): gold is tier 3, so a better place is a
// higher tier and the merge keeps the best. A teacher's badge is written by
// the teacher's app (`addTeacherAward`): `count` goes up by one per award,
// `earnedAt` is the last one, and the student's app sets `seen` to the count
// it announced (`withTeacherBadgesSeen`), so the notice comes once, on
// whichever laptop the student opens first.
//
// Fields this build does not know are kept as they are, on every entry and
// on the map.

import 'package:flutter/foundation.dart';

/// `awardedBy` of a badge the teacher gave (#221).
const String kAwardedByTeacher = 'teacher';

/// `awardedBy` of a medal of the class podium (#221).
const String kAwardedByPodium = 'podium';

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

  /// How many times a teacher's badge was given (#221): `count`, at least
  /// 1 for an entry that is there. 1 for every other badge.
  int get count => _wholeAtLeast(extra['count'], 1) ?? 1;

  /// How many of [count] the student's app has announced (#221): `seen`,
  /// 0 when absent.
  int get seen => _wholeAtLeast(extra['seen'], 0) ?? 0;

  static int? _wholeAtLeast(Object? raw, int min) {
    if (raw is! num || raw.isNaN || raw.isInfinite) return null;
    final n = raw.toInt();
    return n < min ? min : n;
  }

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
    this.hadMap = false,
  });

  /// The `badges` map to store.
  final Map<String, dynamic> badges;

  /// Per badge whose tier went up, the new tier — what to announce.
  final Map<String, int> raised;

  /// The first look at this student's badges, with everything the history
  /// already earned (#220: one summary instead of a notice per badge): the
  /// doc had no `badges` field — or only badges given by the teacher or the
  /// podium (#221), which the teacher's app can store before the student
  /// ever opens the release that counts the rest.
  final bool first;

  /// The doc had a `badges` map already.
  final bool hadMap;

  /// Whether the stored map has to be written: something went up, or there
  /// was no map yet.
  bool get changed => raised.isNotEmpty || (first && !hadMap);
}

/// Merges [reached] (badge id → tier the rules reach now) into [stored], the
/// `badges` field as read from the account doc. A tier only ever goes up:
/// a badge stored higher than reached — a threshold changed, the history
/// was reset — keeps what it has, and so does every entry the rules do not
/// name (another build's, #221's). An entry that goes up gets [now] as its
/// `earnedAt`; its other fields stay.
///
/// [granted] are whole entries from elsewhere — the class podium's medals
/// (#221) — stored as they are, `earnedAt` and all, when they raise the
/// tier stored under their id; fields of the stored entry they do not set
/// stay.
BadgeAward mergeBadgeTiers(
  Object? stored,
  Map<String, int> reached, {
  required DateTime now,
  Map<String, EarnedBadge> granted = const {},
}) {
  final hadMap = stored is Map;
  final out = <String, dynamic>{
    if (stored is Map)
      for (final entry in stored.entries) '${entry.key}': entry.value,
  };
  final first = !hadMap || _onlyAwarded(out);
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
  for (final entry in granted.entries) {
    final medal = entry.value;
    final existing = EarnedBadge.fromJson(out[entry.key]);
    if (existing != null && existing.tier >= medal.tier) continue;
    out[entry.key] = EarnedBadge(
      tier: medal.tier,
      earnedAt: medal.earnedAt ?? now.toUtc(),
      awardedBy: medal.awardedBy ?? existing?.awardedBy,
      extra: {...?existing?.extra, ...medal.extra},
    ).toJson();
    raised[entry.key] = medal.tier;
  }
  return BadgeAward(badges: out, raised: raised, first: first, hadMap: hadMap);
}

/// A stored map with badges in it, every one of them given by the teacher
/// or the podium: the rules have not looked yet. An empty map is the rules'
/// first look that found nothing.
bool _onlyAwarded(Map<String, dynamic> stored) {
  var any = false;
  for (final value in stored.values) {
    final badge = EarnedBadge.fromJson(value);
    if (badge == null) continue;
    if (badge.awardedBy == null) return false;
    any = true;
  }
  return any;
}

/// What giving teacher badge [id] once more does to [stored], the `badges`
/// field as read: the map to store and the badge's new count. The entry's
/// `count` goes up by one, `earnedAt` becomes [now], `awardedBy` is
/// `teacher`; `seen` and every other field and entry stay.
({Map<String, dynamic> badges, int count}) addTeacherAward(
  Object? stored,
  String id, {
  required DateTime now,
}) {
  final out = <String, dynamic>{
    if (stored is Map)
      for (final entry in stored.entries) '${entry.key}': entry.value,
  };
  final existing = EarnedBadge.fromJson(out[id]);
  final count = existing == null ? 1 : existing.count + 1;
  out[id] = EarnedBadge(
    tier: 1,
    earnedAt: now.toUtc(),
    awardedBy: kAwardedByTeacher,
    extra: {...?existing?.extra, 'count': count},
  ).toJson();
  return (badges: out, count: count);
}

/// [stored] with `seen` raised to [seen] (badge id → count announced) on
/// each of those entries; `null` when nothing goes up — `seen` never goes
/// down, and never past the entry's own count.
Map<String, dynamic>? withTeacherBadgesSeen(
  Object? stored,
  Map<String, int> seen,
) {
  if (stored is! Map) return null;
  final out = <String, dynamic>{
    for (final entry in stored.entries) '${entry.key}': entry.value,
  };
  var changed = false;
  for (final entry in seen.entries) {
    final raw = out[entry.key];
    final badge = EarnedBadge.fromJson(raw);
    if (badge == null || raw is! Map) continue;
    final target = entry.value < badge.count ? entry.value : badge.count;
    if (target <= badge.seen) continue;
    out[entry.key] = {
      for (final e in raw.entries) '${e.key}': e.value,
      'seen': target,
    };
    changed = true;
  }
  return changed ? out : null;
}
