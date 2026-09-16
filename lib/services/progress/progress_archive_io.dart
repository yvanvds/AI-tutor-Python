// The "choose a file" half of progress export / import (#32), kept behind a
// provider so the flow can be driven without an OS file dialog — a modal the
// Windows shell owns, which no widget or integration test can click.
//
// The bug-report card saves through the same seam (#127): a report a student
// sends to the teacher by chat is a `.txt` written with the same "ask where,
// then write" dialog, so [ProgressArchiveIo.save] takes the extension filter
// as a parameter rather than hard-coding the archive's.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// A file the user picked, with its name for the confirmation message.
typedef ArchiveFile = ({String name, String contents});

abstract class ProgressArchiveIo {
  /// Asks where to write, writes [contents], and returns the path — or null
  /// when the user cancelled. [allowedExtensions] is the dialog's filter,
  /// without the dot; it defaults to the progress archive's.
  Future<String?> save({
    required String suggestedName,
    required String contents,
    List<String> allowedExtensions = const ['json'],
  });

  /// Asks which file to read and returns it, or null when cancelled.
  Future<ArchiveFile?> open();
}

class FilePickerArchiveIo implements ProgressArchiveIo {
  const FilePickerArchiveIo();

  @override
  Future<String?> save({
    required String suggestedName,
    required String contents,
    List<String> allowedExtensions = const ['json'],
  }) async {
    // `saveFile` only returns the chosen path on desktop; writing is ours.
    final path = await FilePicker.platform.saveFile(
      fileName: suggestedName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (path == null) return null;
    await File(path).writeAsString(contents);
    return path;
  }

  @override
  Future<ArchiveFile?> open() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return (name: p.basename(path), contents: await File(path).readAsString());
  }
}

final progressArchiveIoProvider = Provider<ProgressArchiveIo>(
  (_) => const FilePickerArchiveIo(),
);
