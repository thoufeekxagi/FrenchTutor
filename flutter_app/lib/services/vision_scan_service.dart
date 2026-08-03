import 'dart:typed_data';

import 'lesson_agent_service.dart';
import 'ocr/ocr_service.dart';

/// Result of scanning one image: what on-device OCR read off it (may be
/// empty — OCR failure never blocks the Gemini reply) and Marie's reply.
class VisionScanResult {
  const VisionScanResult({required this.ocrText, required this.reply});

  final String ocrText;
  final String reply;

  /// Text worth remembering for the next scan in the same session (chat
  /// history / mid-call injection) — prefers the reply, since it's already
  /// the digested, corrected version of whatever the OCR text said.
  String get summaryForContext => reply.isNotEmpty ? reply : ocrText;
}

/// Single seam both the single-shot Scan chat and the mid-call photo
/// injection go through: run on-device OCR and Gemini image understanding
/// concurrently, then merge. Kept as one small orchestrator so neither call
/// site has to re-implement the OCR+Gemini merge itself.
class VisionScanService {
  VisionScanService({LessonAgentService? agent, OcrService? ocr})
    : _agent = agent ?? LessonAgentService.shared,
      _ocr = ocr ?? OcrService();

  final LessonAgentService _agent;
  final OcrService _ocr;

  Future<VisionScanResult> scan({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
    String? conversationContext,
  }) async {
    // OCR runs first (on-device, typically well under a second) so its text
    // can travel as a correction hint inside the SAME Gemini request, rather
    // than firing two independent calls the caller would have to reconcile.
    // OCR failure is swallowed — it's a hint, not a dependency.
    final ocrText = await _ocr.recognizeText(imageBytes);
    final reply = await _agent.describeImage(
      imageBytes: imageBytes,
      mimeType: mimeType,
      ocrHint: ocrText,
      conversationContext: conversationContext,
    );
    return VisionScanResult(ocrText: ocrText, reply: reply);
  }

  void dispose() => _ocr.dispose();
}
