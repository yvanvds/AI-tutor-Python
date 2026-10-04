// Issue #221 — the class podium: who is first (create on place 1, a 409
// moves on), students finishing at the same time never share a place, a
// place once held is found again rather than a second taken, a fourth gets
// nothing, finishing again does not count, and the docs sit in the `podium`
// partition of `config` with the student's uid and nothing else about them.

import 'package:ai_tutor_python/core/answer_quality.dart';
import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/badges/class_podium.dart';
import 'package:ai_tutor_python/services/badges/earned_badges.dart';
import 'package:ai_tutor_python/services/student_state/turn_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

PersistedTurnRecord _turn(
  String id,
  DateTime at, {
  String subgoal = 's1',
  String? active,
  bool advanced = true,
}) => PersistedTurnRecord(
  id: id,
  turnAt: at,
  subgoalId: subgoal,
  activeSubgoalId: active,
  targetLOIds: const ['lo1'],
  questionType: 'mcQuestion',
  difficulty: QuestionDifficulty.medium,
  isFollowUp: false,
  chainDepth: 0,
  selectionReason: null,
  overallQuality: AnswerQuality.correct,
  loSignals: const [],
  hadFallback: false,
  appliedSignals: const [],
  calibrationBefore: QuestionDifficulty.medium,
  calibrationAfter: QuestionDifficulty.medium,
  subgoalProgressAfter: 1,
  loStatusAfter: const [],
  subgoalAdvanced: advanced,
);

/// A config container whose creates can be made to fail, or to wait.
class _Flaky implements CosmosContainer {
  _Flaky(this.inner);
  final CosmosContainer inner;
  bool down = false;
  int creates = 0;

