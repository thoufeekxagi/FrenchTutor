import 'dart:typed_data';

import 'lesson_agent_service.dart';
import 'sync_service.dart';

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
    String aspectRatio = '4:3',
  }) {
    final context = coverPrompt == null || coverPrompt.trim().isEmpty
        ? 'Show the exact everyday place, objects, and action named by this learning session. Use a friendly book-reference composition; do not invent a protagonist or unrelated cinematic setting.'
        : coverPrompt.trim();
    final ratioInstruction = switch (aspectRatio) {
      '9:16' =>
        'CUSTOM LISTENING BACKDROP: this is a true vertical 9:16 phone player image. '
            'Ignore every compact-cover, 4:3, portrait-card, square, landscape, thumbnail, or crop '
            'instruction in the source context. Compose directly on a 9:16 canvas with '
            'important details inside the central 70% safe area, a clean upper area for '
            'status and controls, and a clean lower area for lyrics and playback controls. '
            'Do not stretch, crop, or zoom a source composition. ',
      '2:3' =>
        'CUSTOM READING COVER: this is a portrait 2:3 book-reference image. '
            'Ignore landscape and 4:3 instructions in the source context. '
            'Keep the concrete story objects and action readable in the central safe area. ',
      _ => '',
    };
    return LessonAgentService.shared.generateStoryCover(
      title: title,
      summary: summary,
      topic: topic,
      levelBand: levelBand,
      variationSeed: id,
      aspectRatio: aspectRatio,
      coverPrompt:
          '$ratioInstruction'
          'LESSON VISUAL BRIEF: $context\n'
          'Create one coherent text-free $aspectRatio learning reference image. Match the lesson title, summary, topic, '
          'and brief exactly. People are optional and only belong if the lesson requires them; never add a generic hero, '
          'futuristic city, dramatic stranger, fantasy scene, or unrelated landmark. Keep important visual details inside '
          'the central safe area. Render no text, letters, '
          'numbers, logos, signs, captions, or other typography. Make the composition, '
          'camera angle, dominant subject, and color balance distinct from other sessions while staying semantically faithful. '
          'Use the variation key $id only as an internal visual seed; '
          'never render it.',
    );
  }

  /// Shared generation and storage path for every practice session. There are
  /// exactly two provider attempts: attempt one must compress to 25 KB; only
  /// the regeneration attempt may use the 40 KB ceiling.
  static Future<String?> generateAndUpload({
    required SyncService sync,
    required String id,
    required String title,
    required String summary,
    required String topic,
    required String levelBand,
    String? coverPrompt,
    String? diagnosticRoleplayId,
    String aspectRatio = '4:3',
  }) {
    final targetAspectRatio = switch (aspectRatio) {
      '2:3' => 2 / 3,
      '9:16' => 9 / 16,
      _ => 4 / 3,
    };
    final maxWidth = switch (aspectRatio) {
      '2:3' => 384,
      '9:16' => 384,
      _ => 512,
    };
    final maxHeight = switch (aspectRatio) {
      '2:3' => 576,
      '9:16' => 682,
      _ => 384,
    };
    return sync.uploadGeneratedStoryCover(
      storyId: id,
      diagnosticRoleplayId: diagnosticRoleplayId,
      targetAspectRatio: targetAspectRatio,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      generate: (attempt) => generate(
        id: '$id-attempt-${attempt + 1}',
        title: title,
        summary: summary,
        topic: topic,
        levelBand: levelBand,
        coverPrompt: coverPrompt,
        aspectRatio: aspectRatio,
      ),
    );
  }

  /// Generates independent portrait artwork for the full-screen listening
  /// player. The object is intentionally separate from the compact cover.
  static Future<String?> generateListeningBackgroundAndUpload({
    required SyncService sync,
    required String id,
    required String title,
    required String summary,
    required String topic,
    required String levelBand,
    String? coverPrompt,
  }) {
    return sync.uploadGeneratedStoryCover(
      storyId: id,
      storageSuffix: '-listening',
      targetAspectRatio: 9 / 16,
      maxWidth: 768,
      maxHeight: 1365,
      maxBytes: 160 * 1024,
      retryMaxBytes: 240 * 1024,
      generate: (attempt) => generate(
        id: '$id-music-attempt-${attempt + 1}',
        title: title,
        summary: summary,
        topic: topic,
        levelBand: levelBand,
        coverPrompt: coverPrompt,
        aspectRatio: '9:16',
      ),
    );
  }

  /// Backward-compatible name for callers that still explicitly request a
  /// music backdrop.
  static Future<String?> generateMusicBackgroundAndUpload({
    required SyncService sync,
    required String id,
    required String title,
    required String summary,
    required String topic,
    required String levelBand,
    String? coverPrompt,
  }) {
    return generateListeningBackgroundAndUpload(
      sync: sync,
      id: id,
      title: title,
      summary: summary,
      topic: topic,
      levelBand: levelBand,
      coverPrompt: coverPrompt,
    );
  }
}
