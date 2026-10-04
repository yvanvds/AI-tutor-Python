// Computes the signed-in student's badges (#220), stores what they earned
// on their account doc, and announces what is new.
//
// When:
//
//   - at app start, once per student: one query on their own partition of
//     `turn_history` (`TurnHistoryService.listForBadges`), the goals and the
//     lesson times of their class. The first start after the release finds
//     everything the history already earned: one summary, not a notice per
//     badge (`BadgeAward.first`);
//   - after every graded turn (`TutorService`, once the turn record is
//     built): the new record joins the history in memory and the badges are
//     counted again — no query. The grade's feedback is on screen by then,
//     so the notice never lands in the middle of a question.
//
// Badges are for students: a teacher's account is left alone (they are not
// graded either; `Section.myReports` is student-only for the same reason),
// and sees the whole set on the proof sheet under Options.
//
// Two kinds no rule counts (#221):
//
//   - the class podium (`class_podium.dart`): a graded turn that moves the
//     student past a subgoal for the first time claims a place on their
//     class's podium for it, and the start-up read finds every place the
//     student holds — also the ones `tooling/badges/podium_backfill.py`
//     filled in — so each medal lands on the account doc in the same write
//     as the other badges, and is announced like them;
//   - the teacher's badges: the teacher's app writes them on the account doc;
//     the next poll of it (5 s, or the next start) announces what the
//     student has not seen yet and marks it seen there, so another laptop
//     does not announce it again.
//
// Everything here is best-effort and off the student's path: a failed read
// leaves the badges as they were stored, a failed write is tried again after
// the next graded turn. Nothing here gives XP or touches a grade.

import 'dart:async';

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_facts.dart';
import 'package:ai_tutor_python/services/badges/class_podium.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/classes/classes_service.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:ai_tutor_python/services/goal/goal.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:ai_tutor_python/services/supervision/supervision_source.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// From this many badges at once a notice per badge becomes one summary.
const int kBadgeSummaryFrom = 3;

/// What the badges were counted from: the facts, and the hoofddoelen for
/// the "Kenner van …" badges.
@immutable
class BadgeSnapshot {
  const BadgeSnapshot({
    required this.facts,
    this.roots = const [],
    this.goals = const [],
  });

  /// `null` when the history could not be read: the trophy case then shows
  /// what is stored, without progress.
  final BadgeFacts? facts;

  /// The hoofddoelen, in leerpad order; empty when the goals could not be
  /// read.
  final List<Goal> roots;

  /// Every goal, for the subgoal a medal of the class podium is for (#221);
  /// empty when the goals could not be read.
  final List<Goal> goals;
}

/// One class list read, now — the seam a test replaces.
final badgeClassListReaderProvider = Provider<Future<ClassList> Function()>(
  (ref) =>
      () => safeCosmos(() => ClassesService.readOnce()),
);

class BadgeService extends Notifier<BadgeSnapshot?> {
  /// The student the history in memory belongs to.
  String? _uid;
  Future<void>? _loading;
  bool _loaded = false;
  List<PersistedTurnRecord> _records = const [];

  /// Graded turns that came in while the history was still loading.
  final Map<String, PersistedTurnRecord> _pending = {};
  List<Goal>? _goals;
  LessonTimeCheck? _inLesson;

  /// The medals of the class podium the student holds (#221), by badge id:
  /// read at start, and won since.
  Map<String, EarnedBadge> _podium = const {};

  /// Advances past a subgoal whose podium claim is still to be made: the
  /// history was loading, or Cosmos did not answer (tried again after the
  /// next graded turn).
  final Map<String, PersistedTurnRecord> _toClaim = {};

  /// Per teacher's badge, the count this app announced (#221): the `seen` on
  /// the doc may lag a poll behind the write that sets it.
  final Map<String, int> _teacherAnnounced = {};
  bool _markingSeen = false;

  @override
  BadgeSnapshot? build() {
    ref.listen<Account?>(
      accountServiceProvider,
      (_, account) => _onAccount(account),
    );
    // An account already there when the service is first read (the shell
    // reads it once it is up): handled right after this build, which may
    // not set the state itself.
    final current = ref.read(accountServiceProvider);
    if (current != null) Future.microtask(() => _onAccount(current));
    return null;
  }

  bool get _isTeacher => ref.read(isTeacherProvider);

