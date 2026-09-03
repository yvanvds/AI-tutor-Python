// Issue #32 — export / import of a student's progress.
//
// The point of the feature is moving state between *accounts*, so the two
// things worth pinning down are that the file carries no identity of the
// account it came from, and that importing it into a different uid produces
// docs the conductor can read back unchanged.

import 'dart:convert';

import 'package:ai_tutor_python/core/question_difficulty.dart';
import 'package:ai_tutor_python/services/progress/progress_archive.dart';
import 'package:ai_tutor_python/services/progress/progress_service.dart';
import 'package:ai_tutor_python/services/student_state/lo_beliefs_service.dart';
import 'package:ai_tutor_python/services/student_state/student_calibration.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_cosmos.dart';

const _from = 'old-account';
const _to = 'new-account';

Map<String, dynamic> _progressDoc(String uid, String goalId, double value) => {
  'id': '${uid}_$goalId',
  'uid': uid,
  'goalId': goalId,
  'progress': value,
  'updatedAt': '2026-05-01T10:00:00Z',
  'lastSessionAt': '2026-05-01T10:00:00Z',
};

Map<String, dynamic> _sampleDoc(String uid, String id, String goalId) => {
  'id': id,
  'uid': uid,
  'goalId': goalId,
  'progress': 0.5,
  'quality': 'correct',
  'at': '2026-05-01T10:00:00Z',
};

Map<String, dynamic> _beliefDoc(String uid, String subgoalId, String loId) => {
  'id': '${uid}_${subgoalId}_$loId',
  'type': 'lo_belief',
  'uid': uid,
  'subgoalId': subgoalId,
  'loId': loId,
  'alpha': 3.0,
  'beta': 1.5,
  'lastUpdatedAt': '2026-05-01T10:00:00Z',
  'lastQuestionType': 'socraticQuestion',
  'highestPositiveDifficulty': 'hard',
  'recentNegativesAtCalibrated': 2,
  'firstMasteredAt': '2026-04-20T10:00:00.000Z',
};

