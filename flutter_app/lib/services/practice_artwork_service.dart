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
        ? 'Show one clear real-life moment from this learning session.'
        : coverPrompt.trim();
    final ratioInstruction = aspectRatio == '9:16'
        ? 'CUSTOM LISTENING BACKDROP: this is a true vertical 9:16 phone player image. '
              'Ignore every compact-cover, 4:3, square, landscape, card, thumbnail, or crop '
              'instruction in the source context. Compose directly on a 9:16 canvas with '
              'important details inside the central 70% safe area, a clean upper area for '
              'status and controls, and a clean lower area for lyrics and playback controls. '
              'Do not stretch, crop, or zoom a source composition. '
        : '';
    return LessonAgentService.shared.generateStoryCover(
      title: title,
      summary: summary,
      topic: topic,
      levelBand: levelBand,
      variationSeed: id,
      aspectRatio: aspectRatio,
      coverPrompt:
          '$ratioInstruction'
          '$context\n'
          'Create one coherent text-free $aspectRatio story image. A single visible character '
          'is welcome when relevant; keep the character inside the central safe area '
          'with the full face and body visible. Render no text, letters, '
          'numbers, logos, signs, captions, or other typography. Make the composition, '
          'camera angle, dominant subject, and color balance distinct from other '
          'sessions. Use the variation key $id only as an internal visual seed; '
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
    return sync.uploadGeneratedStoryCover(
      storyId: id,
      diagnosticRoleplayId: diagnosticRoleplayId,
      targetAspectRatio: aspectRatio == '9:16' ? 9 / 16 : 4 / 3,
      maxWidth: aspectRatio == '9:16' ? 384 : 512,
      maxHeight: aspectRatio == '9:16' ? 682 : 384,
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
