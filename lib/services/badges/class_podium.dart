// The class podium (#221): gold, silver and bronze for the first three
// students of a class to finish a subgoal — the first time, on the graded
// turn that moved them past it (`subgoalAdvanced`). Per subgoal, not per
// hoofddoel, so there are many chances and not always the same few win.
//
// The only badge that looks across students, so it needs a shared place:
// per class and subgoal three docs with a fixed id in the `podium` partition
// of the `config` container, `podium_{class}_{subgoal}_1`, `_2` and `_3`
// (`CosmosDocId.podium`). A student who finishes tries `create` on place 1;
// a 409 (taken) moves on to place 2, then 3. A `create` never overwrites, so
// two students can never both get gold — the question bank's pattern (#185).
//
// Only the winner sees a medal: a doc names the student by uid and nothing
// else, and nothing in the app lists the podium — no ranking, no other
// names. Three places also in a class of six. A student without a class
// does not take part. Finishing a subgoal again after working through it
// once more does not count again: only the first advance in the student's
// history claims (`isFirstAdvance`), and a place once held is found again
// rather than a second one taken.
//
// What came before the release is filled in once by
// `tooling/badges/podium_backfill.py`, in the same docs.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The places on a podium, also in a small class.
const int kPodiumPlaces = 3;

/// The tier a medal is stored at: gold (place 1) is 3, silver 2, bronze 1 —
/// the tier colours of `badge_style.dart`, and a better place is a higher
/// tier, so a merge that only ever raises keeps the best.
int podiumTierOf(int place) => kPodiumPlaces + 1 - place;

/// The place a medal stored at [tier] stands for.
int podiumPlaceOf(int tier) => kPodiumPlaces + 1 - tier;

/// The subgoal [record] moved the student past: the one they were on, which
/// a warm-up or a recheck names apart (as `badge_facts.dart` reads it).
String podiumSubgoalOf(PersistedTurnRecord record) =>
    record.activeSubgoalId ?? record.subgoalId;

/// Whether [record] is the student's first advance past its subgoal in
/// [history] — which may or may not hold [record] itself. A later advance
/// of the same subgoal, after the student worked through it again, is not.
bool isFirstAdvance(
  Iterable<PersistedTurnRecord> history,
  PersistedTurnRecord record,
) {
  if (!record.subgoalAdvanced) return false;
  final subgoal = podiumSubgoalOf(record);
  if (subgoal.isEmpty) return false;
  for (final other in history) {
    if (other.id == record.id || !other.subgoalAdvanced) continue;
    if (podiumSubgoalOf(other) != subgoal) continue;
    final at = other.turnAt.compareTo(record.turnAt);
    if (at < 0 || (at == 0 && other.id.compareTo(record.id) < 0)) {
      return false;
    }
  }
  return true;
}

/// One place on a class podium, as its doc stores it.
@immutable
class PodiumPlace {
  const PodiumPlace({
    required this.className,
    required this.subgoalId,
    required this.place,
    required this.uid,
    this.awardedAt,
  });

  final String className;
  final String subgoalId;

  /// 1 (gold), 2 (silver) or 3 (bronze).
  final int place;

  /// The student who holds it. No name: the doc is never shown to anyone
  /// but this student.
  final String uid;

  /// When the student finished the subgoal.
  final DateTime? awardedAt;

  String get id => CosmosDocId.podium(className, subgoalId, place);

  /// A podium doc, or `null` when [doc] is not one.
  static PodiumPlace? fromDoc(Map<String, dynamic> doc) {
    final className = doc['className'];
    final subgoalId = doc['subgoalId'];
    final place = doc['place'];
    final uid = doc['uid'];
    if (doc['type'] != CosmosPartitions.podium ||
        className is! String ||
        subgoalId is! String ||
        subgoalId.isEmpty ||
        place is! num ||
        uid is! String ||
        uid.isEmpty) {
      return null;
    }
    final p = place.toInt();
    if (p < 1 || p > kPodiumPlaces) return null;
    final at = doc['awardedAt'];
    return PodiumPlace(
      className: className,
      subgoalId: subgoalId,
      place: p,
      uid: uid,
      awardedAt: at is String ? DateTime.tryParse(at) : null,
    );
  }