void main() {
  late InMemoryCosmos progress;
  late InMemoryCosmos history;
  late InMemoryCosmos beliefs;
  late StudentCalibration calibration;

  ProgressArchive archiveFor(String uid) => ProgressArchive(
    progress: ProgressService(
      container: progress.container,
      historyContainer: history.container,
      getUid: () => uid,
    ),
    loBeliefs: LoBeliefsService(
      container: beliefs.container,
      getUid: () => uid,
    ),
    calibration: () => calibration,
    setCalibration: (c) async => calibration = c,
  );

  List<Map<String, dynamic>> docsOf(InMemoryCosmos store, String uid) =>
      store.docs.values.where((d) => d['uid'] == uid).toList();

  setUp(() {
    progress = InMemoryCosmos([
      _progressDoc(_from, 'r1', 0.75),
      _progressDoc(_from, 's1', 1.0),
      // A doc belonging to somebody else in the same container.
      _progressDoc('stranger', 's1', 0.2),
    ]);
    history = InMemoryCosmos([
      _sampleDoc(_from, 'h1', 's1'),
      _sampleDoc(_from, 'h2', 'r1'),
    ]);
    beliefs = InMemoryCosmos([
      _beliefDoc(_from, 's1', 'lo-print'),
      _beliefDoc(_from, 's2', 'lo-var'),
    ]);
    calibration = const StudentCalibration(difficulty: QuestionDifficulty.hard);
  });

  test('export collects only the signed-in user, and no identity', () async {
    final data = await archiveFor(_from).export();

    expect(data['kind'], ProgressArchive.kind);
    expect(data['version'], ProgressArchive.formatVersion);
    expect(data['progress'], hasLength(2));
    expect(data['history'], hasLength(2));
    expect(data['beliefs'], hasLength(2));
    expect((data['calibration'] as Map)['difficulty'], 'hard');

    // Nothing that would pin the file to the account it came from.
    final encoded = jsonEncode(data);
    expect(encoded, isNot(contains(_from)));
    expect(encoded, isNot(contains('"uid"')));
    expect(encoded, isNot(contains('"id"')));
  });

  test('import writes the archive into a different account', () async {
    final data = await archiveFor(_from).export();
    // Round-trip through JSON: that is what the panel actually hands over.
    final decoded = jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

    calibration = const StudentCalibration(difficulty: QuestionDifficulty.easy);
    final summary = await archiveFor(_to).import(decoded);

    expect(summary, (goals: 2, samples: 2, beliefs: 2));
    expect(calibration.difficulty, QuestionDifficulty.hard);

    final imported = docsOf(progress, _to);
    expect(imported, hasLength(2));
    expect(imported.map((d) => d['goalId']).toSet(), {'r1', 's1'});
    expect(progress['${_to}_s1']!['progress'], 1.0);
    expect(docsOf(history, _to), hasLength(2));

    final belief = docsOf(
      beliefs,
      _to,
    ).singleWhere((d) => d['subgoalId'] == 's1');
    expect(belief['id'], '${_to}_s1_lo-print');
    expect(belief['alpha'], 3.0);
    expect(belief['lastQuestionType'], 'socraticQuestion');
    expect(belief['highestPositiveDifficulty'], 'hard');
    expect(belief['recentNegativesAtCalibrated'], 2);
    expect(belief['firstMasteredAt'], '2026-04-20T10:00:00.000Z');

    // The account the file came from is untouched.
    expect(progress['${_from}_s1'], isNotNull);
    expect(progress['stranger_s1'], isNotNull);
  });

  test('import replaces what the target account already had', () async {
    final data = await archiveFor(_from).export();

    progress = InMemoryCosmos([
      ...progress.docs.values,
      _progressDoc(_to, 'r1', 0.1),
      _progressDoc(_to, 's9', 0.9),
    ]);
    beliefs = InMemoryCosmos([
      ...beliefs.docs.values,
      _beliefDoc(_to, 's9', 'lo-old'),
    ]);

    await archiveFor(_to).import(data);

    final goalIds = docsOf(progress, _to).map((d) => d['goalId']).toSet();
    expect(goalIds, {'r1', 's1'}, reason: 's9 should have been wiped');
    expect(docsOf(beliefs, _to), hasLength(2));
  });

  test('the progress writes an import makes do not add history of their '
      'own', () async {
    final data = await archiveFor(_from).export();
    await archiveFor(_to).import(data);
    // Two samples came from the file; the upserts must not append more.
    expect(docsOf(history, _to), hasLength(2));
  });

  group('rejects a file it cannot read', () {
    test('a JSON file that is not an archive', () {
      expect(
        () => archiveFor(_to).import({'hello': 'world'}),
        throwsA(isA<ProgressArchiveException>()),
      );
    });

    test('an archive from a newer build', () {
      expect(
        () => archiveFor(_to).import({
          'kind': ProgressArchive.kind,
          'version': ProgressArchive.formatVersion + 1,
        }),
        throwsA(isA<ProgressArchiveException>()),
      );
    });

    test('a damaged section', () {
      expect(
        () => archiveFor(_to).import({
          'kind': ProgressArchive.kind,
          'version': ProgressArchive.formatVersion,
          'progress': 'not a list',
        }),
        throwsA(isA<ProgressArchiveException>()),
      );
    });

    test('a rejected file leaves the target account alone', () async {
      progress = InMemoryCosmos([
        ...progress.docs.values,
        _progressDoc(_to, 'r1', 0.1),
      ]);
      await expectLater(
        archiveFor(_to).import({
          'kind': ProgressArchive.kind,
          'version': ProgressArchive.formatVersion,
          'progress': [
            {'goalId': 'r1', 'progress': 1.0},
            'not a doc',
          ],
        }),
        throwsA(isA<ProgressArchiveException>()),
      );
      expect(progress['${_to}_r1']!['progress'], 0.1);
    });
  });
}
