// 1C.2 — Tests `Debouncer`. Used wherever search/typing triggers Cosmos
// reads; a regression to "fire immediately" multiplies read costs. Drives
// the timer through `package:fake_async` so the test stays deterministic.

import 'package:ai_tutor_python/core/debounce.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Debouncer', () {
    test('fires the action exactly once after the delay elapses', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(const Duration(milliseconds: 200));

        d.run(() => calls += 1);

        // Just before the deadline — nothing should have fired yet.
        async.elapse(const Duration(milliseconds: 199));
        expect(calls, 0);

        // At the deadline — fires.
        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);

        // After the fire, no further callbacks.
        async.elapse(const Duration(seconds: 1));
        expect(calls, 1);
      });
    });

    test('two run() calls inside the delay only fire the second action', () {
      fakeAsync((async) {
        var first = 0;
        var second = 0;
        final d = Debouncer(const Duration(milliseconds: 200));

        d.run(() => first += 1);
        async.elapse(const Duration(milliseconds: 100)); // mid-delay
        d.run(() => second += 1); // restarts the timer

        async.elapse(const Duration(milliseconds: 199));
        expect(first, 0);
        expect(second, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(first, 0);
        expect(second, 1);
      });
    });

    test('dispose() cancels a pending action', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(const Duration(milliseconds: 200));

        d.run(() => calls += 1);
        async.elapse(const Duration(milliseconds: 100));
        d.dispose();

        async.elapse(const Duration(seconds: 1));
        expect(calls, 0);
      });
    });

    test('dispose() with no pending action is a no-op', () {
      // Just don't crash.
      Debouncer(const Duration(milliseconds: 200)).dispose();
    });

    test('a fresh run() after a successful fire schedules a new action', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(const Duration(milliseconds: 200));

        d.run(() => calls += 1);
        async.elapse(const Duration(milliseconds: 200));
        expect(calls, 1);

        d.run(() => calls += 1);
        async.elapse(const Duration(milliseconds: 200));
        expect(calls, 2);
      });
    });
  });
}
