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
}
