import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SplashService', () {
    late SplashService service;
    late GoalSplashState? tracked;

    setUp(() {
      tracked = null;
      service = SplashService(onStateChanged: (s) => tracked = s);
    });

    test('state is null initially', () {
      expect(tracked, isNull);
    });

    test('showGoalReached sets correct state fields', () {
      service.showGoalReached(
        goalTitle: 'Loops',
        description: 'You understand for loops!',
      );
      expect(tracked, isNotNull);
      expect(tracked!.goalTitle, 'Loops');
      expect(tracked!.description, 'You understand for loops!');
      // The phrase itself is localized by the overlay (#23); the service
      // only picks which one.
      expect(tracked!.phraseIndex, inInclusiveRange(0, SplashService.phraseCount - 1));
    });

    test('hide clears state', () {
      service.showGoalReached(goalTitle: 'X', description: 'Y');
      service.hide();
      expect(tracked, isNull);
    });

    test('randomPhraseIndex stays within the localized phrase table', () {
      for (var i = 0; i < 200; i++) {
        expect(
          service.randomPhraseIndex(),
          inInclusiveRange(0, SplashService.phraseCount - 1),
        );
      }
    });

    test('auto-hides after duration elapses', () {
      fakeAsync((async) {
        service.showGoalReached(
          goalTitle: 'Vars',
          description: 'Variables!',
          duration: const Duration(seconds: 5),
        );
        expect(tracked, isNotNull);
        async.elapse(const Duration(seconds: 6));
        expect(tracked, isNull);
      });
    });

    test('auto-hide does not clear state when another goal replaced it', () {
      fakeAsync((async) {
        service.showGoalReached(
          goalTitle: 'A',
          description: 'desc A',
          duration: const Duration(seconds: 5),
        );
        // Replace with a different goal before first timer fires
        service.showGoalReached(
          goalTitle: 'B',
          description: 'desc B',
          duration: const Duration(seconds: 10),
        );
        async.elapse(const Duration(seconds: 6));
        // First timer should not clear goal B
        expect(tracked?.goalTitle, 'B');
      });
    });
  });
}
