// Test stand-in for the plugin behind `FilePicker.platform` (#85). The goals
// page calls `FilePicker.platform.pickFiles` directly, and the real
// implementation opens an OS-owned dialog no widget or integration test can
// click. This fake "picks" a fixed path immediately; reading the file stays
// real, so a test exercises the same parse path a teacher does.

import 'package:file_picker/file_picker.dart';

class FakeFilePicker extends FilePicker {
  FakeFilePicker(this.path);

  /// The file every pick "chooses".
  String path;

  /// Installs this fake as the process-wide `FilePicker.platform`.
  void install() => FilePicker.platform = this;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([PlatformFile(name: 'goals.json', size: 0, path: path)]);
}
