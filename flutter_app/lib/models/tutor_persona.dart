import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The four tutor personas (PILOT_EXECUTION_PLAN.md P2.1): two accents
/// (France / Québec), one female and one male tutor per accent. A persona is a
/// display identity + a Gemini prebuilt voice + an accent/register block that
/// is composed into every live system prompt.
enum TutorAccent { france, quebec }

extension TutorAccentLabel on TutorAccent {
  String get label => switch (this) {
    TutorAccent.france => 'France',
    TutorAccent.quebec => 'Québec',
  };
}

class TutorPersona {
  const TutorPersona({
    required this.id,
    required this.displayName,
    required this.accent,
    required this.isFemale,
    required this.voiceName,
    required this.tagline,
    required this.sampleLine,
    required this.promptBlock,
  });

  /// Stable id persisted in prefs — never rename.
  final String id;
  final String displayName;
  final TutorAccent accent;
  final bool isFemale;

  /// Gemini Live / Gemini TTS prebuilt voice name.
  final String voiceName;

  /// One-line description for pickers.
  final String tagline;

  /// The spoken voice-preview sample (P2.2/onboarding v2): a few sentences in
  /// this tutor's own words, synthesized once with their real voice so the
  /// student can HEAR each tutor before choosing. Mixes French and English the
  /// way the tutor actually teaches.
  final String sampleLine;

  /// Identity + accent block composed into every live system prompt.
  final String promptBlock;

  String get initial => displayName.substring(0, 1);

  static const marie = TutorPersona(
    id: 'marie',
    displayName: 'Marie',
    accent: TutorAccent.france,
    isFemale: true,
    voiceName: 'Aoede',
    tagline: 'Warm and patient, from Lyon',
    sampleLine:
        "Bonjour ! Je m'appelle Marie. Hi, I'm Marie, from Lyon. We'll take "
        'French one small step at a time, and I promise: no rushing, ever. '
        'On y va ?',
    promptBlock:
        'You are Marie, a warm, patient French tutor from Lyon, France. You speak '
        'standard metropolitan French with clear, textbook pronunciation, exactly '
        'what the student will hear in exam listening materials.',
  );

  static const julien = TutorPersona(
    id: 'julien',
    displayName: 'Julien',
    accent: TutorAccent.france,
    isFemale: false,
    voiceName: 'Puck',
    tagline: 'Upbeat and direct, from Paris',
    sampleLine:
        "Salut ! Moi, c'est Julien. Hey, I'm Julien, from Paris. I like to "
        "keep things moving, celebrate every win, and get you speaking out "
        "loud from day one. Prêt ?",
    promptBlock:
        'You are Julien, an upbeat, encouraging French tutor from Paris, France. '
        'You speak standard metropolitan French with clear pronunciation, and you '
        'keep the energy high without ever rushing the student.',
  );

  static const camille = TutorPersona(
    id: 'camille',
    displayName: 'Camille',
    accent: TutorAccent.quebec,
    isFemale: true,
    voiceName: 'Leda',
    tagline: 'Friendly Québécoise, from Montréal',
    sampleLine:
        "Allô ! Moi, c'est Camille, de Montréal. Hi, I'm Camille. I'll teach "
        "you the French people actually speak here in Canada, eh, c'est "
        "correct if you make mistakes, that's how we learn. Bienvenue !",
    promptBlock:
        'You are Camille, a friendly French tutor from Montréal, Québec. You speak '
        'Québec French: use natural, everyday Québécois pronunciation and expressions '
        'where they fit (bienvenue for "you\'re welcome", c\'est correct, dispendieux, '
        'déjeuner/dîner/souper for the meals), but keep it beginner-clear, introduce '
        'any Québécois expression gently, and gloss it in English the first time. This '
        'is exactly the French the student will hear in Canada and on TEF Canada.',
  );

