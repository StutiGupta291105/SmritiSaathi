
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The server refuses chat photos over 600 000 bytes, and a refused message is
/// dropped for good. So a photo is made small enough *before* it is queued.
const int kMaxChatPhotoBytes = 450000;

/// Returns [bytes] unchanged when they already fit; otherwise a JPEG, scaled
/// down step by step until it fits. Returns null if it cannot be made to fit
/// (or is not an image), so the caller can tell the person instead of losing it.
Future<Uint8List?> shrinkPhoto(Uint8List bytes,
    {int maxBytes = kMaxChatPhotoBytes}) async {
  if (bytes.length <= maxBytes) return bytes;
  return compute(_shrink, (bytes, maxBytes));
}

Uint8List? _shrink((Uint8List, int) a) {
  final decoded = img.decodeImage(a.$1);
  if (decoded == null) return null;
  var side = decoded.width > decoded.height ? decoded.width : decoded.height;
  var quality = 80;
  for (var i = 0; i < 8; i++) {
    final target = side > 1024 ? 1024 : side;
    final scaled = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: target)
        : img.copyResize(decoded, height: target);
    final out = Uint8List.fromList(img.encodeJpg(scaled, quality: quality));
    if (out.length <= a.$2) return out;
    side = (target * 0.75).round();
    quality = quality > 50 ? quality - 10 : quality;
    if (side < 96) break;
  }
  return null;
}
