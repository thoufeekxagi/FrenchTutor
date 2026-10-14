/// V3 story format (see docs/v3/STORY_FORMAT.md). A story is one JSON file of
/// sentences plus a meaning for every word, so a tapped word is never blank.
class V3Word {
  const V3Word({
    required this.en,
    this.pos = '',
    this.sound = '',
    this.gender = '',
    this.number = '',
    this.lemma = '',
    this.note = '',
  });

  final String en;
  final String pos;
  final String sound;
  final String gender;
  final String number;
  final String lemma;
  final String note;
}

/// One tappable word as drawn on screen. Punctuation that French sets apart
/// from words (« » : ! ?) is glued to its neighbour so it can never wrap onto
/// a line of its own, and [key] is the glossary key (punctuation removed).
class V3Unit {
  const V3Unit({required this.text, required this.key});

  final String text;
  final String key;
}

class V3StorySentence {
  const V3StorySentence({
    required this.fr,
    required this.en,
    required this.note,
    required this.units,
    required this.rawToUnit,
  });

  final String fr;
  final String en;
  final String note;
  final List<V3Unit> units;

  /// Index of the whitespace-separated token in [fr] (the numbering the
  /// narration timeline uses) to the index of the unit that contains it.
  final List<int> rawToUnit;

  /// The French as one string with ordinary spaces, for narration.
  String get narration => fr;
}

class V3QuizQuestion {
  const V3QuizQuestion({
    required this.prompt,
    required this.options,
    required this.answer,
    required this.explain,
  });

  final String prompt;
  final List<String> options;
  final int answer;
  final String explain;
}

class V3Story {
  const V3Story({
    required this.id,
    required this.title,
    required this.titleEn,
    required this.level,
    required this.minutes,
    required this.summary,
    required this.unit,
    required this.sentences,
    required this.words,
    required this.keywords,
    required this.quiz,
  });

  final String id;
  final String title;
  final String titleEn;
  final String level;
  final int minutes;
  final String summary;
  final String unit;
  final List<V3StorySentence> sentences;
  final Map<String, V3Word> words;
  final List<String> keywords;
  final List<V3QuizQuestion> quiz;

  static const _strip = '«»"“”‘’\'.,!?;:()—–…';
  static const _opening = '«“‘(';

  /// The glossary key of one word: punctuation trimmed from both ends,
  /// lowercase. Same rule as `story_tokens` in content/tcf/tools/validate.py.
  static String keyOf(String raw) {
    var s = raw.replaceAll('\u2019', "'").trim();
    var start = 0;
    var end = s.length;
    while (start < end &&
        (_strip.contains(s[start]) || s[start].trim().isEmpty)) {
      start++;
    }
    while (end > start &&
        (_strip.contains(s[end - 1]) || s[end - 1].trim().isEmpty)) {
      end--;
    }
    return s.substring(start, end).toLowerCase();
  }

  /// Builds the on-screen units of a sentence and the raw-token mapping.
  static ({List<V3Unit> units, List<int> rawToUnit}) unitsOf(String fr) {
    final raw = fr.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final units = <String>[];
    final rawToUnit = List<int>.filled(raw.length, 0);
    String? carry;
    for (var i = 0; i < raw.length; i++) {
      final token = raw[i];
      final onlyPunctuation = keyOf(token).isEmpty;
      if (onlyPunctuation) {
        if (_opening.contains(token[0])) {
          carry = carry == null ? token : '$carry\u00a0$token';
          rawToUnit[i] = units.length;
        } else if (units.isNotEmpty) {
          units[units.length - 1] = '${units.last}\u00a0$token';
          rawToUnit[i] = units.length - 1;
        } else {
          carry = carry == null ? token : '$carry\u00a0$token';
          rawToUnit[i] = 0;
        }
        continue;
      }
      units.add(carry == null ? token : '$carry\u00a0$token');
      carry = null;
      rawToUnit[i] = units.length - 1;
    }
    return (
      units: [for (final u in units) V3Unit(text: u, key: keyOf(u))],
      rawToUnit: rawToUnit,
    );
  }

  factory V3Story.fromJson(Map<String, dynamic> json) {
    String str(Map<String, dynamic> m, String key) {
      final v = m[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      throw FormatException('Missing or empty "$key" in ${m['id'] ?? m}');
    }

    final id = str(json, 'id');
    final rawWords = json['words'];
    if (rawWords is! Map) throw FormatException('Story $id has no words');
    final words = <String, V3Word>{
      for (final e in rawWords.entries)
        (e.key as String): V3Word(
          en: str((e.value as Map).cast<String, dynamic>(), 'en'),
          pos: ((e.value as Map)['pos'] as String?) ?? '',
          sound: ((e.value as Map)['sound'] as String?) ?? '',
          gender: ((e.value as Map)['gender'] as String?) ?? '',
          number: ((e.value as Map)['number'] as String?) ?? '',
          lemma: ((e.value as Map)['lemma'] as String?) ?? '',
          note: ((e.value as Map)['note'] as String?) ?? '',
        ),
    };

    final rawSentences = json['sentences'];
    if (rawSentences is! List || rawSentences.isEmpty) {
      throw FormatException('Story $id has no sentences');
    }
    final sentences = <V3StorySentence>[];
    for (final s in rawSentences) {
      final m = (s as Map).cast<String, dynamic>();
      final fr = str(m, 'fr');
      final built = unitsOf(fr);
      for (final u in built.units) {
        if (!words.containsKey(u.key)) {
          throw FormatException('Story $id: word "${u.key}" has no meaning');
        }
      }
      sentences.add(
        V3StorySentence(
          fr: fr,
          en: str(m, 'en'),
          note: (m['note'] as String?) ?? '',
          units: built.units,
          rawToUnit: built.rawToUnit,
        ),
      );
    }

    final keywords = ((json['keywords'] as List?) ?? const []).cast<String>();
    for (final k in keywords) {
      if (!words.containsKey(k)) {
        throw FormatException('Story $id: keyword "$k" is not in words');
      }
    }

    final quiz = <V3QuizQuestion>[];
    for (final q in (json['quiz'] as List? ?? const [])) {
      final m = (q as Map).cast<String, dynamic>();
      final options = (m['options'] as List?)?.cast<String>() ?? const [];
      final answer = m['answer'];
      if (options.length < 2 ||
          answer is! int ||
          answer < 0 ||
          answer >= options.length) {
        throw FormatException(
          'Story $id has a quiz question with a bad answer',
        );
      }
      quiz.add(
        V3QuizQuestion(
          prompt: str(m, 'prompt'),
          options: options,
          answer: answer,
          explain: str(m, 'explain'),
        ),
      );
    }
    if (quiz.isEmpty) throw FormatException('Story $id has no quiz');

    return V3Story(
      id: id,
      title: str(json, 'title'),
      titleEn: str(json, 'titleEn'),
      level: str(json, 'level'),
      minutes: (json['minutes'] as num?)?.toInt() ?? 3,
      summary: str(json, 'summary'),
      unit: (json['unit'] as String?) ?? '',
      sentences: sentences,
      words: words,
      keywords: keywords,
      quiz: quiz,
    );
  }
}
