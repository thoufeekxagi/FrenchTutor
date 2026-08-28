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
    final anchor = _visualAnchor(
      title: title,
      summary: summary,
      topic: topic,
      coverPrompt: coverPrompt,
    );
    return LessonAgentService.shared.generateStoryCover(
      title: title,
      summary: summary,
      topic: topic,
      levelBand: levelBand,
      variationSeed: id,
      aspectRatio: aspectRatio,
      coverPrompt: anchor,
    );
  }

  static String _visualAnchor({
    required String title,
    required String summary,
    required String topic,
    String? coverPrompt,
  }) {
    final brief = coverPrompt?.trim() ?? '';
    final candidates = [
      if (brief.isNotEmpty && !_isGenericBrief(brief)) brief,
      title.trim(),
      topic.trim(),
      summary.trim(),
      brief,
    ].where((value) => value.isNotEmpty);
    final source = candidates.isEmpty
        ? 'an everyday learning scene'
        : candidates.first;
    final firstLine = source.split(RegExp(r'[\n.!?]')).first.trim();
    if (firstLine.length <= 240) return firstLine;
    return '${firstLine.substring(0, 237).trimRight()}...';
  }

  static bool _isGenericBrief(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('grounded realistic') ||
        normalized.contains('french language') ||
        normalized.contains('vocabulary set') ||
        normalized.contains('grammar story') ||
        normalized.contains('render no text') ||
        normalized.contains('no people') ||
        normalized.contains('text-free') ||
        normalized.contains('text free') ||
        normalized.contains('short everyday story') ||
        normalized.contains('something related to') ||
        normalized.contains('could happen in daily life') ||
        normalized.contains('create a ') ||
        normalized.contains('create one ');
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
