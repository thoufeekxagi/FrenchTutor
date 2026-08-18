import '../models/profile.dart';
import '../models/speak_curriculum.dart';

/// The stable learning promise behind a personalized course.
///
/// The published catalog remains the CEFR/prerequisite spine. This service
/// only changes the *future lesson wrapper* around that spine: the situation,
/// wording, examples, and practice context. Completed catalog keys are never
/// rewritten by [personalize]. That makes a goal or level change safe for
/// existing learners and gives the AI a narrow, testable contract.
class AdaptiveCurriculumProfile {
  const AdaptiveCurriculumProfile({
    required this.id,
    required this.label,
    required this.description,
    required this.contexts,
    required this.constraints,
    this.examName,
  });

  final String id;
  final String label;
  final String description;
  final List<String> contexts;
  final List<String> constraints;
  final String? examName;
}

/// A catalog-compatible item with learner-specific context.
///
/// It intentionally keeps the original `contentKey`, skill, unit order, and
/// estimated time. Existing screens therefore continue to open the same
/// alphabet, story, roleplay, grammar, vocabulary, writing, and image-cover
/// flows without needing a second lesson system.
class AdaptiveLessonItem {
  const AdaptiveLessonItem({
    required this.item,
    required this.title,
    required this.subtitle,
    required this.unitTitle,
    required this.contextPrompt,
    required this.targetPhrases,
    this.roleplay,
  });

  final SpeakCurriculumItem item;
  final String title;
  final String subtitle;
  final String unitTitle;
  final String contextPrompt;
  final List<String> targetPhrases;
  final SpeakRoleplayScene? roleplay;
}

abstract final class AdaptiveCurriculumService {
  static const _interestTokens = <String, Set<String>>{
    'everyday': {
      'speaking',
      'roleplay',
      'listening',
      'vocabulary',
      'stories',
      'review',
      'conversation',
    },
    'tef_canada': {
      'speaking',
      'listening',
      'writing',
      'grammar',
      'vocabulary',
      'review',
    },
    'work': {
      'meetings',
      'emails',
      'interviews',
      'presentations',
      'small talk',
      'vocabulary',
    },
    'relocation': {
      'housing',
      'healthcare',
      'administration',
      'school and family',
      'neighbours',
      'daily life',
    },
    'travel': {
      'hotels',
      'restaurants',
      'directions',
      'transport',
      'shopping',
      'conversation',
    },
    'culture': {
      'conversation',
      'family',
      'films and music',
      'reading',
      'food',
      'review',
    },
  };

  static const tracks = <String, AdaptiveCurriculumProfile>{
    'everyday': AdaptiveCurriculumProfile(
      id: 'everyday',
      label: 'Everyday French',
      description: 'Practical conversations for daily life and confidence.',
      contexts: [
        'introductions and small talk',
        'appointments and everyday services',
        'shopping and making choices',
        'asking for help and clarification',
        'plans, routines, and personal preferences',
      ],
      constraints: [
        'Prefer useful spoken French over textbook-only examples.',
        'Use ordinary adult situations without assuming a travel scenario.',
      ],
    ),
    'tef_canada': AdaptiveCurriculumProfile(
      id: 'tef_canada',
      label: 'TEF / TCF Canada',
      description: 'French for immigration exams and life in Canada.',
      contexts: [
        'immigration and administrative conversations',
        'housing, work, and appointments in Quebec',
        'understanding announcements and instructions',
        'giving reasons, opinions, and comparisons',
        'timed speaking, listening, reading, and writing tasks',
      ],
      constraints: [
        'Keep the French CEFR-appropriate while gradually increasing exam pressure.',
        'Use exam-style prompts only when they match the learner level.',
        'Do not claim that generated practice is an official exam item.',
      ],
      examName: 'TEF/TCF Canada',
    ),
    'work': AdaptiveCurriculumProfile(
      id: 'work',
      label: 'Professional French',
      description:
          'French for workplace communication, interviews, and growth.',
      contexts: [
        'introducing yourself and your role',
        'meetings, clarification, and teamwork',
        'email, messages, and scheduling',
        'interviews, achievements, and career goals',
        'presenting a problem and proposing a solution',
      ],
      constraints: [
        'Use workplace situations without assuming a specific industry.',
        'Teach register: concise professional French versus casual French.',
      ],
    ),
    'relocation': AdaptiveCurriculumProfile(
      id: 'relocation',
      label: 'Relocation French',
      description:
          'French for settling in, handling services, and building a life.',
      contexts: [
        'housing, leases, and utilities',
        'healthcare and appointments',
        'government forms and administration',
        'schools, family, and community life',
        'work, transport, and solving daily problems',
      ],
      constraints: [
        'Prioritize independence in real services and conversations.',
        'Explain regional vocabulary when Quebec or France-specific wording matters.',
      ],
    ),
    'travel': AdaptiveCurriculumProfile(
      id: 'travel',
      label: 'Travel French',
      description: 'French for navigating places, services, and conversations.',
      contexts: [
        'checking in and asking for information',
        'transport, directions, and tickets',
        'restaurants, shopping, and preferences',
        'handling a change or a problem',
        'meeting people and sharing simple experiences',
      ],
      constraints: [
        'Keep travel contexts useful, natural, and transferable to daily French.',
      ],
    ),
    'culture': AdaptiveCurriculumProfile(
      id: 'culture',
      label: 'Culture and Connection',
      description:
          'French for family, media, interests, and deeper conversation.',
      contexts: [
        'family and personal stories',
        'films, music, and cultural recommendations',
        'food, traditions, and preferences',
        'social conversations and invitations',
        'opinions, reactions, and respectful disagreement',
      ],
      constraints: [
        'Use culturally specific material with a short, clear explanation.',
        'Keep the learner speaking about things they actually care about.',
      ],
    ),
  };

