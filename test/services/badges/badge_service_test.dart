// Issue #220 — the badge service over in-memory Cosmos: one read of the
// student's history at start, the badges stored on the account doc, a
// summary for the first look and a notice per badge after a graded turn, no
// lesson badge without lesson times, nothing for a teacher, and a failed
// read that leaves the stored badges standing and is tried again.
//
// #221: a first advance past a subgoal claims a place on the class podium
// and the medal is stored and announced like the other badges; finishing
// again, or without a class, claims nothing; the places the backfill handed
// out are picked up at start; a claim Cosmos cannot answer waits for the
// next graded turn. A badge from the teacher is announced once, with how
// often, and marked seen on the doc.

import 'dart:async';

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/auth/auth_service.dart';
import 'package:ai_tutor_python/services/badges/badge_catalog.dart';
import 'package:ai_tutor_python/services/badges/badge_service.dart';
import 'package:ai_tutor_python/services/badges/class_podium.dart';
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
  bool advanced = false,
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
  subgoalAdvanced: advanced,
);

/// The account service, with a way to hand the badge service the doc as the
/// next 5 s poll would (#221).
class _Accounts221 extends AccountService {
  _Accounts221({super.container});

  void poll(Map<String, dynamic> doc) => state = Account.fromMap(doc);
}

