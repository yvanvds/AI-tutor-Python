import 'package:ai_tutor_python/services/tutor/tutor_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/legacy.dart';

final aiResponseProvider = StateProvider<String>((ref) {
  return '';
});

final tutorServiceProvider = Provider<TutorService>((ref) {
  final service = TutorService(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

final tutorWorkingProvider = StateProvider<bool>((ref) => false);
