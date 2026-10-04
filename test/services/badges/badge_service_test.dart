// Issue #220 — the badge service over in-memory Cosmos: one read of the
// student's history at start, the badges stored on the account doc, a
// summary for the first look and a notice per badge after a graded turn, no
// lesson badge without lesson times, nothing for a teacher, and a failed
// read that leaves the stored badges standing and is tried again.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:ai_tutor_python/services/goal/goals_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_history_service.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _uid = 'u1';

class _Auth extends AuthService {
  _Auth(this.who);
  final AccountIdentity? who;

  @override
  AccountIdentity? build() => who;

  void set(AccountIdentity? v) => state = v;
}

AccountIdentity _identity({bool teacher = false}) => AccountIdentity(
  oid: _uid,
  displayName: 'Sam Student',
  email: 'sam@example.com',
  firstName: 'Sam',
  lastName: 'Student',
  isTeacher: teacher,
);

/// Monday 14 September 2026, 10:00 local time, plus [minutes].
DateTime _at(int minutes) =>
    DateTime(2026, 9, 14, 10).add(Duration(minutes: minutes));

PersistedTurnRecord _turn(
  int i, {
  AnswerQuality quality = AnswerQuality.correct,
}) => PersistedTurnRecord(
  id: 't${i.toString().padLeft(3, '0')}',
  turnAt: _at(i).toUtc(),
  subgoalId: 's1',
  targetLOIds: const ['lo1'],
  questionType: 'mcQuestion',
  difficulty: QuestionDifficulty.medium,
  isFollowUp: false,
  chainDepth: 0,
  selectionReason: null,
  overallQuality: quality,
  loSignals: const [],
  hadFallback: false,
  appliedSignals: const [],
  calibrationBefore: QuestionDifficulty.medium,
  calibrationAfter: QuestionDifficulty.medium,
  subgoalProgressAfter: 0,
  loStatusAfter: const [],
  subgoalAdvanced: false,
);

/// Reads the history from the in-memory container, or fails, or waits.
class _History extends TurnHistoryService {
  _History(InMemoryCosmos store)
    : super(container: store.container, getUid: () => _uid);

  Object? failWith;
  Completer<void>? gate;
  int reads = 0;

  @override
  Future<List<PersistedTurnRecord>> listForBadges(String uid) async {
    reads++;
    final error = failWith;
    if (error != null) throw error;
    final records = await super.listForBadges(uid);
    await gate?.future;
    return records;
  }
}

/// The accounts container, whose writes can be made to fail.
class _Accounts implements CosmosContainer {
  _Accounts(this.inner);
  final CosmosContainer inner;
  bool failWrites = false;

