import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Converts generated story artwork into a small, predictable Storage object.
/// Artwork is normalized to the shared 4:3 card ratio before compression, so
/// provider-specific aspect ratios never leak into the learner experience.
abstract final class ImageStorageOptimizer {
  static const targetAspectRatio = 4 / 3;
  static const maxWidth = 512;
  static const maxHeight = 384;
  static const maxBytes = 25 * 1024;
  static const _qualities = [72, 65, 58, 52, 46, 40, 34, 28, 20, 12, 5, 1];
  static const _scaleSteps = [
    1.0,
    0.9,
    0.8,
    0.7,
    0.6,
    0.5,
    0.4,
    0.33,
    0.25,
    0.2,
    0.15,
    0.1,
    0.075,
    0.05,
  ];

  static Uint8List optimizeCover(Uint8List source, {int maxBytes = 25 * 1024}) {
    if (source.isEmpty) return source;
    try {
      final decoded = img.decodeImage(source);
      if (decoded == null) {
        throw const FormatException('Generated cover is not a decodable image');
      }

      // Providers can return a portrait or square image even when the prompt
      // requests landscape. Normalize at the storage boundary so every card
      // receives the same 4:3 artwork contract.
      final cropped = _cropToAspectRatio(decoded);
      final baseScale = _scaleFor(cropped.width, cropped.height);
      Uint8List? smallest;
      for (final scaleStep in _scaleSteps) {
        final scale = baseScale * scaleStep;
        final resized = img.copyResize(
          cropped,
          width: (cropped.width * scale).round().clamp(1, maxWidth).toInt(),
          height: (cropped.height * scale).round().clamp(1, maxHeight).toInt(),
          interpolation: img.Interpolation.linear,
        );
        for (final quality in _qualities) {
          final candidate = Uint8List.fromList(
            img.encodeJpg(resized, quality: quality),
          );
          if (smallest == null || candidate.length < smallest.length) {
            smallest = candidate;
          }
          if (candidate.length <= maxBytes) return candidate;
        }
      }

      final result = smallest;
      if (result == null || result.length > maxBytes) {
        throw const FormatException(
          'Generated cover could not be reduced below the storage limit',
        );
      }
      return result;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Generated cover optimization failed: $error');
    }
  }

  static double _scaleFor(int width, int height) {
    final widthScale = maxWidth / width;
    final heightScale = maxHeight / height;
    final scale = widthScale < heightScale ? widthScale : heightScale;
    return scale < 1 ? scale : 1;
  }

  static img.Image _cropToAspectRatio(img.Image source) {
    final sourceAspectRatio = source.width / source.height;
    if ((sourceAspectRatio - targetAspectRatio).abs() < 0.001) {
      return source;
    }

    if (sourceAspectRatio > targetAspectRatio) {
      final cropWidth = (source.height * targetAspectRatio).round();
      return img.copyCrop(
        source,
        x: (source.width - cropWidth) ~/ 2,
        y: 0,
        width: cropWidth,
        height: source.height,
      );
    }

    final cropHeight = (source.width / targetAspectRatio).round();
    return img.copyCrop(
      source,
      x: 0,
      y: (source.height - cropHeight) ~/ 2,
      width: source.width,
      height: cropHeight,
    );
  }
}
