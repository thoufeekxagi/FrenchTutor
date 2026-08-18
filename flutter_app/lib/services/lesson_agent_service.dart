import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/content_models.dart';
import '../utils/generated_text.dart';
import '../models/tutor_persona.dart';
import 'gemini_live_audio_service.dart';
import 'story_variety_service.dart';
import 'vocabulary_level_policy.dart';
import '../prompts/live_prompts.dart';

/// Shared instruction for every generated lesson image. Keep this in the
/// client prompt as well as the Edge Function so local previews and release
/// builds describe the same image-only contract.
const _imageOnlyInstruction = '''
IMAGE-ONLY OUTPUT: create the visual scene and nothing else. Do not render or
draw any text, words, letters, numbers, punctuation, symbols, signs, labels,
logos, watermarks, captions, book titles, UI, borders, frames, or overlays.
Leave all surfaces free of writing. The image must communicate through people,
objects, actions, lighting, colour, and composition only.
''';

/// The "brain" behind lesson labs: answers questions, grades writing, explains
/// wrong quiz answers — text-only (voice is LessonSpeechService / GeminiLiveService).
///
/// Text generation uses Gemini Flash-Lite.
/// Thrown by any raw Gemini HTTP call in this file (text
/// generation) instead of the generic [AgentError] so callers can tell a
/// rate limit (429, back off longer and retry) apart from any other
/// failure (back off briefly and retry, then give up).
class GeminiHttpError implements Exception {
  GeminiHttpError(this.statusCode, {this.retryAfter});

  /// Retained for retry-policy tests and older callers. Production provider
  /// responses now arrive as Edge Function errors, never as direct app HTTP.
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

