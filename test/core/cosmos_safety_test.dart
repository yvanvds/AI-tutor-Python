// Issue #7 — `safeCosmosStream` absorbs a failed poll so the consumer keeps
// the last good value and picks up the next successful fetch; the polling
// source itself must keep ticking through the failure.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a failing poll is absorbed and polling continues', () async {
    var calls = 0;
    final stream = safeCosmosStream(
      pollingStream<int>(() async {
        calls++;
        if (calls == 2) throw CosmosException(503, 'blip');
        return calls;
      }, interval: const Duration(milliseconds: 10)),
    );

    final values = <int>[];
    final errors = <Object>[];
    final sub = stream.listen(values.add, onError: errors.add);

    // Wait until the poll after the failing one has landed.
    while (values.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await sub.cancel();

    expect(values.first, 1);
    expect(values[1], 3, reason: 'the 503 tick (2) is skipped, not fatal');
    expect(errors, isEmpty);
  });

  test(
    'pollingStream itself still reports the error to a raw listener',
    () async {
      var calls = 0;
      final stream = pollingStream<int>(() async {
        calls++;
        if (calls == 1) throw StateError('first fetch failed');
        return calls;
      }, interval: const Duration(milliseconds: 10));

      final errors = <Object>[];
      final values = <int>[];
      final sub = stream.listen(values.add, onError: errors.add);
      while (values.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await sub.cancel();

      expect(errors.single, isA<StateError>());
      expect(values.first, 2);
    },
  );
}