  void _onAccount(Account? account) {
    if (account == null) {
      if (ref.read(authServiceProvider) == null) _reset();
      return;
    }
    if (_isTeacher) return;
    if (account.uid != _uid) {
      _reset();
      _uid = account.uid;
      _loading = _load(account);
    }
    _announceTeacherBadges(account);
  }

  void _reset() {
    _uid = null;
    _loading = null;
    _loaded = false;
    _records = const [];
    _pending.clear();
    _goals = null;
    _inLesson = null;
    _podium = const {};
    _toClaim.clear();
    _teacherAnnounced.clear();
    _markingSeen = false;
    state = null;
    ref.read(badgeAnnouncementsProvider.notifier).clear();
  }

  /// The teacher's badges on [account] the student has not seen (#221):
  /// announced once, and marked seen on the doc.
  void _announceTeacherBadges(Account account) {
    final earned = account.badges;
    if (earned == null) return;
    final notices = <EarnedBadgeNotice>[];
    final unseen = <String, int>{};
    for (final badge in BadgeCatalog.teacher) {
      final entry = earned.byId[badge.id];
      if (entry == null || entry.count <= entry.seen) continue;
      unseen[badge.id] = entry.count;
      final announced = _teacherAnnounced[badge.id] ?? entry.seen;
      if (entry.count <= announced) continue;
      _teacherAnnounced[badge.id] = entry.count;
      notices.add(EarnedBadgeNotice(badge: badge, tier: 1, count: entry.count));
    }
    if (notices.isNotEmpty) {
      ref.read(badgeAnnouncementsProvider.notifier).announceGiven(notices);
    }
    if (unseen.isEmpty || _markingSeen) return;
    _markingSeen = true;
    final uid = _uid;
    unawaited(
      ref
          .read(accountServiceProvider.notifier)
          .markTeacherBadgesSeen(unseen)
          .catchError((Object e) {
            // The next poll tries again; this app does not announce twice.
            debugPrint(
              'BadgeService: marking the teacher\'s badges failed: $e',
            );
          })
          .whenComplete(() {
            if (_uid == uid) _markingSeen = false;
          }),
    );
  }

  /// The badges after [record], a graded turn just built: it joins the
  /// history and the badges are counted again. Never throws.
  Future<void> afterTurn(PersistedTurnRecord record) async {
    try {
      if (_isTeacher || record.questionType.isEmpty) return;
      final account = ref.read(accountServiceProvider);
      if (account == null) return;
      if (account.uid != _uid || (!_loaded && _loading == null)) {
        // Not loaded (the start-up read failed, or never ran): load again,
        // with this record waiting in case its write is not in yet.
        if (account.uid != _uid) _reset();
        _uid = account.uid;
        _pending[record.id] = record;
        _loading = _load(account);
        return;
      }
      if (!_loaded) {
        // The start-up load picks it up when it is done.
        _pending[record.id] = record;
        return;
      }
      _records = _merged(_records, [record]);
      if (record.subgoalAdvanced) _toClaim[record.id] = record;
      await _claimPodium();
      await _evaluate();
    } catch (e, stack) {
      debugPrint('BadgeService: after a turn failed: $e\n$stack');
    }
  }

  Future<void> _load(Account account) async {
    final uid = account.uid;
    try {
      final records = await ref
          .read(turnHistoryServiceProvider)
          .listForBadges(uid);
      final goals = await _readGoals();
      final inLesson = await _readLessons(account.className);
      final podium = await _readPodium(uid);
      if (_uid != uid) return;
      _records = _merged(records, _pending.values);
      for (final r in _pending.values) {
        if (r.subgoalAdvanced) _toClaim[r.id] = r;
      }
      _pending.clear();
      _goals = goals;
      _inLesson = inLesson;
      _podium = {...podium, ..._podium};
      _loaded = true;
      await _claimPodium();
      await _evaluate();
    } catch (e, stack) {
      debugPrint('BadgeService: loading the badges failed: $e\n$stack');
      if (_uid != uid) return;
      // The next graded turn tries again; the trophy case shows what is
      // stored in the meantime.
      _loading = null;
      state = const BadgeSnapshot(facts: null);
    }
  }

  /// The medals of every podium place [uid] holds (#221); none when they
  /// could not be read — the next start reads them again, and a claim finds
  /// a place already held without them.
  Future<Map<String, EarnedBadge>> _readPodium(String uid) async {
    try {
      return podiumMedals(await ref.read(classPodiumProvider).placesOf(uid));
    } catch (e) {
      debugPrint('BadgeService: podium not read: $e');
      return const {};
    }
  }

