import 'package:ai_tutor_python/services/splash/splash_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SplashService', () {
    late SplashService service;

    setUp(() => service = SplashService());
    tearDown(() => service.dispose());

    test('state is null initially', () {
      expect(service.state.value, isNull);
    });

    test('showGoalReached sets correct state fields', () {
      service.showGoalReached(
        goalTitle: 'Loops',
        description: 'You understand for loops!',
      );
      final state = service.state.value;
      expect(state, isNotNull);
      expect(state!.title, 'Goal reached!');
      expect(state.goalTitle, 'Loops');
      expect(state.description, 'You understand for loops!');
      expect(state.message, isA<String>());
      expect(state.message, isNotEmpty);
    });

    test('hide clears state', () {
      service.showGoalReached(goalTitle: 'X', description: 'Y');
      service.hide();
      expect(service.state.value, isNull);
    });

    test('randomPhrase returns a non-empty string', () {
      expect(service.randomPhrase(), isNotEmpty);
    });

    test('auto-hides after duration elapses', () {
      fakeAsync((async) {
        service.showGoalReached(
          goalTitle: 'Vars',
          description: 'Variables!',
          duration: const Duration(seconds: 5),
        );
        expect(service.state.value, isNotNull);
        async.elapse(const Duration(seconds: 6));
        expect(service.state.value, isNull);
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
        expect(service.state.value?.goalTitle, 'B');
      });
    });
  });
}
