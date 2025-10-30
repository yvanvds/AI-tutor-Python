// lib/data/instructions/instructions_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'instruction.dart';

class InstructionsRepository {
  InstructionsRepository(FirebaseFirestore db)
    : _col = db
          .collection('instructions')
          .withConverter<Instruction>(
            fromFirestore: (snap, _) =>
                Instruction.fromMap(snap.id, snap.data() ?? {}),
            toFirestore: (instruction, _) => instruction.toMap(),
          );

  final CollectionReference<Instruction> _col;

  /// Stream all instruction docs (live updates).
  Stream<List<Instruction>> watchAll() {
    return _col
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((q) => q.docs.map((d) => d.data()).toList());
  }

  /// One-shot fetch of all docs.
  Future<List<Instruction>> getAll() async {
    final q = await _col.orderBy('updatedAt', descending: true).get();
    return q.docs.map((d) => d.data()).toList();
  }

  /// Stream a single doc by id (null if it doesn’t exist).
  Stream<Instruction?> watchById(String id) {
    return _col.doc(id).snapshots().map((d) => d.data());
  }

  /// One-shot fetch a single doc (null if not found).
  Future<Instruction?> getById(String id) async {
    final snap = await _col.doc(id).get();
    return snap.data();
  }

  /// Upsert: create or update the doc with merge semantics.
  Future<void> upsert(Instruction instruction) async {
    await _col.doc(instruction.id).set(instruction, SetOptions(merge: true));
  }

  /// Delete by id.
  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}
