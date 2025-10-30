// lib/data/instructions/instructions_providers.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'instructions_repository.dart';
import 'instruction.dart';

/// Repository provider
final instructionsRepositoryProvider = Provider<InstructionsRepository>((ref) {
  final db = FirebaseFirestore.instance;
  return InstructionsRepository(db);
});

/// Streams the full list (live).
final instructionsListStreamProvider = StreamProvider<List<Instruction>>((ref) {
  return ref.watch(instructionsRepositoryProvider).watchAll();
});

/// Stream a single doc by id (live).
final instructionStreamProvider = StreamProvider.family<Instruction?, String>((
  ref,
  id,
) {
  return ref.watch(instructionsRepositoryProvider).watchById(id);
});

/// One-shot fetch helpers (optional)
final instructionsListFutureProvider = FutureProvider<List<Instruction>>((ref) {
  return ref.watch(instructionsRepositoryProvider).getAll();
});

final instructionFutureProvider = FutureProvider.family<Instruction?, String>((
  ref,
  id,
) {
  return ref.watch(instructionsRepositoryProvider).getById(id);
});
