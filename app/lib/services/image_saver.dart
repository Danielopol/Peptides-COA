import 'dart:typed_data';

import 'image_saver_stub.dart'
    if (dart.library.js_interop) 'image_saver_web.dart' as impl;

/// Save/export a PNG. On web this triggers a browser download; on other
/// platforms it's a no-op for now (returns false so the UI can fall back to a
/// "screenshot to share" hint). Returns true when the save was handled.
Future<bool> savePng(Uint8List bytes, String filename) =>
    impl.savePng(bytes, filename);