  @override
  Future<Map<String, dynamic>> create(
    Map<String, Object?> doc, {
    required Object partitionKey,
  }) async {
    creates++;
    if (down) throw CosmosException(503, 'unavailable');
    // Let the other claims of a Future.wait run in between.
    await Future<void>.delayed(Duration.zero);
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

void main() {
  final at = DateTime.utc(2026, 10, 5, 9);

  group('the rules', () {
    test('gold is the highest tier, bronze the lowest', () {
      expect(kPodiumPlaces, 3);
      expect([1, 2, 3].map(podiumTierOf), [3, 2, 1]);
      expect([3, 2, 1].map(podiumPlaceOf), [1, 2, 3]);
    });

    test('the doc id: class trimmed, what Cosmos refuses in an id made safe '
        '(the same examples as the backfill\'s test)', () {
      expect(CosmosDocId.podium('6EWI', 's1', 1), 'podium_6EWI_s1_1');
      expect(
        CosmosDocId.podium(' 6 EWI ', r'a/b?c#d\e', 3),
        'podium_6-EWI_a-b-c-d-e_3',
      );
    });

    test('only the first advance past a subgoal counts — not finishing it '
        'again after working through it once more', () {
      final first = _turn('t1', at);
      final again = _turn('t2', at.add(const Duration(days: 3)));
      final other = _turn('t3', at.add(const Duration(days: 1)), subgoal: 's2');
      final history = [first, other, again];
      expect(isFirstAdvance(history, first), isTrue);
      expect(isFirstAdvance(history, again), isFalse);
      expect(isFirstAdvance(history, other), isTrue);
      // Also before the record itself joined the history.
      expect(isFirstAdvance([again], first), isTrue);
      expect(
        isFirstAdvance(history, _turn('t4', at, advanced: false)),
        isFalse,
      );
    });

    test('the subgoal is the one the student was on', () {
      final warmUp = _turn('t1', at, subgoal: 'old', active: 's1');
      expect(podiumSubgoalOf(warmUp), 's1');
      final later = _turn('t2', at.add(const Duration(hours: 1)));
      expect(isFirstAdvance([warmUp, later], later), isFalse);
    });

    test('a medal per subgoal, the best place when a student holds two', () {
      final medals = podiumMedals([
        PodiumPlace(className: '6A', subgoalId: 's1', place: 3, uid: 'u'),
        PodiumPlace(
          className: '6B',
          subgoalId: 's1',
          place: 1,
          uid: 'u',
          awardedAt: at,
        ),
        PodiumPlace(className: '6B', subgoalId: 's2', place: 2, uid: 'u'),
      ]);
      expect(medals.keys, unorderedEquals(['podium:s1', 'podium:s2']));
      expect(
        medals['podium:s1'],
        EarnedBadge(
          tier: 3,
          earnedAt: at,
          awardedBy: kAwardedByPodium,
          extra: const {'place': 1, 'className': '6B'},
        ),
      );
      expect(medals['podium:s2']!.tier, 2);
    });
  });

  group('claiming', () {
    late InMemoryCosmos config;
    late _Flaky container;
    late ClassPodium podium;

    setUp(() {
      // Partitioned on `type` as in Cosmos: a podium doc written to another
      // partition than its own `type` fails.
      config = InMemoryCosmos.partitioned('type', [
        {'id': 'global', 'type': 'config', 'Model': 'gpt-4o'},
      ]);
      container = _Flaky(config.container);
      podium = ClassPodium(container: container);
    });

    Future<PodiumPlace?> claim(String uid, {String klas = '6EWI'}) =>
        podium.claim(uid: uid, className: klas, subgoalId: 's1', at: at);

    test('the first three of a class get gold, silver and bronze — three '
        'places also in a small class — and the fourth nothing', () async {
      expect((await claim('a'))!.place, 1);
      expect((await claim('b'))!.place, 2);
      expect((await claim('c'))!.place, 3);
      expect(await claim('d'), isNull);
      final doc = config['podium/podium_6EWI_s1_1']!;
      expect(doc, {
        'id': 'podium_6EWI_s1_1',
        'type': 'podium',
        'className': '6EWI',
        'subgoalId': 's1',
        'place': 1,
        'uid': 'a',
        'awardedAt': '2026-10-05T09:00:00.000Z',
      });
      // The settings next to it are untouched.
      expect(config['config/global'], isNotNull);
    });

    test('another class has a podium of its own', () async {
      await claim('a');
      expect((await claim('x', klas: '6WEWI'))!.place, 1);
    });

    test(
      'students who finish at the same moment never share a place',
      () async {
        final won = await Future.wait([
          for (final uid in ['a', 'b', 'c', 'd', 'e']) claim(uid),
        ]);
        final places = [for (final p in won) ?p];
        expect(places.map((p) => p.place).toSet(), {1, 2, 3});
        expect(places.map((p) => p.uid).toSet(), hasLength(3));
        expect(won.where((p) => p == null), hasLength(2));
        expect(
          config.docs.keys.where((k) => k.startsWith('podium/')),
          hasLength(3),
        );
      },
    );

    test('a place already held is found again, not a second one taken — the '
        'same student on another laptop, or after a failed write', () async {
      await claim('a');
      await claim('b');
      final again = await claim('b');
      expect(again!.place, 2);
      expect(again.uid, 'b');
      expect(config['podium/podium_6EWI_s1_3'], isNull);
    });

    test('no class: no claim, nothing written', () async {
      expect(await claim('a', klas: '  '), isNull);
      expect(container.creates, 0);
    });

    test('Cosmos not answering: it throws, and nothing is claimed', () async {
      container.down = true;
      await expectLater(claim('a'), throwsA(isA<CosmosException>()));
      expect(config.docs.keys.where((k) => k.startsWith('podium/')), isEmpty);
    });

    test('a student\'s places: only their own', () async {
      await claim('a');
      await claim('b');
      await podium.claim(uid: 'a', className: '6EWI', subgoalId: 's2', at: at);
      final mine = await podium.placesOf('a');
      expect(
        mine.map((p) => (p.subgoalId, p.place)),
        unorderedEquals([('s1', 1), ('s2', 1)]),
      );
      expect(mine.every((p) => p.uid == 'a'), isTrue);
    });
  });
}