  static AdaptiveCurriculumProfile forProfile(Profile profile) {
    return tracks[profile.goal] ?? tracks['everyday']!;
  }

  /// The six learner-facing foundations. A learner can emphasize one or all
  /// of them; the course still uses supporting skills such as roleplay,
  /// reading, pronunciation, and connectors when they make the lesson work.
  static const coreFocusSkills = <SpeakSkill>[
    SpeakSkill.speaking,
    SpeakSkill.listening,
    SpeakSkill.writing,
    SpeakSkill.grammar,
    SpeakSkill.vocabulary,
    SpeakSkill.review,
  ];

  static List<SpeakSkill> focusSkills(Profile profile) {
    final selected = <SpeakSkill>[];
    for (final value in profile.interests) {
      final skill = speakSkillFromWire(value);
      if (skill != null &&
          coreFocusSkills.contains(skill) &&
          !selected.contains(skill)) {
        selected.add(skill);
      }
    }
    return selected.isEmpty ? coreFocusSkills : selected;
  }

  /// Adapts only an unfinished catalog row. The caller passes [completed] so
  /// a previously completed train-station lesson, for example, remains the
  /// same historical lesson after the learner switches to Professional French.
  static AdaptiveLessonItem personalize(
    SpeakCurriculumItem item,
    Profile profile, {
    required bool completed,
  }) {
    if (completed || item.isAlphabetFoundation) {
      return AdaptiveLessonItem(
        item: item,
        title: item.title,
        subtitle: item.subtitle,
        unitTitle: item.unitTitle,
        contextPrompt: item.contextPrompt,
        targetPhrases: item.targetPhrases,
        roleplay: item.roleplay,
      );
    }

    final track = forProfile(profile);
    final context = track.contexts[item.sessionIndex % track.contexts.length];
    final interest = _relevantInterest(profile);
    final learnerContext = interest == null
        ? context
        : '$context, with a light connection to "$interest"';
    final level = SpeakCurriculumLevel.normalise(profile.level);
    final title = _titleFor(item.primarySkill);
    final subtitle = _subtitleFor(item.primarySkill, track.label);
    final unitTitle = '${track.label} · ${_unitTheme(context)}';
    final prompt = _promptFor(
      item: item,
      profile: profile,
      track: track,
      context: learnerContext,
      level: level,
    );

    // Old catalog target phrases are often tied to the old unit story. Do
    // not leak them into a new learner context. The AI practice contract will
    // create level-appropriate phrases from the personalized specification.
    final roleplay = item.roleplay == null
        ? null
        : SpeakRoleplayScene(
            id: '${item.roleplay!.id}:${track.id}',
            level: level,
            title: title,
            subtitle: subtitle,
            location: context,
            learnerRole: 'yourself',
            tutorRole: 'a helpful conversation partner',
            goal: 'Complete the $context task in clear French.',
            openingLine: 'Bonjour, je voudrais pratiquer cette situation.',
            targetPhrases: const [],
          );

    return AdaptiveLessonItem(
      item: item,
      title: title,
      subtitle: subtitle,
      unitTitle: unitTitle,
      contextPrompt: prompt,
      targetPhrases: const [],
      roleplay: roleplay,
    );
  }