  factory GeminiHttpError.fromFunctionException(FunctionException error) {
    Duration? retryAfter;
    final details = error.details;
    if (details is Map) {
      final seconds = double.tryParse(details['retryAfter']?.toString() ?? '');
      if (seconds != null) {
        retryAfter = Duration(milliseconds: (seconds * 1000).ceil() + 500);
      }
    }
    return GeminiHttpError(error.status, retryAfter: retryAfter);
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
  static const duplicateStory = AgentError._(
    'The AI returned a duplicate story. No duplicate was saved.',
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
    this.scoreBreakdown = const {},
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

  /// Level-aware rubric marks. Empty for older cached/model responses that
  /// predate the detailed writing review contract.
  final Map<String, double> scoreBreakdown;
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
  /// Model choice is a code decision, never user- or settings-configurable.
  static const _forceOpenRouter = false;

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
    final band = levelBand.trim().toUpperCase();
    final system =
        '''
You are a professional French writing examiner grading like a TCF/TEF rater. Grade the student's submission against the task at CEFR level $band. The level is part of the rubric: do NOT hold an A1/A2 learner to a B2 essay bar, and do NOT reward a B1/B2 answer merely for being long. Judge task completion, grammar/agreement, vocabulary, and coherence against what is realistic at this level.

Respond with ONLY one compact JSON object, with exactly this shape:
{"score_out_of_10": number, "score_breakdown": {"task_completion": number, "grammar": number, "vocabulary": number, "coherence": number}, "strengths": [string,...], "corrections": [{"original": string, "fixed": string, "why": string}, ...], "connector_feedback": string, "model_answer": string, "next_steps": [string,...]}

SCORING: Every score is from 0 to 10. The four breakdown scores must be justified by evidence in the submission. The overall score is the level-appropriate combined judgment, not a random average. For A1, expect one or a few short understandable sentences with basic high-frequency words. For A2, expect short connected everyday sentences. For B1, expect a coherent paragraph with developing control. For B2, expect a developed, logically organized response with appropriate range and accuracy.

CORRECTIONS: Use exact words or short spans copied from the student's submission in "original". Give the corrected French in "fixed". Explain the specific rule in English in "why". Do not invent an error that is not present. Include at most 5 high-value corrections, prioritizing patterns the learner can reuse.

MODEL ANSWER: "model_answer" must be a concise, natural French answer to THIS task at exactly level $band. It is a reference answer, not an advanced rewrite. It must satisfy the prompt and be realistic for this learner's level. Do not add facts the prompt does not ask for.

LANGUAGE: Every explanation — strengths, why, connector_feedback, and next_steps — MUST be in English. French is allowed only in original, fixed, and model_answer. next_steps must contain 2 to 4 concrete actions based on THIS submission, not generic encouragement.''';
    final user =
        '''
LEVEL: $band
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
    return _ensureWritingFeedback(
      _parseWritingFeedback(raw),
      submission: submission,
    );
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
    String? contextPrompt,
    List<({String tag, String description, int count})> mistakeTags = const [],
  }) async {
    final surpriseMode =
        (topic == null || topic.trim().isEmpty) &&
        (contextPrompt == null || contextPrompt.trim().isEmpty);
    final system = '''
Write one French writing-practice task for a language learner, calibrated STRICTLY to their CEFR level. Respond with ONLY compact JSON with this exact shape: {"title": string, "type": string, "prompt_fr": string, "prompt_en": string, "min_words": number, "target_connectors": [string,...], "rubric_hints": [string,...]}.
"type" is a short label like "micro" or "email" or "opinion". "rubric_hints" are 2-4 short English bullet points on what a good answer includes.
FORMAT RULE FOR "prompt_fr"/"prompt_en", ABSOLUTE — READ THIS TWICE: these two fields must be a QUESTION or an INSTRUCTION addressed directly TO the student (start with an imperative like "Écris...", "Décris...", "Raconte...", "Parle de...", or a direct question like "Où habites-tu ?"), asking them to produce their OWN original sentences. They must NEVER be a statement of fact, a narrated example, or anything that already reads as a complete, correct answer — if a student could just copy "prompt_fr" verbatim into the answer box and be done, you have generated it WRONG.
BAD, NEVER DO THIS (this is an already-written answer, not a task): prompt_fr: "Je suis avec ma famille. Je suis content." / prompt_en: "I am with my family. I am happy."
GOOD (this is an instruction the student must respond to): prompt_fr: "Écris deux phrases sur ta famille et comment tu te sens aujourd'hui." / prompt_en: "Write two sentences about your family and how you feel today."
DYNAMISM, JUST AS IMPORTANT AS THE FORMAT RULE ABOVE: keep A1/A2 concrete and easy to scan. You may vary the everyday object, food, place, or routine, but never add complexity just to make a prompt feel creative. Use the SEED DETAILS only for B1/B2. Two prompts at the same level can be simple while still changing topic and vocabulary.
LEVEL CALIBRATION, FOLLOW EXACTLY — this governs how SHORT/simple the instruction and expected answer are:
- A1: this is a true beginner. The French instruction must be 4-10 words and ask for exactly one short sentence of 5-10 words. Never use a named character, a multi-part situation, "pourquoi", "comment", "quel est ton préféré", a subordinate clause, or a sentence that reads like a story. Use only known vocabulary plus basic words (articles, je/tu/il, être/avoir, aimer, et). min_words 5-10. target_connectors: empty list. If the creative seed conflicts with these rules, ignore the seed.
- A2: keep the prompt easy to scan. Use one everyday task in 10-18 French words and ask for 3 short sentences, mostly using known vocabulary and common extra words. Avoid names, abstract topics, multi-part questions, and long context. min_words 15-25. target_connectors: at most 1 simple connector (e.g. "et", "mais", "parce que").
- B1: answerable in a short paragraph (5-8 sentences), may introduce a couple of new but common words beyond the known list. min_words 40-70. target_connectors: 1-2.
- B2: answerable as a fuller opinion/complaint/narrative piece, TEF-style. min_words 120-180. target_connectors: 2-3 (e.g. "néanmoins", "quant à", "bien que").
Never ask for anything harder than the stated level allows, even if the topic invites it.
Prefer a fresh, specific prompt each time. Vary the scenario and phrasing when it is natural, while keeping the task educational and level-appropriate.
${surpriseMode || mistakeTags.isEmpty ? '' : 'If it fits naturally, gently work in a chance to practice one of the RECURRING MISTAKES below — never force it, never call it out as "fixing a mistake", just a natural opportunity.'}''';
    // Surprise mode is intentionally context-free: learner vocabulary and
    // mistake history are useful for explicitly guided tasks, but must not
    // quietly steer a "Surprise me" generation back toward old material.
    final vocabLine = surpriseMode || knownVocab.isEmpty
        ? 'KNOWN VOCABULARY: (none recorded yet — use only the most basic beginner words)'
        : 'KNOWN VOCABULARY: ${knownVocab.take(40).join(', ')}';
    final chosenTopic =
        topic ??
        (surpriseMode
            ? ''
            : _writingTopics[Random().nextInt(_writingTopics.length)]);
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
      ..writeln(vocabLine);
    if (surpriseMode) {
      buf.writeln(
        'MODE: SURPRISE ME. No topic or learner context was selected. Choose a '
        'new everyday situation yourself. Do not use onboarding interests, '
        'course themes, prior transcripts, review phrases, or a fixed default '
        'scenario. Keep it natural, wholesome, and appropriate to the level.',
      );
    } else {
      buf.writeln('TOPIC (loose inspiration only): $chosenTopic');
      buf.writeln(
        'SEED DETAILS for a specific, creative angle (use naturally, do not just state them): '
        'a person named $seedName, a setting around $seedSetting, involving $seedTwist. '
        'Use these details only when LEVEL is B1 or B2.',
      );
    }
    if (contextPrompt != null && contextPrompt.trim().isNotEmpty) {
      buf.writeln(
        'COURSE CONTEXT: Build this as a fresh application of the course language, '
        'not a copy of the lesson. $contextPrompt',
      );
    }
    if (!surpriseMode && mistakeTags.isNotEmpty) {
      buf.writeln(
        'RECURRING MISTAKES (optional to touch on): '
        '${mistakeTags.map((m) => m.description).take(3).join('; ')}',
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
    final task = _calibrateGeneratedWritingTask(
      _parseWritingTask(raw, levelBand: levelBand),
      levelBand: levelBand,
      topic: chosenTopic,
    );
    return task;
  }

  /// Models sometimes obey the CEFR label but still make an A1 prompt
  /// needlessly long because the creative seed is interesting. Keep the AI
  /// variety, but apply a deterministic beginner guardrail before content
  /// reaches the learner.
  WritingTask _calibrateGeneratedWritingTask(
    WritingTask task, {
    required String levelBand,
    required String topic,
  }) {
    final band = levelBand.trim().toUpperCase();
    final promptWords = task.promptFr.trim().split(RegExp(r'\s+')).length;
    final hasComplexA1Marker = RegExp(
      r'\b(pourquoi|comment|parce que|ce que|quel(le)?|préféré|préférée|raconte|explique|décris)\b',
      caseSensitive: false,
    ).hasMatch(task.promptFr);
    final tooLong = band == 'A1'
        ? promptWords > 13 || hasComplexA1Marker
        : band == 'A2' && promptWords > 22;
    if (!tooLong) return task;

    final fallback = switch (band) {
      'A1' => const [
        (
          fr: 'Écris une phrase. Dis ce que tu aimes.',
          en: 'Write one sentence. Say what you like.',
          title: 'One thing I like',
          hint: 'Use one short present-tense sentence.',
        ),
        (
          fr: 'Écris une phrase sur ta famille.',
          en: 'Write one sentence about your family.',
          title: 'My family',
          hint: 'Use a family word and être or avoir.',
        ),
        (
          fr: 'Écris une phrase sur ton repas.',
          en: 'Write one sentence about your meal.',
          title: 'My meal',
          hint: 'Use one simple food word.',
        ),
        (
          fr: 'Écris une phrase sur ta journée.',
          en: 'Write one sentence about your day.',
          title: 'My day',
          hint: 'Use one simple present-tense verb.',
        ),
      ],
      'A2' => const [
        (
          fr: 'Écris trois phrases sur ta journée et ce que tu aimes.',
          en: 'Write three sentences about your day and what you like.',
          title: 'A simple day',
          hint: 'Use the present tense and one simple connector.',
        ),
        (
          fr: 'Écris trois phrases sur ta maison ou ton quartier.',
          en: 'Write three sentences about your home or neighbourhood.',
          title: 'My place',
          hint: 'Name two simple things and connect them with et.',
        ),
      ],
      _ => const [],
    };
    if (fallback.isEmpty) return task;
    final choice = fallback[topic.hashCode.abs() % fallback.length];
    return WritingTask(
      id: task.id,
      type: band == 'A1' ? 'micro' : task.type,
      title: choice.title,
      promptFr: choice.fr,
      promptEn: choice.en,
      minWords: band == 'A1' ? 5 : 15,
      targetConnectors: band == 'A1' ? const [] : const ['et'],
      rubricHints: [choice.hint],
      levelBand: task.levelBand,
    );
  }

  Future<SpeakingMockFeedback> gradeSpeakingMock({
    required String monologuePrompt,
    required String monologueTranscript,
    required String interactionPrompt,
    required String interactionTranscript,
    String examName = 'TEF / TCF Canada',
    String levelBand = 'B1',
  }) async {
    const system = '''
You are a strict TEF/TCF Canada speaking examiner. Assess only evidence present in the learner transcripts. Speech recognition may contain minor transcription noise, so do not penalize an isolated spelling artifact. Score task completion, fluency/coherence, grammatical range/accuracy, and vocabulary range/precision from 0 to 10. Estimate a CLB band conservatively. Give specific, brief feedback in English. Respond with ONLY compact JSON matching exactly:
{"overall_score": number, "clb_estimate": string, "task_completion": number, "fluency": number, "grammar": number, "vocabulary": number, "strengths": [string, string], "next_steps": [string, string]}''';
    final user =
        '''
EXAM: $examName
TARGET LEVEL: $levelBand
LANGUAGE POLICY: For A1/A2, evaluate the French the learner successfully produced while treating brief scaffold use as support. For B1/B2, the assessed response must be French-only; do not award task-completion credit for English answers.

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

  /// Runs once, briefly, before a vocab session starts and chooses a varied
  /// set from the current candidate pool. It never reads prior sessions or
  /// compact history records, so an automatic session remains a fresh pick.
  /// Curates the actual set of words a practice session shows, from a
  /// CANDIDATE POOL deliberately larger than [count] — this used to only
  /// ever be handed a pre-sliced list of exactly the words about to be
  /// shown (picked upstream in fixed curriculum order) and could merely
  /// reorder them, so even a perfect AI call was just reshuffling the same
  /// deterministic slice. Now it genuinely SELECTS which [count] words to
  /// serve, out of a much wider pool, the way `buildGrammarStory` picks a
  /// tense rather than being handed one.
  Future<SessionPlan> planVocabSession({
    required List<VocabEntry> candidateWords,
    required int count,
  }) async {
    final system =
        '''
You are quietly curating a French vocabulary practice session before it starts, the student won't see this reasoning, only the short focus note you write. From the CANDIDATE WORDS pool, SELECT exactly $count of them to actually practice today — do not just take the first $count in the list, genuinely choose a varied, useful mix. Then write a one-sentence, warm, specific focus note for how today's session should be framed.
SELECTION PRIORITY: favor an interesting, varied, thematically-loose mix over "next in alphabetical/curriculum order" — avoid picking a set that feels like the same category every time.
Respond with ONLY a compact JSON object: {"focus_note": string, "prioritized_word_ids": array_of_strings}. "prioritized_word_ids" MUST contain exactly $count ids (or fewer only if the candidate pool itself has fewer than $count entries), every one of them must be an exact id from CANDIDATE WORDS, never invent a new one, and never repeat an id.''';
    final wordList = candidateWords
        .map((w) => '${w.id}: ${w.fr} (${w.en})')
        .join('; ');
    final user = 'CANDIDATE WORDS: $wordList';
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

  /// Generates the small vocabulary bridge for a published course session.
  ///
  /// This is deliberately separate from [planVocabSession]. The existing
  /// vocab lab curates a learner's global review queue; a course session needs
  /// a fresh, contextual set of words that prepares the speaking and writing
  /// activities that follow it.
  Future<List<VocabEntry>> generateCourseVocabulary({
    required String levelBand,
    required String unitTitle,
    required String sessionTitle,
    required String contextPrompt,
    required List<String> targetPhrases,
    int count = 6,
  }) async {
    final foundationSearch = '$unitTitle $sessionTitle $contextPrompt'
        .toLowerCase();
    final isFoundationSession =
        foundationSearch.contains('alphabet') ||
        foundationSearch.contains('vowel') ||
        foundationSearch.contains('voyelle');
    final system =
        '''
Create a compact French vocabulary deck for one course session. Return ONLY
JSON with exactly this shape: {"words":[{"id":string,"fr":string,"en":string,"phonetic":string}]}.
Create exactly $count unique entries. Every French word or short phrase must be
directly useful in the session scenario, and the English meaning must be clear
to a learner at the requested CEFR level. Use simple, natural, everyday French.
The phonetic field is a short readable English-style hint, not IPA. Prefer a
mix of nouns, verbs, and one or two useful chunks rather than six near-synonyms.
Do not include grammar explanations, full sentences, duplicate concepts, or
words unrelated to the scenario. The deck is shown before speaking and writing,
so choose words that can be reused in both.
${isFoundationSession ? '''This is a French alphabet/vowel foundation session. Every entry MUST be one standalone, high-frequency French word (never a letter, phoneme, sentence, or multi-word phrase). Choose exactly the requested number of different beginner-friendly words that reinforce the sound focus and can be used in the linked speaking practice. Keep the set balanced across the supplied target phrases instead of returning only one example.
''' : ''}
LANGUAGE MIX: A1 uses very common French with English explanations. A2 stays
English-supported with a little more French. B1/B2 may use more French in the
meaning only when it remains clear.
CEFR LEVEL: $levelBand
''';
    final user =
        '''
UNIT CONTEXT: $unitTitle
SESSION TITLE: $sessionTitle
SESSION CONTEXT: $contextPrompt
TARGET PHRASES: ${targetPhrases.isEmpty ? '(none supplied)' : targetPhrases.join('; ')}
The vocabulary must prepare the learner to say the target phrases above. Reuse
their key words where appropriate, and do not invent a disconnected theme.
${VocabularyLevelPolicy.calibration(levelBand)}
''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {'role': 'user', 'content': user},
      ],
      maxTokens: 700,
      temperature: 0.7,
    );
    return _parseCourseVocabulary(raw, count: count, levelBand: levelBand);
  }

  /// Generates the cloze sentence used by the vocabulary workshop's Context
  /// step. The target must appear in the French sentence so the client can
  /// safely replace it with a blank before showing it to the learner.
  Future<BilingualExample> generateVocabularyContext({
    required VocabEntry word,
    required String levelBand,
  }) async {
    const system = '''
Create one short French vocabulary context sentence. Respond with ONLY compact
JSON in exactly this shape: {"fr":"...","en":"..."}.
The French sentence MUST contain the exact target word or phrase exactly as
provided, with the same spelling and accents, so the app can replace it with a
blank. The sentence must be natural, useful, and easy to understand at the
learner's CEFR level. The English field must translate the complete sentence.
Never return a sentence that omits the target, changes its spelling, or puts the
target only in the English field. Do not add markdown or extra keys.''';
    final user =
        '''
CEFR LEVEL: $levelBand
TARGET WORD: ${word.fr}
TARGET MEANING: ${word.en}
Write one everyday sentence using the target exactly as written.''';

    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await _complete(
        messages: [
          {'role': 'system', 'content': system + languageGuardrail},
          {'role': 'user', 'content': user},
        ],
        maxTokens: 180,
        temperature: attempt == 0 ? 0.4 : 0.1,
      );
      try {
        final decoded = jsonDecode(extractJSON(raw));
        if (decoded is Map) {
          final fr = decoded['fr'];
          final en = decoded['en'];
          if (fr is String &&
              en is String &&
              _containsVocabularyTarget(fr, word.fr)) {
            return BilingualExample(fr: fr.trim(), en: en.trim());
          }
        }
      } catch (_) {
        // Retry once with the same strict contract before the caller falls
        // back to a deterministic offline sentence.
      }
    }
    throw AgentError.badResponse;
  }

  bool _containsVocabularyTarget(String sentence, String target) {
    String normalize(String value) {
      var text = value.toLowerCase().trim();
      const replacements = {
        'é': 'e',
        'è': 'e',
        'ê': 'e',
        'ë': 'e',
        'à': 'a',
        'â': 'a',
        'ç': 'c',
        'î': 'i',
        'ï': 'i',
        'ô': 'o',
        'û': 'u',
        'ù': 'u',
        'œ': 'oe',
      };
      replacements.forEach((from, to) => text = text.replaceAll(from, to));
      return text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    }

    final normalizedSentence = normalize(sentence);
    final normalizedTarget = normalize(target);
    if (normalizedTarget.isEmpty) return false;
    return ' $normalizedSentence '.contains(' $normalizedTarget ');
  }

  /// Runs once, briefly, before a grammar session starts, when the student
  /// picks "Auto" in the grammar picker. It chooses from the current
  /// candidate list without reading prior session material.
  Future<GrammarSessionPlan> planGrammarSession({
    required List<({String id, String title})> candidates,
  }) async {
    final system = '''
You are quietly picking which ONE French grammar point a beginner should practice today, the student won't see this reasoning, only the short focus note you write. Given the candidate list of tenses/topics, choose a varied, useful point to practice right now and write a one-sentence warm, specific focus note for how today's session should be framed. If nothing stands out, pick the first candidate. Respond with ONLY a compact JSON object: {"chosen_id": string, "focus_note": string}. chosen_id MUST be exactly one of the candidate IDs given, never invent a new one.''';
    final list = candidates.map((c) => '${c.id}: ${c.title}').join('; ');
    final user = 'CANDIDATES: $list';
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
    final system = '''
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
Write a short two-role French roleplay for a language-learning mission. The app will direct it beat by beat, then ${ActiveTutor.current.displayName} will continue the same scene live. Return ONLY compact JSON with this exact shape: {"title": string, "title_en": string, "beats": [{"character_fr": string, "character_en": string, "learner_fr": string, "learner_en": string, "grammar_note": string, "pronunciation_tip": string}]}. "title_en" is a short 2-4 word English gloss of "title" (e.g. French "Au café du coin" → English "At the corner café"), for a beginner who can't read the French title yet. Write 4 to 6 realistic beats: greeting, purpose, one follow-up, resolution, goodbye. Every learner line must support the mission prompt. Do not award a score or claim mastery.
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
    String? scenario,
    required String levelBand,
    Iterable<String> avoidTitles = const [],
    Iterable<String> avoidOpenings = const [],
  }) async {
    final surpriseMode = scenario == null || scenario.trim().isEmpty;
    final titles = avoidTitles.toList(growable: false);
    final openings = avoidOpenings.toList(growable: false);
    final exclusion = StoryVarietyService.exclusionPrompt(
      titles: titles,
      openings: openings,
    );
    final system =
        '''
Write a short two-role French roleplay scene for a language learner to practice. The app will direct it beat by beat, then a live tutor will continue the same scene. Return ONLY compact JSON with this exact shape: {"title": string, "title_en": string, "beats": [{"character_fr": string, "character_en": string, "learner_fr": string, "learner_en": string, "grammar_note": string, "pronunciation_tip": string}]}. "title_en" is a short 2-4 word English gloss of "title" (e.g. French "Au café du coin" → English "At the corner café"), for a beginner who can't read the French title yet. Write 4 to 6 realistic beats: greeting, purpose, one follow-up, resolution, goodbye. Do not award a score or claim mastery.
${_cefrCalibration(levelBand)}
The SCENARIO given is only a loose inspiration for the setting, not a rigid script — build an ordinary, realistic scene that fits it.
This app's users are teens and adults (13+): keep the scene wholesome and educational, appropriate for a general audience, never mature, violent, or otherwise inappropriate.
Aim for a fresh, specific scene: pick a concrete setting, named character, and small realistic details (items, prices, times, a tiny complication) that fit the scenario type. Vary the premise when it is natural, without forcing novelty.
${surpriseMode ? 'SURPRISE MODE: No scenario was selected. Choose an ordinary new everyday scene yourself. Keep it natural and level-appropriate; do not rely on onboarding interests or a fixed default.' : 'SELECTED CONTEXT: Use the learner scenario only as loose inspiration; do not copy a previous scene.'}''';
    Future<ReadingPassage> request(String retryInstruction) async {
      final seed = StoryVarietyService.chooseSeed(
        avoidTexts: [...titles, ...openings],
      );
      final user = StringBuffer()
        ..writeln(
          surpriseMode
              ? 'MODE: SURPRISE ME — no scenario supplied'
              : 'SCENARIO (loose inspiration): $scenario',
        )
        ..writeln('LEVEL: $levelBand')
        ..writeln(
          'SURPRISE SEED: $seed. Make the setting, object, character, and '
          'small complication clearly different around this seed.',
        )
        ..writeln(exclusion)
        ..writeln(retryInstruction)
        ..writeln('REQUEST NONCE: ${DateTime.now().microsecondsSinceEpoch}');
      final raw = await _complete(
        messages: [
          {'role': 'system', 'content': system + languageGuardrail},
          {'role': 'user', 'content': user.toString()},
        ],
        maxTokens: 1400,
        temperature: 1.0,
      );
      return _parseReadingPassage(raw);
    }

    var scene = await request('');
    if (StoryVarietyService.isDuplicate(
      title: scene.title,
      opening: scene.segments.firstOrNull?.fr ?? '',
      avoidTitles: titles,
      avoidOpenings: openings,
    )) {
      scene = await request(
        'DUPLICATE REJECTION: discard the previous scene completely. Return '
        'a different premise, title, opening, characters, and dominant image.',
      );
      if (StoryVarietyService.isDuplicate(
        title: scene.title,
        opening: scene.segments.firstOrNull?.fr ?? '',
        avoidTitles: titles,
        avoidOpenings: openings,
      )) {
        throw AgentError.duplicateStory;
      }
    }
    return scene;
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

  /// Generates the complete short-book payload in one text call. The caller
  /// persists this package immediately, then may request one cover image. All
  /// lesson tabs are therefore available offline/on reopen without another
  /// model request.
  ///
  /// Reading has its own prompt and is intentionally not an alias for the
  /// listening book generator. The payload stays compatible with
  /// [StoryBookGeneration] so the library/storage contract remains one-call
  /// and the reading lesson can teach from the same frozen text it saves.
  Future<StoryBookGeneration> buildReadingStoryBook({
    String? topic,
    required String levelBand,
    String? examName,
    String? examLevel,
    Iterable<String> avoidTitles = const [],
    Iterable<String> avoidOpenings = const [],
  }) async {
    final surpriseMode = topic == null || topic.trim().isEmpty;
    final examBlock = _examComprehensionPrompt(
      examName: examName,
      levelBand: examLevel ?? levelBand,
      listening: false,
    );
    final system =
        '''
Create one short, polished French READING storybook for a language learner. Return ONLY compact JSON with exactly this shape: {"title": string, "title_en": string, "summary": string, "read_time_minutes": number, "cover_prompt": string, "segments": [{"fr": string, "en": string, "grammar_note": string, "pronunciation_tip": string}], "quiz": [{"q": string, "q_en": string, "choices": [string, string, string, string], "choices_en": [string, string, string, string], "answerIndex": number}], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}]}.

READING DESIGN: Write 7 to 10 short narrative sentences, one per segment. The learner will first read the French for meaning, then study one selected sentence, then reread with support, so every segment must stand alone, be natural, and move the plot forward. This is a complete mini-story with a beginning, a small change or problem, and a satisfying ending. It is not a dialogue, roleplay, listening transcript, or speaking exercise.

CEFR CONTRACT: Keep sentence length, verb forms, vocabulary, inference load, and story structure at the requested level. A1 uses concrete daily situations, mostly familiar present-tense language, and very short sentences. A2 adds simple past/future or cause-and-effect when useful. B1 uses connected narration and everyday idioms. B2 can use richer description and implicit meaning without becoming literary or academic. Do not put advanced language into an easier level just to make the story sound impressive.

TEACHING FIELDS: For each exact French sentence, write a clear English meaning, one short English grammar note that points to a real pattern in that sentence, and one short pronunciation tip (or an empty string). Include 6 to 10 useful words or short phrases that actually appear in the story. Write 4 to 6 comprehension questions. In regular lessons, provide q_en and choices_en as learner support at every level. If an EXAM READINESS OVERRIDE appears below, it takes precedence: follow its language policy exactly. Each has exactly 3 choices and one valid zero-based answerIndex.

SUMMARY: One inviting English sentence. READ TIME: a whole number, normally 3 to 7 minutes. COVER PROMPT: one concise English prompt for a portrait editorial illustration of the story's setting and mood. Do not request text, letters, logos, borders, watermarks, or UI in the image.

The topic is inspiration, not a requirement that every sentence mention it. Keep the story wholesome and appropriate for teens and adults. Prefer a fresh, specific premise and vary it naturally.
${surpriseMode ? '''SURPRISE MODE: No topic was selected. Choose an ordinary new everyday premise yourself. Keep it natural and calibrated to the requested level; do not rely on onboarding interests or a fixed default.''' : '''SELECTED CONTEXT: The learner supplied a topic. Use it only as loose inspiration and create a new story, not a rewrite or continuation of any previous lesson.'''}
${_cefrCalibration(levelBand)}
$examBlock
''';
    return _buildUniqueStoryBook(
      system: system + languageGuardrail,
      levelBand: levelBand,
      topic: topic ?? '',
      maxTokens: 3000,
      avoidTitles: avoidTitles,
      avoidOpenings: avoidOpenings,
      userContent: (seed, nonce, exclusion, retryInstruction) =>
          '${surpriseMode ? 'MODE: SURPRISE ME — no topic supplied' : 'TOPIC (loose inspiration): $topic'}\nLEVEL: $levelBand\n'
          '${examName == null ? '' : 'EXAM: $examName\n'}'
          'SURPRISE SEED: $seed. Build the premise, setting, object, and small turn around this seed.\n'
          'A human character is optional; the story may follow an object, animal, place, or natural moment.\n'
          '$exclusion\n$retryInstruction\nREQUEST NONCE: $nonce',
    );
  }

  /// Listening has its own generation contract. It shares the persisted
  /// story shape with reading, but the writing is intentionally spoken-first:
  /// short lines, natural rhythm, and bilingual check questions for beginners.
  Future<StoryBookGeneration> buildListeningStoryBook({
    String? topic,
    required String levelBand,
    String? examName,
    String? examLevel,
    Iterable<String> avoidTitles = const [],
    Iterable<String> avoidOpenings = const [],
  }) async {
    final surpriseMode = topic == null || topic.trim().isEmpty;
    final examBlock = _examComprehensionPrompt(
      examName: examName,
      levelBand: examLevel ?? levelBand,
      listening: true,
    );
    final system =
        '''
Create one short, polished French LISTENING lesson for a language learner. Return ONLY compact JSON with exactly this shape: {"title": string, "title_en": string, "summary": string, "read_time_minutes": number, "cover_prompt": string, "segments": [{"fr": string, "en": string, "grammar_note": string, "pronunciation_tip": string}], "quiz": [{"q": string, "q_en": string, "choices": [string, string, string, string], "choices_en": [string, string, string, string], "answerIndex": number}], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}]}.

LISTENING DESIGN: Write 6 to 9 short spoken French sentences, one per segment. Each sentence must sound natural when read aloud and move a tiny everyday story forward. Use a clear beginning, one small change, and a satisfying ending. This is a listening lesson, not a reading essay, roleplay, or grammar worksheet. A human character is optional: the story may follow an object, animal, place, or natural moment. Never force a named character.

CEFR CONTRACT: Match the requested level exactly. A1 uses 4 to 8 familiar words per sentence, mostly present tense and concrete daily situations. A2 can add simple past/future and short cause-and-effect. B1 can use connected narration and everyday idioms. B2 can use richer but still conversational language. Do not put advanced language into an easier level.

CHECK SUPPORT: Write 4 to 6 comprehension questions. For every question, q is the French question and q_en is its plain English translation. choices must be French options and choices_en must be their English translations in the exact same order. Each question has exactly 3 choices and one valid zero-based answerIndex. Questions must test only details stated or clearly implied by the audio story.

TEACHING FIELDS: For each exact French sentence, provide its English meaning, one short English grammar note tied to that sentence, and an optional pronunciation tip. Include 5 to 8 useful French words or short phrases that actually appear in the story.

SUMMARY: One inviting English sentence. READ TIME: a whole number, normally 2 to 5 minutes. COVER PROMPT: one concise English prompt for a portrait editorial illustration of the story's setting and mood. Do not request text, letters, logos, borders, watermarks, or UI in the image.

Keep it wholesome and appropriate for teens and adults. Prefer a fresh, specific premise and vary it naturally.
${surpriseMode ? '''SURPRISE MODE: No topic was selected. Choose an ordinary new everyday premise yourself. Keep it natural and calibrated to the requested level; do not rely on onboarding interests or a fixed default.''' : '''SELECTED CONTEXT: The learner supplied a topic. Use it only as loose inspiration and create a new listening lesson, not a rewrite or continuation of any previous lesson.'''}
${_cefrCalibration(levelBand)}
$examBlock
''';
    return _buildUniqueStoryBook(
      system: system + languageGuardrail,
      levelBand: levelBand,
      topic: topic ?? '',
      maxTokens: 2800,
      avoidTitles: avoidTitles,
      avoidOpenings: avoidOpenings,
      userContent: (seed, nonce, exclusion, retryInstruction) =>
          '${surpriseMode ? 'MODE: SURPRISE ME — no topic supplied' : 'TOPIC (loose inspiration): $topic'}\nLEVEL: $levelBand\n'
          '${examName == null ? '' : 'EXAM: $examName\n'}'
          'SURPRISE SEED: $seed. Build the premise, setting, object, and small turn around this seed.\n'
          '$exclusion\n$retryInstruction\nREQUEST NONCE: $nonce',
    );
  }

  Future<StoryBookGeneration> _buildUniqueStoryBook({
    required String system,
    required String levelBand,
    required String topic,
    required int maxTokens,
    required Iterable<String> avoidTitles,
    required Iterable<String> avoidOpenings,
    required String Function(
      String seed,
      String nonce,
      String exclusion,
      String retryInstruction,
    )
    userContent,
  }) async {
    final titles = avoidTitles.toList(growable: false);
    final openings = avoidOpenings.toList(growable: false);
    final priorText = [...titles, ...openings];
    final exclusion = StoryVarietyService.exclusionPrompt(
      titles: titles,
      openings: openings,
    );

    Future<StoryBookGeneration> request(String retryInstruction) async {
      final seed = StoryVarietyService.chooseSeed(avoidTexts: priorText);
      final nonce =
          '${DateTime.now().microsecondsSinceEpoch}-${seed.hashCode.abs()}';
      final raw = await _complete(
        messages: [
          {'role': 'system', 'content': system},
          {
            'role': 'user',
            'content': userContent(seed, nonce, exclusion, retryInstruction),
          },
        ],
        maxTokens: maxTokens,
        temperature: 1.0,
      );
      return _parseStoryBookGeneration(raw, levelBand: levelBand, topic: topic);
    }

    var package = await request('');
    if (StoryVarietyService.isDuplicate(
      title: package.passage.title,
      opening: package.passage.segments.firstOrNull?.fr ?? '',
      avoidTitles: titles,
      avoidOpenings: openings,
    )) {
      package = await request(
        'DUPLICATE REJECTION: the previous draft collided with a recent story. '
        'Discard it completely and create a different premise, title, opening, '
        'and dominant image. Do not mention or reuse the rejected draft.',
      );
      if (StoryVarietyService.isDuplicate(
        title: package.passage.title,
        opening: package.passage.segments.firstOrNull?.fr ?? '',
        avoidTitles: titles,
        avoidOpenings: openings,
      )) {
        throw AgentError.duplicateStory;
      }
    }
    return package;
  }

  String _examComprehensionPrompt({
    required String? examName,
    required String levelBand,
    required bool listening,
  }) {
    if (examName == null || examName.trim().isEmpty) return '';
    final isTcf = examName.toLowerCase().startsWith('tcf');
    final band = LivePrompts.normalizeLevel(levelBand);
    final officialShape = isTcf
        ? listening
              ? 'TCF Canada listening comprehension is a progressive four-option QCM; the official paper has 39 items in 35 minutes and each recording is played once.'
              : 'TCF Canada reading comprehension is a progressive four-option QCM; the official paper has 39 items in 60 minutes.'
        : listening
        ? 'TEF Canada listening comprehension is a four-option QCM; the official paper has 40 items in 40 minutes and each audio is played once without going back.'
        : 'TEF Canada reading comprehension is a four-option QCM; the official paper has 40 items in 60 minutes.';
    final languagePolicy = band == 'A1' || band == 'A2'
        ? '''This app's A1/A2 training mode includes controlled bilingual support: write every question in simple French and include q_en in plain English; include choices_en in the same order as choices. The French question and French choices remain authoritative, and the English support must not reveal the answer.'''
        : '''This app's $band exam mode is French-only: write questions and choices in French, omit q_en and choices_en, and never translate, explain, or simplify the answer choices.''';
    return '''
EXAM READINESS OVERRIDE: This is an independent $examName $band training set, not a full official-length exam. $officialShape Generate a mobile-sized practice set of exactly 8 questions so the learner can complete it in one sitting, while modeling the same item discipline. Every question must have exactly 4 answer choices, exactly one correct answer, and an answerIndex from 0 to 3. $languagePolicy Do not add vocabulary cards, grammar tabs, or teaching notes to the exam content. Keep the reading document/audio script and questions self-contained, original, and appropriate to $band. For listening, write short spoken lines and never rely on information that would only be visible in a transcript.
''';
  }

  Future<StoryBookGeneration> buildStoryBook({
    required String topic,
    required String levelBand,
  }) async {
    final system =
        '''
Create one short, polished French reading book for a language learner. Return ONLY compact JSON with exactly this shape: {"title": string, "title_en": string, "summary": string, "read_time_minutes": number, "cover_prompt": string, "segments": [{"fr": string, "en": string, "grammar_note": string, "pronunciation_tip": string}], "quiz": [{"q": string, "q_en": string, "choices": [string, string, string], "choices_en": [string, string, string], "answerIndex": number}], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}]}.

STORY: Write 7 to 10 short narrative segments with a clear beginning, small turn, and satisfying ending. This is a reading-app story, not a textbook exercise and not a dialogue. Keep the story wholesome and appropriate for teens and adults. The topic is inspiration, not a requirement that every sentence mention it.
SUMMARY: Write one short English sentence that makes the story inviting to open.
READ TIME: Estimate the reading time in whole minutes, normally 3 to 7.
COVER PROMPT: Write one concise English prompt for a portrait book-cover illustration of the story's setting and mood. Do not request any text, letters, logos, borders, or UI in the image; the app overlays the title.
QUIZ: Write 4 to 6 comprehension questions. At A1/A2, q must be simple French plus q_en in plain English, and choices must be French plus choices_en in the exact same order. At B1/B2, still provide the English support fields. Each question must have exactly 3 choices and one valid zero-based answerIndex. Only ask about details stated or clearly implied by the story.
KEYWORDS: Write 6 to 10 useful French words or short phrases that appear in the story, with simple English meanings and non-IPA phonetic hints. IDs must be short unique snake_case slugs.
GRAMMAR: Each segment gets one plain-English grammar note tied to that exact sentence. pronunciation_tip may be empty when no useful tip is needed.
${_cefrCalibration(levelBand)}
The learner's target level is $levelBand. Match sentence length, grammar, vocabulary, and plot complexity to that level exactly. Never make an A1/A2 story sound like B2 prose.
''';
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
              'TOPIC: $topic\nLEVEL: $levelBand\n'
              'SEED: use a main character named $name, a setting around $setting, '
              'and a small turn involving $twist. Make the result specific and fresh.',
        },
      ],
      maxTokens: 3000,
      temperature: 0.9,
    );
    return _parseStoryBookGeneration(raw, levelBand: levelBand, topic: topic);
  }