  Map<String, Object?> toDoc() => {
    'id': id,
    'type': CosmosPartitions.podium,
    'className': className.trim(),
    'subgoalId': subgoalId,
    'place': place,
    'uid': uid,
    if (awardedAt != null) 'awardedAt': awardedAt!.toUtc().toIso8601String(),
  };

  /// The medal on the student's account doc: under `podium:{subgoal}`
  /// (`podiumBadgeId`), at [podiumTierOf] the place, awarded by the podium.
  EarnedBadge toEarned() => EarnedBadge(
    tier: podiumTierOf(place),
    earnedAt: awardedAt?.toUtc(),
    awardedBy: kAwardedByPodium,
    extra: {'place': place, 'className': className.trim()},
  );

  @override
  bool operator ==(Object other) =>
      other is PodiumPlace &&
      other.className == className &&
      other.subgoalId == subgoalId &&
      other.place == place &&
      other.uid == uid &&
      other.awardedAt == awardedAt;

  @override
  int get hashCode => Object.hash(className, subgoalId, place, uid, awardedAt);
}

/// The podium docs in Cosmos.
class ClassPodium {
  ClassPodium({CosmosContainer? container}) : _override = container;

  final CosmosContainer? _override;

  CosmosContainer get _container => _override ?? CosmosPaths.config();

  /// Claims the first free place on the podium of [className] for
  /// [subgoalId] for [uid], who finished it at [at]: `create` on place 1,
  /// on a 409 the next. Returns the place won — or the place [uid] already
  /// holds there, which is not a second one — or `null` when all three are
  /// someone else's. A class name that is empty claims nothing. Throws when
  /// Cosmos does not answer; nothing is claimed then.
  Future<PodiumPlace?> claim({
    required String uid,
    required String className,
    required String subgoalId,
    required DateTime at,
  }) async {
    final klas = className.trim();
    if (klas.isEmpty || subgoalId.isEmpty || uid.isEmpty) return null;
    for (var place = 1; place <= kPodiumPlaces; place++) {
      final mine = PodiumPlace(
        className: klas,
        subgoalId: subgoalId,
        place: place,
        uid: uid,
        awardedAt: at.toUtc(),
      );
      try {
        await safeCosmos(
          () => _container.create(
            mine.toDoc(),
            partitionKey: CosmosPartitions.podium,
          ),
        );
        return mine;
      } on CosmosException catch (e) {
        if (e.statusCode != 409) rethrow;
      }
      // Taken. By this student, on another laptop or by the backfill?
      final held = await safeCosmos(
        () => _container.read(mine.id, partitionKey: CosmosPartitions.podium),
      );
      final holder = held == null ? null : PodiumPlace.fromDoc(held);
      if (holder != null && holder.uid == uid) return holder;
    }
    return null;
  }

  /// Every place [uid] holds, on any class's podium: one query on the
  /// `podium` partition. Throws when Cosmos does not answer.
  Future<List<PodiumPlace>> placesOf(String uid) async {
    final docs = await safeCosmos(
      () => _container.query(
        'SELECT * FROM c WHERE c.uid = @uid',
        parameters: {'@uid': uid},
        partitionKey: CosmosPartitions.podium,
      ),
    );
    return [
      for (final doc in docs)
        if (PodiumPlace.fromDoc(doc) case final place? when place.uid == uid)
          place,
    ];
  }
}

final classPodiumProvider = Provider<ClassPodium>((ref) => ClassPodium());

/// [places] as medals on the account doc, by badge id: one per subgoal, the
/// best place when a student holds two (a class change).
Map<String, EarnedBadge> podiumMedals(Iterable<PodiumPlace> places) {
  final out = <String, EarnedBadge>{};
  for (final place in places) {
    final id = podiumBadgeId(place.subgoalId);
    final medal = place.toEarned();
    final before = out[id];
    if (before == null || before.tier < medal.tier) out[id] = medal;
  }
  return out;
}
