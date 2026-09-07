enum SpeakSessionKind { video, review, speaking, roleplay, story }

/// The learning modes that can be composed into one course session. These are
/// deliberately separate from [SpeakSessionKind], which is kept as a wire-
/// compatible legacy field for already-generated catalog rows.
enum SpeakSkill {
  alphabet,
  vocabulary,
  reading,
  listening,
  grammar,
  connectors,
  liaison,
  writing,
  speaking,
  roleplay,
  review,
  freeTalk,
}

extension SpeakSkillPresentation on SpeakSkill {
  String get label => switch (this) {
    SpeakSkill.alphabet => 'Alphabet',
    SpeakSkill.vocabulary => 'Vocabulary',
    SpeakSkill.reading => 'Reading',
    SpeakSkill.listening => 'Listening',
    SpeakSkill.grammar => 'Grammar',
    SpeakSkill.connectors => 'Connectors',
    SpeakSkill.liaison => 'Liaison',
    SpeakSkill.writing => 'Writing',
    SpeakSkill.speaking => 'Speaking',
    SpeakSkill.roleplay => 'Roleplay',
    SpeakSkill.review => 'Review',
    SpeakSkill.freeTalk => 'Free Talk',
  };

  String get description => switch (this) {
    SpeakSkill.alphabet => 'Recognize and say the sounds you need first.',
    SpeakSkill.vocabulary => 'Build the words that make the situation useful.',
    SpeakSkill.reading => 'Understand a short, realistic French text.',
    SpeakSkill.listening => 'Catch the meaning when someone speaks naturally.',
    SpeakSkill.grammar => 'Notice the pattern and use it in context.',
    SpeakSkill.connectors => 'Join ideas with clear everyday connectors.',
    SpeakSkill.liaison => 'Make connected French sound more natural.',
    SpeakSkill.writing => 'Create a useful message in your own words.',
    SpeakSkill.speaking => 'Say the language before the roleplay.',
    SpeakSkill.roleplay => 'Use the lesson in a real conversation.',
    SpeakSkill.review => 'Bring the important language back from memory.',
    SpeakSkill.freeTalk => 'Choose the situation and speak freely.',
  };

  String get wireName => name == 'freeTalk' ? 'free_talk' : name;
}

SpeakSkill? speakSkillFromWire(Object? value) {
  final raw = value?.toString().toLowerCase().replaceAll('-', '_');
  return switch (raw) {
    'alphabet' => SpeakSkill.alphabet,
    'vocabulary' || 'vocab' => SpeakSkill.vocabulary,
    'reading' => SpeakSkill.reading,
    'listening' => SpeakSkill.listening,
    'grammar' => SpeakSkill.grammar,
    'connectors' || 'connector' => SpeakSkill.connectors,
    'liaison' => SpeakSkill.liaison,
    'writing' || 'write' => SpeakSkill.writing,
    'speaking' || 'speak' => SpeakSkill.speaking,
    'roleplay' || 'role_play' => SpeakSkill.roleplay,
    'review' => SpeakSkill.review,
    'free_talk' || 'freetalk' => SpeakSkill.freeTalk,
    _ => null,
  };
}

/// A published roleplay scene from the shared course catalog.
///
/// The scene is deliberately text-first. An image is a visual cue, not a
/// second source of truth for the tutor prompt. This keeps roleplay useful
/// offline and avoids requiring Gemini Vision for an ordinary lesson.
class SpeakRoleplayScene {
  const SpeakRoleplayScene({
    required this.id,
    required this.level,
    required this.title,
    required this.subtitle,
    required this.location,
    required this.learnerRole,
    required this.tutorRole,
    required this.goal,
    required this.openingLine,
    required this.targetPhrases,
    this.imageUrl,
  });

  final String id;
  final String level;
  final String title;
  final String subtitle;
  final String location;
  final String learnerRole;
  final String tutorRole;
  final String goal;
  final String openingLine;
  final List<String> targetPhrases;
  final String? imageUrl;

