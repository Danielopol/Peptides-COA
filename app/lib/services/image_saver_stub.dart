import 'dart:typed_data';

/// Non-web fallback: no file-system export wired yet. The share screen falls
/// back to a "screenshot to share" hint when this returns false.
Future<bool> savePng(Uint8List bytes, String filename) async => false;
