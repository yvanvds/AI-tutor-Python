// #79: the report side must not publish the student's mastery estimates.

import 'package:ai_tutor_python/services/debug/turn_payload_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redactBeliefData', () {
    test('replaces belief values wherever they sit, and keeps the rest', () {
      final redacted = redactBeliefData({
        'turnId': 4,
        'events': [
          {
            'name': 'conductor.planned',
            'data': {
              'targetLO': 'write_input_call',
              'questionType': 'completeCodeQuestion',
              'difficulty': 'medium',
              'chosenReason': 'lowest mean unmastered',
              'notchDropFired': false,
              'candidateLOs': [
                {'loId': 'write_input_call', 'mean': 0.5677, 'evidence': 6.144},
                {'loId': 'recall_input', 'mean': 0.6657, 'evidence': 10.98},
              ],
            },
          },
        ],
      });

      final data = (redacted['events'] as List).single as Map<String, dynamic>;
      final planned = data['data'] as Map<String, dynamic>;
      final candidates = (planned['candidateLOs'] as List)
          .cast<Map<String, dynamic>>();

      // The numbers are gone — including the ones nested two lists deep.
      expect(candidates.map((c) => c['mean']), everyElement(kRedactedBelief));
      expect(
        candidates.map((c) => c['evidence']),
        everyElement(kRedactedBelief),
      );

      // …and everything a diagnosis is made of survived (#78 was solved from
      // exactly these fields).
      expect(redacted['turnId'], 4);
      expect(candidates.map((c) => c['loId']), [
        'write_input_call',
        'recall_input',
      ]);
      expect(planned['targetLO'], 'write_input_call');
      expect(planned['questionType'], 'completeCodeQuestion');
      expect(planned['difficulty'], 'medium');
      expect(planned['chosenReason'], 'lowest mean unmastered');
      expect(planned['notchDropFired'], false);
    });

    test('catches the graded turn as well as the plan', () {
      final redacted = redactBeliefData({
        'persisted': {
          'subgoalId': 'input_basics',
          'targetLOIds': ['write_input_call'],
          'overallQuality': 'partial',
          'subgoalProgressAfter': 0.42,
          'appliedSignals': [
            {'loId': 'write_input_call', 'alphaDelta': 0.6, 'betaDelta': 0.0},
          ],
          'loStatusAfter': [
            {
              'loId': 'write_input_call',
              'mean': 0.5677,
              'evidence': 6.144,
              'mastered': false,
              'stuck': true,
            },
          ],
        },
      });

      final persisted = redacted['persisted'] as Map<String, dynamic>;
      final status =
          (persisted['loStatusAfter'] as List).single as Map<String, dynamic>;
      final applied =
          (persisted['appliedSignals'] as List).single as Map<String, dynamic>;

      expect(persisted['subgoalProgressAfter'], kRedactedBelief);
      expect(applied['alphaDelta'], kRedactedBelief);
      expect(applied['betaDelta'], kRedactedBelief);
      // "stuck on this LO" is the same statement as the number it came from.
      expect(status['mastered'], kRedactedBelief);
      expect(status['stuck'], kRedactedBelief);
      expect(status['loId'], 'write_input_call');
      expect(persisted['subgoalId'], 'input_basics');
      expect(persisted['targetLOIds'], ['write_input_call']);
    });

    test('never touches the payload it was given', () {
      // A `TurnEvent`'s data map is handed out by reference, so redacting in
      // place would blank the numbers in Options → Developer tools as a side
      // effect of filing a report.
      final live = <String, dynamic>{
        'candidateLOs': [
          <String, dynamic>{'loId': 'write_input_call', 'mean': 0.5677},
        ],
      };

      redactBeliefData(live);

      final candidate = (live['candidateLOs'] as List).single as Map;
      expect(candidate['mean'], 0.5677);
    });

    test('survives nulls, empty collections and unexpected shapes', () {
      final redacted = redactBeliefData({
        'error': null,
        'events': <dynamic>[],
        'parsedResponse': {
          'type': 'question',
          'options': ['a', 'b'],
          'nested': [
            [
              {'mean': 0.1},
            ],
          ],
        },
      });

      expect(redacted['error'], isNull);
      expect(redacted['events'], isEmpty);
      final parsed = redacted['parsedResponse'] as Map<String, dynamic>;
      expect(parsed['options'], ['a', 'b']);
      final nested = ((parsed['nested'] as List).single as List).single as Map;
      expect(nested['mean'], kRedactedBelief);
    });
  });
}
