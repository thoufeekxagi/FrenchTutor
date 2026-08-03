import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/api_keys.dart';
import '../models/content_models.dart';
import '../utils/generated_text.dart';
import '../models/tutor_persona.dart';

/// The "brain" behind lesson labs: answers questions, grades writing, explains
/// wrong quiz answers — text-only (voice is LessonSpeechService / GeminiLiveService).
///
/// Text generation uses Gemini Flash-Lite.
/// Thrown by any raw Gemini HTTP call in this file (TTS synthesis, text
/// generation) instead of the generic [AgentError] so callers can tell a
/// rate limit (429, back off longer and retry) apart from any other
/// failure (back off briefly and retry, then give up).
class GeminiHttpError implements Exception {
  GeminiHttpError(this.statusCode, {this.retryAfter});

  factory GeminiHttpError.fromResponse(http.Response response) {
    final retryMatch = RegExp(
      r'Please retry in ([0-9.]+)s',
    ).firstMatch(response.body);
    final seconds = double.tryParse(retryMatch?.group(1) ?? '');
    return GeminiHttpError(
      response.statusCode,
      retryAfter: seconds == null
          ? null
          : Duration(milliseconds: (seconds * 1000).ceil() + 500),
    );
  }

  final int statusCode;
  final Duration? retryAfter;

  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'GeminiHttpError($statusCode)';
}

class AgentError implements Exception {
  const AgentError._(this.message);

  final String message;

  static const missingKey = AgentError._(
    'AI feedback unavailable, add a Gemini key in Settings.',
  );
  static const requestFailed = AgentError._(
    'The AI tutor is busy right now. Try again in a moment.',
  );
  static const badResponse = AgentError._(
    'The AI tutor gave an unexpected response.',
  );

  static AgentError badJSON(String raw) => AgentError._(
    'LLM returned non-JSON: ${raw.substring(0, raw.length > 200 ? 200 : raw.length)}',
  );

  @override
  String toString() => message;
}

class WritingFeedback {
  WritingFeedback({
    required this.scoreOutOf10,
    required this.strengths,
    required this.corrections,
    required this.connectorFeedback,
    required this.improvedVersion,
    this.nextSteps = const [],
  });

  final double scoreOutOf10;
  final List<String> strengths;
  final List<({String original, String fixed, String why})> corrections;
  final String connectorFeedback;
  final String improvedVersion;

  /// 2-4 concrete, actionable tips for what to work on next — the
  /// TCF-examiner-style "how to improve" a plain score/corrections list
  /// doesn't give on its own. May be empty for older cached feedback
  /// generated before this field existed.
  final List<String> nextSteps;
}

class MicroWritingFeedback {
  MicroWritingFeedback({required this.scoreOutOf10, required this.comment});

  final double scoreOutOf10;
  final String comment;
}

class SpeakingMockFeedback {
  SpeakingMockFeedback({
    required this.overallScore,
    required this.clbEstimate,
    required this.taskCompletion,
    required this.fluency,
    required this.grammar,
    required this.vocabulary,
    required this.strengths,
    required this.nextSteps,
  });

  final double overallScore;
  final String clbEstimate;
  final double taskCompletion;
  final double fluency;
  final double grammar;
  final double vocabulary;
  final List<String> strengths;
  final List<String> nextSteps;
}

/// One rung of the Socratic hint ladder for in-progress writing. Never
/// contains the corrected sentence — only a nudge scoped to [tier]. The app
/// tracks how many rungs a learner has climbed, not the service; each call
/// is stateless and just asked to answer at a given tier.
class WritingHint {
  WritingHint({required this.tier, required this.message});

  final int tier;
  final String message;
}

class MistakeJudgment {
  MistakeJudgment({required this.isCorrect, this.tag, this.description});

  final bool isCorrect;
  final String? tag;
  final String? description;
}

class SessionPlan {
  SessionPlan({required this.focusNote, this.prioritizedWordIds});

  final String focusNote;
  final List<String>? prioritizedWordIds;
}

class GrammarSessionPlan {
  GrammarSessionPlan({required this.chosenId, required this.focusNote});

  final String chosenId;
  final String focusNote;
}

/// What the student's utterance means for a live session, judged with full card
/// context instead of keyword matching. `attempt` = they practiced the target;
/// `chat` = conversation/question/echo — neither is a navigation command.
/// `goto` carries a 1-based card number ("go to the third card").
/// `finish` = they want to end the lesson ("let's finish this lesson", "I'm done").
enum LiveNavIntent { advance, back, again, attempt, chat, goto, finish }

class LiveIntentVerdict {
  LiveIntentVerdict({
    required this.intent,
    this.cardNumber,
    this.explicit = true,
  });

  final LiveNavIntent intent;

  /// 1-based target card, only set when [intent] is [LiveNavIntent.goto].
  final int? cardNumber;

  /// True when the utterance itself is a navigation command ("next word", "skip");
  /// false when it's mere agreement to the tutor's own offer ("yes", "oui", "sure").
  /// The app honors explicit commands unconditionally (user sovereignty) but honors
  /// consent only if the tutor's offer was legal — i.e. enough practice had happened.
  final bool explicit;
}

class LessonAgentService {
  LessonAgentService._();

  static final LessonAgentService shared = LessonAgentService._();

  /// Output-language + content guardrail for every prompt whose text reaches the
  /// student's eyes or ears (PILOT_EXECUTION_PLAN.md P0.1/P0.6). Invisible JSON
  /// judges/planners don't carry it — their output is never shown. Mirrors
  /// LivePrompts.languageGuardrail + contentSafety.
  static const languageGuardrail =
      ' LANGUAGE RULE: ABSOLUTE: reply ONLY in French and English, never any other '
      'language, whatever language the student used; never translate or engage with '
      'other-language text, say in English that this course works in French and '
      'English, and stay on the task. CONTENT POLICY: ABSOLUTE: keep every reply '
      'family-friendly; never use profanity, slurs, or sexual, violent, hateful, or '
      'otherwise inappropriate language; if the student\'s text contains offensive '
      'content, never repeat it, respond calmly and stay on the lesson. '
      'STYLE: never use emojis or em dashes in any output.';

  /// Pinned (not `-latest`) so a Google-side model bump can't silently change
  /// cost or quality mid-testing. Re-pinned 2026-07-29: `gemini-2.5-flash-lite`
  /// started returning HTTP 404 "no longer available to new users" well
  /// before its estimated 2026-10-16 retirement — every text-generation call
  /// in the shipped app was failing. Discovered via the
  /// personalized_test_verification/ harness's smoke test.
  /// `gemini-3.1-flash-lite` is the cheapest currently-available Flash-Lite
  /// tier ($0.25/$1.50 per 1M input/output tokens vs. $0.30/$2.50 for
  /// `gemini-3.5-flash-lite`; `gemini-2.0-flash-lite` was shut down entirely
  /// in June 2026). Re-pin again once 3.1 shows similar signs of retiring.
  static const _geminiTextModel = 'gemini-3.1-flash-lite';

  static const _openRouterModel = 'nvidia/nemotron-3-super-120b-a12b:free';

  /// Model choice is a code decision, never user- or settings-configurable.
  static const _forceOpenRouter = false;

