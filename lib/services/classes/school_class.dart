// The school's classes and their weekly lessons (#218).
//
// One doc, `classes`, in the `config` container (partition `/type`, like
// `global`): per class a `name` and its `lessons`, each lesson a weekday and
// a start and end time. Before this the classes existed nowhere but in the
// free-text `className` on the accounts; the Students and Reports filters
// derived them from there, so a typo made an extra class.
//
// The name stays the key. An account keeps the same text in `className` it
// always had, so nothing is migrated and everything that looks a class up by
// `className` — the filters, the reports, `tooling/evaluation` — works as it
// did. This list only says which names are real and when they have lessons.
//
// Times are LOCAL wall-clock times, never UTC: a lesson at 10:50 stays at
// 10:50 when the clock goes to winter time, which a UTC time would not. The
// laptops run on Belgian time, so comparing against `DateTime.toLocal()` is
// what makes summer and winter time come out right by themselves.
//
// Read by the Classes page and the Students page's class choice, and by
// whatever asks "is this moment in a lesson of class X" — supervision from
// the timetable (#219), the lesson badges (#220): [ClassList.lessonsOf] and
// [ClassList.isDuringLesson], or [LessonSlot.contains] for one lesson.

import 'package:flutter/foundation.dart';

/// Minutes in a day: the first minute that is no longer a time of day.
const int kMinutesPerDay = 24 * 60;

/// `HH:MM` for [minute] minutes after midnight.
String formatClockMinute(int minute) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(minute ~/ 60)}:${two(minute % 60)}';
}

