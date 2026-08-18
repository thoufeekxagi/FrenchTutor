import 'dart:typed_data';

import 'lesson_agent_service.dart';

/// The single artwork boundary used by every generated practice library.
///
/// Keeping the scene brief and the variation seed here means a new lab does
/// not need to invent its own image prompt or accidentally fall back to a
/// repeated starter image. The low-level AI call remains in
/// [LessonAgentService]; this class owns the cross-session visual contract.
class PracticeArtworkService {
  const PracticeArtworkService._();

  static Future<Uint8List> generate({
    required String id,
    required String title,
    required String summary,
    required String topic,
    required String levelBand,
    String? coverPrompt,
  }) {
    final context = coverPrompt == null || coverPrompt.trim().isEmpty
        ? 'Show one clear real-life moment from this learning session.'
        : coverPrompt.trim();
    return LessonAgentService.shared.generateStoryCover(
      title: title,
      summary: summary,
      topic: topic,
      levelBand: levelBand,
      variationSeed: id,
      coverPrompt:
          '$context\n'
          'Create a single image only. Make the composition, camera angle, '
          'dominant subject, and color balance distinct from other sessions. '
          'Use the variation key $id only as an internal visual seed; never '
          'render it or any other text in the image.',
    );
  }
}
