import 'dart:typed_data';

/// Fallback OCR implementation. V3 deliberately returns no OCR text on every
/// platform while Photo Tutor is deferred to V4.
class OcrService {
  Future<String> recognizeText(Uint8List imageBytes) async => '';

  void dispose() {}
}
