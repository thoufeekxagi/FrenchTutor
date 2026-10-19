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
    this.unit = '',
    this.unitTitle = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final int minutes;
  final List<V3Step> steps;

  /// Dev-only lessons are hidden from release builds.
  final bool dev;

  /// Which Path section the lesson belongs to: `s0` (Stage 0) or `a1-u02`.
  final String unit;
  final String unitTitle;

  /// Short label for the Path: "Stage 0" or "Unit 2".
  String get unitLabel {
    if (unit == 's0') return 'Stage 0';
    final m = RegExp(r'-u(\d+)$').firstMatch(unit);
    if (m != null) return 'Unit ${int.parse(m.group(1)!)}';
    return unit.toUpperCase();
  }

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
      unit: (json['unit'] as String?) ?? '',
      unitTitle: (json['unitTitle'] as String?) ?? '',
      steps: steps,
    );
  }
}

class V3FrLine {
  const V3FrLine(this.fr, this.en);

  final String fr;
  final String en;
}

/// Result of checking an answer on a trusted content service.
class V3AnswerFeedback {
  const V3AnswerFeedback({
    required this.correct,
    required this.explanation,
    this.correctAnswer,
  });

  final bool correct;
  final String explanation;
  final String? correctAnswer;
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
          say: str(m, 'say', required: false),
        );
      case 'table':
        final headers = (m['headers'] as List?)?.cast<String>() ?? const [];
        final rows = <List<String>>[];
        for (final r in (m['rows'] as List? ?? const [])) {
          final row = (r as List).cast<String>();
          if (row.length != headers.length) {
            throw FormatException('Step $id has a row of the wrong length');
          }
          rows.add(row);
        }
        if (headers.length < 2 || rows.isEmpty) {
          throw FormatException('Step $id needs headers and rows');
        }
        final layout = str(m, 'layout', required: false);
        final hear = (m['hear'] as num?)?.toInt() ?? -1;
        final group = (m['group'] as num?)?.toInt() ?? 2;
        // In a grouped table `hear` counts inside one group, not the row.
        final hearLimit = layout == 'groups' ? group : headers.length;
        if (hear >= hearLimit) {
          throw FormatException('Step $id has a bad hear column');
        }
        final hearCols = [
          for (final c in (m['hearCols'] as List? ?? const []))
            (c as num).toInt(),
        ];
        if (hearCols.any((c) => c < 0 || c >= headers.length)) {
          throw FormatException('Step $id has a bad hearCols column');
        }
        if (layout == 'groups' && (group < 1 || headers.length % group != 0)) {
          throw FormatException('Step $id has a bad group size');
        }
        return V3TableStep(
          id,
          title: str(m, 'title'),
          headers: headers,
          rows: rows,
          hear: hear,
          layout: layout.isEmpty ? 'grid' : layout,
          hearCols: hearCols,
          group: group,
          perRow: (m['perRow'] as num?)?.toInt() ?? 2,
          hearPrefix: m['hearPrefix'] == true,
        );
      case 'phrase':
        return V3PhraseStep(
          id,
          fr: str(m, 'fr'),
          en: str(m, 'en'),
          tip: str(m, 'tip', required: false),
          say: str(m, 'say', required: false),
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
    this.say = '',
  });

  final String fr;
  final String en;
  final String sound;
  final String exampleFr;
  final String exampleEn;

  /// What the voice says when it differs from [fr] ("enchanté / enchantée"
  /// is shown in full and spoken as "enchanté").
  final String say;
  String get spoken => say.isNotEmpty ? say : fr;
}

class V3PhraseStep extends V3Step {
  const V3PhraseStep(
    super.id, {
    required this.fr,
    required this.en,
    this.tip = '',
    this.say = '',
  });

  final String fr;
  final String en;
  final String tip;
  final String say;
  String get spoken => say.isNotEmpty ? say : fr;
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

/// A reference table (conjugations, articles, numbers). When [hear] is a
/// column index, each row gets a speaker that says that cell.
class V3TableStep extends V3Step {
  const V3TableStep(
    super.id, {
    required this.title,
    required this.headers,
    required this.rows,
    this.hear = -1,
    this.layout = 'grid',
    this.hearCols = const [],
    this.group = 2,
    this.perRow = 2,
    this.hearPrefix = false,
  });

  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  /// `grid`: a speaker at the end of each row says this column.
  final int hear;

  /// `grid`: these columns can each be tapped to hear that cell.
  final List<int> hearCols;

  /// `grid` is the plain table. `letters` shows each (letter, how to say it)
  /// pair with its own speaker, two to a line, using the bundled recordings.
  /// `groups` splits every row into groups of [group] columns (a number, its
  /// French, how to say it), each with a speaker for the cell at [hear], with
  /// up to [perRow] groups on a line.
  final String layout;
  final int group;
  final int perRow;

  /// Say the row's first column before each tapped cell ("je" + "parle").
  final bool hearPrefix;

  /// What a speaker should say for a table cell: the French only. Pronunciation
  /// hints in brackets, the English side of an equation and arrows are dropped,
  /// and separators become pauses. Null when there is nothing to say.
  static String? speechOf(String cell, {String? prefix}) {
    var t = cell;
    final eq = t.lastIndexOf('=');
    if (eq >= 0) t = t.substring(eq + 1);
    final arrow = t.lastIndexOf('→');
    if (arrow >= 0) t = t.substring(arrow + 1);
    final out = StringBuffer();
    var depth = 0;
    for (final ch in t.split('')) {
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        out.write(ch);
      }
    }
    t = out
        .toString()
        .replaceAll('·', ', ')
        .replaceAll(' / ', ', ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    t = t.replaceAll(RegExp(r'^[—–\-\s]+$'), '');
    if (t.isEmpty) return null;
    t = t.replaceAll(RegExp(r'\s+,'), ',');
    if (prefix != null) {
      var p = prefix;
      final colon = p.lastIndexOf(':');
      if (colon >= 0) p = p.substring(colon + 1);
      p = p.replaceAll(RegExp(r'\([^)]*\)'), '');
      final alts = [
        for (final a in p.split(RegExp(r'\s*[,/·]\s*')))
          if (a.trim().isNotEmpty) a.trim().toLowerCase(),
      ];
      final lower = t.toLowerCase();
      final has =
          alts.isEmpty ||
          alts.any(
            (a) =>
                lower.startsWith('$a ') ||
                lower.startsWith("$a'") ||
                (a == 'je' && lower.startsWith("j'")),
          ) ||
          RegExp("^(m|t|s|j|l)'").hasMatch(lower);
      if (!has) {
        final first = alts.first;
        t = first == 'je' && RegExp(r'^[aeiouhàâéèêëîïôûœ]').hasMatch(lower)
            ? "j'$t"
            : '$first $t';
      }
    }
    return t;
  }
}
