import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/api_keys.dart';
import '../models/content_models.dart';

/// The "brain" behind lesson labs: answers questions, grades writing, explains
/// wrong quiz answers — text-only (voice is LessonSpeechService / GeminiLiveService).
///
/// Primary provider is Gemini Flash-Lite, chosen by live head-to-head benchmarking
/// (July 2026) against the OpenRouter free tier on this app's actual prompt shapes:
/// ~0.85s vs ~9s median for the session-planning JSON call, and the OpenRouter free
/// tier's rate limits reject roughly half of a real session's calls outright — so
/// OpenRouter is now the fallback, not the default.
class AgentError implements Exception {
  const AgentError._(this.message);

  final String message;

  static const missingKey = AgentError._(
    'AI feedback unavailable — add a Gemini or OpenRouter key in Settings.',
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
  });

  final double scoreOutOf10;
  final List<String> strengths;
  final List<({String original, String fixed, String why})> corrections;
  final String connectorFeedback;
  final String improvedVersion;
}

class MicroWritingFeedback {
  MicroWritingFeedback({required this.scoreOutOf10, required this.comment});

  final double scoreOutOf10;
  final String comment;
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

  /// Output-language guardrail for every prompt whose text reaches the student's
  /// eyes or ears (PILOT_EXECUTION_PLAN.md P0.1). Invisible JSON judges/planners
  /// don't carry it — their output is never shown. Mirrors LivePrompts.languageGuardrail.
  static const languageGuardrail =
      ' LANGUAGE RULE — ABSOLUTE: your reply must be written ONLY in French and '
      'English, whatever language the student used. Understand any language, but '
      'never produce a single word in any other language, even when asked directly; '
      'if asked, say in English that this course lives in French and English only.';

  /// The non-thinking, low-latency Gemini tier. The `-latest` alias auto-tracks
  /// Google's newest Flash-Lite so we inherit upgrades for free.
  static const _geminiTextModel = 'gemini-flash-lite-latest';

  /// Fallback OpenRouter model, used only when the Gemini call fails or no Gemini key
  /// is configured. Setting the "openrouter_model_override" preference forces ALL
  /// traffic through OpenRouter with that model — the escape hatch if Gemini
  /// misbehaves in the field.
  Future<String> get _openRouterModel async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString('openrouter_model_override');
    if (override != null && override.isNotEmpty) return override;
    return 'nvidia/nemotron-3-super-120b-a12b:free';
  }

  Future<bool> get _forceOpenRouter async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString('openrouter_model_override');
    return override != null && override.isNotEmpty;
  }

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
You are a friendly, encouraging bilingual (English/French) French tutor helping a student preparing for the TEF/TCF Canada exam (target CLB 7). The student is mid-lesson; use the LESSON CONTEXT to ground your answer. Keep answers under 120 words, spoken-style — no markdown, no bullet lists, no asterisks, since your reply will be read aloud by a speech synthesizer. Answer in English unless the student asks in French or asks for a French example.''';
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '$system$languageGuardrail\n\nLESSON CONTEXT:\n$lessonContext',
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

  Future<WritingFeedback> gradeWriting({
    required WritingTask task,
    required String submission,
  }) async {
    const system = '''
