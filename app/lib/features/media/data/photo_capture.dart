import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Taking a photo that is safe to store.
///
/// TWO SETTINGS, TWO PURPOSES. PhotoSnap already captures at 1024px/80 because
/// it is feeding a vision model with a request-size guard. A photo we KEEP is a
/// different job: it is rendered back to the user, sometimes years later, so it
/// gets more resolution — and it must be a real JPEG, because the bucket's
/// allowlist validates the Content-Type we declare rather than the bytes we
/// send (measured in #160). Re-encoding is the only thing that makes that
/// declaration honest.
class PhotoCapture {
  const PhotoCapture({ImagePicker? picker})
      : _picker = picker; // ignore: prefer_initializing_formals
  final ImagePicker? _picker;

  /// Longest edge for a stored photo.
  ///
  /// Enough to fill a phone screen and stand being cropped; small enough that
  /// a queued photo is a nuisance rather than a bill on Indian mobile data.
  static const maxEdge = 1200.0;

  /// JPEG quality. High enough that skin and food do not band, low enough that
  /// a typical capture lands well under a megabyte.
  static const quality = 85;

  /// Capture and write it into [directory] under a generated [name].
  ///
  /// Returns the file, or null if the user backed out. THE PICKER DOES THE
  /// RE-ENCODE: `imageQuality` re-compresses to JPEG, which is what turns a
  /// HEIC from an iPhone camera into something our `.jpg` naming and
  /// `image/jpeg` declaration are actually true about.
  Future<File?> capture({
    required Directory directory,
    required String name,
    ImageSource source = ImageSource.camera,
  }) async {
    try {
      final picked = await (_picker ?? ImagePicker()).pickImage(
        source: source,
        maxWidth: maxEdge,
        maxHeight: maxEdge,
        imageQuality: quality,
      );
      if (picked == null) return null;

      // COPIED, not referenced. The picker hands back a file in a cache the OS
      // may clear at any moment, and the queue's whole job is to survive the
      // gap between capture and upload.
      final dest = File('${directory.path}/$name');
      await dest.writeAsBytes(await picked.readAsBytes(), flush: true);
      return dest;
    } catch (e) {
      debugPrint('photo capture failed: $e');
      return null;
    }
  }
}
