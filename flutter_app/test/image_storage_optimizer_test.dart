import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:french_tutor/services/image_storage_optimizer.dart';

void main() {
  test('cover optimizer resizes and emits compact JPEG bytes', () {
    final image = img.Image(width: 1200, height: 1800);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
      }
    }
    final source = img.encodeJpg(image, quality: 100);
    final optimized = ImageStorageOptimizer.optimizeCover(
      Uint8List.fromList(source),
    );
    final decoded = img.decodeImage(optimized)!;

    expect(decoded.width, lessThanOrEqualTo(ImageStorageOptimizer.maxWidth));
    expect(decoded.height, lessThanOrEqualTo(ImageStorageOptimizer.maxHeight));
    expect(
      decoded.width / decoded.height,
      closeTo(ImageStorageOptimizer.targetAspectRatio, 0.01),
    );
    expect(optimized[0], 0xff);
    expect(optimized[1], 0xd8);
    expect(optimized.length, lessThanOrEqualTo(ImageStorageOptimizer.maxBytes));
    expect(optimized.length, lessThan(source.length));
  });

  test('optimizer keeps empty input safe', () {
    expect(ImageStorageOptimizer.optimizeCover(Uint8List(0)), isEmpty);
  });

  test(
    'listening backdrop preserves true 9:16 composition at a larger budget',
    () {
      final image = img.Image(width: 1080, height: 1920);
      for (var y = 0; y < image.height; y += 4) {
        for (var x = 0; x < image.width; x += 4) {
          image.setPixelRgb(x, y, (x + y) % 256, y % 256, x % 256);
        }
      }
      final optimized = ImageStorageOptimizer.optimizeArtwork(
        Uint8List.fromList(img.encodeJpg(image, quality: 100)),
        maxBytes: 160 * 1024,
        targetAspectRatio: 9 / 16,
        maxWidth: 768,
        maxHeight: 1365,
      );
      final decoded = img.decodeImage(optimized)!;

      expect(decoded.width / decoded.height, closeTo(9 / 16, 0.01));
      expect(decoded.width, lessThanOrEqualTo(768));
      expect(decoded.height, lessThanOrEqualTo(1365));
      expect(optimized.length, lessThanOrEqualTo(160 * 1024));
    },
  );

  test('optimizer never uploads undecodable bytes as a raw image', () {
    expect(
      () => ImageStorageOptimizer.optimizeCover(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
