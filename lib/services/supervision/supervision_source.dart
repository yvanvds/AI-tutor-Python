// The seam through which the tutor learns whether a student worked under
// classroom supervision (#100): whether a graded answer is `supervised` or
// `home` evidence, and so whether the supervised weight factor applies.
//
// Supervised means *in the lesson time of the student's class* (#219). The
// class on the student's account (`className`) has weekly lessons in the
// `config/classes` doc (#218); an answer whose moment, in the laptop's local
// time, falls in one of them — from [ScheduleSupervisionSource.margin]
// before the lesson starts to the same margin after it ends — is supervised.
// Students work seriously in the lesson and do not use a chatbot there; the
// data bears the line out (in September 97% of one class's oefeningen and 94%
// of the other's fell in lesson time, the rest in the evening or the
// weekend). Where the student was does not matter: no IP address, no
// network. A sick student who practises at home during the lesson counts as
// lesson time too — that they practise at all then is the point.
//
// Everything else is `home`: outside lesson time, a student without a class,
// a class without lessons, or a schedule that cannot be read. The fail-safe
// direction is "no extra weight", never "assume supervised". The tutor asks
// one question per graded turn and keeps no toggle of its own, so nobody can
// forget to switch supervision off before the evening's homework.
//
// The signal was once to come from Anchor's focus sessions (#106); the
// timetable replaced that. [NoSupervisionSource] is the source without a
// registry — every turn `home`, and it says so through
// [SupervisionSource.isWiredFor] (#160) — kept for tests that need the
// unweighted path.

import 'package:ai_tutor_python/core/cosmos_safety.dart';
import 'package:ai_tutor_python/core/evidence_provenance.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/classes/classes_service.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class SupervisionSource {
  const SupervisionSource();

  /// Whether the provenance this source gives a student of class
  /// [className] is a measurement (#160).
  ///
  /// While it is `false` every turn of that student is `home` by
  /// construction, so a supervised/home split is not a measurement and
  /// nothing may present it as one: the grade justification prompt leaves
  /// the split out and does not ask the model to name it, and the Reports
  /// pane leaves the tally off its reliability line (#173). The timetable
  /// source answers `true` once the class has lessons, and the split is
  /// back without anyone having to remember it.
  bool isWiredFor(String className);

  /// Provenance of evidence produced by [uid] at [at].
  ///
  /// Implementations answer per student, not per class hour. A failure to
  /// look the answer up must resolve to [EvidenceProvenance.home] — the
  /// fail-safe direction is "no extra weight", never "assume supervised".
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  });

  /// [provenanceFor] at each of [ats], in order: the grade proposal's tally
  /// of a whole grading window (#219). The timetable source looks the
  /// student's class up once for all of them; this default asks
  /// [provenanceFor] once per moment.
  Future<List<EvidenceProvenance>> provenancesFor({
    required String uid,
    required List<DateTime> ats,
  }) => Future.wait([for (final at in ats) provenanceFor(uid: uid, at: at)]);
}

/// No supervision registry: every turn is home work.
class NoSupervisionSource extends SupervisionSource {
  const NoSupervisionSource();

  @override
  bool isWiredFor(String className) => false;

  @override
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  }) async => EvidenceProvenance.home;
}

/// Supervision from the timetable (#219): an answer is `supervised` when it
/// falls in a lesson of the student's class, [margin] before and after
/// included, compared in local time ([LessonSlot.contains]).
class ScheduleSupervisionSource extends SupervisionSource {
  ScheduleSupervisionSource({
    required this.classNameOf,
    required this.readClasses,
    required this.cachedClasses,
  });

  /// How long before a lesson starts and after it ends an answer still
  /// counts as lesson time: the student who opens the app in the corridor,
  /// or finishes the exercise after the bell.
  static const Duration margin = Duration(minutes: 10);

  /// The class on [uid]'s account (`className`), `''` for none.
  final Future<String> Function(String uid) classNameOf;

  /// One read of the class list, now.
  final Future<ClassList> Function() readClasses;

  /// The class list as last polled, `null` while it is not known yet: what
  /// the synchronous [isWiredFor] reads.
  final ClassList? Function() cachedClasses;

  /// The rule itself: `supervised` when [at] falls in a lesson of class
  /// [className] in [classes], [margin] included. A student without a class,
  /// a class that is not in the list or one without lessons is `home`.
  static EvidenceProvenance provenanceAt(
    ClassList classes,
    String className,
    DateTime at,
  ) => classes.isDuringLesson(className, at, margin: margin)
      ? EvidenceProvenance.supervised
      : EvidenceProvenance.home;

  /// A class with lessons: its students' turns can come out either way.
  /// Before the list is known it is not wired — the split is left out
  /// rather than claimed.
  @override
  bool isWiredFor(String className) =>
      cachedClasses()?.lessonsOf(className).isNotEmpty ?? false;

  @override
  Future<EvidenceProvenance> provenanceFor({
    required String uid,
    required DateTime at,
  }) async => (await provenancesFor(uid: uid, ats: [at])).single;

  @override
  Future<List<EvidenceProvenance>> provenancesFor({
    required String uid,
    required List<DateTime> ats,
  }) async {
    final home = List.filled(ats.length, EvidenceProvenance.home);
    if (ats.isEmpty) return home;
    try {
      final className = (await classNameOf(uid)).trim();
      // No class, no lessons: nothing to read.
      if (className.isEmpty) return home;
      final classes = await readClasses();
      return [for (final at in ats) provenanceAt(classes, className, at)];
    } catch (e) {
      debugPrint('ScheduleSupervisionSource: lookup for $uid failed: $e');
      return home;
    }
  }
}

/// The registry the tutor consults when integrating a graded answer, and the
/// grade proposal when it tallies a period's oefeningen: the timetable
/// (#219). Override it with a fake in tests.
///
/// The class list is read once per question, not polled: on a student's
/// laptop nothing else watches it, and one read per graded answer is less
/// than a poll every few seconds. [isWiredFor] reads the polled list the
/// teacher's pages keep (`classesServiceProvider`).
final supervisionSourceProvider = Provider<SupervisionSource>(
  (ref) => ScheduleSupervisionSource(
    classNameOf: (uid) async {
      // The signed-in student's own account is polled already.
      final own = ref.read(accountServiceProvider);
      if (own != null && own.uid == uid) return own.className;
      final account = await ref
          .read(accountServiceProvider.notifier)
          .getAccount(uid);
      return account?.className ?? '';
    },
    readClasses: () => safeCosmos(() => ClassesService.readOnce()),
    cachedClasses: () => ref.read(classesServiceProvider),
  ),
);