  @override
  Future<Map<String, dynamic>> replace(
    String id,
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) {
    if (failWrites) throw CosmosException(503, 'unavailable');
    return inner.replace(id, doc, partitionKey: partitionKey);
  }

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) => inner.read(id, partitionKey: partitionKey);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late InMemoryCosmos accounts;
  late _Accounts accountsContainer;
  late InMemoryCosmos turns;
  late InMemoryCosmos goals;
  late _History history;
  late ProviderContainer pc;
  var classes = ClassList.empty;

  void seedAccount({String className = '', Map<String, dynamic>? badges}) {
    accounts = InMemoryCosmos([
      {
        'id': _uid,
        'uid': _uid,
        'firstName': 'Sam',
        'className': className,
        'oefeningCount': 0,
        'badges': ?badges,
      },
    ]);
    accountsContainer = _Accounts(accounts.container);
  }

  void seedTurns(Iterable<PersistedTurnRecord> records) {
    turns = InMemoryCosmos([for (final r in records) r.toMap(uid: _uid)]);
    history = _History(turns);
  }

  ProviderContainer start({bool teacher = false}) {
    pc = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWith(
          () => _Auth(_identity(teacher: teacher)),
        ),
        accountServiceProvider.overrideWith(
          () => AccountService(container: accountsContainer),
        ),
        turnHistoryServiceProvider.overrideWithValue(history),
        goalsServiceProvider.overrideWithValue(
          GoalsService(container: goals.container),
        ),
        badgeClassListReaderProvider.overrideWithValue(() async => classes),
      ],
    );
    addTearDown(pc.dispose);
    // What the shell does once it is up.
    pc.read(accountServiceProvider);
    pc.read(badgeServiceProvider);
    return pc;
  }

  Future<void> until(bool Function() done, {String? reason}) async {
    for (var i = 0; i < 200; i++) {
      if (done()) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail(reason ?? 'condition never held');
  }

  Map<String, dynamic>? storedBadges() =>
      accounts.docs[_uid]!['badges'] as Map<String, dynamic>?;

  List<BadgeAnnouncement> announced() => pc.read(badgeAnnouncementsProvider);

  setUp(() {
    classes = ClassList.empty;
    goals = InMemoryCosmos();
    seedAccount();
    seedTurns(const []);
  });

  test('the first look stores what the history earned and sums it up in one '
      'announcement', () async {
    seedTurns([for (var i = 0; i < 12; i++) _turn(i)]);
    start();

    await until(() => storedBadges() != null, reason: 'nothing stored');
    final stored = EarnedBadges.fromDoc(accounts.docs[_uid]!)!;
    expect(stored.tierOf('effort'), 1);
    expect(stored.tierOf('streak'), 1);
    expect(stored.tierOf('helloWorld'), 1);
    expect(stored.tierOf('fortyTwo'), 0);
    expect(history.reads, 1);

    await until(() => announced().isNotEmpty);
    final summary = announced().single;
    expect(summary.first, isTrue);
    expect(summary.isSummary, isTrue);
    expect(summary.badges.map((n) => n.badge.id), [
      'effort',
      'streak',
      'helloWorld',
    ]);
  });

  test('a first look with nothing earned stores an empty map and says '
      'nothing', () async {
    start();
    await until(() => storedBadges() != null);
    expect(storedBadges(), isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(announced(), isEmpty);
  });

  test('a start with the badges already stored announces nothing', () async {
    seedAccount(
      badges: {
        'effort': {'tier': 1},
        'streak': {'tier': 1},
        'helloWorld': {'tier': 1},
      },
    );
    seedTurns([for (var i = 0; i < 12; i++) _turn(i)]);
    start();
    await until(() => pc.read(badgeServiceProvider)?.facts != null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(announced(), isEmpty);
    expect(pc.read(badgeBoardProvider)!.earnedCount, 3);
  });

  test('after a graded turn: no query, the new badge stored and announced on '
      'its own', () async {
    seedAccount(
      badges: {
        'helloWorld': {'tier': 1},
      },
    );
    // Nine oefeningen with a wrong one among them: no streak of ten.
    seedTurns([
      for (var i = 0; i < 9; i++)
        _turn(i, quality: i == 4 ? AnswerQuality.wrong : AnswerQuality.correct),
    ]);
    start();
    await until(() => pc.read(badgeServiceProvider)?.facts != null);
    expect(announced(), isEmpty);

    await pc.read(badgeServiceProvider.notifier).afterTurn(_turn(9));

    expect(history.reads, 1, reason: 'the history is in memory');
    expect(EarnedBadges.fromDoc(accounts.docs[_uid]!)!.tierOf('effort'), 1);
    final notice = announced().single;
    expect(notice.isSummary, isFalse);
    expect(notice.badges.single.badge.id, 'effort');
    expect(notice.badges.single.tier, 1);
    expect(pc.read(badgeServiceProvider)!.facts!.oefeningen, 10);
  });

  test('a turn that comes in while the history is still loading is counted '
      'once', () async {
    seedTurns([for (var i = 0; i < 10; i++) _turn(i)]);
    history.gate = Completer<void>();
    start();
    await until(() => history.reads == 1);
    // Its write is in, so the query has it too.
    await pc.read(badgeServiceProvider.notifier).afterTurn(_turn(9));
    history.gate!.complete();
    await until(() => pc.read(badgeServiceProvider)?.facts != null);
    expect(pc.read(badgeServiceProvider)!.facts!.oefeningen, 10);
  });

  group('the lesson badges (#219)', () {
    test('a class without lesson times: unknown, never awarded — not every '
        'oefening home work', () async {
      seedAccount(className: '6X');
      classes = const ClassList([SchoolClass(name: '6X')]);
      seedTurns([for (var i = 0; i < 60; i++) _turn(i)]);
      start();
      await until(() => storedBadges() != null);
      expect(storedBadges()!.containsKey('homeWork'), isFalse);
      final board = pc.read(badgeBoardProvider)!;
      final tile = board.tiers.firstWhere((t) => t.badge.id == 'homeWork');
      expect(tile.value, isNull);
      expect(tile.progressKnown, isTrue);
    });

    test('with lesson times: oefeningen out of them are home work, the ones '
        'in them count lesson weeks', () async {
      seedAccount(className: '6X');
      classes = ClassList([
        SchoolClass(
          name: '6X',
          lessons: [
            // Monday 10:00 to 10:30: the first 30 oefeningen (and 10 more
            // minutes of margin) are in it.
            LessonSlot(
              weekday: DateTime.monday,
              startMinute: 600,
              endMinute: 630,
            ),
          ],
        ),
      ]);
      seedTurns([for (var i = 0; i < 100; i++) _turn(i)]);
      start();
      await until(() => pc.read(badgeServiceProvider)?.facts != null);
      final facts = pc.read(badgeServiceProvider)!.facts!;
      expect(facts.homeOefeningen, 100 - 41);
      expect(facts.lessonWeeks, 1);
      await until(() => storedBadges() != null);
      expect(EarnedBadges.fromDoc(accounts.docs[_uid]!)!.tierOf('homeWork'), 1);
    });
  });

  test('a teacher gets no badges: nothing read, nothing written', () async {
    seedTurns([for (var i = 0; i < 12; i++) _turn(i)]);
    start(teacher: true);
    await until(() => pc.read(accountServiceProvider) != null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pc.read(badgeServiceProvider.notifier).afterTurn(_turn(12));
    expect(history.reads, 0);
    expect(storedBadges(), isNull);
    expect(pc.read(badgeServiceProvider), isNull);
  });

  test('a history that cannot be read: the stored badges show without '
      'progress, and the next graded turn tries again', () async {
    seedAccount(
      badges: {
        'effort': {'tier': 1},
      },
    );
    seedTurns([for (var i = 0; i < 10; i++) _turn(i)]);
    history.failWith = StateError('Cosmos is down');
    start();
    await until(() => pc.read(badgeServiceProvider) != null);
    expect(pc.read(badgeServiceProvider)!.facts, isNull);
    // The stored badge shows; no progress is claimed.
    await until(() => pc.read(accountServiceProvider) != null);
    final board = pc.read(badgeBoardProvider)!;
    expect(board.progressKnown, isFalse);
    expect(board.earnedCount, 1);

    history.failWith = null;
    await pc.read(badgeServiceProvider.notifier).afterTurn(_turn(10));
    await until(() => pc.read(badgeServiceProvider)?.facts != null);
    expect(history.reads, 2);
    expect(pc.read(badgeServiceProvider)!.facts!.oefeningen, 11);
  });

  test('a write that fails leaves the counts standing and announces '
      'nothing; the next graded turn stores and announces', () async {
    seedTurns([for (var i = 0; i < 12; i++) _turn(i)]);
    accountsContainer.failWrites = true;
    start();
    await until(() => pc.read(badgeServiceProvider)?.facts != null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(storedBadges(), isNull);
    expect(announced(), isEmpty);
    expect(pc.read(badgeServiceProvider)!.facts!.oefeningen, 12);

    accountsContainer.failWrites = false;
    await pc.read(badgeServiceProvider.notifier).afterTurn(_turn(12));
    expect(EarnedBadges.fromDoc(accounts.docs[_uid]!)!.tierOf('effort'), 1);
    expect(announced().single.first, isTrue);
    expect(history.reads, 1);
  });

  test('signing out forgets the student and the notices waiting', () async {
    seedTurns([for (var i = 0; i < 12; i++) _turn(i)]);
    start();
    await until(() => announced().isNotEmpty);
    (pc.read(authServiceProvider.notifier) as _Auth).set(null);
    await until(() => pc.read(badgeServiceProvider) == null);
    expect(announced(), isEmpty);
  });

  group('announcing', () {
    BadgeAward award(Map<String, int> raised, {bool first = false}) =>
        BadgeAward(badges: const {}, raised: raised, first: first);

    late ProviderContainer local;
    setUp(() {
      local = ProviderContainer();
      addTearDown(local.dispose);
    });

    BadgeAnnouncer announcer() =>
        local.read(badgeAnnouncementsProvider.notifier);

    test('one or two badges at once: a notice each, in trophy-case order', () {
      announcer().announce(
        award({'helloWorld': 1, 'effort': 1}),
        goalTitle: (_) => null,
      );
      final queue = local.read(badgeAnnouncementsProvider);
      expect(queue, hasLength(2));
      expect(queue.map((a) => a.badges.single.badge.id), [
        'effort',
        'helloWorld',
      ]);
      expect(queue.every((a) => !a.isSummary), isTrue);
    });

    test('three at once: one summary', () {
      announcer().announce(
        award({'helloWorld': 1, 'effort': 1, 'streak': 1}),
        goalTitle: (_) => null,
      );
      final queue = local.read(badgeAnnouncementsProvider);
      expect(queue.single.isSummary, isTrue);
      expect(queue.single.first, isFalse);
      expect(kBadgeSummaryFrom, 3);
    });

    test('a "Kenner van …" carries its hoofddoel\'s title; an id this build '
        'does not know is not announced', () {
      announcer().announce(
        award({expertBadgeId('r1'): 1, 'teacher:helper': 1}),
        goalTitle: (id) => id == 'r1' ? 'Lussen' : null,
      );
      final notice = local.read(badgeAnnouncementsProvider).single;
      expect(notice.badges.single.goalTitle, 'Lussen');
    });

    test('dismissing takes the first off the queue', () {
      announcer().announce(
        award({'helloWorld': 1, 'effort': 1}),
        goalTitle: (_) => null,
      );
      announcer().dismissCurrent();
      expect(
        local.read(badgeAnnouncementsProvider).single.badges.single.badge.id,
        'helloWorld',
      );
    });
  });
}
