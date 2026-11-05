import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smriti_assist/services/image_shrink.dart';

void main() {
  Uint8List noisyPng(int side) {
    final r = Random(1);
    final im = img.Image(width: side, height: side);
    for (final p in im) {
      p
        ..r = r.nextInt(256)
        ..g = r.nextInt(256)
        ..b = r.nextInt(256);
    }
    return Uint8List.fromList(img.encodePng(im));
  }

  test('a small photo is returned untouched', () async {
    final small = Uint8List.fromList(List.filled(1000, 7));
    expect(identical(await shrinkPhoto(small), small), isTrue);
  });

  test('a large photo is shrunk to fit under the server limit', () async {
    final big = noisyPng(900); // random noise: a very large PNG
    expect(big.length, greaterThan(kMaxChatPhotoBytes));
    final out = await shrinkPhoto(big);
    expect(out, isNotNull);
    expect(out!.length, lessThanOrEqualTo(kMaxChatPhotoBytes));
    expect(img.decodeImage(out), isNotNull, reason: 'still a valid image');
  });

  test('something that is not an image and is too big gives null, not a crash', () async {
    expect(await shrinkPhoto(Uint8List(kMaxChatPhotoBytes + 10)), isNull);
  });
}
