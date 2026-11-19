// What the first-start choice, Options and the stand-alone key screen share
// about the school file (#307): pick it, check it, store it, and say what
// happened. Switching mode takes a restart; the dialog says so.

import 'package:ai_tutor_python/core/app_start.dart';
import 'package:ai_tutor_python/core/school_file.dart';
import 'package:ai_tutor_python/core/app_mode.dart';
import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user is told about a refused school file.
String schoolFileProblemText(AppLocalizations l, SchoolFileException e) =>
    switch (e.problem) {
      SchoolFileProblem.unreadable => l.schoolFile_error_unreadable,
      SchoolFileProblem.notASchoolFile => l.schoolFile_error_notASchoolFile,
      SchoolFileProblem.newerFormat => l.schoolFile_error_newerFormat,
      SchoolFileProblem.invalidField => l.schoolFile_error_invalidField(
        e.field ?? '',
      ),
      SchoolFileProblem.containsSecret => l.schoolFile_error_containsSecret(
        e.field ?? '',
      ),
    };

/// The outcome of [pickAndImportSchoolFile].
sealed class SchoolFileImport {
  const SchoolFileImport();
}

/// Stored; the next start is in [school]'s mode.
final class SchoolFileImported extends SchoolFileImport {
  const SchoolFileImported(this.school);
  final SchoolConfig school;
}

/// The user closed the dialog without a file.
final class SchoolFileCancelled extends SchoolFileImport {
  const SchoolFileCancelled();
}

/// Refused; nothing changed.
final class SchoolFileRefused extends SchoolFileImport {
  const SchoolFileRefused(this.error);
  final SchoolFileException error;
}

/// Asks for a school file and, when the app can use it, stores it.
Future<SchoolFileImport> pickAndImportSchoolFile(WidgetRef ref) async {
  try {
    final text = await ref.read(schoolFilePickerProvider)();
    if (text == null) return const SchoolFileCancelled();
    final school = await importSchoolFile(
      text,
      store: ref.read(schoolFileStoreProvider),
      prefs: await SharedPreferences.getInstance(),
    );
    return SchoolFileImported(school);
  } on SchoolFileException catch (e) {
    return SchoolFileRefused(e);
  }
}

/// From a running app (Options, the key screen): import, then say that the
/// app has to start again — or why the file was refused.
Future<void> importSchoolFileAndAskRestart(
  BuildContext context,
  WidgetRef ref,
) async {
  final result = await pickAndImportSchoolFile(ref);
  if (!context.mounted) return;
  final l = AppLocalizations.of(context);
  switch (result) {
    case SchoolFileCancelled():
      return;
    case SchoolFileRefused(:final error):
      await showSchoolFileMessage(
        context,
        title: null,
        text: schoolFileProblemText(l, error),
        key: const Key('school-file-refused'),
      );
    case SchoolFileImported(:final school):
      await showSchoolFileMessage(
        context,
        title: l.schoolFile_restart_title,
        text: l.schoolFile_restart_imported(school.schoolName ?? ''),
        key: const Key('school-file-restart'),
      );
  }
}

/// A plain message with an OK button.
Future<void> showSchoolFileMessage(
  BuildContext context, {
  required String? title,
  required String text,
  Key? key,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    key: key,
    title: title == null ? null : Text(title),
    content: Text(text),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(AppLocalizations.of(context).schoolFile_restart_ok),
      ),
    ],
  ),
);
