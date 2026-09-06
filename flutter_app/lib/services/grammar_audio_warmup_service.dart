import 'dart:async';

import '../data/grammar_course_catalog.dart';
import 'lesson_speech_service.dart';

/// Starts warming Grammar's short sentence clips after authentication. This
/// reads only frozen local cards and never blocks the auth gate or first frame.
class GrammarAudioWarmupService {
  GrammarAudioWarmupService._();

  static final shared = GrammarAudioWarmupService._();

  void warmForLevel(String rawLevel) {
    final level = GrammarCourseCatalogLevel.normalize(rawLevel);
    final sessions = grammarCourseStarterSessions.where(
      (session) => session.level == level,
    );
    final items = <SpeechItem>[];
    for (final session in sessions) {
      for (var index = 0; index < session.steps.length; index++) {
        final step = session.steps[index];
        final prefix = 'grammar-session:${session.id}:step:$index';
        items.add(
          SpeechItem(
            text: step.target,
            language: 'fr-FR',
            contentItemId: '$prefix:target',
          ),
        );
        if (step.partnerFrench != null) {
          items.add(
            SpeechItem(
              text: step.partnerFrench!,
              language: 'fr-FR',
              contentItemId: '$prefix:partner',
            ),
          );
        }
      }
    }
    if (items.isNotEmpty) {
      unawaited(LessonSpeechService.shared.prewarmNarration(items));
    }
  }
}