  /// Creates only the single portrait cover for an already-generated story.
  /// FLUX.2 Klein is the selected low-cost OpenRouter image tier. The bytes
  /// are uploaded once to Supabase Storage; reopening a story never regenerates
  /// its cover.
  Future<Uint8List> generateStoryCover({
    required String title,
    required String summary,
    required String topic,
    required String levelBand,
    String? coverPrompt,
  }) async {
    const qualityDirection =
        'Create a premium portrait editorial illustration in a 2:3 composition. '
        'Use sophisticated editorial realism, natural lighting, restrained color grading, '
        'one clear focal scene, layered depth, and a polished publishing aesthetic. '
        'Keep important visual details inside safe margins so the image remains clear when cropped. '
        'Do not use anime, Ghibli, chibi, cartoon, childish, storybook, or flat vector styles; '
        'do not use a collage, split panels, decorative frame, or UI mockup.';
    final prompt = coverPrompt == null || coverPrompt.trim().isEmpty
        ? '$qualityDirection\nScene subject: $topic. Mood and context: $summary. Learner level: $levelBand.'
        : '$qualityDirection\n$coverPrompt';
    final imageOnlyPrompt = '$prompt\n$_imageOnlyInstruction';
    try {
      final response = await _invokeFunction('ai-image', {
        'prompt': imageOnlyPrompt,
      }, timeout: const Duration(seconds: 45));
      final encoded = response['imageBase64'] as String?;
      if (encoded != null && encoded.isNotEmpty) return base64Decode(encoded);
      throw AgentError.badResponse;
    } catch (e) {
      if (e is AgentError) rethrow;
      throw AgentError.badResponse;
    }
  }

