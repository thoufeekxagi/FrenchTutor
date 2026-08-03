import 'dart:typed_data';

/// Fallback for platforms without an on-device text recognizer wired in.
/// Not expected to be hit on iOS/Android; [VisionScanService] treats an
/// empty result as "no OCR hint" rather than an error.
class OcrService {
  Future<String> recognizeText(Uint8List imageBytes) async => '';

  void dispose() {}
}
