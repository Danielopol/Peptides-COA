import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../core/config.dart';

/// NOTE: `services/` is reserved for the future auth/billing phase. This MVP
/// adds only file input here (no auth/billing code).

class PickedFile {
  final List<int> bytes;
  final String name;
  final int size;
  const PickedFile(this.bytes, this.name, this.size);
}

class FileInputException implements Exception {
  final String message;
  const FileInputException(this.message);
  @override
  String toString() => message;
}

class FileInput {
  /// Pick a PDF or image via the platform file picker (web + Android).
  static Future<PickedFile?> pickDocument() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConfig.allowedExtensions,
      withData: true, // ensures bytes are available on web
    );
    if (res == null || res.files.isEmpty) return null;
    final f = res.files.first;
    final bytes = f.bytes;
    if (bytes == null) {
      throw const FileInputException('Could not read the file contents.');
    }
    _validate(f.name, bytes.length);
    return PickedFile(bytes, f.name, bytes.length);
  }

  /// Take a photo (Android camera). On platforms without a camera this throws
  /// or returns null gracefully.
  static Future<PickedFile?> pickPhoto() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 90);
    if (x == null) return null;
    final bytes = await x.readAsBytes();
    final name = x.name.isNotEmpty ? x.name : 'photo.jpg';
    _validate(name, bytes.length);
    return PickedFile(bytes, name, bytes.length);
  }

  static void _validate(String name, int size) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (!AppConfig.allowedExtensions.contains(ext)) {
      throw FileInputException('Unsupported file type ".$ext". Use PDF, PNG, JPG, JPEG or WEBP.');
    }
    if (size > AppConfig.maxUploadBytes) {
      throw FileInputException(
          'That file is ${(size / 1024 / 1024).toStringAsFixed(1)} MB — over the 20 MB limit.');
    }
    if (size < 1024) {
      throw const FileInputException('That file is too small to be a valid COA.');
    }
  }
}