/// Minutes after midnight for an `HH:MM` (or `H:MM`) time of day; `null` for
/// anything else, `24:00` included.
int? parseClockMinute(Object? text) {
  if (text is! String) return null;
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(text);
  if (m == null) return null;
  final hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// One weekly lesson of a class: a weekday and a start and end time of day,
/// in local wall-clock time.
@immutable
class LessonSlot {
  const LessonSlot({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  /// ISO weekday, the way [DateTime.weekday] counts: Monday is 1
  /// ([DateTime.monday]), Sunday is 7.
  final int weekday;

  /// Start, in minutes after local midnight.
  final int startMinute;

  /// End, in minutes after local midnight; after [startMinute]. A lesson
  /// never runs past midnight.
  final int endMinute;

  /// The start as stored, `HH:MM`.
  String get start => formatClockMinute(startMinute);

  /// The end as stored, `HH:MM`.
  String get end => formatClockMinute(endMinute);

  /// A lesson as stored: `{weekday, start, end}`. `null` when it cannot be a
  /// lesson — a weekday outside 1–7, a time that is not `HH:MM`, or an end
  /// that is not after the start (a hand edit in the Cosmos portal, say).
  /// Such an entry is left out: it could match no moment anyway.
  static LessonSlot? fromMap(Object? map) {
    if (map is! Map) return null;
    final weekday = map['weekday'];
    final start = parseClockMinute(map['start']);
    final end = parseClockMinute(map['end']);
    if (weekday is! num || start == null || end == null) return null;
    final day = weekday.toInt();
    if (day != weekday || day < 1 || day > 7 || end <= start) return null;
    return LessonSlot(weekday: day, startMinute: start, endMinute: end);
  }

  Map<String, dynamic> toMap() => {
    'weekday': weekday,
    'start': start,
    'end': end,
  };

  /// Whether [at], in local time, falls in this lesson — from [margin]
  /// before its start to [margin] after its end, both ends included, to the
  /// second.
  ///
  /// [at] may be UTC or local; it is compared as the local wall-clock time it
  /// was, so a Cosmos timestamp (`...Z`) can be passed as parsed. The margin
  /// stays within the lesson's own day: a lesson does not start just after
  /// midnight, so it never has to reach into the day before.
  bool contains(DateTime at, {Duration margin = Duration.zero}) {
    final local = at.toLocal();
    if (local.weekday != weekday) return false;
    final second = local.hour * 3600 + local.minute * 60 + local.second;
    return second >= startMinute * 60 - margin.inSeconds &&
        second <= endMinute * 60 + margin.inSeconds;
  }

  LessonSlot copyWith({int? weekday, int? startMinute, int? endMinute}) =>
      LessonSlot(
        weekday: weekday ?? this.weekday,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );

  /// Week order: by weekday, then by start, then by end.
  static int compare(LessonSlot a, LessonSlot b) {
    final byDay = a.weekday.compareTo(b.weekday);
    if (byDay != 0) return byDay;
    final byStart = a.startMinute.compareTo(b.startMinute);
    if (byStart != 0) return byStart;
    return a.endMinute.compareTo(b.endMinute);
  }

  @override
  bool operator ==(Object other) =>
      other is LessonSlot &&
      other.weekday == weekday &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute;

  @override
  int get hashCode => Object.hash(weekday, startMinute, endMinute);

  @override
  String toString() => 'LessonSlot($weekday $start-$end)';
}

/// One class: its name — the text on its students' accounts — and its
/// weekly lessons.
@immutable
class SchoolClass {
  const SchoolClass({
    required this.name,
    this.lessons = const [],
    this.extra = const {},
  });

  /// The key: the exact text in `className` on its students' accounts.
  final String name;

  /// The weekly lessons, in week order.
  final List<LessonSlot> lessons;

  /// Fields on the stored entry this build does not know. Written back as
  /// they were, so a later build's field survives an edit made with this
  /// one.
  final Map<String, dynamic> extra;

  /// `null` for an entry without a name.
  static SchoolClass? fromMap(Object? map) {
    if (map is! Map) return null;
    final name = map['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final rawLessons = map['lessons'];
    final lessons = <LessonSlot>[
      if (rawLessons is List)
        for (final raw in rawLessons) ?LessonSlot.fromMap(raw),
    ]..sort(LessonSlot.compare);
    return SchoolClass(
      name: name.trim(),
      lessons: List<LessonSlot>.unmodifiable(lessons),
      extra: {
        for (final entry in map.entries)
          if (entry.key != 'name' && entry.key != 'lessons')
            '${entry.key}': entry.value,
      },
    );
  }

  Map<String, dynamic> toMap() => {
    ...extra,
    'name': name,
    'lessons': [for (final lesson in lessons) lesson.toMap()],
  };

  /// Whether [at] falls in one of this class's lessons; see
  /// [LessonSlot.contains].
  bool isDuringLesson(DateTime at, {Duration margin = Duration.zero}) =>
      lessons.any((lesson) => lesson.contains(at, margin: margin));

  SchoolClass copyWith({String? name, List<LessonSlot>? lessons}) =>
      SchoolClass(
        name: name ?? this.name,
        lessons: lessons == null
            ? this.lessons
            : List<LessonSlot>.unmodifiable(
                <LessonSlot>[...lessons]..sort(LessonSlot.compare),
              ),
        extra: extra,
      );

  /// By value, so a poll that brings back the same list changes nothing on
  /// screen (see `ClassesService.updateShouldNotify`). [extra] compares one
  /// level deep: a nested unknown field only ever costs a rebuild.
  @override
  bool operator ==(Object other) =>
      other is SchoolClass &&
      other.name == name &&
      listEquals(other.lessons, lessons) &&
      mapEquals(other.extra, extra);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(lessons));
}

/// Every class the school has: the `classes` doc in the `config` container.
@immutable
class ClassList {
  const ClassList([this.classes = const []]);

  /// No classes: what a database without the doc reads as.
  static const ClassList empty = ClassList();

  /// Sorted by name, case-insensitively.
  final List<SchoolClass> classes;

  /// The doc as stored; a missing or unreadable `classes` field is no
  /// classes. A name that is there twice is kept once (the first).
  factory ClassList.fromDoc(Map<String, dynamic> doc) {
    final raw = doc['classes'];
    final byName = <String, SchoolClass>{};
    if (raw is List) {
      for (final entry in raw) {
        final schoolClass = SchoolClass.fromMap(entry);
        if (schoolClass == null) continue;
        byName.putIfAbsent(schoolClass.name, () => schoolClass);
      }
    }
    return ClassList.sorted(byName.values);
  }

  /// [classes] in name order.
  factory ClassList.sorted(Iterable<SchoolClass> classes) => ClassList(
    List<SchoolClass>.unmodifiable(
      <SchoolClass>[...classes]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    ),
  );

  /// The `classes` field of the doc.
  List<Map<String, dynamic>> toMaps() => [
    for (final schoolClass in classes) schoolClass.toMap(),
  ];

  /// The class names, in list order.
  List<String> get names => [for (final c in classes) c.name];

  bool get isEmpty => classes.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ClassList && listEquals(other.classes, classes);

  @override
  int get hashCode => Object.hashAll(classes);

  /// The class called exactly [name] (leading and trailing spaces aside).
  SchoolClass? byName(String name) {
    final key = name.trim();
    for (final schoolClass in classes) {
      if (schoolClass.name == key) return schoolClass;
    }
    return null;
  }

  /// Whether [name] is a class in the list — what an account's `className`
  /// is checked against.
  bool contains(String name) => byName(name) != null;

  /// The class whose name is [name] up to case — what a new or renamed class
  /// may not be called, so "6ewi" cannot sit next to "6EWI" — leaving out
  /// the class called [except] (the one being renamed).
  SchoolClass? clashWith(String name, {String? except}) {
    final key = name.trim().toLowerCase();
    for (final schoolClass in classes) {
      if (schoolClass.name == except) continue;
      if (schoolClass.name.toLowerCase() == key) return schoolClass;
    }
    return null;
  }

  /// The weekly lessons of class [className]; none for a class that is not
  /// in the list, or that has no lessons.
  List<LessonSlot> lessonsOf(String className) =>
      byName(className)?.lessons ?? const [];

  /// Whether [at] falls in a lesson of class [className], [margin] before
  /// and after each lesson included. `false` for a student without a class
  /// (`''`), a class that is not in the list, or one without lessons.
  bool isDuringLesson(
    String className,
    DateTime at, {
    Duration margin = Duration.zero,
  }) => byName(className)?.isDuringLesson(at, margin: margin) ?? false;
}