  /// Claims a podium place (#221) for every advance waiting in [_toClaim]:
  /// only the student's first advance past that subgoal, only with a class,
  /// and not when they hold its medal already. One Cosmos cannot answer
  /// stays waiting for the next graded turn.
  Future<void> _claimPodium() async {
    for (final record in _toClaim.values.toList()) {
      final account = ref.read(accountServiceProvider);
      final uid = _uid;
      if (account == null || uid == null || account.uid != uid) return;
      final className = account.className.trim();
      final subgoal = podiumSubgoalOf(record);
      final id = podiumBadgeId(subgoal);
      if (className.isEmpty ||
          subgoal.isEmpty ||
          !isFirstAdvance(_records, record) ||
          _podium.containsKey(id) ||
          (account.badges?.tierOf(id) ?? 0) > 0) {
        _toClaim.remove(record.id);
        continue;
      }
      try {
        final place = await ref
            .read(classPodiumProvider)
            .claim(
              uid: uid,
              className: className,
              subgoalId: subgoal,
              at: record.turnAt,
            );
        if (_uid != uid) return;
        _toClaim.remove(record.id);
        if (place != null) _podium = {..._podium, id: place.toEarned()};
      } catch (e) {
        debugPrint('BadgeService: podium claim failed, tried again later: $e');
      }
    }
  }

  Future<List<Goal>?> _readGoals() async {
    try {
      return await ref.read(goalsServiceProvider).getAllGoalsOnce();
    } catch (e) {
      debugPrint('BadgeService: goals not read, no "Kenner van": $e');
      return null;
    }
  }

  /// The lesson time of [className] (#219), `null` when it has no lessons
  /// or they could not be read: then no lesson badge is counted — every
  /// oefening would look like home work, and a badge once given stays.
  Future<LessonTimeCheck?> _readLessons(String className) async {
    final name = className.trim();
    if (name.isEmpty) return null;
    try {
      final classes = await ref.read(badgeClassListReaderProvider)();
      if (classes.lessonsOf(name).isEmpty) return null;
      return (at) => classes.isDuringLesson(
        name,
        at,
        margin: ScheduleSupervisionSource.margin,
      );
    } catch (e) {
      debugPrint('BadgeService: lessons not read, no lesson badges: $e');
      return null;
    }
  }

  static List<PersistedTurnRecord> _merged(
    Iterable<PersistedTurnRecord> a,
    Iterable<PersistedTurnRecord> b,
  ) {
    final byId = <String, PersistedTurnRecord>{
      for (final r in a) r.id: r,
      for (final r in b) r.id: r,
    };
    return byId.values.toList(growable: false);
  }

  Future<void> _evaluate() async {
    final goals = _goals;
    final facts = BadgeFacts.from(
      records: _records,
      goals: goals,
      inLesson: _inLesson,
    );
    final all = goals ?? const <Goal>[];
    final roots = all.where((g) => g.parentId == null).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    state = BadgeSnapshot(facts: facts, roots: roots, goals: all);

    final reached = <String, int>{};
    for (final badge in BadgeCatalog.all(
      expertGoalIds: roots.map((g) => g.id),
    )) {
      final tier = badge.tierFor(badge.valueIn(facts));
      if (tier > 0) reached[badge.id] = tier;
    }
    // Only write when something may have gone up since the last poll of the
    // account doc — the write itself checks against the doc as stored.
    final stored = ref.read(accountServiceProvider)?.badges;
    final podium = _podium;
    final mayRaise =
        stored == null ||
        reached.entries.any((e) => e.value > stored.tierOf(e.key)) ||
        podium.entries.any((e) => e.value.tier > stored.tierOf(e.key));
    if (!mayRaise) return;
    final uid = _uid;
    final BadgeAward? award;
    try {
      award = await ref
          .read(accountServiceProvider.notifier)
          .awardBadges(reached, granted: podium);
    } catch (e) {
      // The counts stand; the write is tried again after the next graded
      // turn, and what it raises is announced then.
      debugPrint('BadgeService: storing the badges failed: $e');
      return;
    }
    if (award == null || _uid != uid) return;
    ref
        .read(badgeAnnouncementsProvider.notifier)
        .announce(
          award,
          goalTitle: (id) => all.where((g) => g.id == id).firstOrNull?.title,
        );
  }
}

final badgeServiceProvider = NotifierProvider<BadgeService, BadgeSnapshot?>(
  BadgeService.new,
);

// ---- Announcements ---------------------------------------------------------

