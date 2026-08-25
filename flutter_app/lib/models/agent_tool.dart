class AgentTool {
  AgentTool({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;

  Map<String, dynamic> get declaration => {
    'name': name,
    'description': description,
    'parameters': parameters,
  };

  static Map<String, dynamic> _object(
    Map<String, dynamic> properties, {
    List<String> required = const [],
  }) => {'type': 'OBJECT', 'properties': properties, 'required': required};

  static Map<String, dynamic> _stringEnum(
    String description, {
    List<String>? values,
  }) => {'type': 'STRING', 'description': description, 'enum': ?values};

  static final vocabPalette = [
    AgentTool(
      name: 'mark_result',
      description:
          'Propose a grade for how well the student did with the current word. The app will only accept this if the student has actually attempted the word.',
      parameters: _object(
        {
          'grade': _stringEnum(
            'How well the student recalled/pronounced the word.',
            values: ['again', 'good', 'easy'],
          ),
        },
        required: ['grade'],
      ),
    ),
  ];

  static final readingPalette = [
    AgentTool(
      name: 'mark_segment_result',
      description:
          'Propose a grade for how well the student did with the current word/phrase segment. The app will only accept this if the student has actually attempted it.',
      parameters: _object(
        {
          'grade': _stringEnum(
            'How well the student recalled/pronounced the segment.',
            values: ['again', 'good', 'easy'],
          ),
        },
        required: ['grade'],
      ),
    ),
  ];

  static final grammarPalette = [
    AgentTool(
      name: 'mark_drill_result',
      description:
          "Record whether the student's spoken answer to the current drill was correct. The app will only accept this if the student has actually attempted an answer.",
      parameters: _object(
        {
          'correct': {
            'type': 'BOOLEAN',
            'description': "Whether the student's answer was correct.",
          },
        },
        required: ['correct'],
      ),
    ),
  ];

  /// One result event for a controlled guided speaking turn. The screen owns
  /// progression; Gemini supplies the judgment it already gives aloud so the
  /// UI does not run a second grading path after the Live turn.
  static final guidedSpeakingPalette = [
    AgentTool(
      name: 'grade_guided_phrase',
      description:
          'Report the result of the learner\'s just-finished guided speaking attempt. '
          'Call exactly once immediately after the learner turn closes, before speaking any feedback, '
          'using only the current phrase. This is a UI event, not an invitation to advance the lesson.',
      parameters: _object(
        {
          'step_index': {
            'type': 'INTEGER',
            'description': 'The 1-based current lesson step index.',
          },
          'matched': {
            'type': 'BOOLEAN',
            'description':
                'Whether the learner said the current target closely enough.',
          },
          'heard': {
            'type': 'STRING',
            'description':
                'A short transcript of what the learner said, or an empty string if unclear.',
          },
          'feedback': {
            'type': 'STRING',
            'description': 'One short beginner-friendly feedback sentence.',
          },
        },
        required: ['step_index', 'matched', 'heard', 'feedback'],
      ),
    ),
  ];

  /// One result event for an open Free Talk answer. The tutor keeps the
  /// conversation natural, while the screen receives the same judgment the
  /// tutor has just spoken aloud.
  static final freeTalkSpeakingPalette = [
    AgentTool(
      name: 'grade_free_talk_turn',
      description:
          'Report the result of the learner\'s just-finished Free Talk answer. '
          'Call exactly once after the learner turn closes. Accept a meaningful '
          'on-topic answer, even when it is different from the visible frame. '
          'If correction is needed, provide only one short corrected French sentence.',
      parameters: _object(
        {
          'step_index': {
            'type': 'INTEGER',
            'description': 'The 1-based current lesson step index.',
          },
          'accepted': {
            'type': 'BOOLEAN',
            'description': 'Whether the learner gave a usable on-topic answer.',
          },
          'heard': {
            'type': 'STRING',
            'description':
                'The short final French transcript, or empty if unclear.',
          },
          'correction': {
            'type': 'STRING',
            'description':
                'One short corrected French sentence, or empty when no correction is needed.',
          },
          'feedback': {
            'type': 'STRING',
            'description': 'One short beginner-friendly feedback sentence.',
          },
        },
        required: ['step_index', 'accepted', 'heard', 'correction', 'feedback'],
      ),
    ),
  ];
}
