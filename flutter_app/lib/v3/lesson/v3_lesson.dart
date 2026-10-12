/// V3 lesson format. One lesson is an ordered list of steps, stored as a JSON
/// file under `assets/content/tcf/lessons/`. Nothing is generated at runtime.
///
/// ```json
/// {
///   "id": "s0-01",
///   "title": "How French works",
///   "subtitle": "Spelling and sound are different",
///   "minutes": 6,
///   "steps": [
///     {"type": "explain", "id": "e1", "title": "...", "body": "...",
///      "examples": [{"fr": "bonjour", "en": "hello"}]},
///     {"type": "word", "id": "w1", "fr": "bonjour", "en": "hello",
///      "sound": "bon-ZHOOR", "exampleFr": "Bonjour, madame.", "exampleEn": "Hello, madam."},
///     {"type": "phrase", "id": "p1", "fr": "Je m'appelle Sam.", "en": "My name is Sam.", "tip": "..."},
///     {"type": "choose", "id": "c1", "prompt": "What does bonjour mean?",
///      "promptFr": "bonjour", "options": ["hello", "goodbye"], "answer": 0, "explain": "..."},
///     {"type": "listen", "id": "l1", "fr": "Il est huit heures.", "question": "What time is it?",
///      "options": ["7:00", "8:00"], "answer": 1, "explain": "..."}
///   ]
/// }
/// ```
///
/// Every French string (`fr`, `exampleFr`, `promptFr`, `examples[].fr`) gets a
/// speaker button in the player, and is part of the audio list for the shared
/// Gemini Live voice catalog.
class V3Lesson {
  const V3Lesson({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.minutes,
    required this.steps,
    this.dev = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final int minutes;
  final List<V3Step> steps;

  /// Dev-only lessons are hidden from release builds.
  final bool dev;

  int get questionCount =>
      steps.where((s) => s is V3ChooseStep || s is V3ListenStep).length;

  factory V3Lesson.fromJson(Map<String, dynamic> json) {
    String str(Map<String, dynamic> m, String key, {bool required = true}) {
      final v = m[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (required) {
        throw FormatException('Missing or empty "$key" in ${m['id'] ?? m}');
      }
      return '';
    }

    final id = str(json, 'id');
    final rawSteps = json['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      throw FormatException('Lesson $id has no steps');
    }
    final seen = <String>{};
    final steps = <V3Step>[];
    for (final raw in rawSteps) {
      if (raw is! Map<String, dynamic>) {
        throw FormatException('Lesson $id has a step that is not an object');
      }
      final step = V3Step.fromJson(raw, str);
      if (!seen.add(step.id)) {
        throw FormatException('Lesson $id repeats step id "${step.id}"');
      }
      steps.add(step);
    }
    return V3Lesson(
      id: id,
      title: str(json, 'title'),
      subtitle: str(json, 'subtitle', required: false),
      minutes: (json['minutes'] as num?)?.toInt() ?? 5,
      dev: json['dev'] == true,
      steps: steps,
    );
  }
}

class V3FrLine {
  const V3FrLine(this.fr, this.en);

  final String fr;
  final String en;
}

sealed class V3Step {
  const V3Step(this.id);

  final String id;

  static V3Step fromJson(
    Map<String, dynamic> m,
    String Function(Map<String, dynamic>, String, {bool required}) str,
  ) {
    final id = str(m, 'id');
    List<String> options() {
      final o = m['options'];
      if (o is! List || o.length < 2 || o.any((e) => e is! String)) {
        throw FormatException('Step $id needs at least 2 string options');
      }
      return o.cast<String>();
    }

    int answer(int count) {
      final a = m['answer'];
      if (a is! int || a < 0 || a >= count) {
        throw FormatException(
          'Step $id answer must be an index 0..${count - 1}',
        );
      }
      return a;
    }

    switch (m['type']) {
      case 'explain':
        final ex = <V3FrLine>[];
        for (final e in (m['examples'] as List? ?? const [])) {
          final map = (e as Map).cast<String, dynamic>();
          ex.add(V3FrLine(str(map, 'fr'), str(map, 'en')));
        }
        return V3ExplainStep(
          id,
          title: str(m, 'title'),
          body: str(m, 'body'),
          examples: ex,
        );
      case 'word':
        return V3WordStep(
          id,
          fr: str(m, 'fr'),
          en: str(m, 'en'),
          sound: str(m, 'sound', required: false),
          exampleFr: str(m, 'exampleFr', required: false),
          exampleEn: str(m, 'exampleEn', required: false),
        );
      case 'phrase':
        return V3PhraseStep(
          id,
          fr: str(m, 'fr'),
          en: str(m, 'en'),
          tip: str(m, 'tip', required: false),
        );
      case 'choose':
        final opts = options();
        return V3ChooseStep(
          id,
          prompt: str(m, 'prompt'),
          promptFr: str(m, 'promptFr', required: false),
          options: opts,
          answer: answer(opts.length),
          explain: str(m, 'explain', required: false),
        );
      case 'listen':
        final opts = options();
        return V3ListenStep(
          id,
          fr: str(m, 'fr'),
          question: str(m, 'question'),
          options: opts,
          answer: answer(opts.length),
          explain: str(m, 'explain', required: false),
        );
      default:
        throw FormatException('Step $id has unknown type "${m['type']}"');
    }
  }
}

class V3ExplainStep extends V3Step {
  const V3ExplainStep(
    super.id, {
    required this.title,
    required this.body,
    this.examples = const [],
  });

  final String title;
  final String body;
  final List<V3FrLine> examples;
}

class V3WordStep extends V3Step {
  const V3WordStep(
    super.id, {
    required this.fr,
    required this.en,
    this.sound = '',
    this.exampleFr = '',
    this.exampleEn = '',
  });

  final String fr;
  final String en;
  final String sound;
  final String exampleFr;
  final String exampleEn;
}

class V3PhraseStep extends V3Step {
  const V3PhraseStep(
    super.id, {
    required this.fr,
    required this.en,
    this.tip = '',
  });

  final String fr;
  final String en;
  final String tip;
}

class V3ChooseStep extends V3Step {
  const V3ChooseStep(
    super.id, {
    required this.prompt,
    this.promptFr = '',
    required this.options,
    required this.answer,
    this.explain = '',
  });

  final String prompt;
  final String promptFr;
  final List<String> options;
  final int answer;
  final String explain;
}

class V3ListenStep extends V3Step {
  const V3ListenStep(
    super.id, {
    required this.fr,
    required this.question,
    required this.options,
    required this.answer,
    this.explain = '',
  });

  final String fr;
  final String question;
  final List<String> options;
  final int answer;
  final String explain;
}
