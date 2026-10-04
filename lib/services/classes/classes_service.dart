// Reads and writes the school's class list (#218): the `classes` doc in the
// `config` container, next to `global`. See `school_class.dart` for the
// shape and why the class name stays the key.

import 'package:ai_tutor_python/core/cosmos_client.dart';
import 'package:ai_tutor_python/core/cosmos_doc_id.dart';
import 'package:ai_tutor_python/core/cosmos_paths.dart';
import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'school_class.dart';

/// A class name that is empty, or that another class already has (up to
/// case). The Classes page checks this before it writes; the service says it
/// again so no caller can put a duplicate key in the list.
class ClassNameException implements Exception {
  const ClassNameException(this.name, {required this.taken});

  final String name;

  /// `true`: another class has this name; `false`: the name is empty.
  final bool taken;

  @override
  String toString() => taken
      ? 'ClassNameException: there already is a class "$name"'
      : 'ClassNameException: a class needs a name';
}

/// A class that is not in the list (any more).
class UnknownClassException implements Exception {
  const UnknownClassException(this.name);

  final String name;

  @override
  String toString() => 'UnknownClassException: no class "$name"';
}

/// Sets the class of one account — `AccountService.setClassName`'s shape, so
/// [ClassesService.renameClass] can take that method as it is.
typedef SetClassName = Future<void> Function({
  required String uid,
  required String className,
});

/// The class list, polled like `config/global`: `null` until the first read
/// is back, then the list — [ClassList.empty] when the doc does not exist
/// yet, so "no classes" and "not known yet" stay apart. A failed poll keeps
/// the last list (see `safeCosmosStream`).
class ClassesService extends Notifier<ClassList?> {
  /// [container] is the test seam the other Cosmos-backed services have:
  /// production leaves it null and gets `CosmosPaths.config()`.
  ClassesService({CosmosContainer? container}) : _containerOverride = container;

  static const String _pk = CosmosPartitions.config;
  static const String _docId = CosmosDocId.classes;

  final CosmosContainer? _containerOverride;

  CosmosContainer get _container => _containerOverride ?? CosmosPaths.config();

  @override
  ClassList? build() {
    final sub = watchClasses().listen((classes) => state = classes);
    ref.onDispose(sub.cancel);
    return null;
  }

  /// Every poll reads a new list; only one that differs is news. Without
  /// this the Students page would rebuild its whole table every 5 s for an
  /// unchanged class list.
  @override
  bool updateShouldNotify(ClassList? previous, ClassList? next) =>
      previous != next;

  /// The list as last read, without waiting: `null` until the first read is
  /// back.
  ClassList? get cachedClasses => state;

  /// One read of the list, now.
  Future<ClassList> getClasses() => safeCosmos(_fetchOnce);

  Stream<ClassList> watchClasses() =>
      safeCosmosStream(pollingStream(() => safeCosmos(_fetchOnce)));

  /// Adds a class called [name] (trimmed), without lessons.
  ///
  /// Throws [ClassNameException] for an empty name or one another class
  /// already has, up to case.
  Future<void> addClass(String name) {
    final key = name.trim();
    return _update((current) {
      _checkName(current, key);
      return ClassList.sorted([...current.classes, SchoolClass(name: key)]);
    });
  }

  /// Removes class [name] and its lessons. Removing a class that is not
  /// there is not an error.
  ///
  /// **Whether it still has students is the caller's to check**: the list
  /// does not know the accounts. The Classes page offers this only for a
  /// class without students, and counts them again right before it calls.
  Future<void> removeClass(String name) => _update(
    (current) =>
        ClassList.sorted(current.classes.where((c) => c.name != name.trim())),
  );

