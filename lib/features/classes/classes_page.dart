// Teacher-only "Klassen" page (#218): the school's classes, each with its
// number of students and its weekly lessons.
//
// Left: the class list, and under it the class names that are on students'
// accounts but not in the list yet, each with a button that adds it in one
// click — that is how the classes typed before this page existed (6EWI,
// 6WEWI) come in. Right: the selected class — rename, delete, and its
// lessons, each a weekday and a start and end time in local clock time.
//
// The name is the key (see `school_class.dart`): renaming a class rewrites
// `className` on each of its students' accounts, one `setClassName` per
// account like the bulk assignment on the Students page (#91), and a class
// can only be deleted once nobody is in it any more.
//
// Every change is written at once — there is no Save. The list comes from
// `classesServiceProvider`, which publishes a write as soon as it is made;
// the student counts come from the accounts, polled.

import 'dart:math' as math;

import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/account/account.dart';
import 'package:ai_tutor_python/services/account/account_service.dart';
import 'package:ai_tutor_python/services/classes/classes_service.dart';
import 'package:ai_tutor_python/services/classes/school_class.dart';
import 'package:ai_tutor_python/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// The lesson a class's first "Add lesson" puts in: Monday, a 50-minute
/// period. The teacher sets the real day and times.
const LessonSlot _firstLesson = LessonSlot(
  weekday: DateTime.monday,
  startMinute: 8 * 60 + 30,
  endMinute: 9 * 60 + 20,
);

/// The name of ISO weekday [weekday] (1 = Monday) in the app's language,
/// capitalised: "Maandag", "Monday".
String weekdayName(BuildContext context, int weekday) {
  final tag = Localizations.localeOf(context).toLanguageTag();
  // 1 January 2024 was a Monday.
  final name = DateFormat.EEEE(tag).format(DateTime(2024, 1, weekday));
  return name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
}

class ClassesPage extends ConsumerStatefulWidget {
  const ClassesPage({super.key});

  @override
  ConsumerState<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends ConsumerState<ClassesPage> {
  late final Stream<List<Account>> _accountsStream;

  /// Name of the class open on the right; `null` when none is.
  String? _selected;

  /// A write is in flight: the controls that start another wait for it.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _accountsStream = ref
        .read(accountServiceProvider.notifier)
        .streamAllAccounts();
  }

  ClassesService get _service => ref.read(classesServiceProvider.notifier);

  AccountService get _accounts => ref.read(accountServiceProvider.notifier);