/// A badge that just went up, as the notice shows it.
@immutable
class EarnedBadgeNotice {
  const EarnedBadgeNotice({
    required this.badge,
    required this.tier,
    this.goalTitle,
    this.count = 1,
  });

  final BadgeDefinition badge;
  final int tier;

  /// The Dutch title of a "Kenner van …" badge's hoofddoel, or of the
  /// subgoal of a medal of the class podium (#221); the notice shows it in
  /// the app language.
  final String? goalTitle;

  /// How many times the teacher gave this badge, this time included (#221).
  final int count;
}

/// What the notice in the corner says: one badge, or several at once.
@immutable
class BadgeAnnouncement {
  const BadgeAnnouncement({required this.badges, this.first = false});

  /// The badges, in trophy-case order. One: a notice for that badge; more:
  /// a summary.
  final List<EarnedBadgeNotice> badges;

  /// The first look at this student's badges (#220): "Je hebt al 14 badges
  /// verdiend!" rather than "nieuwe".
  final bool first;

  bool get isSummary => first || badges.length > 1;
}

/// The notices waiting to be shown, oldest first. The overlay shows the
/// first and drops it when it is dismissed or times out.
class BadgeAnnouncer extends Notifier<List<BadgeAnnouncement>> {
  @override
  List<BadgeAnnouncement> build() => const [];

  /// Queues what [award] raised: one summary on the first look or from
  /// [kBadgeSummaryFrom] badges at once, else a notice per badge. A badge
  /// this build does not know is not announced.
  void announce(
    BadgeAward award, {
    required String? Function(String goalId) goalTitle,
  }) {
    final order = <String, int>{};
    final notices = <EarnedBadgeNotice>[];
    for (final entry in award.raised.entries) {
      final badge = BadgeCatalog.byId(entry.key);
      if (badge == null) continue;
      final goal = badge.goalId;
      notices.add(
        EarnedBadgeNotice(
          badge: badge,
          tier: entry.value,
          goalTitle: goal == null ? null : goalTitle(goal),
        ),
      );
    }
    if (notices.isEmpty) return;
    final all = BadgeCatalog.all();
    for (var i = 0; i < all.length; i++) {
      order[all[i].id] = i;
    }
    notices.sort(
      (a, b) => (order[a.badge.id] ?? all.length).compareTo(
        order[b.badge.id] ?? all.length,
      ),
    );
    if (award.first || notices.length >= kBadgeSummaryFrom) {
      state = [
        ...state,
        BadgeAnnouncement(badges: notices, first: award.first),
      ];
    } else {
      state = [
        ...state,
        for (final notice in notices) BadgeAnnouncement(badges: [notice]),
      ];
    }
  }

  /// Queues the teacher's badges in [notices] (#221), like [announce]: a
  /// notice each, or one summary from [kBadgeSummaryFrom] at once.
  void announceGiven(List<EarnedBadgeNotice> notices) {
    if (notices.isEmpty) return;
    state = [
      ...state,
      if (notices.length >= kBadgeSummaryFrom)
        BadgeAnnouncement(badges: notices)
      else
        for (final notice in notices) BadgeAnnouncement(badges: [notice]),
    ];
  }

  /// Drops the notice on screen.
  void dismissCurrent() {
    if (state.isEmpty) return;
    state = state.sublist(1);
  }

  void clear() => state = const [];

  /// Puts [announcement] up as if it were earned — the proof sheet's
  /// preview of the notice.
  void preview(BadgeAnnouncement announcement) =>
      state = [...state, announcement];
}

final badgeAnnouncementsProvider =
    NotifierProvider<BadgeAnnouncer, List<BadgeAnnouncement>>(
      BadgeAnnouncer.new,
    );

// ---- The trophy case -------------------------------------------------------

/// One badge as the trophy case shows it.
@immutable
class BadgeTile {
  const BadgeTile({
    required this.badge,
    required this.tier,
    this.value,
    this.earned,
    this.goal,
    this.expertProgress,
    this.progressKnown = true,
    this.count = 0,
  });

  final BadgeDefinition badge;

  /// The tier to show: the higher of what is stored and what the history
  /// reaches now (a write may still be on its way).
  final int tier;

  /// What the student has for this badge; `null` when it is not known.
  final int? value;

  /// What the account doc stores for it.
  final EarnedBadge? earned;

  /// The hoofddoel of a "Kenner van …" badge; the subgoal of a medal of the
  /// class podium (#221).
  final Goal? goal;

  /// How many times the teacher gave this badge (#221); 0 for one not given
  /// and for every other badge.
  final int count;