You are a strict but encouraging TEF Canada writing examiner. Grade the student's submission against the task using a TEF-style rubric (task completion, grammar/conjugation accuracy, vocabulary range, use of logical connectors, coherence). Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape:
{"score_out_of_10": number, "strengths": [string,...], "corrections": [{"original": string, "fixed": string, "why": string}, ...], "connector_feedback": string, "improved_version": string}''';
    final user =
        '''
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
Silently audit a French pronunciation attempt (student never sees this). They were asked to say a French word aloud; below is what speech recognition captured (imperfect — be lenient on transcription noise, but flag real errors: wrong verb form, confused similar word, wrong word, silence). Reply with ONLY compact JSON, no markdown, no commentary: {"correct": boolean, "tag": string_or_null, "description": string_or_null}. tag = short stable snake_case slug for the error type (e.g. "nasal_vowel_confusion"), reused across words so it can be tracked over time. Both null when correct is true.''';
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
  /// (~0.7s measured) that this sits inside the natural turn-taking gap. Callers keep
  /// the keyword matcher as the fallback when this throws or times out.
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
You classify one utterance from a student in a live voice French lesson. The app — not the tutor — moves the on-screen card based on your verdict. Reply with ONLY compact JSON: {"intent": "advance"|"back"|"again"|"attempt"|"chat"|"goto"|"finish", "card": number_or_null, "explicit": boolean}.
- "finish": an EXPLICIT request to end the whole lesson/session ("let's finish this lesson", "I'm done for today", "end the session") — NOT merely finishing the current word.
- "advance": an EXPLICIT request to move to the next card ("next", "next word", "got it, let's move on", "suivant") — set "explicit": true. A bare "yes"/"oui"/"sure" counts ONLY if the tutor's last line directly asked whether to move on — never otherwise — and is "explicit": false (it's consent to the tutor's offer, not the student's own command). "explicit" is true for every other navigation verdict (back/goto/again).
- "back": an explicit request to return to the previous card.
- "goto": an explicit request to jump to a specific card by number or position ("go to the third card", "back to card 2", "the first one", "the last card") — set "card" to the 1-based target number, using the card position/count given.
- "again": they want the current item repeated or re-explained.
- "attempt": they are practicing/attempting the current target (saying the French word or sentence, possibly imperfectly — speech recognition is noisy, be lenient).
- "chat": anything else — a question, an answer to a non-navigation question, small talk. Words like "next"/"oui"/"continue" inside a longer sentence about something else (e.g. "the bakery is next to the station") are NOT commands.
ECHO RULE (critical): the mic sometimes picks up the tutor's own voice, so compare the utterance to the tutor's last line word by word. If it repeats the tutor's NON-TARGET words — her prompts or questions like "ready for the next?" — it is an echo: "chat", NEVER navigation, even though it contains command-like words. Repeating only the target French word/sentence itself is the student practicing: "attempt".
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
  Future<SessionPlan> planVocabSession({
    required List<VocabEntry> candidateWords,
    required List<({String tag, String description, int count})> mistakeTags,
    required List<String> recentDiary,
  }) async {
    const system = '''
