import 'dart:typed_data';

/// V3 no-op implementation. The OCR engine is deferred to V4.
class OcrService {
  Future<String> recognizeText(Uint8List imageBytes) async => '';

  void dispose() {}
}