  /// Generates a story's Quiz and Keywords tabs together, right after
  /// `buildPersonalStory` — one call instead of two round-trips, since both
  /// draw on the same passage text. Grammar needs no separate call; it
  /// already reads off each segment's `grammarNote`/`pronunciationTip`.
  /// Best-effort by design: callers should fall back to empty lists on
  /// failure rather than block the story from being created, since the
  /// Story/Grammar tabs work fine on their own.
  Future<({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})>
  buildStoryQuizAndKeywords(
    ReadingPassage passage, {
    String levelBand = 'A2',
  }) async {
    const system = '''
Given a short French story, write a comprehension quiz and a keyword glossary for a language learner. Return ONLY compact JSON with this exact shape: {"quiz": [{"q": string, "q_en": string, "choices": [string, string, string], "choices_en": [string, string, string], "answerIndex": number}, ...], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}, ...]}.
QUIZ: 4 to 6 multiple-choice comprehension questions about events/details in the story. At A1/A2, q must be simple French with q_en as plain English support; choices must be French with choices_en as translations in exactly the same order. At B1/B2, still provide the support fields. Each question has exactly 3 choices and answerIndex points at the correct one (0-based). Only ask about things stated or clearly implied in the story.
KEYWORDS: 6 to 10 entries for useful French words or short phrases that actually appear in the story (verbatim or their dictionary form), each with its English meaning and a simple phonetic hint (e.g. "buh-ROH" style, not IPA). "id" is a short unique snake_case slug per entry.''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content': 'LEVEL: $levelBand\nSTORY:\n${passage.fullText}',
        },
      ],
      maxTokens: 1400,
    );
    return _parseStoryQuizAndKeywords(raw, levelBand: levelBand);
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
    'Impératif',
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
    String? contextTopic,
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
              '${contextTopic == null ? '' : 'COURSE SITUATION: $contextTopic\n'}'
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
  buildGrammarQuiz({
    required ReadingPassage passage,
    required String grammarPoint,
    String levelBand = 'A2',
  }) async {
    final system =
        '''
Given a short French story built specifically around the grammar point "$grammarPoint", write a quiz that TESTS THAT GRAMMAR POINT (not just story comprehension) plus a keyword glossary, same as for a regular story. Return ONLY compact JSON with this exact shape: {"quiz": [{"q": string, "q_en": string, "choices": [string, string, string], "choices_en": [string, string, string], "answerIndex": number}, ...], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}, ...]}.
QUIZ: 5 to 6 questions. At A1/A2, q must be a simple French question with q_en in plain English, and choices must be French with choices_en in the exact same order. Mostly ask "which form is correct" fill-in-the-blank questions, with only one grammatically correct answer for "$grammarPoint", plus 1-2 questions asking how the story used that grammar point. At B1/B2, still provide the English support fields. Base every question on "$grammarPoint" and the story's own sentences/vocabulary, never an unrelated grammar point.
KEYWORDS: 6 to 10 entries for useful French words or short phrases that actually appear in the story (verbatim or their dictionary form), each with its English meaning and a simple phonetic hint (e.g. "buh-ROH" style, not IPA). "id" is a short unique snake_case slug per entry.''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content':
              'LEVEL: $levelBand\nGRAMMAR POINT: $grammarPoint\nSTORY:\n${passage.fullText}',
        },
      ],
      maxTokens: 1400,
    );
    return _parseStoryQuizAndKeywords(raw, levelBand: levelBand);
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
  buildLiaisonQuiz({
    required ReadingPassage passage,
    String levelBand = 'A2',
  }) async {
    const system = '''
Given a short French story written specifically to be rich in liaison examples, write a quiz that TESTS LIAISON RECOGNITION (not just story comprehension) plus a keyword glossary. Return ONLY compact JSON with this exact shape: {"quiz": [{"q": string, "q_en": string, "choices": [string, string, string], "choices_en": [string, string, string], "answerIndex": number}, ...], "keywords": [{"id": string, "fr": string, "en": string, "phonetic": string}, ...]}.
QUIZ: 5 to 6 questions. At A1/A2, q must be simple French with q_en in plain English, and choices must be French with choices_en in the exact same order. Ask "does this word pair have a liaison?" or "how is this pronounced?" using actual word pairs from the story, plus 1-2 questions about a specific liaison. At B1/B2, still provide the English support fields. Base every question on the story's own sentences.
KEYWORDS: 6 to 10 entries for useful French words or short phrases that actually appear in the story, each with its English meaning and a simple phonetic hint (e.g. "buh-ROH" style, not IPA).''';
    final raw = await _complete(
      messages: [
        {'role': 'system', 'content': system + languageGuardrail},
        {
          'role': 'user',
          'content': 'LEVEL: $levelBand\nSTORY:\n${passage.fullText}',
        },
      ],
      maxTokens: 1400,
    );
    return _parseStoryQuizAndKeywords(raw, levelBand: levelBand);
  }

  /// Runs ONCE, right after a tense/topic is chosen for the Grammar stage — builds a short
  /// deck of `GrammarPracticeCard`s (one short French sentence in the chosen tense per card,
  /// its English meaning, and a one-line grammar note). Pre-generation, not live teaching:
  /// the prompt uses only the selected grammar material and current CEFR/content rules.
  String lastRawResponse = '';

  Future<List<GrammarPracticeCard>> generateGrammarPracticeCards({
    required String tenseTitle,
    required List<String> tenseUsage,
    required List<String> vocabWords,
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

  /// Compatibility entry point for callers that still ask the lesson agent
  /// for audio. The implementation is Gemini Live, not the retired HTTP TTS
  /// endpoint, and uses the selected tutor's voice.
  /// [voiceName] overrides the active persona's voice — used by tutor voice
  /// previews, where each candidate tutor must speak with their OWN voice.
  Future<List<int>> synthesizeSpeech(
    String text, {
    bool slow = false,
    String? voiceName,
  }) async {
    final bytes = await GeminiLiveAudioService.shared.resolve(
      text: text,
      contentItemId: 'lesson-agent:${text.trim()}',
      voiceName: voiceName ?? ActiveTutor.current.voiceName,
      slow: slow,
    );
    if (bytes == null) throw AgentError.requestFailed;
    return bytes;
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
    if (pcmBytes.isEmpty) return '';
    try {
      final response = await _invokeFunction('ai-text', {
        'provider': 'gemini',
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
        'maxTokens': 220,
        'temperature': 0.1,
      }, timeout: const Duration(seconds: 15));
      return (response['text'] as String? ?? '').trim();
    } on AgentError {
      return '';
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
    try {
      final response = await _invokeFunction('ai-text', {
        'provider': 'gemini',
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
        'maxTokens': 300,
        'temperature': 0.25,
      }, timeout: const Duration(seconds: 20));
      return (response['text'] as String? ?? '').trim();
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
    return _requestTextWithRetry(
      provider: _forceOpenRouter ? 'openrouter' : 'gemini',
      messages: messages,
      maxTokens: maxTokens,
      timeout: timeout,
      temperature: temperature,
    );
  }

  /// Text-generation calls retry transient provider failures. The provider
  /// credentials never enter this process; the authenticated Edge Function
  /// owns the provider request and returns only the generated text.
  Future<String> _requestTextWithRetry({
    required String provider,
    required List<Map<String, String>> messages,
    required int maxTokens,
    required Duration timeout,
    required double temperature,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _invokeFunction('ai-text', {
          'provider': provider,
          'messages': messages,
          'maxTokens': maxTokens,
          'temperature': temperature,
        }, timeout: timeout);
        final text = response['text'] as String?;
        if (text == null || text.trim().isEmpty) throw AgentError.badResponse;
        return normalizeGeneratedText(text);
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

  Future<Map<String, dynamic>> _invokeFunction(
    String name,
    Map<String, dynamic> body, {
    required Duration timeout,
  }) async {
    if (Supabase.instance.client.auth.currentSession == null) {
      throw AgentError.requestFailed;
    }
    try {
      final response = await Supabase.instance.client.functions
          .invoke(name, body: body)
          .timeout(timeout);
      final data = response.data;
      if (data is! Map) throw AgentError.badResponse;
      return Map<String, dynamic>.from(data);
    } on TimeoutException {
      throw AgentError.requestFailed;
    } on FunctionException catch (error) {
      if (error.status == 401 || error.status == 403) {
        throw AgentError.requestFailed;
      }
      throw GeminiHttpError.fromFunctionException(error);
    } on AgentError {
      rethrow;
    } catch (_) {
      throw AgentError.requestFailed;
    }
  }

  WritingFeedback _parseWritingFeedback(String raw) {
    final obj = _decodeObject(raw);
    final score = _asDouble(
      obj['score_out_of_10'] ?? obj['score'],
    ).clamp(0, 10).toDouble();
    final strengths = _stringList(obj['strengths']);
    final corrections = <({String original, String fixed, String why})>[];
    final correctionsRaw = obj['corrections'];
    if (correctionsRaw is List) {
      for (final item in correctionsRaw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final original = _stringValue(map['original']);
        final fixed = _stringValue(map['fixed']);
        // Ignore empty/malformed correction rows instead of letting one bad
        // item discard the entire grading response.
        if (original.isEmpty && fixed.isEmpty) continue;
        corrections.add((
          original: original,
          fixed: fixed,
          why: _stringValue(map['why']),
        ));
      }
    }
    final connectorFeedback = _stringValue(obj['connector_feedback']);
    final improved = _stringValue(
      obj['model_answer'] ?? obj['improved_version'],
    );
    final nextSteps = _stringList(obj['next_steps']);
    final scoreBreakdown = <String, double>{};
    final rawBreakdown = obj['score_breakdown'];
    if (rawBreakdown is Map) {
      for (final key in const [
        'task_completion',
        'grammar',
        'vocabulary',
        'coherence',
      ]) {
        if (!rawBreakdown.containsKey(key)) continue;
        final value = _asDouble(rawBreakdown[key]);
        if (value.isFinite) {
          scoreBreakdown[key] = value.clamp(0, 10).toDouble();
        }
      }
    }
    // Accept the flat form during rolling updates so an older model response
    // still produces useful review content.
    for (final key in const [
      'task_completion',
      'grammar',
      'vocabulary',
      'coherence',
    ]) {
      if (scoreBreakdown.containsKey(key)) continue;
      if (!obj.containsKey(key)) continue;
      final value = _asDouble(obj[key]);
      if (value.isFinite) scoreBreakdown[key] = value.clamp(0, 10).toDouble();
    }
    return WritingFeedback(
      scoreOutOf10: score,
      strengths: strengths,
      corrections: corrections,
      connectorFeedback: connectorFeedback,
      improvedVersion: improved,
      nextSteps: nextSteps,
      scoreBreakdown: scoreBreakdown,
    );
  }

  /// Keep a successful grading response useful even when the model omits an
  /// optional field. The Review screen must always have something concrete to
  /// show; a sparse JSON response should never turn into a blank lesson.
  WritingFeedback _ensureWritingFeedback(
    WritingFeedback feedback, {
    required String submission,
  }) {
    return WritingFeedback(
      scoreOutOf10: feedback.scoreOutOf10,
      strengths: feedback.strengths.isEmpty
          ? const ['You completed the writing task and produced a draft.']
          : feedback.strengths,
      corrections: feedback.corrections,
      connectorFeedback: feedback.connectorFeedback.isEmpty
          ? 'Keep one clear idea per sentence, then connect the ideas with a simple linking word.'
          : feedback.connectorFeedback,
      improvedVersion: feedback.improvedVersion.isEmpty
          ? submission.trim()
          : feedback.improvedVersion,
      nextSteps: feedback.nextSteps.isEmpty
          ? const [
              'Review the correction above and reuse that pattern in your next sentence.',
            ]
          : feedback.nextSteps,
      scoreBreakdown: feedback.scoreBreakdown,
    );
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return <String>[];
    return value
        .map(_stringValue)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _stringValue(dynamic value) => value?.toString().trim() ?? '';

  WritingTask _parseWritingTask(String raw, {required String levelBand}) {
    final obj = _decodeObject(raw);
    final promptFr = obj['prompt_fr'] as String?;
    if (promptFr == null || promptFr.isEmpty) throw AgentError.badResponse;
    return WritingTask(
      // Writing prompts are learner-owned rows in Supabase, so their id must
      // round-trip as a UUID just like generated stories and grammar stories.
      id: const Uuid().v4(),
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
      levelBand: levelBand,
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

  StoryBookGeneration _parseStoryBookGeneration(
    String raw, {
    required String levelBand,
    required String topic,
  }) {
    final obj = _decodeObject(raw);
    final passage = _parseReadingPassage(raw);
    final enrichment = _parseStoryQuizAndKeywords(raw, levelBand: levelBand);
    final summary = obj['summary']?.toString().trim() ?? '';
    final coverPrompt = obj['cover_prompt']?.toString().trim() ?? '';
    final parsedMinutes = obj['read_time_minutes'];
    final readTimeMinutes = parsedMinutes is num
        ? parsedMinutes.round().clamp(3, 12).toInt()
        : (passage.segments.length / 2).ceil().clamp(3, 12).toInt();
    return StoryBookGeneration(
      passage: passage,
      quiz: enrichment.quiz,
      keywords: enrichment.keywords,
      levelBand: levelBand.toUpperCase(),
      summary: summary,
      topic: topic,
      readTimeMinutes: readTimeMinutes,
      coverPrompt: coverPrompt,
    );
  }

  List<VocabEntry> _parseCourseVocabulary(
    String raw, {
    required int count,
    required String levelBand,
  }) {
    final obj = _decodeObject(raw);
    final wordsRaw = obj['words'] as List? ?? const [];
    final words = <VocabEntry>[];
    final ids = <String>{};
    for (final value in wordsRaw) {
      if (value is! Map) continue;
      final map = value.cast<String, dynamic>();
      final fr = map['fr']?.toString().trim() ?? '';
      final en = map['en']?.toString().trim() ?? '';
      final phonetic = map['phonetic']?.toString().trim() ?? '';
      if (fr.isEmpty || en.isEmpty) continue;
      final rawId = map['id']?.toString().trim() ?? '';
      final id = rawId.isEmpty
          ? 'course-${words.length}-${const Uuid().v4().substring(0, 6)}'
          : rawId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
      if (!ids.add(id)) continue;
      final entry = VocabEntry(id: id, fr: fr, en: en, phonetic: phonetic);
      if (!VocabularyLevelPolicy.allowsGeneratedEntry(entry, levelBand)) {
        continue;
      }
      words.add(entry);
      if (words.length == count) break;
    }
    if (words.length < count) throw AgentError.badResponse;
    return words;
  }

  ({List<MultipleChoiceQuestion> quiz, List<VocabEntry> keywords})
  _parseStoryQuizAndKeywords(String raw, {String levelBand = 'A2'}) {
    final obj = _decodeObject(raw);
    final quizRaw = (obj['quiz'] as List?) ?? [];
    final quiz = <MultipleChoiceQuestion>[];
    final beginnerLevel = switch (levelBand.trim().toUpperCase()) {
      'A1' || 'A2' => true,
      _ => false,
    };
    for (final q in quizRaw) {
      final map = q as Map<String, dynamic>;
      final question = map['q'] as String?;
      final choices = (map['choices'] as List?)?.cast<String>() ?? const [];
      final answerIndex = map['answerIndex'];
      final qEn = map['q_en']?.toString() ?? map['question_en']?.toString();
      final choicesEn = (map['choices_en'] as List?)
          ?.map((choice) => choice.toString())
          .toList(growable: false);
      if (question == null ||
          question.isEmpty ||
          choices.isEmpty ||
          answerIndex is! int ||
          answerIndex < 0 ||
          answerIndex >= choices.length ||
          (beginnerLevel &&
              (qEn == null ||
                  qEn.trim().isEmpty ||
                  choicesEn == null ||
                  choicesEn.length != choices.length))) {
        continue;
      }
      quiz.add(
        MultipleChoiceQuestion(
          q: question,
          choices: choices,
          answerIndex: answerIndex,
          qEn: qEn,
          choicesEn: choicesEn,
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
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }
}