  String get lessonContext =>
      '''
ROLEPLAY SCENE
Scene: $title
Description: $subtitle
Location: $location
Learner role: $learnerRole
Tutor role: $tutorRole
Learner goal: $goal
Target phrases: ${targetPhrases.join('; ')}
Opening line to use in French: $openingLine

ROLEPLAY CONTRACT
- Stay in the tutor role and keep the scene moving one turn at a time.
- Let the learner speak before correcting. Correct only the most useful issue.
- Reuse the target phrases naturally, but never force every phrase into one turn.
- Keep the level appropriate for ${level.toUpperCase()}.
- Do not leave the scene for generic small talk unless the learner asks for help.
- End with a short, encouraging recap after the learner reaches the goal.
''';

  String get kickoffMessage =>
      '(Note from the app, not the student: the learner just entered the '
      'roleplay "$title". Set the scene in one short English sentence, then '
      'say the opening French line as the $tutorRole. Do not ask what the '
      'learner wants to practise.)';

  factory SpeakRoleplayScene.fromJson(Map<String, dynamic> json) {
    return SpeakRoleplayScene(
      id: json['id'] as String,
      level: (json['level'] as String? ?? 'A1').toUpperCase(),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      location: json['location'] as String,
      learnerRole:
          json['learner_role'] as String? ??
          json['learnerRole'] as String? ??
          'yourself',
      tutorRole:
          json['tutor_role'] as String? ??
          json['tutorRole'] as String? ??
          'conversation partner',
      goal: json['goal'] as String,
      openingLine:
          json['opening_line'] as String? ??
          json['openingLine'] as String? ??
          '',
      targetPhrases:
          ((json['target_phrases'] ?? json['targetPhrases']) as List? ??
                  const [])
              .map((value) => value.toString())
              .toList(growable: false),
      imageUrl: json['image_url'] as String? ?? json['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'level': level,
    'title': title,
    'subtitle': subtitle,
    'location': location,
    'learner_role': learnerRole,
    'tutor_role': tutorRole,
    'goal': goal,
    'opening_line': openingLine,
    'target_phrases': targetPhrases,
    if (imageUrl != null) 'image_url': imageUrl,
  };
}

/// One stable, published item in a learner's course path.
class SpeakCurriculumItem {
  const SpeakCurriculumItem({
    required this.contentKey,
    required this.level,
    required this.unit,
    required this.unitTitle,
    required this.sessionIndex,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.estimatedMinutes,
    this.targetPhrases = const [],
    this.roleplay,
    this.explicitPrimarySkill,
    this.explicitSupportingSkills = const [],
  });

  final String contentKey;
  final String level;
  final int unit;
  final String unitTitle;
  final int sessionIndex;
  final String title;
  final String subtitle;
  final String kind;
  final int estimatedMinutes;
  final List<String> targetPhrases;
  final SpeakRoleplayScene? roleplay;
  final SpeakSkill? explicitPrimarySkill;
  final List<SpeakSkill> explicitSupportingSkills;

  /// The first four A1 sessions are pronunciation foundations, not generic
  /// conversation lessons. Older remote rows may still contain a copied
  /// `speaking` support skill, so keep this rule at the model boundary where
  /// every roadmap projection and screen sees the same activity contract.
  bool get isAlphabetFoundation =>
      level == 'A1' && unit == 1 && sessionIndex <= 3;

  /// The first five Unit 1 sessions establish the sound system before the
  /// learner moves into ordinary course situations.
  bool get isSoundFoundation => level == 'A1' && unit == 1 && sessionIndex <= 4;

  /// The first Unit 1 sessions establish the sound system. After that,
  /// reading/listening/writing/grammar and speaking are mixed around the unit
  /// situation instead of repeating a speaking-only template.
  SpeakSkill get primarySkill {
    if (isAlphabetFoundation) return SpeakSkill.alphabet;
    if (explicitPrimarySkill != null) return explicitPrimarySkill!;
    if (sessionKind == SpeakSessionKind.roleplay || roleplay != null) {
      return SpeakSkill.roleplay;
    }
    final slot = sessionIndex % 10;
    if (unit == 1 && slot == 0) return SpeakSkill.alphabet;
    if (unit == 1 && slot == 1) return SpeakSkill.connectors;
    return switch (slot) {
      0 => SpeakSkill.vocabulary,
      1 => SpeakSkill.reading,
      2 => SpeakSkill.listening,
      3 => SpeakSkill.grammar,
      4 => SpeakSkill.writing,
      5 => SpeakSkill.speaking,
      6 => SpeakSkill.roleplay,
      7 => SpeakSkill.review,
      8 => SpeakSkill.writing,
      _ => SpeakSkill.roleplay,
    };
  }

  List<SpeakSkill> get supportingSkills {
    if (isAlphabetFoundation) return const [SpeakSkill.vocabulary];
    if (explicitSupportingSkills.isNotEmpty) return explicitSupportingSkills;
    final primary = primarySkill;
    final base = <SpeakSkill>[SpeakSkill.vocabulary, SpeakSkill.speaking];
    if (unit == 1) {
      base.addAll([SpeakSkill.alphabet, SpeakSkill.liaison]);
    }
    base.remove(primary);
    return base.take(2).toList(growable: false);
  }

  List<SpeakSkill> get activitySkills => [primarySkill, ...supportingSkills];

  String get contextPrompt {
    if (isSoundFoundation) {
      return 'Use the pronunciation foundation "$title". Keep every '
          'example tied to French letter names, vowel sounds, accent marks, '
          'and very simple words. Do not introduce a travel, station, '
          'roleplay, or generic conversation scenario. Useful examples: '
          '${targetPhrases.take(8).join('; ')}.';
    }
    return 'Use the course situation "$unitTitle" and the session goal '
        '"$title". Reuse these target phrases naturally: '
        '${targetPhrases.take(8).join('; ')}.';
  }

  factory SpeakCurriculumItem.fromJson(Map<String, dynamic> json) {
    final roleplayJson = json['roleplay_scene'] ?? json['roleplayScene'];
    return SpeakCurriculumItem(
      contentKey:
          json['content_key'] as String? ?? json['contentKey'] as String,
      level: (json['level'] as String? ?? 'A1').toUpperCase(),
      unit: (json['unit_number'] as num? ?? json['unit'] as num? ?? 1).toInt(),
      unitTitle:
          json['unit_title'] as String? ??
          json['unitTitle'] as String? ??
          'French in context',
      sessionIndex:
          (json['session_index'] as num? ?? json['sessionIndex'] as num? ?? 0)
              .toInt(),
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      kind: json['kind'] as String? ?? 'speaking',
      estimatedMinutes:
          (json['estimated_minutes'] as num? ??
                  json['estimatedMinutes'] as num? ??
                  8)
              .toInt(),
      targetPhrases:
          ((json['target_phrases'] ?? json['targetPhrases']) as List? ??
                  const [])
              .map((value) => value.toString())
              .toList(growable: false),
      roleplay: roleplayJson is Map
          ? SpeakRoleplayScene.fromJson(roleplayJson.cast<String, dynamic>())
          : null,
      explicitPrimarySkill: speakSkillFromWire(
        json['primary_skill'] ?? json['primarySkill'],
      ),
      explicitSupportingSkills:
          ((json['supporting_skills'] ?? json['supportingSkills']) as List? ??
                  const [])
              .map(speakSkillFromWire)
              .whereType<SpeakSkill>()
              .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'content_key': contentKey,
    'level': level,
    'unit_number': unit,
    'unit_title': unitTitle,
    'session_index': sessionIndex,
    'title': title,
    'subtitle': subtitle,
    'kind': kind,
    'primary_skill': primarySkill.wireName,
    'supporting_skills': supportingSkills
        .map((skill) => skill.wireName)
        .toList(growable: false),
    'estimated_minutes': estimatedMinutes,
    'target_phrases': targetPhrases,
    if (roleplay != null) 'roleplay_scene': roleplay!.toJson(),
  };

  SpeakSessionKind get sessionKind => switch (kind.toLowerCase()) {
    'video' || 'lesson' => SpeakSessionKind.video,
    'review' => SpeakSessionKind.review,
    'roleplay' => SpeakSessionKind.roleplay,
    'story' => SpeakSessionKind.story,
    _ => SpeakSessionKind.speaking,
  };
}
