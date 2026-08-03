import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Wraps ML Kit's on-device text recognizer (Apple Vision on iOS, ML Kit on
/// Android) behind a single method. One recognizer instance is reused across
/// calls — ML Kit's docs recommend keeping it alive rather than
/// creating/closing per image.
///
/// Callers hand us compressed image bytes (JPEG from the camera, gallery, or
/// a rasterized PDF page), not raw camera-stream planes, so `InputImage`
/// needs a file path (`fromFilePath`) rather than `fromBytes` — the latter is
/// for uncompressed plane data with known width/height/rotation, which we
/// don't have here.
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<String> recognizeText(Uint8List imageBytes) async {
    File? temp;
    try {
      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/ocr_${const Uuid().v4()}.jpg');
      await temp.writeAsBytes(imageBytes, flush: true);
      final result = await _recognizer.processImage(
        InputImage.fromFilePath(temp.path),
      );
      return result.text.trim();
    } catch (_) {
      return '';
    } finally {
      if (temp != null && await temp.exists()) {
        unawaited(temp.delete());
      }
    }
  }

  void dispose() {
    _recognizer.close();
  }
}