  Future<String> get _openRouterApiKey async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('openrouter_api_key');
    if (stored != null && stored.isNotEmpty) return stored;
    return ApiKeys.openRouterKey;
  }

  Future<String> get _geminiApiKey async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('gemini_api_key');
    if (stored != null && stored.isNotEmpty) return stored;
    return ApiKeys.geminiKey;
  }

  static String extractJSON(String raw) {
    var s = raw.trim();
    // Strip markdown code fences: ```json ... ``` or ``` ... ```
    if (s.startsWith('```')) {
      final firstNewline = s.indexOf('\n');
      if (firstNewline != -1) {
        s = s.substring(firstNewline + 1);
      }
      if (s.endsWith('```')) {
        s = s.substring(0, s.length - 3).trim();
      }
    }
    final objStart = s.indexOf('{');
    final objEnd = s.lastIndexOf('}');
    if (objStart != -1 && objEnd != -1 && objEnd > objStart) {
      return s.substring(objStart, objEnd + 1);
    }
    final arrStart = s.indexOf('[');
    final arrEnd = s.lastIndexOf(']');
    if (arrStart != -1 && arrEnd != -1 && arrEnd > arrStart) {
      return s.substring(arrStart, arrEnd + 1);
    }
    return s;
  }

  // MARK: - Public API

  /// Bilingual tutor persona; answers are meant to be spoken aloud, so no markdown, ≤120 words.
  Future<String> askQuestion({
    required String lessonContext,
    required String question,
    List<({String role, String text})> history = const [],
  }) async {
    const system = '''
You are a friendly, encouraging bilingual (English/French) French tutor helping a student preparing for the TEF/TCF Canada exam (target CLB 7). The student is mid-lesson; use the LESSON CONTEXT to ground your answer. Keep answers under 120 words, spoken-style, no markdown, no bullet lists, no asterisks, since your reply will be read aloud by a speech synthesizer. Answer in English unless the student asks in French or asks for a French example.''';
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content':
            '$system$languageGuardrail\n\nLESSON CONTEXT:\n$lessonContext',
      },
    ];
    for (final turn in history) {
      messages.add({
        'role': turn.role == 'user' ? 'user' : 'assistant',
        'content': turn.text,
      });
    }
    messages.add({'role': 'user', 'content': question});
    return _complete(messages: messages);
  }

  /// Concrete, non-negotiable difficulty guardrails for roleplay/reading/story
  /// generation, keyed by CEFR band. Without this, prompts that only said
  /// "keep it appropriate to the CEFR band" left the model to guess, and it
  /// consistently guessed too hard for A1/A2 — real words/sentences but not
  /// beginner-simple. Mirrors the concreteness of `generateWritingTask`'s
  /// calibration block below, just phrased for dialogue/narrative content.
  static String _cefrCalibration(String levelBand) {
    final band = levelBand.trim().toLowerCase();
    switch (band) {
      case 'a1':
        return '''
CEFR CALIBRATION FOR A1, FOLLOW EXACTLY:
- Present tense ONLY. No passé composé, no futur, no subjunctive, no conditional.
- Every sentence 3-7 words. One idea per sentence, no subordinate clauses, no "qui/que/si/parce que".
- Vocabulary limited to the ~300-500 most common beginner words: greetings, numbers, family, food, basic verbs (être, avoir, aller, vouloir, aimer, s'appeler), simple nouns for everyday objects/places. No idioms, no rare words.
- If in doubt, write it simpler, even if it feels too easy.''';
      case 'a2':
        return '''
CEFR CALIBRATION FOR A2, FOLLOW EXACTLY:
- Present tense plus simple passé composé and futur proche allowed. No imparfait, no subjunctive, no conditional.
- Sentences up to about 10 words, mostly one clause; at most one simple connector per sentence (et, mais, parce que, alors).
- Vocabulary: common everyday words for shopping, transport, routines, simple feelings. Avoid rare or literary words.
- If in doubt, write it simpler, even if it feels too easy.''';
      case 'b1':
        return '''
CEFR CALIBRATION FOR B1, FOLLOW EXACTLY:
- Present, passé composé, imparfait, and futur simple allowed. Occasional simple subordinate clauses (qui/que/si) are fine. No subjunctive or complex conditional chains.
- Sentences up to about 15 words.
- Vocabulary: moderately varied everyday and some abstract words, still no rare/literary/idiomatic language.''';
      case 'b2':
        return '''
CEFR CALIBRATION FOR B2, FOLLOW EXACTLY:
- Full range of common tenses allowed, including subjonctif and conditionnel where natural.
- Sentences can be longer and combine clauses with connectors like "néanmoins", "bien que", "quant à".
- Vocabulary: more precise and idiomatic language is fine, this learner is past the beginner stage.''';
      default:
        return '''
CEFR CALIBRATION FOR $levelBand: use present tense and short, simple sentences with common everyday vocabulary unless the level is clearly advanced. When unsure of the learner's exact level, err toward simpler, not harder.''';
    }
  }

  Future<WritingFeedback> gradeWriting({
    required WritingTask task,
    required String submission,
    required String levelBand,
  }) async {
    final system =
        '''
You are a professional French writing examiner grading like a TCF/TEF rater — strict but encouraging. Grade the student's submission against the task, calibrated to their CEFR level ($levelBand) — do NOT hold an A1/A2 learner to a B2 essay bar; judge them against what is realistic at their stated level (task completion, basic grammar/agreement accuracy, use of the vocabulary/connectors actually asked for, coherence). Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape:
{"score_out_of_10": number, "strengths": [string,...], "corrections": [{"original": string, "fixed": string, "why": string}, ...], "connector_feedback": string, "improved_version": string, "next_steps": [string,...]}
LANGUAGE, ABSOLUTE RULE: this student is a beginner and reads explanations in English, not French. Every explanatory piece of text — every "strengths" entry, every "why", "connector_feedback", and every "next_steps" entry — MUST be written in English, always, no matter what language the student wrote their submission in. The ONLY French allowed anywhere in the response is inside "original", "fixed", and "improved_version" (the student's actual sentences), since those are the language content being corrected, not an explanation.
"why" should read like a professional examiner's note: name the specific grammar rule or agreement broken, not just "this is wrong" — e.g. "The verb 's'appeler' needs two p's and two l's, and an apostrophe before 'appelle'." rather than a vague comment.
"next_steps": 2 to 4 concrete, actionable tips for what this student should specifically practice next based on THIS submission (e.g. a recurring error pattern, a CEFR skill to work on) — not generic advice.''';
    final user =
        '''
LEVEL: $levelBand
TASK: ${task.title}
PROMPT: ${task.promptFr}
MINIMUM WORDS: ${task.minWords}
TARGET CONNECTORS: ${task.targetConnectors.join(', ')}

STUDENT SUBMISSION:
$submission''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
    );
    return _parseWritingFeedback(raw);
  }

  /// Generates one writing task calibrated to the learner's CEFR level and
  /// actual known vocabulary — replaces reaching for the static bank (still
  /// used as an offline fallback) so an A1 learner gets "one short sentence
  /// with words you already know" instead of a fixed TEF-style essay prompt
  /// meant for B2. [knownVocab] should be French words the learner has
  /// actually mastered (see `ContentService.knownVocabWords`); an empty list
  /// is fine for a brand-new learner, the model just leans on very common
  /// beginner words instead.
  /// A rotating pool of everyday scenarios to seed variety — without this,
  /// two calls with the same level and roughly the same known-vocabulary
  /// list (which barely changes day to day) converge on near-identical
  /// prompts, since nothing else differs between requests. Picked at
  /// random unless the caller supplies its own [topic].
  static const _writingTopics = [
    'describing your morning routine',
    'talking about your favourite food',
    'planning a weekend trip',
    'describing your family',
    'talking about the weather today',
    'describing your home or neighbourhood',
    'talking about a hobby you enjoy',
    'describing a typical day at work or school',
    'talking about your favourite season',
    'describing a friend',
    'talking about what you did yesterday',
    'planning what to buy at the market',
    'a small disagreement with a friend and how you resolved it',
    'a surprising thing that happened on public transport',
    'defending an unpopular opinion about a movie or a food',
    'a mistake you made and what you learned from it',
    'a place you want to visit and why, in your own words',
    'convincing a friend to try something new',
    'a childhood memory that still makes you laugh',
    'describing your dream job and why it appeals to you',
    'a time you helped a stranger, or a stranger helped you',
    'comparing life in a city versus a small town',
    'a tradition or celebration that matters to you and why',
    'explaining a rule you disagree with',
    'a decision you are currently torn about',
    'describing your ideal weekend if money were no object',
    'a skill you wish you had and why',
    'a small act of kindness you witnessed recently',
    'your reaction to an unexpected piece of good news',
    'planning a surprise for someone you care about',
  ];

  Future<WritingTask> generateWritingTask({
    required String levelBand,
    required List<String> knownVocab,
    String? topic,
    List<({String tag, String description, int count})> mistakeTags = const [],
    List<String> recentDiary = const [],
  }) async {
    final system =
        '''
Write one French writing-practice task for a language learner, calibrated STRICTLY to their CEFR level. Respond with ONLY compact JSON with this exact shape: {"title": string, "type": string, "prompt_fr": string, "prompt_en": string, "min_words": number, "target_connectors": [string,...], "rubric_hints": [string,...]}.
"type" is a short label like "micro" or "email" or "opinion". "rubric_hints" are 2-4 short English bullet points on what a good answer includes.
FORMAT RULE FOR "prompt_fr"/"prompt_en", ABSOLUTE — READ THIS TWICE: these two fields must be a QUESTION or an INSTRUCTION addressed directly TO the student (start with an imperative like "Écris...", "Décris...", "Raconte...", "Parle de...", or a direct question like "Où habites-tu ?"), asking them to produce their OWN original sentences. They must NEVER be a statement of fact, a narrated example, or anything that already reads as a complete, correct answer — if a student could just copy "prompt_fr" verbatim into the answer box and be done, you have generated it WRONG.
BAD, NEVER DO THIS (this is an already-written answer, not a task): prompt_fr: "Je suis avec ma famille. Je suis content." / prompt_en: "I am with my family. I am happy."
GOOD (this is an instruction the student must respond to): prompt_fr: "Écris deux phrases sur ta famille et comment tu te sens aujourd'hui." / prompt_en: "Write two sentences about your family and how you feel today."
DYNAMISM, JUST AS IMPORTANT AS THE FORMAT RULE ABOVE: this must feel as varied and alive as this app's story generator, never a flat recycled "describe your morning" every time. Use the SEED DETAILS below (a character, a setting, a twist) as genuine creative fuel for an interesting, specific angle — a scenario, a small dilemma, an opinion to defend, a mystery to explain — not just a generic daily-routine description. Two prompts at the same level should never feel interchangeable.
LEVEL CALIBRATION, FOLLOW EXACTLY — this governs how SHORT/simple the instruction and the expected answer are, it NEVER means the task itself should feel dumbed-down, boring, or babyish. Even at A1, an interesting specific scenario beats a generic one; at B1/B2 actively push the student towards their level's ceiling of complexity/nuance, don't play it safe and default to the easiest version of the level:
- A1: the instruction should be answerable in exactly 1-2 very short sentences, built ONLY from the KNOWN VOCABULARY given below plus basic function words (articles, "je/tu/il", "être/avoir", "et"). min_words 5-10. target_connectors: empty list.
- A2: answerable in 3-4 short sentences on an everyday topic, mostly using the known vocabulary plus a few very common extra words. min_words 15-30. target_connectors: at most 1 simple connector (e.g. "et", "mais", "parce que").
- B1: answerable in a short paragraph (5-8 sentences), may introduce a couple of new but common words beyond the known list. min_words 40-70. target_connectors: 1-2.
- B2: answerable as a fuller opinion/complaint/narrative piece, TEF-style. min_words 120-180. target_connectors: 2-3 (e.g. "néanmoins", "quant à", "bien que").
Never ask for anything harder than the stated level allows, even if the topic invites it.
INVENT A FRESH, SPECIFIC PROMPT EVERY TIME — never repeat the same scenario or phrasing as a previous call, even with the same vocabulary and level.
${mistakeTags.isEmpty ? '' : 'If it fits naturally, gently work in a chance to practice one of the RECURRING MISTAKES below — never force it, never call it out as "fixing a mistake", just a natural opportunity.'}''';
    final vocabLine = knownVocab.isEmpty
        ? 'KNOWN VOCABULARY: (none recorded yet — use only the most basic beginner words)'
        : 'KNOWN VOCABULARY: ${knownVocab.take(40).join(', ')}';
    final chosenTopic =
        topic ?? _writingTopics[Random().nextInt(_writingTopics.length)];
    // Same seeding technique as `buildPersonalStory` — this is what gives
    // stories their variety, and was entirely missing here before, which is
    // why writing prompts felt flat and repetitive by comparison.
    final random = Random();
    final seedName =
        _storyCharacterNames[random.nextInt(_storyCharacterNames.length)];
    final seedSetting = _storySettings[random.nextInt(_storySettings.length)];
    final seedTwist = _storyTwists[random.nextInt(_storyTwists.length)];
    final buf = StringBuffer()
      ..writeln('LEVEL: $levelBand')
      ..writeln(vocabLine)
      ..writeln('TOPIC (loose inspiration only): $chosenTopic')
      ..writeln(
        'SEED DETAILS for a specific, creative angle (use naturally, do not just state them): '
        'a person named $seedName, a setting around $seedSetting, involving $seedTwist.',
      );
    if (mistakeTags.isNotEmpty) {
      buf.writeln(
        'RECURRING MISTAKES (optional to touch on): '
        '${mistakeTags.map((m) => m.description).take(3).join('; ')}',
      );
    }
    if (recentDiary.isNotEmpty) {
      buf.writeln(
        'RECENT PRACTICE, for light context only, do not reference directly: '
        '${recentDiary.take(2).join(' | ')}',
      );
    }
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': buf.toString()},
      ],
      maxTokens: 600,
      temperature: 0.95,
    );
    return _parseWritingTask(raw);
  }

  Future<SpeakingMockFeedback> gradeSpeakingMock({
    required String monologuePrompt,
    required String monologueTranscript,
    required String interactionPrompt,
    required String interactionTranscript,
  }) async {
    const system = '''
You are a strict TEF/TCF Canada speaking examiner. Assess only evidence present in the learner transcripts. Speech recognition may contain minor transcription noise, so do not penalize an isolated spelling artifact. Score task completion, fluency/coherence, grammatical range/accuracy, and vocabulary range/precision from 0 to 10. Estimate a CLB band conservatively. Give specific, brief feedback in English. Respond with ONLY compact JSON matching exactly:
{"overall_score": number, "clb_estimate": string, "task_completion": number, "fluency": number, "grammar": number, "vocabulary": number, "strengths": [string, string], "next_steps": [string, string]}''';
    final user =
        '''
TASK 1, MONOLOGUE
Prompt: $monologuePrompt
Learner transcript: ${monologueTranscript.isEmpty ? '(no usable response)' : monologueTranscript}

TASK 2, INTERACTION
Prompt: $interactionPrompt
Learner transcript: ${interactionTranscript.isEmpty ? '(no usable response)' : interactionTranscript}''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
    );
    return _parseSpeakingMockFeedback(raw);
  }

  /// Runs invisibly alongside a live vocab session — takes what the student was asked to say
  /// and what speech recognition captured, and judges whether it was a reasonable attempt.
  /// Never shown to the user directly; only feeds the mistake ledger. Fire-and-forget by
  /// design: callers should swallow errors rather than surface them, since this is a nice-to-have
  /// enrichment, not part of the live conversation loop.
  Future<MistakeJudgment> judgePronunciationAttempt({
    required String targetWord,
    required String studentSaid,
  }) async {
    // Kept as short as possible — this call fires on nearly every turn of a live session,
    // so its fixed cost multiplies fast; every token trimmed here is the single biggest
    // lever on this service's total token spend.
    const system = '''
Silently audit a French pronunciation attempt (student never sees this). They were asked to say a French word aloud; below is what speech recognition captured (imperfect, be lenient on transcription noise, but flag real errors: wrong verb form, confused similar word, wrong word, silence). Reply with ONLY compact JSON, no markdown, no commentary: {"correct": boolean, "tag": string_or_null, "description": string_or_null}. tag = short stable snake_case slug for the error type (e.g. "nasal_vowel_confusion"), reused across words so it can be tracked over time. Both null when correct is true.''';
    final user =
        'TARGET WORD: $targetWord\nSPEECH RECOGNITION CAPTURED: $studentSaid';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    );
    return _parseMistakeJudgment(raw);
  }

  /// The context-aware replacement for the screens' keyword `_detectIntent`. One call per
  /// completed student utterance during a live session — Flash-Lite is fast enough
  /// (~0.7s measured) that this sits inside the natural turn-taking gap. If this fails,
  /// callers leave navigation unchanged and keep the on-screen controls available.
  ///
  /// Consent rule (the student was clear about this): navigation must be EXPLICIT.
  /// A bare "yes" advances only when it directly answers the tutor's own move-on
  /// question; anything ambiguous stays put. The card + tutor-last-line context is what
  /// makes it not tunnel-visioned: "yes, next to the station" is an answer, not a
  /// command, and an echo of the tutor's own voice is nothing at all.
  Future<LiveIntentVerdict> classifyLiveIntent({
    required String utterance,
    required String cardDescription,
    required String tutorLastLine,
    required int attemptCount,
    required int cardPosition,
    required int cardCount,
  }) async {
    const system = '''
You classify one utterance from a student in a live voice French lesson. The app, not the tutor, moves the on-screen card based on your verdict. Reply with ONLY compact JSON: {"intent": "advance"|"back"|"again"|"attempt"|"chat"|"goto"|"finish", "card": number_or_null, "explicit": boolean}.
- "finish": an EXPLICIT request to end the whole lesson/session ("let's finish this lesson", "I'm done for today", "end the session"), NOT merely finishing the current word.
- "advance": an EXPLICIT request to move to the next card ("next", "next word", "got it, let's move on", "suivant"), set "explicit": true. A bare "yes"/"oui"/"sure" counts ONLY if the tutor's last line directly asked whether to move on, never otherwise, and is "explicit": false (it's consent to the tutor's offer, not the student's own command). "explicit" is true for every other navigation verdict (back/goto/again).
- "back": an explicit request to return to the previous card.
- "goto": an explicit request to jump to a specific card by number or position ("go to the third card", "back to card 2", "the first one", "the last card"), set "card" to the 1-based target number, using the card position/count given.
- "again": they want the current item repeated or re-explained.
- "attempt": they are practicing/attempting the current target (saying the French word or sentence, possibly imperfectly, speech recognition is noisy, be lenient).
- "chat": anything else, a question, an answer to a non-navigation question, small talk. Words like "next"/"oui"/"continue" inside a longer sentence about something else (e.g. "the bakery is next to the station") are NOT commands.
ECHO RULE (critical): the mic sometimes picks up the tutor's own voice, so compare the utterance to the tutor's last line word by word. If it repeats the tutor's NON-TARGET words, her prompts or questions like "ready for the next?", it is an echo: "chat", NEVER navigation, even though it contains command-like words. Repeating only the target French word/sentence itself is the student practicing: "attempt".
Moving the card without the student's clear consent is the worst failure mode. When genuinely ambiguous, ALWAYS prefer "attempt" or "chat" over any navigation verdict. "card" is null except for "goto".''';
    final user =
        '''
CURRENT CARD (number $cardPosition of $cardCount): $cardDescription
TUTOR'S LAST LINE: ${tutorLastLine.isEmpty ? '(none yet)' : tutorLastLine}
GENUINE ATTEMPTS ON THIS CARD SO FAR: $attemptCount
STUDENT SAID: $utterance''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      maxTokens: 60,
      timeout: const Duration(seconds: 4),
    );
    final obj = _decodeObject(raw);
    final intentRaw = obj['intent'] as String?;
    final intent = LiveNavIntent.values
        .where((v) => v.name == intentRaw)
        .firstOrNull;
    if (intent == null) throw AgentError.badJSON(raw);
    final cardValue = obj['card'];
    final cardNumber = cardValue is int
        ? cardValue
        : (cardValue is double ? cardValue.toInt() : null);
    return LiveIntentVerdict(
      intent: intent,
      cardNumber: cardNumber,
      explicit: obj['explicit'] as bool? ?? true,
    );
  }

  /// Runs once, briefly, before a vocab session starts — looks at recurring mistakes and
  /// recent session history and decides what's worth emphasizing today, instead of always
  /// presenting the same fixed order. Callers should treat this as best-effort: on failure,
  /// fall back to the original candidate order with no focus note, no user-visible error.
  /// Curates the actual set of words a practice session shows, from a
  /// CANDIDATE POOL deliberately larger than [count] — this used to only
  /// ever be handed a pre-sliced list of exactly the words about to be
  /// shown (picked upstream in fixed curriculum order) and could merely
  /// reorder them, so even a perfect AI call was just reshuffling the same
  /// deterministic slice. Now it genuinely SELECTS which [count] words to
  /// serve, out of a much wider pool, the way `buildGrammarStory` picks a
  /// tense rather than being handed one. [recentKeywords] are words the
  /// student recently ran into in a generated story or grammar session —
  /// reinforcing those on purpose (not just "next in the textbook") is what
  /// was asked for as "AI and keywords working in tandem".
  Future<SessionPlan> planVocabSession({
    required List<VocabEntry> candidateWords,
    required int count,
    required List<({String tag, String description, int count})> mistakeTags,
    required List<String> recentDiary,
    List<String> recentKeywords = const [],
  }) async {
    final system =
        '''
You are quietly curating a French vocabulary practice session before it starts, the student won't see this reasoning, only the short focus note you write. From the CANDIDATE WORDS pool, SELECT exactly $count of them to actually practice today — do not just take the first $count in the list, genuinely choose based on everything below. Then write a one-sentence, warm, specific focus note for how today's session should be framed.
SELECTION PRIORITIES, IN ORDER:
1. If RECENT KEYWORDS are given (words the student just ran into in a story or grammar lesson), prefer including a few of those among your $count if they're present in the candidate pool — reinforcing something they just encountered elsewhere in the app beats a cold, unconnected word every time.
2. If RECURRING MISTAKES are given, favor words that would let them practice past that specific confusion.
3. Otherwise, favor an interesting, varied, thematically-loose mix over "next in alphabetical/curriculum order" — avoid picking a set that feels like the same category every time.
Respond with ONLY a compact JSON object: {"focus_note": string, "prioritized_word_ids": array_of_strings}. "prioritized_word_ids" MUST contain exactly $count ids (or fewer only if the candidate pool itself has fewer than $count entries), every one of them must be an exact id from CANDIDATE WORDS, never invent a new one, and never repeat an id.''';
    final wordList = candidateWords
        .map((w) => '${w.id}: ${w.fr} (${w.en})')
        .join('; ');
    var user = 'CANDIDATE WORDS: $wordList';
    if (recentKeywords.isNotEmpty) {
      user += '\n\nRECENT KEYWORDS (seen in a recent story/grammar session, reinforce if present above): ${recentKeywords.join(', ')}';
    }
    if (mistakeTags.isNotEmpty) {
      user +=
          '\n\nRECURRING MISTAKES: ${mistakeTags.map((m) => '${m.description} (seen ${m.count}x)').join('; ')}';
    }
    if (recentDiary.isNotEmpty) {
      user += '\n\nRECENT SESSION NOTES: ${recentDiary.join(' | ')}';
    }
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
      temperature: 0.9,
    );
    return _parseSessionPlan(
      raw,
      validIds: candidateWords.map((w) => w.id).toSet(),
      count: count,
    );
  }

  /// Runs once, briefly, before a grammar session starts, when the student picks "Auto" in
  /// the grammar picker — looks at recurring mistakes and recent session history and picks
  /// ONE tense/topic from the candidate list to focus on today, exactly the same best-effort
  /// shape as `planVocabSession` (fall back to the first candidate, no focus note, on failure).
  Future<GrammarSessionPlan> planGrammarSession({
    required List<({String id, String title})> candidates,
    required List<({String tag, String description, int count})> mistakeTags,
    required List<String> recentDiary,
  }) async {
    final system = '''
You are quietly picking which ONE French grammar point a beginner should practice today, the student won't see this reasoning, only the short focus note you write. Given the candidate list of tenses/topics, the student's recurring mistake patterns, and recent session notes, choose the single most useful one to practice right now (e.g. if their mistakes suggest passé composé confusion, pick that), and write a one-sentence warm, specific focus note for how today's session should be framed. If nothing stands out, pick the first candidate. Respond with ONLY a compact JSON object: {"chosen_id": string, "focus_note": string}. chosen_id MUST be exactly one of the candidate IDs given, never invent a new one.''';
    final list = candidates.map((c) => '${c.id}: ${c.title}').join('; ');
    var user = 'CANDIDATES: $list';
    if (mistakeTags.isNotEmpty) {
      user +=
          '\n\nRECURRING MISTAKES: ${mistakeTags.map((m) => '${m.description} (seen ${m.count}x)').join('; ')}';
    }
    if (recentDiary.isNotEmpty) {
      user += '\n\nRECENT SESSION NOTES: ${recentDiary.join(' | ')}';
    }
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
    );
    return _parseGrammarSessionPlan(
      raw,
      validIds: candidates.map((c) => c.id).toSet(),
      fallbackId: candidates.isNotEmpty ? candidates.first.id : '',
    );
  }

  /// Runs ONCE, right after the vocab stage ends, if the student picks "a short reading/
  /// listening session on the words I just practiced" — assembles a short French passage/
  /// dialogue that naturally reuses those words, broken into `ReadingSegment`s (word/phrase,
  /// meaning, one simple grammar note, one pronunciation tip). This is pre-generation, not live
  /// teaching: the result is cached and handed to the listening screen exactly like
  /// offline-authored content — the model is never called again during the teaching session
  /// itself. Grammar notes are intentionally kept simple (no conjugation tables, no advanced
  /// tense discussion) for this first version.
  Future<ReadingPassage> buildReadingPassageFromVocab({
    required List<VocabEntry> words,
    required String levelBand,
  }) async {
    final system =
        '''
You are quietly writing a complete two-role ROLEPLAY SCRIPT for a learner preparing for TEF/TCF Canada, a real-life situation (café, bakery, bus, pharmacy, market...) where the LEARNER plays the customer/visitor and a CHARACTER (server, vendor, clerk) plays the other side. The app will stage this script beat by beat like a director, every line is fixed here, nothing is improvised later. Use ONLY the vocabulary words given below (plus basic connecting words like articles, "et", "je", "est", "s'il vous plaît" as needed for grammatical French), do not introduce unrelated advanced vocabulary. Pick the most natural everyday scenario these words allow.
Write 4-8 beats in scene order (greeting → request → follow-up → thanks/goodbye). Each beat has the CHARACTER's line first (short, simple French that naturally prompts the learner) and then the LEARNER's reply line. Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape:
{"title": string, "beats": [{"character_fr": string, "character_en": string, "learner_fr": string, "learner_en": string, "grammar_note": string, "pronunciation_tip": string}, ...]}
"title" is the scenario in a few words (e.g. "At the bakery"). "character_fr"/"character_en" are the character's line and its English meaning; "learner_fr"/"learner_en" the learner's reply and meaning; "grammar_note" one simple English sentence explaining the learner line's word order/agreement; "pronunciation_tip" one simple English pronunciation pointer for the learner line.
${_cefrCalibration(levelBand)}''';
    final wordList = words.map((w) => '${w.fr} (${w.en})').join(', ');
    final user = 'VOCABULARY WORDS TO REUSE: $wordList\nLEVEL: $levelBand';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
      maxTokens: 1400,
    );
    return _parseReadingPassage(raw);
  }

  Future<ReadingPassage> buildMissionRoleplay({
    required String missionTitle,
    required String scenario,
    required String levelBand,
    required String missionContext,
    required String speakingPrompt,
    required List<String> hints,
  }) async {
    final system =
        '''
Write a short two-role French roleplay for a language-learning mission. The app will direct it beat by beat, then Marie will continue the same scene live. Return ONLY compact JSON with this exact shape: {"title": string, "title_en": string, "beats": [{"character_fr": string, "character_en": string, "learner_fr": string, "learner_en": string, "grammar_note": string, "pronunciation_tip": string}]}. "title_en" is a short 2-4 word English gloss of "title" (e.g. French "Au café du coin" → English "At the corner café"), for a beginner who can't read the French title yet. Write 4 to 6 realistic beats: greeting, purpose, one follow-up, resolution, goodbye. Every learner line must support the mission prompt. Do not award a score or claim mastery.
${_cefrCalibration(levelBand)}
INVENT A FRESH, SPECIFIC SCENE EVERY TIME: pick a concrete setting, named character, and small realistic details (items, prices, times, a tiny complication) that fit the scenario type but differ from the obvious default. The same mission practiced on different days must feel like a different real-life moment, a boulangerie, a market stall, a train station kiosk, a pharmacy, a neighbour's door, never the same generic café twice.''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content':
              '''
MISSION: $missionTitle
SCENARIO: $scenario
LEVEL: $levelBand
MISSION CONTEXT: $missionContext
SPEAKING PROMPT: $speakingPrompt
USEFUL STARTERS: ${hints.join('; ')}''',
        },
      ],
      maxTokens: 1400,
    );
    return _parseReadingPassage(raw);
  }

  /// The Roleplay lab's own generator — a learner picks (or randomizes) a
  /// scenario like "café" or "airport" and gets a fresh scene to walk
  /// through in `AgentLedListeningScreen`, same JSON contract as
  /// `buildMissionRoleplay` above but with no mission fields to inject
  /// (there's no mission here, just a scenario the learner chose). Generated
  /// fresh every call, never pooled — a learner-picked scenario is a
  /// personal one-off, not a fixed prompt shared across every learner the
  /// way a mission's roleplay prompt is.
  Future<ReadingPassage> buildStandaloneRoleplay({
    required String scenario,
    required String levelBand,
  }) async {
    final system =
        '''
Write a short two-role French roleplay scene for a language learner to practice. The app will direct it beat by beat, then a live tutor will continue the same scene. Return ONLY compact JSON with this exact shape: {"title": string, "title_en": string, "beats": [{"character_fr": string, "character_en": string, "learner_fr": string, "learner_en": string, "grammar_note": string, "pronunciation_tip": string}]}. "title_en" is a short 2-4 word English gloss of "title" (e.g. French "Au café du coin" → English "At the corner café"), for a beginner who can't read the French title yet. Write 4 to 6 realistic beats: greeting, purpose, one follow-up, resolution, goodbye. Do not award a score or claim mastery.
${_cefrCalibration(levelBand)}
The SCENARIO given is only a loose inspiration for the setting, not a rigid script — build an ordinary, realistic scene that fits it.
This app's users are teens and adults (13+): keep the scene wholesome and educational, appropriate for a general audience, never mature, violent, or otherwise inappropriate.
INVENT A FRESH, SPECIFIC SCENE EVERY TIME: pick a concrete setting, named character, and small realistic details (items, prices, times, a tiny complication) that fit the scenario type but differ from the obvious default. Never reuse the same premise twice.''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': 'SCENARIO: $scenario\nLEVEL: $levelBand'},
      ],
      maxTokens: 1400,
      temperature: 1.0,
    );
    return _parseReadingPassage(raw);
  }

  /// First names and settings used to force real variety between generated
  /// stories — chosen client-side (not left to the model) since a fixed-topic
  /// prompt at a low-ish temperature can otherwise return the same or a
  /// near-identical story every time it's called with the same topic/level.
  /// Injecting a different concrete name+place+twist into the prompt on
  /// every call makes repeats structurally impossible even if the model's
  /// own creativity doesn't kick in.
  static const _storyCharacterNames = [
    'Léa',
    'Marc',
    'Amadou',
    'Sophie',
    'Nadia',
    'Julien',
    'Camille',
    'Karim',
    'Élise',
    'Thomas',
    'Fatou',
    'Antoine',
    'Chloé',
    'Hugo',
    'Awa',
    'Paul',
  ];
  static const _storySettings = [
    'a small town in Brittany',
    'a busy market in Montreal',
    'a quiet suburb of Lyon',
    'a ski resort in the Alps',
    'a coastal village in Senegal',
    'a university campus in Quebec City',
    'a neighbourhood bakery',
    'a train station',
    'a community garden',
    'a small office',
  ];
  static const _storyTwists = [
    'a small mistake that turns out fine',
    'an unexpected act of kindness from a stranger',
    'a plan that almost goes wrong',
    'a funny misunderstanding',
    'a surprising coincidence',
    'a problem solved just in time',
    'a small risk that pays off',
  ];

  /// A short third-person narrative story (not a roleplay dialogue like the two methods
  /// above) — the Story Reader's Readle-style "read a bilingual story about a topic you
  /// like" experience. Reuses `_parseReadingPassage`'s legacy "segments" shape (plain
  /// fr/en per line, no character split) since that's exactly a narrative's shape.
  Future<ReadingPassage> buildPersonalStory({
    required String topic,
    required String levelBand,
  }) async {
    final system =
        '''
Write a short third-person narrative story in French for a language learner — NOT a dialogue, no characters talking to each other, just a narrator telling a small real-life story (like a short reading-app story). Return ONLY compact JSON with this exact shape: {"title": string, "title_en": string, "segments": [{"fr": string, "en": string, "grammar_note": string, "pronunciation_tip": string}]}. "title_en" is a short 2-4 word English gloss of "title" (e.g. French "Le vélo emprunté" → English "The borrowed bike"), for a beginner who can't read the French title yet. Write 6 to 10 short sentences, one per segment, that together tell one small complete story with a beginning, a small turn, and an ending. "grammar_note" is one simple English sentence about that sentence's grammar; "pronunciation_tip" is one simple English pronunciation pointer for a tricky word in that sentence (or an empty string if nothing stands out).
${_cefrCalibration(levelBand)}
The TOPIC given is only a loose inspiration for the setting or a detail in the background, not the subject of every sentence — do not make the story be "about" the topic word itself; it should read like an ordinary daily-life story that just happens to touch on it.
This app's users are teens and adults (13+): keep the story wholesome and educational in tone, appropriate for a general audience, never dealing in mature, violent, or otherwise inappropriate themes.
INVENT A FRESH, SPECIFIC STORY EVERY TIME: never reuse the same premise, and never write a story with the same title or opening sentence as one already suggested by the seed details below.''';
    final random = Random();
    final name =
        _storyCharacterNames[random.nextInt(_storyCharacterNames.length)];
    final setting = _storySettings[random.nextInt(_storySettings.length)];
    final twist = _storyTwists[random.nextInt(_storyTwists.length)];
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content':
              'TOPIC (loose inspiration only): $topic\nLEVEL: $levelBand\n'
              'SEED DETAILS to build this specific story around: a main character named $name, '
              'set in or around $setting, involving $twist. Use these seed details naturally; '
              'do not just state them, weave them into a real small story.',
        },
      ],
      maxTokens: 1400,
      temperature: 1.0,
    );
    return _parseReadingPassage(raw);
  }

  /// Generates a story's Quiz and Keywords tabs together, right after
  /// `buildPersonalStory` — one call instead of two round-trips, since both
  /// draw on the same passage text. Grammar needs no separate call; it
  /// already reads off each segment's `grammarNote`/`pronunciationTip`.
  /// Best-effort by design: callers should fall back to empty lists on
  /// failure rather than block the story from being created, since the
  /// Story/Grammar tabs work fine on their own.
  Future<({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})>
  buildStoryQuizAndKeywords(ReadingPassage passage) async {
    const system = '''
Given a short French story, write a comprehension quiz and a keyword glossary for a language learner. Return ONLY compact JSON with this exact shape: {"quiz": [{"q": string, "choices": [string, string, string], "answerIndex": number}, ...], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}, ...]}.
QUIZ: 4 to 6 multiple-choice comprehension questions in English about events/details in the story, each with exactly 3 French-or-English choices as appropriate to the question and answerIndex pointing at the correct one (0-based). Only ask about things stated or clearly implied in the story.
KEYWORDS: 6 to 10 entries for useful French words or short phrases that actually appear in the story (verbatim or their dictionary form), each with its English meaning and a simple phonetic hint (e.g. "buh-ROH" style, not IPA). "id" is a short unique snake_case slug per entry.''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': 'STORY:\n${passage.fullText}'},
      ],
      maxTokens: 1400,
    );
    return _parseStoryQuizAndKeywords(raw);
  }

  /// Grammar points offered by the Grammar lab's "Practice a tense" picker —
  /// what the user asked for as "auto and tense they can choose to build and
  /// learn". Deliberately a short, common-first list, not every possible
  /// French tense/mood. ALWAYS fully available regardless of level — a
  /// learner can deliberately choose to get ahead of their level; what stays
  /// bounded to their level is the story's own sentence/vocabulary
  /// simplicity (see the "TENSE OVERRIDE" note in [buildGrammarStory]), not
  /// which tenses they're allowed to pick. First in the list ("Présent") is
  /// the default selection, not a hard floor.
  static const grammarPracticePoints = [
    'Présent',
    'Passé composé',
    'Futur proche',
    'Imparfait',
    'Conditionnel présent',
  ];

  /// Generates a short story built AROUND one chosen grammar point/tense
  /// (level-calibrated, same seeding technique as [buildPersonalStory]) — the
  /// "grammar should be a story generator" rebuild: instead of a static
  /// explanation-plus-drills page, the grammar point is taught by seeing it
  /// used naturally, sentence by sentence, with each segment's `grammarNote`
  /// explicitly tied to that point rather than a generic observation.
  /// Generated FIRST — the explanation (see [buildGrammarExplanationFromStory])
  /// is built FROM this story afterward, not the other way around, so the
  /// explanation always teaches the actual verbs/sentences the student just
  /// read instead of generic textbook examples unrelated to their story.
  Future<ReadingPassage> buildGrammarStory({
    required String grammarPoint,
    required String levelBand,
  }) async {
    final system =
        '''
Write a short third-person narrative story in French for a language learner that puts the grammar point "$grammarPoint" front and center — most sentences should naturally use that grammar point in context, not just mention it once. Return ONLY compact JSON with this exact shape: {"title": string, "title_en": string, "segments": [{"fr": string, "en": string, "grammar_note": string, "pronunciation_tip": string}]}. "title_en" is a short 2-4 word English gloss of "title". Write 6 to 10 short sentences, one per segment, that together tell one small complete story with a beginning, a small turn, and an ending, using "$grammarPoint" as heavily and naturally as a real story allows. "grammar_note" MUST explain, in one simple English sentence, HOW that specific sentence uses "$grammarPoint" (which form, why that form, how it changes from the infinitive/base) — this is the whole point of the story, not an afterthought like in a generic reading passage. "pronunciation_tip" is one simple English pronunciation pointer for a tricky word in that sentence (or an empty string if nothing stands out).
${_cefrCalibration(levelBand)}
TENSE OVERRIDE, TAKES PRIORITY OVER THE CALIBRATION ABOVE: the student deliberately chose to practice "$grammarPoint" specifically, even if it's not the tense that calibration band would normally introduce — use "$grammarPoint" as the story's main tense regardless. Everything else from the calibration still applies in full: sentence length, vocabulary difficulty, and overall simplicity must still match the level exactly. A harder tense at a beginner level means SHORT, SIMPLE sentences that happen to use that tense, e.g. one clear action per sentence with common everyday vocabulary, not a complex plot just because the tense is advanced.
This app's users are teens and adults (13+): keep the story wholesome and educational in tone, appropriate for a general audience.
INVENT A FRESH, SPECIFIC STORY EVERY TIME: never reuse the same premise or opening sentence as one already suggested by the seed details below.''';
    final random = Random();
    final name =
        _storyCharacterNames[random.nextInt(_storyCharacterNames.length)];
    final setting = _storySettings[random.nextInt(_storySettings.length)];
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content':
              'GRAMMAR POINT: $grammarPoint\nLEVEL: $levelBand\n'
              'SEED DETAILS to build this specific story around: a main character named $name, '
              'set in or around $setting. Use these naturally, do not just state them.',
        },
      ],
      maxTokens: 1400,
      temperature: 1.0,
    );
    return _parseReadingPassage(raw);
  }

  /// Builds the grammar explanation FROM the story that was just generated —
  /// the fix for "it's just parler, parler, everything the same": before,
  /// this explanation was written before the story existed, so it always
  /// reached for generic textbook verbs (parler, être) with no connection to
  /// what the student actually just read. Now every part of it is grounded
  /// in the story's own sentences: the conjugation table covers ONLY the
  /// verbs that actually appear in [passage] in this tense (never an
  /// invented one), and the summary/contrast explicitly point back at
  /// specific sentences from the story by quoting them.
  Future<GrammarExplanation> buildGrammarExplanationFromStory({
    required String grammarPoint,
    required String levelBand,
    required ReadingPassage passage,
  }) async {
    final system =
        '''
You are a French grammar teacher. The student just read this exact story, which uses the grammar point "$grammarPoint" throughout. Now explain "$grammarPoint" to them using ONLY the story's own sentences and verbs as your teaching material — never invent an unrelated example verb like "parler" or "être" unless one of those is actually the verb used in the story. Return ONLY compact JSON with this exact shape: {"title": string, "summary": string, "usage": [string, ...], "tense_contrast": string, "conjugations": [{"verb": string, "group": string, "rows": [{"pronoun": string, "form": string}, ...]}, ...], "examples": [{"fr": string, "en": string}, ...]}.
LANGUAGE, ABSOLUTE: "summary", every string in "usage", and "tense_contrast" MUST be written in English, plain teaching English, since this is explaining a grammar concept to a beginner who does not yet read French explanations. The ONLY French allowed in those three fields is a short quoted example dropped inline (e.g. "the story says 'Marc mange une crêpe', using the present tense of manger"). "conjugations" and "examples" are the exception: French forms/sentences there are expected and required, that is the whole point of those two fields.
"title" is the grammar point's name (e.g. "$grammarPoint"). "summary" is 2-3 sentences explaining what it is and when it's used, and it MUST directly reference this specific story (quote or closely paraphrase one of its actual sentences as the illustration, not a made-up one). "usage" is 3-5 short bullet-point rules for how/when to use it, phrased plainly. "tense_contrast" explicitly explains HOW this changes from or relates to another tense the student likely knows, framed around the story's own action (e.g. "If Marc had already finished eating, the story would instead say '...'", adapting one of the story's real sentences into the contrasting tense as the example). "conjugations" gives one full conjugation table (all 6 pronoun rows: je, tu, il/elle, nous, vous, ils/elles) for EACH DISTINCT VERB that actually appears in the story in "$grammarPoint" — read the story carefully and use its real verbs, in their infinitive form as the "verb" field; do not add any verb that isn't actually in the story. "examples" gives 3-4 example sentences reusing or lightly adapting the story's OWN sentences (with their English meaning), not invented ones.
${_cefrCalibration(levelBand)}''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content':
              'GRAMMAR POINT: $grammarPoint\nLEVEL: $levelBand\n'
              'STORY:\n${passage.fullText}',
        },
      ],
      maxTokens: 1300,
    );
    return GrammarExplanation.fromJson(_decodeObject(raw));
  }

  /// The quiz half of the grammar-story rebuild — unlike
  /// [buildStoryQuizAndKeywords]'s comprehension questions, every question
  /// here tests the CHOSEN GRAMMAR POINT itself (conjugation/form-recognition
  /// style, fill-in-the-blank on the story's own sentences), so the existing
  /// 80%-to-pass gate (`grammar_lesson_screen.dart`'s drill threshold) is
  /// actually gating grammar mastery, not just reading comprehension.
  Future<({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})>
  buildGrammarQuiz({required ReadingPassage passage, required String grammarPoint}) async {
    final system =
        '''
Given a short French story built specifically around the grammar point "$grammarPoint", write a quiz that TESTS THAT GRAMMAR POINT (not just story comprehension) plus a keyword glossary, same as for a regular story. Return ONLY compact JSON with this exact shape: {"quiz": [{"q": string, "choices": [string, string, string], "answerIndex": number}, ...], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}, ...]}.
QUIZ: 5 to 6 questions: mostly "which form is correct" fill-in-the-blank questions (English question stem naming the subject/verb, exactly 3 French answer choices, only one grammatically correct for "$grammarPoint"), plus 1-2 questions asking how the story used that grammar point in a specific sentence. Base every question on "$grammarPoint" and the story's own sentences/vocabulary, never an unrelated grammar point.
KEYWORDS: 6 to 10 entries for useful French words or short phrases that actually appear in the story (verbatim or their dictionary form), each with its English meaning and a simple phonetic hint (e.g. "buh-ROH" style, not IPA). "id" is a short unique snake_case slug per entry.''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content':
              'GRAMMAR POINT: $grammarPoint\nSTORY:\n${passage.fullText}',
        },
      ],
      maxTokens: 1400,
    );
    return _parseStoryQuizAndKeywords(raw);
  }

  // ---------------------------------------------------------------------------
  // Liaison practice — same "explanation, then a story grounded in it, then a
  // quiz" shape as the grammar-story rebuild above, reusing the exact same
  // GeneratedGrammarStory storage/sync/UI (saved with grammarPoint: 'Liaison'),
  // but with dedicated prompts: liaison is a PRONUNCIATION rule (when a
  // normally-silent final consonant gets pronounced because the next word
  // starts with a vowel sound), not a tense, so there's no conjugation table
  // and the "how it changes" framing doesn't apply — this teaches WHERE a
  // liaison happens in a sentence and how it sounds instead.
  // ---------------------------------------------------------------------------

  Future<GrammarExplanation> buildLiaisonExplanation({
    required String levelBand,
  }) async {
    final system =
        '''
You are teaching French liaison (pronunciation linking) to a beginner who finds it genuinely confusing. THE GOAL, ALWAYS: this is not an isolated grammar rule to memorize — it exists so the student can read an ordinary French sentence and understand how a native speaker actually SOUNDS when saying it, and start producing that same connected, natural speech themselves instead of choppy word-by-word French. Keep that goal in view in everything you write. Return ONLY compact JSON with this exact shape: {"title": string, "summary": string, "usage": [string, ...], "tense_contrast": string, "conjugations": [], "examples": [{"fr": string, "en": string}, ...]}.
LANGUAGE, ABSOLUTE: "summary", every string in "usage", and "tense_contrast" MUST be written in plain English — the only French allowed there is a short quoted example inline. "examples" are French sentences with their English meaning, as normal.
"title": "Liaison". "summary": 2-3 sentences in plain English explaining what liaison IS — a normally-silent final consonant (s, x, z, t, d, n, p, g) gets pronounced because the next word starts with a vowel sound or a silent h, linking the two words together (e.g. "les amis" is said like "lez-ami", not "les - amis") — frame this as the difference between reading French like a list of separate words and actually SPEAKING it the way a native does.
"usage" MUST cover the FULL RANGE of liaison types appropriate to "$levelBand", not just one example or one category — draw from ALL of these, choosing which ones fit the level (more categories and more nuance as the level rises, never fewer than 4 distinct rules even at A1):
- OBLIGATORY liaisons: after a determiner/article (les_amis, un_ami, des_enfants, ces_hommes), after a subject pronoun before its verb (nous_avons, vous_êtes, ils_ont, on_est), after a short/common adjective before its noun (un grand_homme, un petit_enfant), after numbers (deux_ans, trois_heures), after short one-syllable prepositions/adverbs (chez_elle, dans_un, très_intéressant, bien_arrivé).
- FORBIDDEN liaisons (no linking, even though it looks like it should): after "et" (et_/il, never linked), after a singular noun before an adjective (un étudiant / anglais, not linked), before an aspirated h word (les / héros).
- OPTIONAL/STYLE-DEPENDENT liaisons (B1/B2 only): after longer verbs or in compound tenses, more common in formal/careful speech than casual conversation — mention this exists but don't over-drill it below B1.
At A1/A2, focus on the OBLIGATORY category only, in the simplest most common forms; introduce FORBIDDEN cases at A2/B1; introduce OPTIONAL/style nuance only at B1/B2.
"tense_contrast" here should instead explain the single most common mistake an English speaker makes with liaison (usually: not linking at all, so every word sounds separate and choppy, OR over-linking where it's actually forbidden) and how it changes the sound of a sentence when done correctly versus not at all — give one concrete before/after sound comparison, and tie it back to the goal: this is what makes the difference between "reading French" and actually "speaking French".
"conjugations" must be an empty array, always — liaison has no verb forms. "examples" gives 3-4 short French sentences that each contain a DIFFERENT type of liaison from the categories above (not the same category repeated), with their English meaning, so the range is visible even in the examples alone.
${_cefrCalibration(levelBand)}''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': 'LEVEL: $levelBand'},
      ],
      maxTokens: 1200,
    );
    return GrammarExplanation.fromJson(_decodeObject(raw));
  }

  Future<ReadingPassage> buildLiaisonStory({
    required String levelBand,
    required GrammarExplanation explanation,
  }) async {
    final system =
        '''
Write a short third-person narrative story in French for a language learner that is rich in LIAISON opportunities — sentences that naturally contain word pairs where a liaison happens (an article/pronoun/number/short preposition immediately followed by a word starting with a vowel sound or silent h). Return ONLY compact JSON with this exact shape: {"title": string, "title_en": string, "segments": [{"fr": string, "en": string, "grammar_note": string, "pronunciation_tip": string}]}. "title_en" is a short 2-4 word English gloss of "title". Write 6 to 10 short sentences that together tell one small complete story with a beginning, a small turn, and an ending.
THE GOAL: this story exists to make the student able to read an ordinary French sentence and know how it actually sounds spoken aloud, connected and natural, not word-by-word. In service of that, cover VARIED liaison types across the story, not the same one repeated in every sentence — spread across the sentences: at least one after a determiner/article, one after a subject pronoun before its verb, and (at A2+) one more type (a number, a short preposition/adverb, or a forbidden case where a liaison would be wrong) — pick whichever mix fits "$levelBand" and the explanation given below.
"grammar_note" MUST identify the SPECIFIC liaison(s) in that sentence (or state there are none, if genuinely none fit naturally) and explain in plain English how it sounds, e.g. "les_élèves: the s links to élèves, sounds like 'lez-élèves', not 'les - élèves'" — if the sentence deliberately demonstrates a FORBIDDEN liaison spot, say so explicitly (e.g. "et_arrive is NOT linked — liaison never happens after et"). "pronunciation_tip" gives one more general pronunciation pointer for that sentence if useful, or an empty string.
The student was just taught this explanation of liaison — every sentence must be consistent with it, using genuinely correct liaison spots (and genuinely correct non-liaison spots where forbidden), not invented or forced ones:
SUMMARY: ${explanation.summary}
USAGE RULES: ${explanation.usage.join('; ')}
${_cefrCalibration(levelBand)}
This app's users are teens and adults (13+): keep the story wholesome and educational in tone, appropriate for a general audience.
INVENT A FRESH, SPECIFIC STORY EVERY TIME: never reuse the same premise or opening sentence as one already suggested by the seed details below.''';
    final random = Random();
    final name =
        _storyCharacterNames[random.nextInt(_storyCharacterNames.length)];
    final setting = _storySettings[random.nextInt(_storySettings.length)];
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content':
              'LEVEL: $levelBand\n'
              'SEED DETAILS to build this specific story around: a main character named $name, '
              'set in or around $setting. Use these naturally, do not just state them.',
        },
      ],
      maxTokens: 1400,
      temperature: 1.0,
    );
    return _parseReadingPassage(raw);
  }

  Future<({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})>
  buildLiaisonQuiz({required ReadingPassage passage}) async {
    const system = '''
Given a short French story written specifically to be rich in liaison examples, write a quiz that TESTS LIAISON RECOGNITION (not just story comprehension) plus a keyword glossary. Return ONLY compact JSON with this exact shape: {"quiz": [{"q": string, "choices": [string, string, string], "answerIndex": number}, ...], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}, ...]}.
QUIZ: 5 to 6 questions, mostly "does this word pair have a liaison?" or "how is this pronounced?" style questions quoting an actual word pair from the story, with 3 answer choices (e.g. three different phonetic renderings, only one correct), plus 1-2 questions about a specific liaison the story used. Base every question on the story's own sentences.
KEYWORDS: 6 to 10 entries for useful French words or short phrases that actually appear in the story, each with its English meaning and a simple phonetic hint (e.g. "buh-ROH" style, not IPA).''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': 'STORY:\n${passage.fullText}'},
      ],
      maxTokens: 1400,
    );
    return _parseStoryQuizAndKeywords(raw);
  }

  /// Runs ONCE, right after a tense/topic is chosen for the Grammar stage — builds a short
  /// deck of `GrammarPracticeCard`s (one short French sentence in the chosen tense per card,
  /// its English meaning, and a one-line grammar note), reusing the vocabulary words the
  /// student just practiced in the Vocab stage wherever natural, and informed by that Vocab
  /// session's actual transcript (what they said, how it went) rather than teaching the tense
  /// in a vacuum. Pre-generation, not live teaching: mirrors `buildReadingPassageFromVocab`'s
  /// shape. Kept deliberately lean — only the tense name, a handful of vocab words, and one
  /// short line of recent context go in, not a full transcript or the whole usage-notes list.
  String lastRawResponse = '';

  Future<List<GrammarPracticeCard>> generateGrammarPracticeCards({
    required String tenseTitle,
    required List<String> tenseUsage,
    required List<String> vocabWords,
    required String recentVocabTranscript,
    int count = 6,
  }) async {
    final words = vocabWords.take(6);
    final wordList = words.isEmpty ? '' : ' using words: ${words.join(', ')}';
    final user =
        '$count beginner French sentences in $tenseTitle$wordList. Pure JSON only: {"cards":[{"fr":"...","en":"...","note":"..."}]}';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': languageGuardrail},
        {'role': 'user', 'content': user},
      ],
      maxTokens: 800,
    );
    lastRawResponse = raw;
    return _parseGrammarPracticeCards(raw);
  }

  /// A fast, lightweight grade for the Daily Pathway's writing stage — one or two sentences
  /// using specific target words, not a full TEF rubric essay grade like `gradeWriting`.
  Future<MicroWritingFeedback> gradeMicroWriting({
    required String prompt,
    required List<String> targetWords,
    required String submission,
  }) async {
    const system = '''
You are a friendly French tutor grading a one-to-two sentence micro writing exercise. Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape: {"score_out_of_10": number, "comment": string}. The comment should be one short encouraging sentence, spoken-style with no markdown, since it will be read aloud.''';
    final user =
        '''
TASK: $prompt
TARGET WORDS: ${targetWords.join(', ')}

STUDENT SUBMISSION:
$submission''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
    );
    return _parseMicroWritingFeedback(raw);
  }

  /// A single rung of the Socratic hint ladder — called on a debounced pause
  /// while the learner is still typing, never on every keystroke. [tier] 1
  /// names only the grammatical category of the most important issue; 2
  /// narrows it to where in the sentence and what to check; 3 asks a leading
  /// question that makes the fix obvious without stating it. The model is
  /// never allowed to hand over the corrected form — that's enforced in the
  /// prompt, not just requested, since a hint that reveals the answer would
  /// undermine the whole reason this exists instead of a plain grammar-check.
  Future<WritingHint> getWritingHint({
    required String prompt,
    required List<String> targetWords,
    required String draft,
    required int tier,
  }) async {
    if (tier < 1 || tier > 3) {
      throw ArgumentError.value(tier, 'tier', 'must be 1, 2, or 3');
    }
    const system = '''
You are a Socratic French writing coach. You never give the corrected sentence and never state the fix directly, you point the student toward the single most important issue in their draft so they can fix it themselves. Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape: {"message": string}. The message is one short sentence, spoken-style, no markdown.
Tier 1: name only the grammatical CATEGORY of the issue (e.g. "verb agreement", "the gender of the article"). Nothing more specific.
Tier 2: narrow it to WHERE in the sentence and WHAT KIND of check to do, still without the answer (e.g. "look at the verb right after tu").
Tier 3: ask a leading question that makes the correct form obvious without stating it (e.g. "what is the tu-form of être?").
If the draft has no issue worth flagging yet, respond with a short encouraging confirmation instead, regardless of tier, do not invent a problem.''';
    final user =
        '''
TASK: $prompt
TARGET WORDS: ${targetWords.join(', ')}
HINT TIER REQUESTED: $tier

STUDENT'S DRAFT SO FAR:
$draft''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
      maxTokens: 200,
    );
    return _parseWritingHint(raw, tier: tier);
  }

  Future<String> checkDictation({
    required String expected,
    required String submitted,
  }) async {
    const system = '''
You are a French dictation checker. Compare the EXPECTED sentence to the STUDENT'S TYPED version. In under 60 words, spoken-style with no markdown, tell the student what they got right and point out any missed accents, silent letters, or misheard words.''';
    final user = 'EXPECTED: $expected\nSTUDENT WROTE: $submitted';
    return _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
    );
  }

  Future<String> quizFeedback({
    required String question,
    required String correctAnswer,
    required String studentAnswer,
    required String lessonContext,
  }) async {
    const system = '''
You are a French grammar tutor. The student answered a drill question incorrectly. In under 80 words, spoken-style with no markdown, explain why the correct answer is right and why their answer was wrong, using the LESSON CONTEXT for grounding.''';
    final user =
        'LESSON CONTEXT:\n$lessonContext\n\nQUESTION: $question\nCORRECT ANSWER: $correctAnswer\nSTUDENT ANSWER: $studentAnswer';
    return _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
    );
  }

  /// Auto-generated review note for the floating notetaker (source='ai'),
  /// written right after a live session ends — a short recap of the new
  /// words/phrases the transcript shows the student actually used or was
  /// taught, so it reads like a real notetaker's own shorthand, not a
  /// transcript dump. Sits alongside the student's own typed notes in the
  /// same list. Returns '' (never throws to the caller) when the transcript
  /// is too thin to say anything real about.
  Future<String> summarizeSessionForNotes({
    required String transcript,
    required String topic,
  }) async {
    if (transcript.trim().isEmpty) return '';
    const system = '''
You are a French tutor's assistant writing a SHORT review note right after a live speaking session, the way a real tutor jots down what a student practiced — not a transcript dump, a few lines of real shorthand. Plain spoken-in-writing style, no markdown, no greeting, no headers or labels like "Words:" or "Hardest:" — just short natural sentences/lines a learner would actually read. Cover, only where the transcript genuinely supports it (never invent one to fill a slot):
1. The 2-5 most useful new French words or short phrases from the transcript, each with a 1-3 word English gloss.
2. Roughly how many times the student practiced/attempted something this session (exchanges, repeated phrases, corrected attempts) — a rough count or "a lot"/"a few", not a precise stat you're inventing.
3. Which single word or phrase came up the most, if one clearly did.
4. Which word or phrase seemed hardest for the student — repeated, mispronounced, or corrected more than once.
5. Any specific pronunciation note the tutor actually gave in the transcript (e.g. a sound the student mispronounced and how to say it right) — only if the transcript actually contains one, never invented.
Keep the whole note under 70 words total. If the transcript has nothing substantial to say anything real about (small talk, a dropped call, one word), respond with exactly: NONE''';
    final user = 'TOPIC: $topic\n\nTRANSCRIPT:\n$transcript';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
      maxTokens: 220,
    );
    final trimmed = raw.trim();
    return trimmed.toUpperCase() == 'NONE' ? '' : trimmed;
  }

  /// Natural-voice line synthesis via Gemini's dedicated TTS model — the ACTIVE
  /// PERSONA's voice (P2.1), same API key, so replaying a scene line sounds like the
  /// student's own tutor saying it again, not a robot. On-device TTS was tried and
  /// rejected as robotic. Returns raw 24kHz mono PCM16 (the live session player's
  /// native format). Callers cache by text — scene lines are fixed strings, so each
  /// line costs one call ever (per session; the cache is session-scoped, so a persona
  /// change never replays a stale voice).
  /// [voiceName] overrides the active persona's voice — used by tutor voice
  /// previews, where each candidate tutor must speak with their OWN voice.
  Future<List<int>> synthesizeSpeech(
    String text, {
    bool slow = false,
    String? voiceName,
  }) async {
    final key = await _geminiApiKey;
    if (key.isEmpty) throw AgentError.missingKey;
    final prompt = slow
        ? 'Say this very slowly and clearly, for a beginner learning French: $text'
        : text;
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$key',
    );
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
              'generationConfig': {
                'responseModalities': ['AUDIO'],
                'speechConfig': {
                  'voiceConfig': {
                    'prebuiltVoiceConfig': {
                      'voiceName': voiceName ?? ActiveTutor.current.voiceName,
                    },
                  },
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw AgentError.requestFailed;
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw GeminiHttpError.fromResponse(response);
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final parts =
          ((json['candidates'] as List).first
                  as Map<String, dynamic>)['content']
              as Map<String, dynamic>;
      final audio = <int>[];
      for (final part in (parts['parts'] as List)) {
        final inline = (part as Map<String, dynamic>)['inlineData'];
        if (inline is Map && inline['data'] is String) {
          audio.addAll(base64Decode(inline['data'] as String));
        }
      }
      if (audio.isEmpty) throw AgentError.badResponse;
      // PCM16 mono is 2 bytes/sample — an odd length means a truncated or
      // misaligned inline part got concatenated in, which then plays back as
      // garbled/sped-up noise (every sample boundary after the shift is
      // wrong). Reject rather than return/cache a corrupt buffer.
      if (audio.length.isOdd) throw AgentError.badResponse;
      return audio;
    } catch (e) {
      if (e is AgentError) rethrow;
      throw AgentError.badResponse;
    }
  }

  /// One-shot speech-to-text for a short clip (a single word/phrase attempt),
  /// e.g. the flashcard lab's "say it" check. [pcmBytes] is raw 16-bit PCM
  /// mono at [sampleRateHz] — the same format AudioStreamingService captures
  /// for the live call, reused here so the whole app has exactly one mic
  /// pipeline. Gemini only, by design — no on-device speech recognizer
  /// anywhere in a practice session.
  Future<String> transcribeSpeech(
    List<int> pcmBytes, {
    int sampleRateHz = 16000,
  }) async {
    final key = await _geminiApiKey;
    if (key.isEmpty) throw AgentError.missingKey;
    if (pcmBytes.isEmpty) return '';
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiTextModel:generateContent?key=$key',
    );
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'Transcribe exactly what is said in this short audio clip, in French or English, whichever was spoken. Reply with ONLY the transcribed text, nothing else. If nothing intelligible was said, reply with an empty string.',
                    },
                    {
                      'inlineData': {
                        'mimeType': 'audio/pcm;rate=$sampleRateHz',
                        'data': base64Encode(pcmBytes),
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw AgentError.requestFailed;
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw AgentError.requestFailed;
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return '';
      final content = (candidates.first as Map<String, dynamic>)['content'];
      final parts = (content as Map<String, dynamic>?)?['parts'] as List?;
      final text = parts
          ?.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
          .join();
      return text?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// One-shot image understanding for Live Vision Scan: a photo, gallery
  /// image, or rasterized PDF page, optionally paired with an on-device OCR
  /// hint the model can correct against. Deliberately terse and reactive —
  /// this powers a "point the camera at a sign and get one quiet answer"
  /// flow, not an open-ended conversation, so the system prompt forbids
  /// follow-up questions and small talk.
  Future<String> describeImage({
    required List<int> imageBytes,
    String mimeType = 'image/jpeg',
    String? ocrHint,
    String? conversationContext,
  }) async {
    final key = await _geminiApiKey;
    if (key.isEmpty) throw AgentError.missingKey;
    if (imageBytes.isEmpty) return '';
    const system =
        '''You are a bilingual (English/French) travel companion helping a French learner understand something they just photographed while out and about (a sign, menu, notice, or document). Look at the image directly.

Reply with ONE short, direct answer: what it says and/or means, translated/explained briefly. Under 60 words. No markdown, no bullet lists, no asterisks. Do not ask follow-up questions, do not offer to keep chatting, do not greet the student. Just answer what's shown.''';
    final promptParts = <String>[system];
    if (ocrHint != null && ocrHint.trim().isNotEmpty) {
      promptParts.add(
        'ON-DEVICE OCR EXTRACTED THIS TEXT FROM THE IMAGE (may contain errors, use the image itself as ground truth): ${ocrHint.trim()}',
      );
    }
    if (conversationContext != null && conversationContext.trim().isNotEmpty) {
      promptParts.add(
        'EARLIER IN THIS SCAN SESSION: ${conversationContext.trim()}',
      );
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiTextModel:generateContent?key=$key',
    );
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': promptParts.join('\n\n')},
                    {
                      'inlineData': {
                        'mimeType': mimeType,
                        'data': base64Encode(imageBytes),
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw AgentError.requestFailed;
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw AgentError.requestFailed;
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return '';
      final content = (candidates.first as Map<String, dynamic>)['content'];
      final parts = (content as Map<String, dynamic>?)?['parts'] as List?;
      final text = parts
          ?.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
          .join();
      return text?.trim() ?? '';
    } catch (_) {
      throw AgentError.badResponse;
    }
  }

  Future<String> answerVisionScanChat({
    required String question,
    List<Map<String, String>> conversation = const [],
  }) async {
    const system =
        '''You are the text-chat companion inside a French learner's photo scan session. Answer questions about the signs, menus, notices, or documents the student has uploaded and the summaries in the conversation. Be direct and practical. You may answer in English or French, and include a French phrase when it helps the learner. Keep the answer under 120 words. Do not use markdown headings, bullet lists, emojis, or em dashes.''';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': '$system$languageGuardrail'},
      ...conversation.where(
        (message) =>
            (message['content'] ?? '').trim().isNotEmpty &&
            (message['role'] == 'user' || message['role'] == 'assistant'),
      ),
      {'role': 'user', 'content': question.trim()},
    ];
    final reply = await _complete(
      messages: messages,
      maxTokens: 320,
      timeout: const Duration(seconds: 25),
      temperature: 0.35,
    );
    return reply.trim();
  }

  // MARK: - Networking

  Future<String> _complete({
    required List<Map<String, String>> messages,
    int maxTokens = 1024,
    Duration timeout = const Duration(seconds: 30),
    double temperature = 0.4,
  }) async {
    if (_forceOpenRouter) {
      final openRouterKey = await _openRouterApiKey;
      if (openRouterKey.isEmpty) throw AgentError.missingKey;
      return _requestOpenRouter(
        model: _openRouterModel,
        messages: messages,
        maxTokens: maxTokens,
        apiKey: openRouterKey,
        timeout: timeout,
        temperature: temperature,
      );
    }
    final geminiKey = await _geminiApiKey;
    if (geminiKey.isEmpty) throw AgentError.missingKey;
    return _requestGeminiWithRetry(
      messages: messages,
      maxTokens: maxTokens,
      apiKey: geminiKey,
      timeout: timeout,
      temperature: temperature,
    );
  }

  /// Text-generation calls retry transient Gemini failures. For rate limits,
  /// Gemini's requested cooldown is used before the next attempt.
  Future<String> _requestGeminiWithRetry({
    required List<Map<String, String>> messages,
    required int maxTokens,
    required String apiKey,
    required Duration timeout,
    required double temperature,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _requestGemini(
          messages: messages,
          maxTokens: maxTokens,
          apiKey: apiKey,
          timeout: timeout,
          temperature: temperature,
        );
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        final retryAfter = e is GeminiHttpError && e.isRateLimited
            ? e.retryAfter
            : null;
        await Future.delayed(
          retryAfter ?? Duration(milliseconds: 500 * attempt),
        );
      }
    }
    throw AgentError.requestFailed; // unreachable, satisfies the analyzer
  }

  Future<String> _requestGemini({
    required List<Map<String, String>> messages,
    required int maxTokens,
    required String apiKey,
    required Duration timeout,
    double temperature = 0.4,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_geminiTextModel:generateContent?key=$apiKey',
    );

    // Same OpenAI-shaped message arrays all callers already build, mapped to Gemini's
    // schema: system messages become systemInstruction, assistant becomes "model".
    final systemText = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'] ?? '')
        .join('\n\n');
    final contents = messages
        .where((m) => m['role'] != 'system')
        .map(
          (m) => {
            'role': m['role'] == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': m['content'] ?? ''},
            ],
          },
        )
        .toList();
    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
      },
    };
    if (systemText.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemText},
        ],
      };
    }

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw AgentError.requestFailed;
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw GeminiHttpError.fromResponse(response);
    }

    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      final content =
          (candidates?.isNotEmpty == true
                  ? candidates!.first as Map<String, dynamic>
                  : null)?['content']
              as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      final text =
          parts
              ?.map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
              .join() ??
          '';
      if (text.isEmpty) throw AgentError.badResponse;
      return normalizeGeneratedText(text);
    } catch (e) {
      if (e is AgentError) rethrow;
      throw AgentError.badResponse;
    }
  }

  Future<String> _requestOpenRouter({
    required String model,
    required List<Map<String, String>> messages,
    required int maxTokens,
    required String apiKey,
    required Duration timeout,
    double temperature = 0.4,
  }) async {
    final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'HTTP-Referer': 'https://github.com/frenchtutor-app',
              'X-Title': 'FrenchTutor Passeport',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': temperature,
              'max_tokens': maxTokens,
            }),
          )
          .timeout(timeout);
    } catch (_) {
      throw AgentError.requestFailed;
    }
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw AgentError.requestFailed;
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      final first = choices?.isNotEmpty == true
          ? choices!.first as Map<String, dynamic>
          : null;
      final message = first?['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      if (content == null || content.isEmpty) throw AgentError.badResponse;
      return normalizeGeneratedText(content);
    } catch (e) {
      if (e is AgentError) rethrow;
      throw AgentError.badResponse;
    }
  }

  WritingFeedback _parseWritingFeedback(String raw) {
    final obj = _decodeObject(raw);
    final score = _asDouble(obj['score_out_of_10']);
    final strengths =
        (obj['strengths'] as List?)?.map((e) => e.toString()).toList() ??
        <String>[];
    final correctionsRaw = (obj['corrections'] as List?) ?? [];
    final corrections = correctionsRaw.map((c) {
      final m = c as Map<String, dynamic>;
      return (
        original: m['original'] as String? ?? '',
        fixed: m['fixed'] as String? ?? '',
        why: m['why'] as String? ?? '',
      );
    }).toList();
    final connectorFeedback = obj['connector_feedback'] as String? ?? '';
    final improved = obj['improved_version'] as String? ?? '';
    final nextSteps =
        (obj['next_steps'] as List?)?.map((e) => e.toString()).toList() ??
        <String>[];
    return WritingFeedback(
      scoreOutOf10: score,
      strengths: strengths,
      corrections: corrections,
      connectorFeedback: connectorFeedback,
      improvedVersion: improved,
      nextSteps: nextSteps,
    );
  }

  WritingTask _parseWritingTask(String raw) {
    final obj = _decodeObject(raw);
    final promptFr = obj['prompt_fr'] as String?;
    if (promptFr == null || promptFr.isEmpty) throw AgentError.badResponse;
    return WritingTask(
      id: 'generated-${const Uuid().v4().substring(0, 8)}',
      type: obj['type'] as String? ?? 'micro',
      title: obj['title'] as String? ?? 'Writing practice',
      promptFr: promptFr,
      promptEn: obj['prompt_en'] as String? ?? '',
      minWords: (obj['min_words'] as num?)?.toInt() ?? 5,
      targetConnectors:
          (obj['target_connectors'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      rubricHints:
          (obj['rubric_hints'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  MicroWritingFeedback _parseMicroWritingFeedback(String raw) {
    final obj = _decodeObject(raw);
    final score = _asDouble(obj['score_out_of_10']);
    final comment = obj['comment'] as String? ?? '';
    return MicroWritingFeedback(scoreOutOf10: score, comment: comment);
  }

  SpeakingMockFeedback _parseSpeakingMockFeedback(String raw) {
    final obj = _decodeObject(raw);
    return SpeakingMockFeedback(
      overallScore: _asDouble(obj['overall_score']).clamp(0, 10),
      clbEstimate: obj['clb_estimate'] as String? ?? 'More practice needed',
      taskCompletion: _asDouble(obj['task_completion']).clamp(0, 10),
      fluency: _asDouble(obj['fluency']).clamp(0, 10),
      grammar: _asDouble(obj['grammar']).clamp(0, 10),
      vocabulary: _asDouble(obj['vocabulary']).clamp(0, 10),
      strengths:
          (obj['strengths'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          <String>[],
      nextSteps:
          (obj['next_steps'] as List?)
              ?.map((item) => item.toString())
              .toList() ??
          <String>[],
    );
  }

  WritingHint _parseWritingHint(String raw, {required int tier}) {
    final obj = _decodeObject(raw);
    final message = obj['message'] as String? ?? '';
    return WritingHint(tier: tier, message: message);
  }

  MistakeJudgment _parseMistakeJudgment(String raw) {
    final obj = _decodeObject(raw);
    final correct = obj['correct'] as bool? ?? true;
    return MistakeJudgment(
      isCorrect: correct,
      tag: obj['tag'] as String?,
      description: obj['description'] as String?,
    );
  }

  ReadingPassage _parseReadingPassage(String raw) {
    final obj = _decodeObject(raw);
    final title = obj['title'] as String? ?? 'Reading passage';
    final titleEn = obj['title_en'] as String?;
    // New script shape ("beats" with both roles' lines) with fallback to the
    // legacy "segments" shape so older cached content keeps loading.
    final beatsRaw =
        (obj['beats'] as List?) ?? (obj['segments'] as List?) ?? [];
    final segments = beatsRaw
        .map((s) => s as Map<String, dynamic>)
        .where(
          (s) => ((s['learner_fr'] ?? s['fr']) as String?)?.isNotEmpty == true,
        )
        .map(
          (s) => ReadingSegment(
            fr: (s['learner_fr'] ?? s['fr']) as String,
            en: (s['learner_en'] ?? s['en']) as String? ?? '',
            grammarNote: s['grammar_note'] as String? ?? '',
            pronunciationTip: s['pronunciation_tip'] as String? ?? '',
            characterFr: s['character_fr'] as String?,
            characterEn: s['character_en'] as String?,
          ),
        )
        .toList();
    if (segments.isEmpty) throw AgentError.badResponse;
    final rawFullText = obj['full_text'] as String?;
    final fullText = (rawFullText != null && rawFullText.isNotEmpty)
        ? rawFullText
        : segments.map((s) => s.fr).join(' ');
    return ReadingPassage(
      id: 'generated-${const Uuid().v4().substring(0, 8)}',
      title: title,
      titleEn: titleEn,
      segments: segments,
      fullText: fullText,
    );
  }

  ({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})
  _parseStoryQuizAndKeywords(String raw) {
    final obj = _decodeObject(raw);
    final quizRaw = (obj['quiz'] as List?) ?? [];
    final quiz = <MultipleChoiceQuestion>[];
    for (final q in quizRaw) {
      final map = q as Map<String, dynamic>;
      final question = map['q'] as String?;
      final choices = (map['choices'] as List?)?.cast<String>() ?? const [];
      final answerIndex = map['answerIndex'];
      if (question == null ||
          question.isEmpty ||
          choices.isEmpty ||
          answerIndex is! int ||
          answerIndex < 0 ||
          answerIndex >= choices.length) {
        continue;
      }
      quiz.add(
        MultipleChoiceQuestion(
          q: question,
          choices: choices,
          answerIndex: answerIndex,
        ),
      );
    }

    final keywordsRaw = (obj['keywords'] as List?) ?? [];
    final keywords = <VocabEntry>[];
    for (var i = 0; i < keywordsRaw.length; i++) {
      final map = keywordsRaw[i] as Map<String, dynamic>;
      final fr = map['fr'] as String?;
      if (fr == null || fr.isEmpty) continue;
      keywords.add(
        VocabEntry(
          id: 'story-kw-$i-${const Uuid().v4().substring(0, 6)}',
          en: map['en'] as String? ?? '',
          fr: fr,
          phonetic: map['phonetic'] as String? ?? '',
        ),
      );
    }
    return (quiz: quiz, keywords: keywords);
  }

  List<GrammarPracticeCard> _parseGrammarPracticeCards(String raw) {
    final obj = _decodeObject(raw);
    final cardsRaw = (obj['cards'] as List?) ?? [];
    final cards = <GrammarPracticeCard>[];
    for (var i = 0; i < cardsRaw.length; i++) {
      final card = cardsRaw[i] as Map<String, dynamic>;
      final fr = card['fr'] as String?;
      if (fr == null || fr.isEmpty) continue;
      cards.add(
        GrammarPracticeCard(
          id: 'generated-$i-${const Uuid().v4().substring(0, 6)}',
          fr: fr,
          en: card['en'] as String? ?? '',
          note: card['note'] as String? ?? '',
        ),
      );
    }
    if (cards.isEmpty) throw AgentError.badResponse;
    return cards;
  }

  SessionPlan _parseSessionPlan(
    String raw, {
    required Set<String> validIds,
    int? count,
  }) {
    final obj = _decodeObject(raw);
    final focusNote = obj['focus_note'] as String? ?? '';
    var prioritized = (obj['prioritized_word_ids'] as List?)
        ?.map((e) => e.toString())
        .where(validIds.contains) // drop any hallucinated id
        .toSet() // de-dupe
        .toList();
    if (count != null && prioritized != null) {
      // Trust a genuine selection (any valid subset), just cap it at the
      // requested count — this is a real curation now, not a permutation
      // that must cover every candidate.
      if (prioritized.isEmpty) {
        prioritized = null;
      } else if (prioritized.length > count) {
        prioritized = prioritized.take(count).toList();
      }
    } else if (prioritized != null && prioritized.toSet() != validIds) {
      // Legacy contract (planGrammarSession-style callers with no `count`):
      // only trust it if it's an exact permutation of the real candidates.
      prioritized = null;
    }
    return SessionPlan(focusNote: focusNote, prioritizedWordIds: prioritized);
  }

  GrammarSessionPlan _parseGrammarSessionPlan(
    String raw, {
    required Set<String> validIds,
    required String fallbackId,
  }) {
    final obj = _decodeObject(raw);
    final focusNote = obj['focus_note'] as String? ?? '';
    final chosenId = obj['chosen_id'] as String?;
    // Guard against a hallucinated ID the same way vocab guards a hallucinated reordering.
    final validChosenId = (chosenId != null && validIds.contains(chosenId))
        ? chosenId
        : fallbackId;
    return GrammarSessionPlan(chosenId: validChosenId, focusNote: focusNote);
  }

  Map<String, dynamic> _decodeObject(String raw) {
    final jsonString = extractJSON(raw);
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      throw AgentError.badJSON(raw);
    }
  }

  double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return 0;
  }
}
