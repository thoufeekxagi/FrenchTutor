import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_keys.dart';
import '../design/app_router.dart';
import '../models/tutor_persona.dart';
import '../providers/database_provider.dart';
import '../screens/session/session_screen.dart';
import 'ai_session_gate.dart';
import 'review_material_service.dart';

/// Opens the app-wide, open-ended Free Talk call.
///
/// Home, the standalone Speaking home, and any future quick-start surface use
/// this launcher instead of rebuilding their own setup screen. The live call
/// remains the legacy `SessionScreen` so it keeps the proven transcript,
/// speaker, mute, mic-mode, end-call, and saved-session behavior.
Future<void> openFreeTalkSession(
  BuildContext context,
  WidgetRef ref, {
  String? topic,
}) async {
  final allowed = await ensureAiSessionQuota(
    context,
    ref.read(pilotAccessServiceProvider),
  );
  if (!allowed || !context.mounted) return;

  final store = ref.read(learningStoreProvider);
  final profile = store.profile();
  final recent = ReviewMaterialService.recentSessions(
    ref.read(storageServiceProvider),
    limit: 8,
  );
  final history = ReviewMaterialService.promptContext(
    recent,
    maxCharacters: 1800,
  );
  final selectedTopic = topic?.trim();
  final topicInstruction = selectedTopic == null || selectedTopic.isEmpty
      ? 'No topic was preselected. Ask what the learner wants to discuss, then '
            'let them change direction whenever they want.'
      : 'The learner is interested in "$selectedTopic", but this is still open '
            'conversation: follow their lead if they change the subject.';

  final lessonContext =
      '''
OPEN FREE TALK
This is an unrestricted conversation with the learner's selected French tutor.
The learner may talk about their day, ask questions, change topics, or practise
anything they want. Keep the conversation natural and useful; do not force a
script, roleplay, lesson card, or fixed number of turns.

LEARNER SETTINGS
CEFR LEVEL: ${profile.level}
LEARNING GOAL: ${profile.goal}
SESSION LENGTH PREFERENCE: ${profile.sessionLength}
INTERESTS: ${profile.interests.isEmpty ? 'not provided' : profile.interests.join(', ')}
$topicInstruction

RECENT COMPLETED PRACTICE
Use this only as helpful background. Bring it in naturally when relevant; do
not recite the history or assume the learner wants to repeat it.
${history.isEmpty ? 'No completed practice history is available yet.' : history}

FREE TALK BEHAVIOR
- The learner's speech is the only learner input. Never treat your own audio
  or transcript as something the learner said.
- Match the learner's level and pace. At A1/A2 use short French with brief
  English help when needed; at B1/B2 stay mostly in French and add nuance.
- Correct one high-value mistake naturally, then keep the conversation moving.
- Ask at most one follow-up question at a time and stop after your turn.
'''
          .trim();

  await AppRouter.push(
    context,
    (_) => SessionScreen(
      apiKey: ApiKeys.geminiKey,
      stage: 'free_talk',
      sessionTopic: selectedTopic == null || selectedTopic.isEmpty
          ? 'Open free talk'
          : selectedTopic,
      levelOverride: profile.level,
      lessonContext: lessonContext,
      kickoffMessage:
          '(Note from the app, not the student: open a natural free-talk call. '
          'Greet the learner as ${ActiveTutor.current.displayName} in one short '
          'level-appropriate turn, say they can talk about anything, and ask '
          'what they would like to discuss. Do not introduce a scripted lesson.)',
    ),
    fullscreenDialog: true,
  );
}
