import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_tutor/services/ocr/ocr_service.dart';

void main() {
  test('V3 OCR stays disabled while Photo Tutor is deferred to V4', () async {
    final service = OcrService();
    expect(await service.recognizeText(Uint8List(0)), isEmpty);
    service.dispose();
  });
}
