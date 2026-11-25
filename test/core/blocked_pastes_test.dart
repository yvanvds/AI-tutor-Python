// #334 — the blocked pastes of an oefening: noted by the paste guard, taken
// onto the turn record by the tutor, unknown when a doc does not say.

import 'package:ai_tutor_python/core/blocked_pastes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the ledger counts the blocked pastes and adds up their characters, '
      'and a take starts it again', () {
    final ledger = BlockedPasteLedger();
    expect(ledger.take(), BlockedPastes.none);

    ledger
      ..note(120)
      ..note(30);
    expect(ledger.pending, const BlockedPastes(count: 2, chars: 150));
    expect(ledger.take(), const BlockedPastes(count: 2, chars: 150));
    expect(ledger.take(), BlockedPastes.none);

    ledger.note(5);
    ledger.clear();
    expect(ledger.pending, BlockedPastes.none);
  });

  test('a doc says how many only with both numbers; anything else is '
      'unknown, never 0', () {
    expect(
      BlockedPastes.tryFromDoc({'blockedPastes': 3, 'blockedPasteChars': 90}),
      const BlockedPastes(count: 3, chars: 90),
    );
    expect(
      BlockedPastes.tryFromDoc({'blockedPastes': 0, 'blockedPasteChars': 0}),
      BlockedPastes.none,
    );
    expect(BlockedPastes.tryFromDoc({}), isNull);
    expect(BlockedPastes.tryFromDoc({'blockedPastes': 3}), isNull);
    expect(
      BlockedPastes.tryFromDoc({'blockedPastes': null, 'blockedPasteChars': 0}),
      isNull,
    );
  });
}