/// The podium's config container, whose creates can be made to fail.
class _Config implements CosmosContainer {
  _Config(this.inner);
  final CosmosContainer inner;
  bool down = false;

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) {
    if (down) throw CosmosException(503, 'unavailable');
    return inner.create(doc, partitionKey: partitionKey);
  }

  @override
  Future<Map<String, dynamic>?> read(
    String id, {
    required Object partitionKey,
  }) => inner.read(id, partitionKey: partitionKey);

  @override
  Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, Object?> parameters = const {},
    Object? partitionKey,
    bool crossPartition = false,
  }) => inner.query(
    sql,
    parameters: parameters,
    partitionKey: partitionKey,
    crossPartition: crossPartition,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
    String? ifMatch,
  }) {
    if (failWrites) throw CosmosException(503, 'unavailable');
    return inner.replace(id, doc, partitionKey: partitionKey, ifMatch: ifMatch);
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
  late InMemoryCosmos config;
  late _Config configContainer;

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
          () => _Accounts221(container: accountsContainer),
        ),
        turnHistoryServiceProvider.overrideWithValue(history),
        classPodiumProvider.overrideWithValue(
          ClassPodium(container: configContainer),
        ),
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
    config = InMemoryCosmos.partitioned('type', [
      {'id': 'global', 'type': 'config'},
    ]);
    configContainer = _Config(config.container);
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

  group('the class podium (#221)', () {
    const earnedAlready = {
      'effort': {'tier': 1},
      'helloWorld': {'tier': 1},
    };

    Map<String, dynamic>? podiumDoc(int place) =>
        config['podium/podium_6EWI_s1_$place'];

    void seedVariables() => goals = InMemoryCosmos([
      {'id': 'r1', 'type': 'goal', 'title': 'Basis', 'order': 0},
      {
        'id': 's1',
        'type': 'goal',
        'title': 'Variabelen',
        'parentId': 'r1',
        'order': 1000,
      },
    ]);

    test('a first advance claims the first free place; the medal is stored '
        'and announced with its subgoal', () async {
      seedVariables();
      seedAccount(className: '6EWI', badges: earnedAlready);
      seedTurns([for (var i = 0; i < 10; i++) _turn(i)]);
      // Someone else was first.
      config.create({
        ...PodiumPlace(
          className: '6EWI',
          subgoalId: 's1',
          place: 1,
          uid: 'someone-else',
        ).toDoc(),
      }, partitionKey: 'podium');
      start();
      await until(() => pc.read(badgeServiceProvider)?.facts != null);

      await pc
          .read(badgeServiceProvider.notifier)
          .afterTurn(_turn(10, advanced: true));

      expect(podiumDoc(2)!['uid'], _uid);
      expect(podiumDoc(2)!['awardedAt'], _at(10).toUtc().toIso8601String());
      final medal = EarnedBadges.fromDoc(accounts.docs[_uid]!)!
          .byId['podium:s1']!;
      expect(medal.tier, 2, reason: 'silver');
      expect(medal.awardedBy, kAwardedByPodium);
      expect(medal.extra['place'], 2);
      final notice = announced()
          .expand((a) => a.badges)
          .singleWhere((n) => n.badge.id == 'podium:s1');
      expect(notice.tier, 2);
      expect(notice.goalTitle, 'Variabelen');
      // Nobody else's place is anywhere in what the student has.
      expect(accounts.docs[_uid].toString(), isNot(contains('someone-else')));
    });

    test('finishing the subgoal again does not count again', () async {
      seedAccount(className: '6EWI', badges: earnedAlready);
      seedTurns([for (var i = 0; i < 10; i++) _turn(i, advanced: i == 3)]);
      start();
      await until(() => pc.read(badgeServiceProvider)?.facts != null);
      await pc
          .read(badgeServiceProvider.notifier)
          .afterTurn(_turn(10, advanced: true));
      expect(podiumDoc(1), isNull);
      expect(storedBadges()!.containsKey('podium:s1'), isFalse);
    });

    test('a student without a class does not take part', () async {
      seedAccount(badges: earnedAlready);
      seedTurns([for (var i = 0; i < 10; i++) _turn(i)]);
      start();
      await until(() => pc.read(badgeServiceProvider)?.facts != null);
      await pc
          .read(badgeServiceProvider.notifier)
          .afterTurn(_turn(10, advanced: true));
      expect(podiumDoc(1), isNull);
      expect(storedBadges()!.containsKey('podium:s1'), isFalse);
    });

    test('the start picks up the places the backfill handed out: in the '
        'summary of the first look', () async {
      seedAccount(className: '6EWI');
      seedTurns([for (var i = 0; i < 12; i++) _turn(i, advanced: i == 5)]);
      config.create(
        PodiumPlace(
          className: '6EWI',
          subgoalId: 's1',
          place: 1,
          uid: _uid,
          awardedAt: _at(5).toUtc(),
        ).toDoc(),
        partitionKey: 'podium',
      );
      start();
      await until(() => announced().isNotEmpty);
      final summary = announced().single;
      expect(summary.first, isTrue);
      expect(summary.badges.map((n) => n.badge.id), contains('podium:s1'));
      final medal = EarnedBadges.fromDoc(accounts.docs[_uid]!)!
          .byId['podium:s1']!;
      expect(medal.tier, 3);
      expect(medal.earnedAt, _at(5).toUtc());
      // Its doc was the backfill's: nothing claimed again.
      expect(podiumDoc(2), isNull);
    });

    test(
      'a claim Cosmos cannot answer waits for the next graded turn',
      () async {
        seedAccount(className: '6EWI', badges: earnedAlready);
        seedTurns([for (var i = 0; i < 10; i++) _turn(i)]);
        start();
        await until(() => pc.read(badgeServiceProvider)?.facts != null);
        configContainer.down = true;
        await pc
            .read(badgeServiceProvider.notifier)
            .afterTurn(_turn(10, advanced: true));
        expect(podiumDoc(1), isNull);
        expect(storedBadges()!.containsKey('podium:s1'), isFalse);

        configContainer.down = false;
        await pc.read(badgeServiceProvider.notifier).afterTurn(_turn(11));
        expect(podiumDoc(1)!['uid'], _uid);
        expect(
          podiumDoc(1)!['awardedAt'],
          _at(10).toUtc().toIso8601String(),
          reason: 'when the subgoal was finished, not when the claim got in',
        );
        expect(
          EarnedBadges.fromDoc(accounts.docs[_uid]!)!.tierOf('podium:s1'),
          3,
        );
      },
    );

    test('an advance while the history is still loading is claimed once it '
        'is in', () async {
      seedAccount(className: '6EWI', badges: earnedAlready);
      seedTurns([for (var i = 0; i < 10; i++) _turn(i)]);
      history.gate = Completer<void>();
      start();
      await until(() => history.reads == 1);
      await pc
          .read(badgeServiceProvider.notifier)
          .afterTurn(_turn(10, advanced: true));
      expect(podiumDoc(1), isNull);
      history.gate!.complete();
      await until(() => podiumDoc(1) != null);
      await until(() => storedBadges()!.containsKey('podium:s1'));
    });
  });

  group('the teacher\'s badges (#221)', () {
    Map<String, dynamic> given(int count, {int? seen}) => {
      'tier': 1,
      'awardedBy': 'teacher',
      'earnedAt': '2026-10-05T10:00:00.000Z',
      'count': count,
      'seen': ?seen,
    };

    _Accounts221 accountService() =>
        pc.read(accountServiceProvider.notifier) as _Accounts221;

    test('a badge given is announced once, with how often, and marked seen '
        'on the doc', () async {
      seedAccount(
        badges: {
          'helloWorld': {'tier': 1},
          'teacher:helpingHand': given(2, seen: 1),
          'teacher:goodQuestion': given(1, seen: 1),
        },
      );
      seedTurns([_turn(0)]);
      start();
      await until(() => announced().isNotEmpty);
      final notice = announced().single.badges.single;
      expect(notice.badge.id, 'teacher:helpingHand');
      expect(notice.count, 2);
      await until(
        () => (storedBadges()!['teacher:helpingHand'] as Map)['seen'] == 2,
      );

      // The next poll, with it seen: nothing new.
      pc.read(badgeAnnouncementsProvider.notifier).dismissCurrent();
      accountService().poll(accounts.docs[_uid]!);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(announced(), isEmpty);

      // The teacher gives it again while the app is open.
      final doc = accounts.docs[_uid]!;
      (doc['badges'] as Map)['teacher:helpingHand'] = given(3, seen: 2);
      accountService().poll(doc);
      await until(() => announced().isNotEmpty);
      expect(announced().single.badges.single.count, 3);
      await until(
        () => (storedBadges()!['teacher:helpingHand'] as Map)['seen'] == 3,
      );
    });

    test(
      'a poll before the seen write is in does not announce it twice',
      () async {
        seedAccount(badges: {'teacher:faultFinder': given(1)});
        accountsContainer.failWrites = true;
        start();
        await until(() => announced().isNotEmpty);
        pc.read(badgeAnnouncementsProvider.notifier).dismissCurrent();
        accountService().poll(accounts.docs[_uid]!);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(announced(), isEmpty);
        // The write is tried again on a later poll.
        accountsContainer.failWrites = false;
        accountService().poll(accounts.docs[_uid]!);
        await until(
          () => (storedBadges()!['teacher:faultFinder'] as Map)['seen'] == 1,
        );
        expect(announced(), isEmpty);
      },
    );

    test('a badge given before the student ever opened the release: the '
        'history\'s badges are still the first look\'s summary', () async {
      seedAccount(badges: {'teacher:goodQuestion': given(1)});
      seedTurns([for (var i = 0; i < 12; i++) _turn(i)]);
      start();
      await until(() => announced().length == 2);
      final queue = announced();
      expect(queue.first.badges.single.badge.id, 'teacher:goodQuestion');
      expect(queue.last.first, isTrue);
      expect(queue.last.badges.map((n) => n.badge.id), [
        'effort',
        'streak',
        'helloWorld',
      ]);
    });

    test('a teacher\'s app announces nothing', () async {
      seedAccount(badges: {'teacher:goodQuestion': given(1)});
      start(teacher: true);
      await until(() => pc.read(accountServiceProvider) != null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(announced(), isEmpty);
    });
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
