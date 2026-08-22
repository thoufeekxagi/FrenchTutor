import '../services/speak_language_profile.dart';

/// The canonical contract for a speaking activity.
///
/// The setup screen chooses the activity, but the live tutor must execute a
/// concrete plan. Keeping that plan in one small model prevents every entry
/// point from inventing a different prompt or roleplay choreography.
class SpeakingTaskPlan {
  const SpeakingTaskPlan({
    required this.id,
    required this.mode,
    required this.title,
    required this.level,
    required this.topic,
    required this.objective,
    required this.stages,
    required this.successCriteria,
    required this.supportPhrases,
    required this.rubricFocus,
    this.examSection,
  });

  final String id;
  final String mode;
  final String title;
  final String level;
  final String topic;
  final String objective;
  final List<String> stages;
  final List<String> successCriteria;
  final List<String> supportPhrases;
  final List<String> rubricFocus;
  final String? examSection;

  String get modeLabel => switch (mode) {
    'guided_conversation' => 'Guided conversation',
    'roleplay' => 'Guided roleplay',
    'free_talk' => 'Free talk',
    'tef_section_a' => 'TEF / TCF · Section A',
    'tef_section_b' => 'TEF / TCF · Section B',
    'picture_description' => 'Picture description',
    'pronunciation_repair' => 'Pronunciation repair',
    _ => 'Speaking practice',
  };

  /// This is deliberately plain text: it is easy to inspect in logs, works
  /// with the existing Gemini Live context channel, and remains provider
  /// agnostic if the realtime model changes later.
  String get liveContext {
    final language = SpeakLanguageProfile.forLevel(level);
    final newWords = language.newWordsPerTurn == 1
        ? 'one new content word'
        : '${language.newWordsPerTurn} new content words';
    return '''
SPEAKING TASK PLAN — FOLLOW THIS CONTRACT:
Activity: $modeLabel
Title: $title
Learner level: $level
Topic: $topic
Primary objective: $objective

CEFR LEVEL LOCK — THIS IS AUTHORITATIVE FOR THIS SESSION:
${language.levelContract}
- Tutor turn target: ${language.tutorTurnWordLimit}.
- Introduce no more than $newWords in one turn.
- Never raise the difficulty because the learner answers one easy question well.
- Keep the task's vocabulary, grammar, follow-up questions, and correction style inside this level.

RUN THESE STAGES IN ORDER:
${_numbered(stages)}

SUCCESS CRITERIA:
${_numbered(successCriteria)}

SUPPORT PHRASES (teach only when useful, then make the learner say them):
${_numbered(supportPhrases)}

EVALUATION FOCUS:
${_numbered(rubricFocus)}

APP PACING RULES:
- Speak one short turn, then stop and wait for the learner.
- Never perform the learner's turn for them unless they explicitly request a rescue.
- Correct one high-value issue at a time, explain it briefly, model the improved line,
  and immediately let the learner retry it.
- Keep the communicative goal visible through your behavior: the learner must use the
  language, not listen to a lecture about the language.
''';
  }