  /// Its LOs mastered, of all of them.
  final ExpertProgress? expertProgress;

  /// Whether the history was read. Without it [value] is `null` for every
  /// badge; with it, only for one that cannot be known (the lesson badges
  /// of a class without lesson times).
  final bool progressKnown;

  bool get isEarned => tier > 0;

  /// A secret not found yet: a "?" without name or rule.
  bool get isHidden => badge.secret && !isEarned;

  /// What the next tier needs; `null` at the top.
  int? get next => badge.nextThreshold(tier);
}

/// The whole trophy case.
@immutable
class BadgeBoard {
  const BadgeBoard({
    required this.tiers,
    required this.experts,
    required this.fun,
    required this.progressKnown,
    this.podium = const [],
    this.teacher = const [],
    this.inClass = false,
  });

  final List<BadgeTile> tiers;
  final List<BadgeTile> experts;
  final List<BadgeTile> fun;

  /// The student's medals of the class podium (#221), gold first: only the
  /// ones they hold — there is nothing to show of a place someone else has.
  final List<BadgeTile> podium;

  /// The teacher's badges (#221), every one of them, with how often given.
  final List<BadgeTile> teacher;

  /// Whether the student is in a class, so takes part in the podium.
  final bool inClass;

  /// Whether the history was read: without it the case shows what is
  /// stored, without progress.
  final bool progressKnown;

  List<BadgeTile> get all => [
    ...tiers,
    ...experts,
    ...podium,
    ...teacher,
    ...fun,
  ];

  int get earnedCount => all.where((t) => t.isEarned).length;

  int get total => all.length;

  factory BadgeBoard.from(
    BadgeSnapshot snapshot,
    EarnedBadges earned, {
    bool inClass = false,
  }) {
    final facts = snapshot.facts;
    BadgeTile tile(BadgeDefinition badge, {Goal? goal}) {
      final value = facts == null ? null : badge.valueIn(facts);
      final stored = earned.byId[badge.id];
      final reached = badge.tierFor(value);
      final storedTier = stored?.tier ?? 0;
      return BadgeTile(
        badge: badge,
        tier: storedTier > reached ? storedTier : reached,
        value: value,
        earned: stored,
        goal: goal,
        expertProgress: badge.group == BadgeGroup.experts && goal != null
            ? (facts?.experts?[goal.id])
            : null,
        progressKnown: facts != null,
        count: badge.group == BadgeGroup.teacher && stored != null
            ? stored.count
            : 0,
      );
    }

    final goalsById = {for (final g in snapshot.goals) g.id: g};
    final podium =
        <BadgeTile>[
          for (final id in earned.byId.keys)
            if (BadgeCatalog.byId(id) case final badge?
                when badge.group == BadgeGroup.podium)
              tile(badge, goal: goalsById[badge.goalId]),
        ]..sort((a, b) {
          final byPlace = b.tier.compareTo(a.tier);
          if (byPlace != 0) return byPlace;
          final at = a.earned?.earnedAt;
          final bt = b.earned?.earnedAt;
          if (at == null || bt == null) return a.badge.id.compareTo(b.badge.id);
          return at.compareTo(bt);
        });

    final experts = <BadgeTile>[
      for (final root in snapshot.roots)
        if (facts?.experts?.containsKey(root.id) == true ||
            earned.tierOf(expertBadgeId(root.id)) > 0)
          tile(BadgeCatalog.expert(root.id), goal: root),
    ];
    return BadgeBoard(
      tiers: [for (final b in BadgeCatalog.tiered) tile(b)],
      experts: experts,
      fun: [for (final b in BadgeCatalog.fun) tile(b)],
      podium: podium,
      teacher: [for (final b in BadgeCatalog.teacher) tile(b)],
      inClass: inClass,
      progressKnown: facts != null,
    );
  }
}

/// The signed-in student's trophy case; `null` while the badges load (and
/// for a teacher, who has none).
final badgeBoardProvider = Provider<BadgeBoard?>((ref) {
  final snapshot = ref.watch(badgeServiceProvider);
  if (snapshot == null) return null;
  final earned = ref.watch(accountServiceProvider.select((a) => a?.badges));
  final inClass = ref.watch(
    accountServiceProvider.select(
      (a) => (a?.className.trim() ?? '').isNotEmpty,
    ),
  );
  return BadgeBoard.from(
    snapshot,
    earned ?? EarnedBadges.none,
    inClass: inClass,
  );
});