  /// Runs one write with the controls held, and says so when it fails.
  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l.classes_actionFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addClass(ClassList list) async {
    final l = AppLocalizations.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _ClassNameDialog(
        title: l.classes_dialog_new_title,
        initial: '',
        clashWith: (name) => list.clashWith(name)?.name,
      ),
    );
    if (name == null || !mounted) return;
    await _run(() async {
      await _service.addClass(name);
      if (mounted) setState(() => _selected = name);
    });
  }

  /// Adds a class name that is on accounts already (6EWI, 6WEWI), exactly
  /// as it is written there, so those accounts are in the list at once.
  Future<void> _adopt(ClassList list, String name) async {
    final l = AppLocalizations.of(context);
    // "6ewi" on an account while the list has "6EWI": adding it would make
    // two classes that differ only in case. Those students belong in the
    // listed class — the Students page puts them there.
    final clash = list.clashWith(name);
    if (clash != null) {
      _say(l.classes_validation_taken(clash.name));
      return;
    }
    await _run(() async {
      await _service.addClass(name);
      if (mounted) setState(() => _selected = name);
    });
  }

  Future<void> _rename(
    ClassList list,
    SchoolClass schoolClass,
    int count,
  ) async {
    final l = AppLocalizations.of(context);
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _ClassNameDialog(
        title: l.classes_dialog_rename_title,
        initial: schoolClass.name,
        note: l.classes_dialog_rename_note(count),
        clashWith: (name) =>
            list.clashWith(name, except: schoolClass.name)?.name,
      ),
    );
    if (to == null || to == schoolClass.name || !mounted) return;
    // Taken before the first await: the page may be gone by the time the
    // accounts are back, and the rename should still finish.
    final service = _service;
    final accounts = _accounts;
    await _run(() async {
      // The members as they are now, not as the last poll had them: a
      // student put in this class a moment ago moves along too.
      final members = [
        for (final a in await accounts.getAllAccounts())
          if (a.className == schoolClass.name) a.uid,
      ];
      await service.renameClass(
        from: schoolClass.name,
        to: to,
        memberUids: members,
        setClassName: accounts.setClassName,
      );
      if (mounted) setState(() => _selected = to);
    });
  }

  Future<void> _delete(SchoolClass schoolClass) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.classes_delete_dialog_title(schoolClass.name)),
        content: Text(l.classes_delete_dialog_body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.classes_delete_dialog_cancel),
          ),
          FilledButton(
            key: const Key('class-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.classes_delete_dialog_confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final service = _service;
    final accountService = _accounts;
    await _run(() async {
      // Counted again right before the delete: the count on screen can be a
      // poll behind, and a class with students in it may not go.
      final accounts = await accountService.getAllAccounts();
      if (accounts.any((a) => a.className == schoolClass.name)) {
        _say(l.classes_delete_hasStudents(schoolClass.name));
        return;
      }
      await service.removeClass(schoolClass.name);
      if (mounted) setState(() => _selected = null);
    });
  }

  Future<void> _setLessons(SchoolClass schoolClass, List<LessonSlot> lessons) =>
      _run(() => _service.setLessons(schoolClass.name, lessons));

  Future<void> _addLesson(SchoolClass schoolClass) {
    final lessons = schoolClass.lessons;
    // The next lesson is most likely the same period on another day.
    final next = lessons.isEmpty
        ? _firstLesson
        : lessons.last.copyWith(weekday: lessons.last.weekday % 7 + 1);
    return _setLessons(schoolClass, [...lessons, next]);
  }

  Future<void> _replaceLesson(
    SchoolClass schoolClass,
    int index,
    LessonSlot lesson,
  ) => _setLessons(schoolClass, [...schoolClass.lessons]..[index] = lesson);

  Future<void> _deleteLesson(SchoolClass schoolClass, int index) =>
      _setLessons(schoolClass, [...schoolClass.lessons]..removeAt(index));

  /// A time of day from the time picker, in minutes after midnight; `null`
  /// when the teacher cancels. Opens on typing the time — quicker for a
  /// timetable than the dial, which is a tap away — in 24-hour time, the
  /// way the times are stored and the way the school writes them.
  Future<int?> _pickTime(int minute) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  /// A new start keeps the lesson's length: moving a 50-minute lesson from
  /// 08:30 to 10:50 makes it end at 11:40.
  Future<void> _pickStart(
    SchoolClass schoolClass,
    int index,
    LessonSlot lesson,
  ) async {
    final l = AppLocalizations.of(context);
    final start = await _pickTime(lesson.startMinute);
    if (start == null || start == lesson.startMinute || !mounted) return;
    final length = lesson.endMinute - lesson.startMinute;
    final end = math.min(start + length, kMinutesPerDay - 1);
    if (end <= start) {
      _say(l.classes_lesson_endBeforeStart);
      return;
    }
    await _replaceLesson(
      schoolClass,
      index,
      lesson.copyWith(startMinute: start, endMinute: end),
    );
  }

  Future<void> _pickEnd(
    SchoolClass schoolClass,
    int index,
    LessonSlot lesson,
  ) async {
    final l = AppLocalizations.of(context);
    final end = await _pickTime(lesson.endMinute);
    if (end == null || end == lesson.endMinute || !mounted) return;
    if (end <= lesson.startMinute) {
      _say(l.classes_lesson_endBeforeStart);
      return;
    }
    await _replaceLesson(schoolClass, index, lesson.copyWith(endMinute: end));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(classesServiceProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxxl,
        AppSpacing.xxl,
        AppSpacing.xxxl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.classes_page_title,
            style: TextStyle(
              color: AppColors.fg,
              fontSize: 30,
              fontWeight: FontWeight.w700,
              height: 1.15,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.classes_page_subtitle,
            style: TextStyle(
              color: AppColors.fgFaint,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            // The accounts stream is single-subscription (`pollingStream`),
            // so its builder sits outside every conditional branch.
            child: StreamBuilder<List<Account>>(
              stream: _accountsStream,
              builder: (context, snap) {
                if (list == null) {
                  return const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                final accounts = snap.data;
                final counts = <String, int>{};
                for (final a in accounts ?? const <Account>[]) {
                  if (a.className.isEmpty) continue;
                  counts[a.className] = (counts[a.className] ?? 0) + 1;
                }
                final unlisted =
                    counts.keys.where((name) => !list.contains(name)).toList()
                      ..sort(
                        (a, b) => a.toLowerCase().compareTo(b.toLowerCase()),
                      );
                final selected = _selected == null
                    ? null
                    : list.byName(_selected!);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 300,
                      child: _buildList(l, list, counts, unlisted),
                    ),
                    const VerticalDivider(width: 24),
                    Expanded(
                      child: selected == null
                          ? Center(
                              child: Text(
                                l.classes_placeholder,
                                style: TextStyle(color: AppColors.fgFaint),
                              ),
                            )
                          : _buildEditor(
                              l,
                              list,
                              selected,
                              // Unknown until the accounts are in: then
                              // nothing may be deleted yet.
                              count: accounts == null
                                  ? null
                                  : counts[selected.name] ?? 0,
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    AppLocalizations l,
    ClassList list,
    Map<String, int> counts,
    List<String> unlisted,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const Key('classes-new'),
          onPressed: _busy ? null : () => _addClass(list),
          icon: const Icon(Icons.add),
          label: Text(l.classes_button_new),
        ),
        const SizedBox(height: AppSpacing.m),
        Expanded(
          child: ListView(
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                  child: Text(
                    l.classes_list_empty,
                    style: TextStyle(color: AppColors.fgFaint),
                  ),
                ),
              for (final c in list.classes)
                ListTile(
                  key: Key('class-row-${c.name}'),
                  selected: c.name == _selected,
                  title: Text(c.name),
                  subtitle: Text(l.classes_studentCount(counts[c.name] ?? 0)),
                  onTap: () => setState(() => _selected = c.name),
                ),
              if (unlisted.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppColors.accent2,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        l.classes_unlisted_header,
                        style: TextStyle(
                          color: AppColors.fgMute,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final name in unlisted)
                  ListTile(
                    key: Key('class-unlisted-row-$name'),
                    title: Text(name),
                    subtitle: Text(l.classes_studentCount(counts[name] ?? 0)),
                    trailing: TextButton.icon(
                      key: Key('class-adopt-$name'),
                      onPressed: _busy ? null : () => _adopt(list, name),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l.classes_unlisted_add),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(
    AppLocalizations l,
    ClassList list,
    SchoolClass schoolClass, {
    required int? count,
  }) {
    final mayDelete = count == 0;
    return ListView(
      key: const Key('class-editor'),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                schoolClass.name,
                key: const Key('class-editor-name'),
                style: TextStyle(
                  color: AppColors.fg,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              key: const Key('class-rename'),
              tooltip: l.classes_rename_tooltip,
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy || count == null
                  ? null
                  : () => _rename(list, schoolClass, count),
            ),
            // A disabled button shows no tooltip of its own, so the reason
            // it is disabled sits on a Tooltip around it.
            Tooltip(
              message: mayDelete
                  ? l.classes_delete_tooltip
                  : l.classes_delete_blocked_tooltip,
              child: IconButton(
                key: const Key('class-delete'),
                icon: const Icon(Icons.delete_outline),
                onPressed: _busy || !mayDelete
                    ? null
                    : () => _delete(schoolClass),
              ),
            ),
          ],
        ),
        if (count != null)
          Text(
            l.classes_studentCount(count),
            style: TextStyle(color: AppColors.fgFaint, fontSize: 13),
          ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l.classes_lessons_header,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.s),
        if (schoolClass.lessons.isEmpty)
          Text(
            l.classes_lessons_empty,
            style: TextStyle(color: AppColors.fgFaint),
          ),
        for (var i = 0; i < schoolClass.lessons.length; i++)
          _buildLessonRow(l, schoolClass, i),
        const SizedBox(height: AppSpacing.s),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('lesson-add'),
            onPressed: _busy ? null : () => _addLesson(schoolClass),
            icon: const Icon(Icons.add),
            label: Text(l.classes_lesson_add),
          ),
        ),
      ],
    );
  }

  Widget _buildLessonRow(AppLocalizations l, SchoolClass schoolClass, int i) {
    final lesson = schoolClass.lessons[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Tooltip(
            message: l.classes_lesson_weekday_tooltip,
            child: SizedBox(
              width: 160,
              child: DropdownButton<int>(
                key: Key('lesson-weekday-$i'),
                isExpanded: true,
                value: lesson.weekday,
                onChanged: _busy
                    ? null
                    : (day) {
                        if (day == null || day == lesson.weekday) return;
                        _replaceLesson(
                          schoolClass,
                          i,
                          lesson.copyWith(weekday: day),
                        );
                      },
                items: [
                  for (var day = 1; day <= 7; day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text(weekdayName(context, day)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.m),
          Tooltip(
            message: l.classes_lesson_start_tooltip,
            child: OutlinedButton(
              key: Key('lesson-start-$i'),
              onPressed: _busy
                  ? null
                  : () => _pickStart(schoolClass, i, lesson),
              child: Text(lesson.start),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.s),
            child: Text('–'),
          ),
          Tooltip(
            message: l.classes_lesson_end_tooltip,
            child: OutlinedButton(
              key: Key('lesson-end-$i'),
              onPressed: _busy ? null : () => _pickEnd(schoolClass, i, lesson),
              child: Text(lesson.end),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          IconButton(
            key: Key('lesson-delete-$i'),
            tooltip: l.classes_lesson_delete_tooltip,
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : () => _deleteLesson(schoolClass, i),
          ),
        ],
      ),
    );
  }
}

/// Asks for a class name: a new class, or a new name for one. Pops the
/// trimmed name, or nothing when cancelled. Owns its text controller so it
/// is disposed with the dialog, not mid-animation.
class _ClassNameDialog extends StatefulWidget {
  const _ClassNameDialog({
    required this.title,
    required this.initial,
    required this.clashWith,
    this.note,
  });

  final String title;
  final String initial;

  /// The name of the class [name] would clash with, up to case; `null` when
  /// it is free.
  final String? Function(String name) clashWith;

  /// A line under the field: what a rename does to the students.
  final String? note;

  @override
  State<_ClassNameDialog> createState() => _ClassNameDialogState();
}

class _ClassNameDialogState extends State<_ClassNameDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final l = AppLocalizations.of(context);
    final name = _ctrl.text.trim();
    final clash = name.isEmpty ? null : widget.clashWith(name);
    final error = name.isEmpty
        ? l.classes_validation_empty
        : clash != null
        ? l.classes_validation_taken(clash)
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final note = widget.note;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('class-name-input'),
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l.classes_dialog_name_label,
                errorText: _error,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
            if (note != null) ...[
              const SizedBox(height: AppSpacing.m),
              Text(
                note,
                style: TextStyle(color: AppColors.fgMute, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.classes_dialog_cancel),
        ),
        FilledButton(
          key: const Key('class-name-save'),
          onPressed: _save,
          child: Text(l.classes_dialog_save),
        ),
      ],
    );
  }
}