  /// Renames class [from] to [to], and moves its students along: one
  /// [setClassName] per account in [memberUids] — the accounts whose
  /// `className` is [from] — the way the Students page's bulk assignment
  /// does it (#91). The lessons stay with the class.
  ///
  /// The accounts go first and the list last. A failure halfway leaves the
  /// list on the old name with some of its students already on the new one;
  /// renaming again moves the rest and then the list, so a retry finishes
  /// the job. The other order would leave the old name in no list at all,
  /// with nothing to rename any more.
  ///
  /// Throws [ClassNameException] when [to] is empty or another class has
  /// it, [UnknownClassException] when [from] is not in the list — both
  /// before any account is touched.
  Future<void> renameClass({
    required String from,
    required String to,
    required Iterable<String> memberUids,
    required SetClassName setClassName,
  }) async {
    final oldName = from.trim();
    final newName = to.trim();
    final before = await getClasses();
    if (!before.contains(oldName)) throw UnknownClassException(oldName);
    _checkName(before, newName, except: oldName);
    for (final uid in memberUids) {
      await setClassName(uid: uid, className: newName);
    }
    await _update((current) {
      final schoolClass = current.byName(oldName);
      if (schoolClass == null) throw UnknownClassException(oldName);
      _checkName(current, newName, except: oldName);
      return ClassList.sorted([
        for (final c in current.classes)
          if (c.name == oldName) c.copyWith(name: newName) else c,
      ]);
    });
  }

  /// Sets the weekly lessons of class [name] to [lessons]; they are stored
  /// in week order.
  ///
  /// Throws [UnknownClassException] when [name] is not in the list.
  Future<void> setLessons(String name, List<LessonSlot> lessons) =>
      _update((current) {
        final key = name.trim();
        if (!current.contains(key)) throw UnknownClassException(key);
        return ClassList.sorted([
          for (final c in current.classes)
            if (c.name == key) c.copyWith(lessons: lessons) else c,
        ]);
      });

  static void _checkName(ClassList list, String name, {String? except}) {
    if (name.isEmpty) throw ClassNameException(name, taken: false);
    if (list.clashWith(name, except: except) != null) {
      throw ClassNameException(name, taken: true);
    }
  }

  /// Read-modify-write of the doc, the way `GlobalConfigService.setModel`
  /// writes `global`: the stored doc is the base, so a field this build does
  /// not model survives, and the list is worked out from what is stored
  /// now, not from the last poll — a change made on another laptop since
  /// is kept. A doc that is not there yet is created.
  Future<void> _update(ClassList Function(ClassList current) change) async {
    await safeCosmos(() async {
      final stored = await _container.read(_docId, partitionKey: _pk);
      final next = change(ClassList.fromDoc(stored ?? const {}));
      final base = Map<String, dynamic>.from(stored ?? const {})
        // Cosmos owns `_rid`, `_etag`, `_ts`…
        ..removeWhere((k, _) => k.startsWith('_'));
      final doc = <String, dynamic>{
        ...base,
        'id': _docId,
        'type': _pk,
        'classes': next.toMaps(),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await _container.upsert(doc, partitionKey: _pk);
      // The poll would get here within `kCosmosPollInterval`; publishing now
      // means the page shows the change on the next frame.
      state = next;
    });
  }

  Future<ClassList> _fetchOnce() async {
    final doc = await _container.read(_docId, partitionKey: _pk);
    return doc == null ? ClassList.empty : ClassList.fromDoc(doc);
  }
}

/// The class list. Watch it for the list (`null` while it loads); read its
/// notifier to change it, or for [ClassesService.getClasses] — one fresh
/// read — when a decision should not wait on the poll.
final classesServiceProvider = NotifierProvider<ClassesService, ClassList?>(
  ClassesService.new,
);

/// The weekly lessons of one class (#218): what supervision from the
/// timetable (#219) and the lesson badges (#220) ask. `null` while the list
/// loads; empty for a class that is not in the list or has no lessons.
final classLessonsProvider = Provider.family<List<LessonSlot>?, String>(
  (ref, className) => ref.watch(classesServiceProvider)?.lessonsOf(className),
);