  static SpeakingTaskPlan create({
    required String mode,
    required String level,
    required String topic,
    required String goal,
  }) {
    final normalizedLevel = normalizeLevel(level);
    final normalizedTopic = topic == 'Surprise me'
        ? 'an everyday situation'
        : topic;
    final baseId =
        '${mode}_${normalizedLevel}_${normalizedTopic.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

    return switch (mode) {
      'guided_conversation' => SpeakingTaskPlan(
        id: baseId,
        mode: mode,
        title: 'One useful conversation',
        level: normalizedLevel,
        topic: normalizedTopic,
        objective: 'listen, repeat, repair, and use one phrase naturally',
        stages: const [
          'Introduce one short phrase in context.',
          'Ask the learner to repeat it aloud.',
          'Give immediate feedback on one pronunciation or grammar issue.',
          'Model the corrected phrase and let the learner retry.',
          'Use the phrase in a tiny back-and-forth exchange.',
        ],
        successCriteria: const [
          'The learner repeats the target phrase.',
          'The learner improves one identified issue.',
          'The learner uses the phrase without reading it.',
        ],
        supportPhrases: const [
          'Écoutez et répétez.',
          'Encore une fois, plus lentement.',
          'Très bien. Maintenant, dans une situation réelle.',
        ],
        rubricFocus: const [
          'pronunciation',
          'accuracy',
          'recall',
          'confidence',
        ],
      ),
      'roleplay' => SpeakingTaskPlan(
        id: baseId,
        mode: mode,
        title: 'Handle $normalizedTopic',
        level: normalizedLevel,
        topic: normalizedTopic,
        objective:
            'complete a realistic conversation while staying in character',
        stages: const [
          'Set the scene and identify the learner’s role.',
          'Model the first exchange, then hand over the turn.',
          'Respond naturally to what the learner actually says.',
          'Introduce one small change or follow-up question.',
          'Repair one weak line and replay the ending.',
        ],
        successCriteria: const [
          'The learner completes the practical goal.',
          'The learner asks or answers a follow-up question.',
          'The learner closes the conversation naturally.',
        ],
        supportPhrases: const [
          'Excusez-moi, j’ai une question.',
          'Pouvez-vous répéter, s’il vous plaît ?',
          'D’accord, merci beaucoup.',
        ],
        rubricFocus: const [
          'interaction',
          'task completion',
          'fluency',
          'grammar',
        ],
      ),
      'tef_section_a' => SpeakingTaskPlan(
        id: baseId,
        mode: mode,
        title: 'TEF / TCF · Obtain information',
        level: normalizedLevel,
        topic: normalizedTopic,
        objective:
            'ask relevant questions, clarify answers, and gather information',
        examSection: 'A',
        stages: const [
          'Read or hear the situation and identify the information needed.',
          'Ask the first question without coaching.',
          'Follow up on the interlocutor’s answer.',
          'Ask for clarification or confirmation.',
          'Complete the exchange within the timed limit.',
        ],
        successCriteria: const [
          'Questions are relevant to the situation.',
          'The learner follows up instead of reading a list.',
          'The learner confirms or summarizes the useful information.',
        ],
        supportPhrases: const [
          'J’aimerais avoir quelques renseignements.',
          'Est-ce que vous pouvez préciser ?',
          'Si j’ai bien compris…',
        ],
        rubricFocus: const [
          'interaction',
          'question quality',
          'clarity',
          'fluency',
        ],
      ),
      'tef_section_b' => SpeakingTaskPlan(
        id: baseId,
        mode: mode,
        title: 'TEF / TCF · Convince someone',
        level: normalizedLevel,
        topic: normalizedTopic,
        objective: 'state an opinion, support it, and respond to disagreement',
        examSection: 'B',
        stages: const [
          'Understand the offer or situation and take a position.',
          'Present the idea clearly to the interlocutor.',
          'Give a reason and a concrete example.',
          'Handle disagreement without abandoning the conversation.',
          'Close with a clear recommendation or next step.',
        ],
        successCriteria: const [
          'The learner states a clear position.',
          'The learner gives reasons and examples.',
          'The learner responds to a counterargument.',
        ],
        supportPhrases: const [
          'À mon avis, c’est une bonne idée parce que…',
          'Je comprends votre point de vue, mais…',
          'Par exemple, on pourrait…',
        ],
        rubricFocus: const [
          'argumentation',
          'coherence',
          'vocabulary',
          'register',
        ],
      ),
      'picture_description' => SpeakingTaskPlan(
        id: baseId,
        mode: mode,
        title: 'Describe what you see',
        level: normalizedLevel,
        topic: normalizedTopic,
        objective: 'describe a scene clearly and make a simple inference',
        stages: const [
          'Name the main people, objects, and setting.',
          'Describe what is happening now.',
          'Add one detail about place, time, or feeling.',
          'Make one reasonable inference.',
          'Summarize the scene in a natural closing sentence.',
        ],
        successCriteria: const [
          'The learner organizes the description from general to specific.',
          'The learner uses connected sentences.',
          'The learner adds at least one personal inference.',
        ],
        supportPhrases: const [
          'Sur cette image, je vois…',
          'Au premier plan / à l’arrière-plan…',
          'Je pense que…',
        ],
        rubricFocus: const ['coherence', 'vocabulary', 'grammar', 'fluency'],
      ),
      'pronunciation_repair' => SpeakingTaskPlan(
        id: baseId,
        mode: mode,
        title: 'Repair one sound',
        level: normalizedLevel,
        topic: normalizedTopic,
        objective:
            'hear, reproduce, and transfer one difficult sound or phrase',
        stages: const [
          'Play a natural model at a comfortable pace.',
          'Have the learner repeat the target phrase.',
          'Identify one sound, stress, or rhythm issue.',
          'Model the corrected version and retry it.',
          'Use the repaired phrase in a new sentence.',
        ],
        successCriteria: const [
          'The target sound is intelligible.',
          'Stress and rhythm improve on the retry.',
          'The learner transfers the sound to a new sentence.',
        ],
        supportPhrases: const [
          'Écoutez le rythme.',
          'Répétez après moi.',
          'Très bien. Utilisez-le dans une phrase.',
        ],
        rubricFocus: const [
          'intelligibility',
          'stress',
          'rhythm',
          'retry improvement',
        ],
      ),
      _ => SpeakingTaskPlan(
        id: baseId,
        mode: 'free_talk',
        title: 'Talk about $normalizedTopic',
        level: normalizedLevel,
        topic: normalizedTopic,
        objective: goal.toLowerCase(),
        stages: const [
          'Start with one accessible question.',
          'Keep the learner speaking with one follow-up at a time.',
          'Repair one high-value issue without interrupting the flow.',
          'Finish with a more independent response.',
        ],
        successCriteria: const [
          'The learner speaks in connected turns.',
          'The learner responds to follow-up questions.',
          'The learner tries one new phrase.',
        ],
        supportPhrases: const [
          'Pouvez-vous donner un exemple ?',
          'Je veux dire que…',
          'Pour résumer…',
        ],
        rubricFocus: const ['fluency', 'interaction', 'grammar', 'vocabulary'],
      ),
    };
  }

  static String normalizeLevel(String raw) => switch (raw.toLowerCase()) {
    'a1' || 'zero' || 'basics' => 'A1',
    'a2' => 'A2',
    'b1' || 'conversational' => 'B1',
    'b2' => 'B2',
    _ => 'A1',
  };

  String _numbered(List<String> values) => values
      .asMap()
      .entries
      .map((entry) => '${entry.key + 1}. ${entry.value}')
      .join('\n');
}