You are quietly planning a French vocabulary practice session before it starts — the student won't see this reasoning, only the short focus note you write. Given the candidate word list, the student's recurring mistake patterns, and recent session notes, decide: (1) a one-sentence, warm, specific focus note for how today's session should be framed (e.g. referencing a specific recurring mistake if relevant), and (2) optionally reorder the word IDs to front-load anything especially relevant to their recent struggles — or return null to keep the given order if no reordering is warranted. Respond with ONLY a compact JSON object: {"focus_note": string, "prioritized_word_ids": array_of_strings_or_null}. The prioritized_word_ids, if provided, must be a permutation of the exact candidate IDs given — never invent new ones.''';
    final wordList = candidateWords
        .map((w) => '${w.id}: ${w.fr} (${w.en})')
        .join('; ');
    var user = 'CANDIDATE WORDS: $wordList';
    if (mistakeTags.isNotEmpty) {
      user +=
          '\n\nRECURRING MISTAKES: ${mistakeTags.map((m) => '${m.description} (seen ${m.count}x)').join('; ')}';
    }
    if (recentDiary.isNotEmpty) {
      user += '\n\nRECENT SESSION NOTES: ${recentDiary.join(' | ')}';
    }
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    );
    return _parseSessionPlan(
      raw,
      validIds: candidateWords.map((w) => w.id).toSet(),
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
    const system = '''
You are quietly picking which ONE French grammar point a beginner should practice today — the student won't see this reasoning, only the short focus note you write. Given the candidate list of tenses/topics, the student's recurring mistake patterns, and recent session notes, choose the single most useful one to practice right now (e.g. if their mistakes suggest passé composé confusion, pick that), and write a one-sentence warm, specific focus note for how today's session should be framed. If nothing stands out, pick the first candidate. Respond with ONLY a compact JSON object: {"chosen_id": string, "focus_note": string}. chosen_id MUST be exactly one of the candidate IDs given — never invent a new one.''';
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
        {'role': 'system', 'content': system},
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
  }) async {
    const system = '''
You are quietly writing a complete two-role ROLEPLAY SCRIPT for a total beginner preparing for TEF/TCF Canada — a real-life situation (café, bakery, bus, pharmacy, market...) where the LEARNER plays the customer/visitor and a CHARACTER (server, vendor, clerk) plays the other side. The app will stage this script beat by beat like a director — every line is fixed here, nothing is improvised later. Use ONLY the vocabulary words given below (plus basic connecting words like articles, "et", "je", "est", "s'il vous plaît" as needed for grammatical French) — do not introduce unrelated advanced vocabulary. Pick the most natural everyday scenario these words allow.
Write 4-8 beats in scene order (greeting → request → follow-up → thanks/goodbye). Each beat has the CHARACTER's line first (short, simple French that naturally prompts the learner) and then the LEARNER's reply line. Keep grammar SIMPLE: present tense, short sentences, no advanced conjugation — this is intentionally basic. Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape:
{"title": string, "beats": [{"character_fr": string, "character_en": string, "learner_fr": string, "learner_en": string, "grammar_note": string, "pronunciation_tip": string}, ...]}
"title" is the scenario in a few words (e.g. "At the bakery"). "character_fr"/"character_en" are the character's line and its English meaning; "learner_fr"/"learner_en" the learner's reply and meaning; "grammar_note" one simple English sentence explaining the learner line's word order/agreement; "pronunciation_tip" one simple English pronunciation pointer for the learner line.''';
    final wordList = words.map((w) => '${w.fr} (${w.en})').join(', ');
    final user = 'VOCABULARY WORDS TO REUSE: $wordList';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
      maxTokens: 1400,
    );
    return _parseReadingPassage(raw);
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
You are a Socratic French writing coach. You never give the corrected sentence and never state the fix directly — you point the student toward the single most important issue in their draft so they can fix it themselves. Respond with ONLY a compact JSON object, no markdown fences, no commentary outside the JSON, matching exactly this shape: {"message": string}. The message is one short sentence, spoken-style, no markdown.
Tier 1: name only the grammatical CATEGORY of the issue (e.g. "verb agreement", "the gender of the article"). Nothing more specific.
Tier 2: narrow it to WHERE in the sentence and WHAT KIND of check to do, still without the answer (e.g. "look at the verb right after tu").
Tier 3: ask a leading question that makes the correct form obvious without stating it (e.g. "what is the tu-form of être?").
If the draft has no issue worth flagging yet, respond with a short encouraging confirmation instead, regardless of tier — do not invent a problem.''';
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

  /// Natural-voice line synthesis via Gemini's dedicated TTS model — same voice family
  /// as Marie (Puck), same API key, so replaying a scene line sounds like HER saying it
  /// again, not a robot. On-device TTS was tried and rejected as robotic. Returns raw
  /// 24kHz mono PCM16 (the live session player's native format). Callers cache by text —
  /// scene lines are fixed strings, so each line costs one call ever.
  Future<List<int>> synthesizeSpeech(String text, {bool slow = false}) async {
    final key = await _geminiApiKey;
    if (key.isEmpty) throw AgentError.missingKey;
    final prompt = slow
        ? 'Say this very slowly and clearly, for a beginner learning French: $text'
        : text;
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$key');
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
                    'prebuiltVoiceConfig': {'voiceName': 'Puck'},
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
      throw AgentError.requestFailed;
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final parts =
          ((json['candidates'] as List).first as Map<String, dynamic>)['content']
              as Map<String, dynamic>;
      final audio = <int>[];
      for (final part in (parts['parts'] as List)) {
        final inline = (part as Map<String, dynamic>)['inlineData'];
        if (inline is Map && inline['data'] is String) {
          audio.addAll(base64Decode(inline['data'] as String));
        }
      }
      if (audio.isEmpty) throw AgentError.badResponse;
      return audio;
    } catch (e) {
      if (e is AgentError) rethrow;
      throw AgentError.badResponse;
    }
  }

  // MARK: - Networking

  /// Provider chain: Gemini Flash-Lite first, OpenRouter as fallback. An explicit
  /// "openrouter_model_override" preference skips Gemini entirely (field escape hatch).
  Future<String> _complete({
    required List<Map<String, String>> messages,
    int maxTokens = 1024,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final orKey = await _openRouterApiKey;
    if (await _forceOpenRouter) {
      if (orKey.isEmpty) throw AgentError.missingKey;
      return _requestOpenRouter(
        model: await _openRouterModel,
        messages: messages,
        maxTokens: maxTokens,
        apiKey: orKey,
        timeout: timeout,
      );
    }
    final geminiKey = await _geminiApiKey;
    if (geminiKey.isNotEmpty) {
      try {
        return await _requestGemini(
          messages: messages,
          maxTokens: maxTokens,
          apiKey: geminiKey,
          timeout: timeout,
        );
      } catch (e) {
        // Only swallow the Gemini error if there's an OpenRouter key to fall back to.
        if (orKey.isEmpty) rethrow;
      }
    }
    if (orKey.isEmpty) throw AgentError.missingKey;
    return _requestOpenRouter(
      model: await _openRouterModel,
      messages: messages,
      maxTokens: maxTokens,
      apiKey: orKey,
      timeout: timeout,
    );
  }

  Future<String> _requestGemini({
    required List<Map<String, String>> messages,
    required int maxTokens,
    required String apiKey,
    required Duration timeout,
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
      'generationConfig': {'temperature': 0.4, 'maxOutputTokens': maxTokens},
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
      throw AgentError.requestFailed;
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
      return text.trim();
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
            // Without an explicit cap, a large batch response (e.g. 25 example sentences in one
            // JSON array) can get cut off mid-object by the model's own default completion length,
            // producing invalid JSON that fails to parse entirely — silently dropping every example
            // in the whole session, not just the ones past the cutoff. Callers with bigger expected
            // outputs (batch generation) pass a larger explicit value.
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': 0.4,
              'max_tokens': maxTokens,
            }),
          )
          .timeout(timeout);
    } catch (_) {
      throw AgentError.requestFailed;
    }

    if (response.statusCode == 429 ||
        (response.statusCode >= 500 && response.statusCode <= 599)) {
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
      return content.trim();
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
    return WritingFeedback(
      scoreOutOf10: score,
      strengths: strengths,
      corrections: corrections,
      connectorFeedback: connectorFeedback,
      improvedVersion: improved,
    );
  }

  MicroWritingFeedback _parseMicroWritingFeedback(String raw) {
    final obj = _decodeObject(raw);
    final score = _asDouble(obj['score_out_of_10']);
    final comment = obj['comment'] as String? ?? '';
    return MicroWritingFeedback(scoreOutOf10: score, comment: comment);
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
      segments: segments,
      fullText: fullText,
    );
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

  SessionPlan _parseSessionPlan(String raw, {required Set<String> validIds}) {
    final obj = _decodeObject(raw);
    final focusNote = obj['focus_note'] as String? ?? '';
    var prioritized = (obj['prioritized_word_ids'] as List?)
        ?.map((e) => e.toString())
        .toList();
    // Guard against a hallucinated/incomplete reordering — only trust it if it's an exact
    // permutation of the real candidate IDs, otherwise fall back to the given order.
    if (prioritized != null && prioritized.toSet() != validIds) {
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