  static const mathieu = TutorPersona(
    id: 'mathieu',
    displayName: 'Mathieu',
    accent: TutorAccent.quebec,
    isFemale: false,
    voiceName: 'Orus',
    tagline: 'Calm Québécois, from Québec City',
    sampleLine:
        "Bonjour, bonjour ! Je m'appelle Mathieu, de la ville de Québec. "
        "Hi, I'm Mathieu. We'll go steady and calm, on jase en français un "
        "peu chaque jour, a little chat in French every day. Ça te va ?",
    promptBlock:
        'You are Mathieu, a calm, steady French tutor from Québec City. You speak '
        'Québec French: use natural, everyday Québécois pronunciation and expressions '
        'where they fit (bienvenue for "you\'re welcome", c\'est correct, jaser for '
        '"to chat", déjeuner/dîner/souper for the meals), but keep it beginner-clear, '
        'introduce any Québécois expression gently, and gloss it in English the first '
        'time. This is exactly the French the student will hear in Canada and on TEF '
        'Canada.',
  );

  static const all = [marie, julien, camille, mathieu];

  /// Unknown/legacy ids fall back to Marie — a persona must never be null.
  static TutorPersona byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => marie);

  static List<TutorPersona> byAccent(TutorAccent accent) =>
      all.where((p) => p.accent == accent).toList(growable: false);
}

/// App-wide active persona, readable synchronously from any widget and
/// listenable for live updates. Loaded once at startup; changed only from
/// Settings/Onboarding (never mid-call — a running call keeps the persona it
/// connected with).
class ActiveTutor {
  ActiveTutor._();

  static const _prefsKey = 'tutor_persona_id';

  static final ValueNotifier<TutorPersona> notifier = ValueNotifier(
    TutorPersona.marie,
  );

  static TutorPersona get current => notifier.value;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      notifier.value = TutorPersona.byId(prefs.getString(_prefsKey));
    } catch (_) {
      // Prefs unavailable (fresh install edge) — Marie default stands.
    }
  }

  static Future<void> set(TutorPersona persona) async {
    notifier.value = persona;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, persona.id);
  }
}

/// The two prompt-level tutor tuning knobs (P2.3), persisted app-wide.
/// Values are read at call setup — changing them mid-call applies from the
/// next call on.
class TutorTuning {
  TutorTuning._();

  static const mixKey = 'tutor_language_mix';
  static const speedKey = 'tutor_voice_speed';

  static const mixValues = ['gentle', 'balanced', 'immersive'];
  static const speedValues = ['slower', 'natural', 'faster'];

  static Future<String> languageMix() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(mixKey);
    return mixValues.contains(v) ? v! : 'balanced';
  }

  static Future<String> voiceSpeed() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(speedKey);
    return speedValues.contains(v) ? v! : 'natural';
  }

  static Future<void> saveLanguageMix(String value) async {
    assert(mixValues.contains(value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(mixKey, value);
  }

  static Future<void> saveVoiceSpeed(String value) async {
    assert(speedValues.contains(value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(speedKey, value);
  }

  /// Prompt line for the chosen English/French mix. Framed as a preference the
  /// stage-specific rules can override — the vocab stage's level-based language
  /// rules, for example, always win inside that stage.
  static String mixPromptLine(String mix) => switch (mix) {
    'gentle' =>
      "STUDENT'S CHOSEN LANGUAGE MIX: GENTLE: lead in English; French appears "
          'mainly as the material being practiced, always paired with its English '
          'meaning. If the LESSON CONTEXT gives more specific language-balance '
          'rules for this stage, those win.',
    'immersive' =>
      "STUDENT'S CHOSEN LANGUAGE MIX: IMMERSION: lead in simple, clear French "
          'and drop to English only when the student is lost or asks. If the '
          'LESSON CONTEXT gives more specific language-balance rules for this '
          'stage, those win.',
    _ =>
      "STUDENT'S CHOSEN LANGUAGE MIX: BALANCED: mix English explanations with "
          'plenty of spoken French practice, following the student\'s lead. If the '
          'LESSON CONTEXT gives more specific language-balance rules for this '
          'stage, those win.',
  };

  /// Prompt line for the chosen speaking pace.
  static String speedPromptLine(String speed) => switch (speed) {
    'slower' =>
      'PACE: speak noticeably slowly and articulate every word clearly, with '
          'short pauses between phrases, the student chose a slower pace.',
    'faster' =>
      'PACE: speak at a brisk, natural native pace, the student chose faster '
          'speech to train their ear.',
    _ => 'PACE: speak at a relaxed, natural conversational pace.',
  };
}
