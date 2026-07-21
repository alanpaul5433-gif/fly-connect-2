import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

/// Resizes an image to a sensible upload size before it hits Firebase
/// Storage / Firestore.
///
/// Phone cameras now routinely produce 12 MP / 8 MB files. Posting one
/// of those as a profile photo (rendered in a 40 px circle) wastes the
/// user's data, our bandwidth bill, and CDN cache. We resize so the
/// **longest edge** is at most [maxDimension] pixels, preserving aspect
/// ratio. PNG output (no JPEG encoder in dart:ui without an extra dep).
///
/// If anything throws (corrupt bytes, OOM, etc.) we return the original
/// bytes unchanged — better to upload a big file than fail the upload.
///
/// Typical numbers:
///   • 4032×3024 JPEG (~5 MB) → 1600×1200 PNG (~600–800 KB)
///   • Already-small images pass through.
Future<Uint8List> compressForUpload(
  Uint8List bytes, {
  int maxDimension = 1600,
}) async {
  try {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxDimension,
      // If we set both targetWidth and targetHeight, dart:ui will scale
      // each dimension independently, distorting the image. We only set
      // width here — when the image is portrait, see the post-decode
      // resize fallback below.
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // If the image is portrait, the width-targeted decode may still
    // leave the height above maxDimension. Detect and do a second pass
    // by re-encoding via a PictureRecorder at the right dimensions.
    if (image.height > maxDimension) {
      final ratio = maxDimension / image.height;
      final newW = (image.width * ratio).round();
      final newH = maxDimension;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, newW.toDouble(), newH.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final resized = await picture.toImage(newW, newH);
      final png = await resized.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      resized.dispose();
      image.dispose();
      if (png != null) return png.buffer.asUint8List();
      return bytes;
    }

    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png != null) return png.buffer.asUint8List();
    return bytes;
  } catch (e) {
    debugPrint('[compressForUpload] failed, using original: $e');
    return bytes;
  }
}
