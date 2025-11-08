// // lib/data/instructions/instructions_providers.dart
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:hooks_riverpod/hooks_riverpod.dart';
// import 'instructions_service.dart';
// import 'instruction.dart';

// /// Repository provider
// final instructionsRepositoryProvider = Provider<InstructionsRepository>((ref) {
//   final db = FirebaseFirestore.instance;
//   return InstructionsRepository(db);
// });

// /// Streams the full list (live).
// final instructionsListProviderStream = StreamProvider<List<Instruction>>((ref) {
//   return ref.watch(instructionsRepositoryProvider).watchAll();
// });

// /// Stream a single doc by id (live).
// final instructionProviderStream = StreamProvider.family<Instruction?, String>((
//   ref,
//   id,
// ) {
//   return ref.watch(instructionsRepositoryProvider).watchById(id);
// });

// /// One-shot fetch helpers (optional)
// final instructionsListProviderFuture =
//     FutureProvider.autoDispose<List<Instruction>>((ref) {
//       return ref.watch(instructionsRepositoryProvider).getAll();
//     });

// final instructionFutureProvider = FutureProvider.autoDispose
//     .family<Instruction?, String>((ref, id) {
//       return ref.watch(instructionsRepositoryProvider).getById(id);
//     });