  static String _titleFor(SpeakSkill skill) {
    final title = switch (skill) {
      SpeakSkill.vocabulary => 'Build useful words',
      SpeakSkill.reading => 'Read for meaning',
      SpeakSkill.listening => 'Catch the main idea',
      SpeakSkill.grammar => 'Use one useful pattern',
      SpeakSkill.writing => 'Write a clear message',
      SpeakSkill.speaking => 'Say it with confidence',
      SpeakSkill.roleplay => 'Use it in conversation',
      SpeakSkill.review => 'Bring it back from memory',
      SpeakSkill.connectors => 'Connect your ideas',
      SpeakSkill.liaison => 'Sound more natural',
      SpeakSkill.freeTalk => 'Talk freely',
      SpeakSkill.alphabet => 'Recognize French sounds',
    };
    return title;
  }

  static String _subtitleFor(SpeakSkill skill, String trackLabel) =>
      '${skill.label} · $trackLabel';

  /// Returns the selected interest only when it belongs to the learner's
  /// current goal. This prevents a stale interest (for example, "meetings"
  /// after switching from work to relocation) from leaking into new lessons.
  static String? relevantInterest(Profile profile) {
    final allowedInterests =
        _interestTokens[profile.goal] ?? _interestTokens['everyday']!;
    for (final value in profile.interests) {
      final trimmed = value.trim();
      // The same persisted list carries the learner's six focus skills. They
      // shape route weighting, but must never become a fake lesson topic such
      // as "appointments with a light connection to Speaking".
      if (speakSkillFromWire(trimmed) != null) continue;
      if (trimmed.isNotEmpty &&
          allowedInterests.contains(trimmed.toLowerCase())) {
        return trimmed;
      }
    }
    return null;
  }

  static String? _relevantInterest(Profile profile) =>
      relevantInterest(profile);

  static String _unitTheme(String context) {
    final first = context.split(',').first.trim();
    return first.length > 34 ? '${first.substring(0, 34)}…' : first;
  }

  static String _promptFor({
    required SpeakCurriculumItem item,
    required Profile profile,
    required AdaptiveCurriculumProfile track,
    required String context,
    required String level,
  }) {
    final minutes = switch (profile.sessionLength) {
      'quick' => 5,
      'deep' => 20,
      _ => 10,
    };
    final relevantInterest = _relevantInterest(profile);
    final interests = relevantInterest == null
        ? 'No extra interests were selected.'
        : 'Learner interest: $relevantInterest.';
    final exam = track.examName == null
        ? ''
        : 'Exam target: ${track.examName}\n';
    return '''PERSONALIZED COURSE SPECIFICATION
Goal: ${track.label} — ${track.description}
$exam
Current CEFR level: $level
Target practice context: $context
Session budget: $minutes minutes
$interests
Primary skill: ${item.primarySkill.label}
Supporting skills: ${item.supportingSkills.map((skill) => skill.label).join(', ')}

CONTENT RULES
- Preserve the requested CEFR level exactly; relevance must not make the French too advanced.
- Teach one clear competency in this session, then transfer it into the target context.
- Use natural adult French and explain English support only when helpful.
- Do not default to an unrelated travel, restaurant, or generic scene unless it fits the target context.
- Do not repeat an earlier scene; vary the people, setting, and task while keeping the same skill objective.
- Keep the output usable by the existing story card, quiz, vocabulary, speaking, writing, roleplay, and image-cover flows.
- Use a compact lesson shape: a short title, a one-line subtitle, two to four tiny examples, one controlled check, and one transfer prompt.
- Explain one idea at a time. Keep each explanation to one or two short sentences; never put a lesson plan, audience, goal, or long context paragraph into a heading.
- Teach with concrete French examples before asking the learner to produce language.
${track.constraints.map((constraint) => '- $constraint').join('\n')}
''';
  }
}

abstract final class SpeakCurriculumLevel {
  static String normalise(String level) => switch (level.toLowerCase()) {
    'a1' || 'zero' || 'basics' => 'A1',
    'a2' => 'A2',
    'b1' || 'conversational' => 'B1',
    'b2' => 'B2',
    _ => 'A1',
  };
}
