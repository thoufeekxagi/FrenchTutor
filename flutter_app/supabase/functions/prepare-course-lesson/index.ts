import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type Json = Record<string, unknown>;

type VocabularyCandidate = Json & {
  id: string;
  fr: string;
  en: string;
  phonetic: string;
  role: "review" | "new";
};

// Mirrors adaptiveCourseFoundationSize/adaptiveCourseBatchSize in
// lib/data/database/adaptive_course_store.dart. Sequences 1-5 (foundation)
// and 6-10 (Unit 2) are both fixed, authored content for every learner;
// real AI generation only begins at sequence 11.
const AUTHORED_SEQUENCE_CEILING = 10;

// Mirrors _unitTwoWords in lib/data/database/adaptive_course_store.dart.
// Unit 2's five words are fixed and identical for every learner, so no AI
// vocabulary lesson from sequence 11 onward may ever reteach one of them as
// if it were new — the model has no other way to know they already exist,
// since they never pass through target_phrases_json like real generated
// history does.
const UNIT_TWO_TAUGHT_WORDS = ["marché", "pomme", "vendeuse", "prix", "fraîche"];

function foldFrench(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim();
}

function response(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers });
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function boundedText(value: unknown, maxCharacters: number): string {
  const valueText = text(value);
  return valueText.length <= maxCharacters
    ? valueText
    : valueText.slice(0, maxCharacters).trimEnd();
}

// Word-order reconstruction checks (Guided Writing/Grammar, Complete
// Grammar) exist to verify the token bank rebuilds the target sentence's
// *words* in order, not to demand a byte-perfect punctuation match. Models
// routinely vary curly vs straight apostrophes and where a comma/period
// token attaches, which a literal string comparison rejects even though the
// word bank is pedagogically correct. Normalize both sides the same way
// before comparing so only real word-order/word-choice mistakes fail.
function normalizeForReconstruction(value: string): string {
  return value
    .toLowerCase()
    .replace(/[’‘]/g, "'")
    .replace(/[.,!?;:«»""]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function stripGuidedTokenPunctuation(value: unknown): string {
  return text(value)
    .replace(/^[.,!?;:«»"“”]+/u, "")
    .replace(/[.,!?;:«»"“”]+$/u, "")
    .trim();
}

function stripGuidedSentencePunctuation(value: unknown): string {
  return text(value)
    .replace(/[.,!?;:«»"“”]/gu, "")
    .replace(/\s+/g, " ")
    .trim();
}

// Guided Writing chips represent selectable words or short chunks. Punctuation
// stays out of the target and out of the word bank so the learner only orders
// language-bearing items. Clean the model artifact once at the server boundary
// so older punctuation-heavy responses follow the same contract before
// validation and persistence.
function normalizeGuidedWritingArtifact(artifact: Json): Json {
  if (text(artifact.practiceMode) !== "guided") return artifact;
  const lessonValue = artifact.lesson;
  if (!lessonValue || typeof lessonValue !== "object" || Array.isArray(lessonValue)) {
    return artifact;
  }
  const lesson = object(lessonValue);
  if (!Array.isArray(lesson.steps)) return artifact;
  const steps = lesson.steps.map((raw) => {
    const step = object(raw);
    if (text(step.kind) !== "arrange" || !Array.isArray(step.tokens)) {
      return raw;
    }
    const rawMeanings = Array.isArray(step.token_meanings)
      ? step.token_meanings
      : [];
    const tokens: string[] = [];
    const meanings: string[] = [];
    step.tokens.forEach((rawToken, index) => {
      const token = stripGuidedTokenPunctuation(rawToken);
      if (!token) return;
      tokens.push(token);
      meanings.push(text(rawMeanings[index]));
    });
    return {
      ...step,
      target: stripGuidedSentencePunctuation(step.target),
      tokens,
      token_meanings: meanings,
    };
  });
  return { ...artifact, lesson: { ...lesson, steps } };
}

function list(value: unknown, limit = 4): string[] {
  return Array.isArray(value)
    ? value.map(text).filter(Boolean).slice(0, limit)
    : [];
}

function object(value: unknown): Json {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Prepared lesson is not a JSON object");
  }
  return value as Json;
}

function parseModelJson(value: unknown): Json {
  const raw = text(value)
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/, "");
  return object(JSON.parse(raw));
}

function idPart(value: string): string {
  return value.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 80);
}

function baseArtifact(session: Json, kind: string): Json {
  const now = new Date().toISOString();
  const id = text(session.id);
  return {
    id: `${kind}-${id}`,
    title: text(session.title),
    summary: text(session.competency),
    topic: text(session.context),
    levelBand: text(session.level) || "A1",
    createdAt: now,
    coverUrl: "asset:assets/starter_covers/lantern.png",
  };
}

function cefrRules(level: string): string {
  switch (level.trim().toUpperCase()) {
    case "A1":
      return `CEFR A1 — enforce this, not a suggestion:
- Use only very common everyday words and one idea per line.
- Prefer present tense and familiar near-future expressions only when essential.
- Keep each French speaking line to 3–8 words.
- Avoid long subordinate clauses. Do not use si/parce que conditions, opinions with reasons, past narration, or abstract language.
- Use greetings, identity, routine, food, places, numbers, simple requests, likes, and short questions.`;
    case "A2":
      return `CEFR A2 — enforce this, not a suggestion:
- Use common everyday vocabulary and mostly one-clause sentences.
- Keep each French speaking line to 4–11 words.
- A simple passé composé or futur proche is allowed; do not use conditional, subjunctive, or multi-clause hypotheses.
- Use one simple connector at most (et, mais, parce que) and stay concrete.`;
    case "B1":
      return `CEFR B1 — use familiar everyday language with short connected sentences.
- Simple past, future, reasons, and one subordinate clause are allowed.
- Avoid academic, literary, or C1 vocabulary.`;
    case "B2":
      return `CEFR B2 — natural connected French is allowed, including nuanced reasons and common subordinate clauses.
- Avoid rare literary vocabulary and keep the task usable for the stated learner goal.`;
    default:
      return `Use short, common French and err simpler when the level is unclear.`;
  }
}

function earlyPhaseRules(level: string, sequence: number, skill: string): string {
  if (!Number.isFinite(sequence) || sequence > 15 || sequence <= 5) {
    return "Use the normal Practice shape for this skill, but keep the French at the requested CEFR band.";
  }
  const band = level.trim().toUpperCase();
  const shape = skill === "speaking" || skill === "roleplay" || skill === "free_talk"
    ? "Use the dedicated guided phrase flow: hear one short phrase, repeat it, and repair it before moving on. Do not add Free Talk or Roleplay."
    : skill === "listening" || skill === "reading"
    ? "Use four to six short lines, one idea per line, followed by two or three simple checks."
    : skill === "vocabulary"
    ? "Use five common words in one tiny connected situation; do not introduce a large word list."
    : skill === "grammar"
    ? "Teach one pattern with a pick-one check, a sentence builder, and one tiny transfer example."
    : skill === "writing"
    ? "Use a word bank or sentence builder before asking for a short message."
    : "Use one small, concrete check before any open response.";
  if (band === "A1") {
    return `EARLY COURSE PHASE (lesson ${sequence}, A1): ${shape}
- Keep every French target concrete, common, and short. Prefer greetings, identity, routine, food, places, numbers, simple requests, and likes.
- Keep target sentences to one clause and about 3–8 words. No conditionals, abstract opinions, past narration, or long explanations.
- This is a confidence-building bridge from onboarding, not an exam task or an open-ended challenge.
- The learner's stated goal (e.g. exam prep, immigration, work) may choose the SCENE, but not the vocabulary yet. Even inside an administrative or professional situation, teach only the most basic words a total beginner already needs: greetings, yes/no, numbers, please/thank you, simple requests like "I would like...". Do not teach bureaucratic, technical, or exam-register words (for example: formulaire, dossier, service, agence, rendez-vous administratif, demande) at this stage. That vocabulary belongs to a later lesson once the foundation is solid, never the first few personalized lessons.`;
  }
  if (band === "A2") {
    return `EARLY COURSE PHASE (lesson ${sequence}, A2): ${shape}
- Keep the task concrete and mostly one clause. Use a simple past or futur proche only when it serves the situation.
- Keep target sentences short (about 4–11 words). Add at most one small new grammar step.
- Do not turn this early lesson into an essay, debate, or complex roleplay.
- The learner's stated goal may choose the scene, but keep the vocabulary itself everyday and concrete. Introduce at most one situation-specific word, glossed clearly; do not stack multiple technical/bureaucratic terms into one early lesson.`;
  }
  return `EARLY COURSE PHASE (lesson ${sequence}, ${band}): ${shape}
- Keep the lesson compact and controlled before offering one optional extension. Reuse recent language for the 60% retrieval portion and add only 40% new language.`;
}

function validateSimpleFrench(value: string, level: string, label: string, maxWords?: number) {
  const band = level.trim().toUpperCase();
  const words = value.split(/\s+/).filter(Boolean);
  const limit = maxWords ?? (band === "A1" ? 10 : band === "A2" ? 14 : 24);
  if ((band === "A1" || band === "A2") && words.length > limit) {
    throw new Error(`${label} is too long for ${band}`);
  }
  const folded = value.toLowerCase();
  if (band === "A1" && /\b(conditionnel|subjonctif|à condition que|bien que|cependant|pourtant)\b/u.test(folded)) {
    throw new Error(`${label} uses an advanced structure for A1`);
  }
}

function validateVocabulary(
  artifact: Json,
  level: string,
  vocabularyCandidates: VocabularyCandidate[] = [],
) {
  const entries = artifact.entries;
  const examples = artifact.storyExamples;
  if (!Array.isArray(entries) || entries.length !== 5) {
    throw new Error("Vocabulary must contain exactly five words");
  }
  const storyExamples = object(examples);
  const ids = new Set<string>();
  const candidateById = new Map(
    vocabularyCandidates.map((candidate) => [candidate.id, candidate]),
  );
  let reviewCount = 0;
  let newCount = 0;
  for (const raw of entries) {
    const entry = object(raw);
    const id = text(entry.id);
    if (!id || !text(entry.fr) || !text(entry.en) || !text(entry.phonetic)) {
      throw new Error("Every vocabulary word needs id, French, English, and phonetic text");
    }
    if (ids.has(id)) throw new Error("Vocabulary word ids must be unique");
    ids.add(id);
    if (vocabularyCandidates.length > 0) {
      const candidate = candidateById.get(id);
      if (!candidate || foldFrench(candidate.fr) !== foldFrench(text(entry.fr))) {
        throw new Error(`Vocabulary word "${id}" was not selected from the app lexicon`);
      }
      if (candidate.role === "review") reviewCount += 1;
      if (candidate.role === "new") newCount += 1;
    }
    // Real generation defect caught directly from a learner's screenshot: the
    // model can echo the English gloss into the French field too (fr and en
    // byte-identical), while id/phonetic still correctly hold the real French
    // word. A learner then sees "FRENCH WORD: milk" for lait. Word-count and
    // banned-structure checks below never catch this since plain English
    // words pass both. Reject the whole artifact so it regenerates instead
    // of ever reaching a learner's screen.
    if (text(entry.fr).toLowerCase() === text(entry.en).toLowerCase()) {
      throw new Error(
        `Vocabulary word "${id}" has the same text for French and English ("${text(entry.fr)}") — the French field must contain the actual French word`,
      );
    }
    const example = object(storyExamples[id]);
    if (!text(example.fr) || !text(example.en)) {
      throw new Error("Every vocabulary word needs one prepared bilingual sentence");
    }
    if (text(example.fr).toLowerCase() === text(example.en).toLowerCase()) {
      throw new Error(
        `Vocabulary word "${id}"'s example sentence has the same text for French and English`,
      );
    }
    if (level.trim().toUpperCase() === "A1" && text(entry.fr).split(/\s+/).length > 3) {
      throw new Error("A1 vocabulary entries must be short words or chunks");
    }
    // When a lexical candidate payload is present, previously learned words
    // are deliberate review material. Without that payload, keep the older
    // safety rule for production callers that have not yet shipped the
    // client-side lexicon slice.
    if (vocabularyCandidates.length === 0 && UNIT_TWO_TAUGHT_WORDS.some((word) => foldFrench(word) === foldFrench(text(entry.fr)))) {
      throw new Error(
        `"${text(entry.fr)}" was already taught in Unit 2; choose a genuinely new word`,
      );
    }
    validateSimpleFrench(text(example.fr), level, "Vocabulary example", 10);
  }
  if (vocabularyCandidates.length > 0) {
    const availableReview = vocabularyCandidates.filter((candidate) => candidate.role === "review").length;
    const availableNew = vocabularyCandidates.filter((candidate) => candidate.role === "new").length;
    const requiredReview = Math.min(2, availableReview);
    const requiredNew = Math.min(3, availableNew);
    if (reviewCount < requiredReview || newCount < requiredNew) {
      throw new Error("Vocabulary must balance reviewed and new lexical items");
    }
  }
}

function validateStory(artifact: Json, level = "", sequence = 0) {
  const passage = object(artifact.passage);
  if (!Array.isArray(passage.segments) || passage.segments.length < 2) {
    throw new Error("Story must contain prepared bilingual segments");
  }
  for (const raw of passage.segments) {
    const segment = object(raw);
    if (!text(segment.fr) || !text(segment.en)) {
      throw new Error("Every story segment needs French and English");
    }
    if (text(segment.fr).toLowerCase() === text(segment.en).toLowerCase()) {
      throw new Error("A story segment has the same text for French and English");
    }
    if (level) validateSimpleFrench(text(segment.fr), level, "Story line");
  }
  if (!Array.isArray(artifact.quiz) || artifact.quiz.length < 1) {
    throw new Error("Story must contain prepared comprehension checks");
  }
}

function validateWriting(artifact: Json, level: string) {
  const expectedMode = text(artifact.practiceMode);
  // Course Writing is intentionally limited to the two beginner-safe
  // interactions that are stable across every CEFR band: word-bank ordering
  // and choose-the-missing-word. Roleplay remains a separate Practice-only
  // surface and must never be persisted by this Course generator.
  if (!["guided", "complete"].includes(expectedMode)) {
    throw new Error("Writing Practice mode is invalid");
  }
  const lesson = object(artifact.lesson);
  const band = level.trim().toUpperCase();
  if (!text(lesson.id) || !text(lesson.title) || !text(lesson.subtitle)) {
    throw new Error("Writing lesson metadata is incomplete");
  }
  if (text(lesson.mode) !== expectedMode) {
    throw new Error("Writing lesson mode does not match its Practice mode");
  }
  if (text(lesson.level).toUpperCase() !== band) {
    throw new Error("Writing level band does not match the session");
  }
  const steps = lesson.steps;
  const expectedCount = 5;
  if (!Array.isArray(steps) || steps.length !== expectedCount) {
    throw new Error(`Writing ${expectedMode} requires exactly ${expectedCount} steps`);
  }
  for (const raw of steps) {
    const step = object(raw);
    const prompt = text(step.prompt);
    const promptEnglish = text(step.prompt_english);
    const target = text(step.target);
    if (!prompt || !promptEnglish || !target || !text(step.tip)) {
      throw new Error("A Writing Practice step is incomplete");
    }
    validateSimpleFrench(target, level, "Writing target");
    if (expectedMode === "guided") {
      const tokens = list(step.tokens, 20);
      const meanings = list(step.token_meanings, 20);
      if (text(step.kind) !== "arrange" || tokens.length < 2 ||
        meanings.length !== tokens.length ||
        normalizeForReconstruction(tokens.join(" ")) !==
          normalizeForReconstruction(target)) {
        throw new Error("Guided Writing needs one reconstructable bilingual word bank");
      }
    } else if (expectedMode === "complete") {
      const choices = list(step.choices, 3);
      const meanings = list(step.choice_meanings, 3);
      if (text(step.kind) !== "choice" || !prompt.includes("___") ||
        choices.length !== 3 || new Set(choices).size !== 3 ||
        !choices.includes(target) || meanings.length !== choices.length) {
        throw new Error("Complete Writing needs one blank and three bilingual choices");
      }
    } else {
      throw new Error("Writing roleplay is disabled for Course generation");
    }
  }
}

function validateGrammar(artifact: Json, level: string) {
  const expectedMode = text(artifact.practiceMode);
  if (!["guided", "complete", "roleplay"].includes(expectedMode)) {
    throw new Error("Grammar Practice mode is invalid");
  }
  const session = object(artifact.session);
  const band = level.trim().toUpperCase();
  if (!text(session.id) || !text(session.title) || !text(session.subtitle) ||
    !text(session.tense) || !text(session.grammar_focus)) {
    throw new Error("Grammar session metadata is incomplete");
  }
  if (text(session.mode) !== expectedMode) {
    throw new Error("Grammar session mode does not match its Practice mode");
  }
  if (text(session.level).toUpperCase() !== band) {
    throw new Error("Grammar level band does not match the session");
  }
  const steps = session.steps;
  const expectedCount = expectedMode === "roleplay" ? 4 : 5;
  if (!Array.isArray(steps) || steps.length !== expectedCount) {
    throw new Error(`Grammar ${expectedMode} requires exactly ${expectedCount} steps`);
  }
  const labels = new Set<string>();
  for (const raw of steps) {
    const step = object(raw);
    const label = text(step.label).toLowerCase();
    const prompt = text(step.prompt);
    const target = text(step.target);
    const answer = text(step.answer);
    if (!label || labels.has(label) || !prompt || !text(step.prompt_english) ||
      !target || !answer || !text(step.tip)) {
      throw new Error("A Grammar Practice step is incomplete or duplicated");
    }
    labels.add(label);
    validateSimpleFrench(target, level, "Grammar target");
    if (expectedMode === "guided") {
      const choices = list(step.choices, 3);
      if (!prompt.includes("___") || choices.length !== 3 ||
        new Set(choices).size !== 3 || !choices.includes(answer)) {
        throw new Error("Guided Grammar needs one blank and three unique choices");
      }
    } else if (expectedMode === "complete") {
      const tokens = list(step.tokens, 20);
      if (tokens.length < 2 ||
        normalizeForReconstruction(tokens.join(" ")) !==
          normalizeForReconstruction(target)) {
        throw new Error("Complete Grammar needs a word bank that rebuilds the target");
      }
    } else {
      const choices = list(step.choices, 3);
      if (!text(step.partner_french) || !text(step.partner_english) ||
        choices.length !== 3 || new Set(choices).size !== 3 ||
        !choices.includes(answer)) {
        throw new Error("Grammar roleplay needs a translated partner and three replies");
      }
      validateSimpleFrench(text(step.partner_french), level, "Grammar partner line");
    }
  }
}

function validateSpeaking(artifact: Json, level: string, expectedMode: string) {
  if (text(artifact.practiceMode) !== expectedMode) {
    throw new Error("Speaking lesson mode does not match its Practice mode");
  }
  if (!Array.isArray(artifact.lines) || artifact.lines.length < 3) {
    throw new Error("Speaking lesson must contain at least three prepared lines");
  }
  const normalized = level.trim().toUpperCase();
  const seenFrench = new Set<string>();
  for (const raw of artifact.lines) {
    const line = object(raw);
    const french = text(line.fr);
    if (!french || !text(line.en)) {
      throw new Error("Every speaking line needs French and English");
    }
    if (french.toLowerCase() === text(line.en).toLowerCase()) {
      throw new Error("A speaking line has the same text for French and English");
    }
    if (expectedMode !== "guidedConversation" &&
      (!text(line.partnerFr) || !text(line.partnerEn) || line.openResponse !== true)) {
      throw new Error(`${expectedMode} needs translated partner prompts and an open response`);
    }
    const words = french.split(/\s+/).filter(Boolean);
    const folded = french.toLowerCase();
    const normalizedFrench = folded
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9 ]/g, "")
      .replace(/\s+/g, " ")
      .trim();
    if (/^(répétez|repetez|repeat|say|listen)\b/iu.test(french)) {
      throw new Error("Guided speaking lines must contain the phrase only, not an instruction");
    }
    if (seenFrench.has(normalizedFrench)) {
      throw new Error("Guided speaking lines must be unique; do not duplicate a card");
    }
    seenFrench.add(normalizedFrench);
    if (normalized === "A1") {
      if (words.length > 8) {
        throw new Error("A1 speaking lines must contain 8 words or fewer");
      }
      if (/\b(si|parce que|dont|cependant|pourtant)\b/u.test(folded)) {
        throw new Error("A1 speaking lines cannot use subordinate clauses");
      }
    }
    if (normalized === "A2") {
      if (words.length > 11) {
        throw new Error("A2 speaking lines must contain 11 words or fewer");
      }
      if (/\b(à condition que|bien que|pourrais|pourrait|devrais|devrait)\b/u.test(folded)) {
        throw new Error("A2 speaking lines cannot use conditional or complex clauses");
      }
    }
  }
}

function artifactKind(skill: string): string {
  switch (skill) {
    case "vocabulary": return "vocabulary";
    case "reading": return "reading";
    case "listening": return "listening";
    case "writing": return "writing";
    case "grammar": return "grammar";
    case "speaking":
    case "roleplay":
    case "free_talk": return "speaking";
    default: return "deterministic";
  }
}

// A release can outlive the generator that created its cached artifact. Keep
// stale guided cards from being shown forever: the next Course pass queues the
// row again and prepares the current phrase-only contract.
function needsGuidedSpeakingRefresh(row: Json): boolean {
  if (text(row.primary_skill) !== "speaking" ||
      text(row.generation_status) !== "ready") return false;
  const sequence = Number(row.sequence ?? 0);
  const title = text(row.title).toLowerCase();
  if (sequence >= 6 && sequence <= 8 &&
      new Set(["say hello", "say your name", "say what you like"]).has(title)) {
    return true;
  }
  const raw = row.artifact_json;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return false;
  const lines = (raw as Json).lines;
  if (!Array.isArray(lines)) return false;
  const seen = new Set<string>();
  for (const item of lines) {
    const line = item && typeof item === "object" && !Array.isArray(item)
      ? item as Json
      : {};
    const french = text(line.fr);
    if (/^(répétez|repetez|repeat|say|listen)\b/iu.test(french)) return true;
    const normalized = french.toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9 ]/g, "")
      .replace(/\s+/g, " ")
      .trim();
    if (normalized && !seen.add(normalized)) return true;
  }
  return false;
}

function practiceModeFor(skill: string, sequence: number): string {
  const variant = Math.max(0, sequence - 6) % 3;
  switch (skill) {
    case "speaking":
    case "roleplay":
    case "free_talk": return "guidedConversation";
    // Course Writing deliberately alternates only between word-bank ordering
    // and fill-in-the-blank. Roleplay is Practice-only until a later release.
    case "writing": return ["complete", "guided"][Math.max(0, sequence - 6) % 2];
    case "grammar": return ["guided", "complete", "roleplay"][variant];
    case "listening": return ["story", "narration", "music"][variant];
    case "reading": return "story";
    case "vocabulary": return "wordsAndSentences";
    default: return skill;
  }
}

// Units alternate between two honest, simple postures instead of applying
// the same 60/40 reuse ratio everywhere. A learner should feel real spaced
// repetition in some units and real new-ground exploration in others, never
// the same recycled sentence shape every single time — but every unit still
// keeps one connected through-line, never a random grab-bag of words.
function unitBalanceLine(sequence: number): string {
  const unit = Math.floor((sequence - 1) / 5) + 1;
  return unit % 2 === 0
    ? "This unit favors EXPLORATION: reuse only about 30% of recent/onboarding language and spend about 70% on genuinely new words and a new situation, while still keeping one clear through-line so the unit feels cohesive, not a random grab-bag."
    : "This unit favors REPETITION for spaced practice: reuse about 60% of recent/onboarding language and add about 40% new language.";
}

function promptFor(
  session: Json,
  kind: string,
  vocabularyCandidates: VocabularyCandidate[] = [],
): string {
  const primarySkill = text(session.primary_skill);
  const sequence = Number(session.sequence ?? 0);
  const brief = {
    goal: text(session.subtitle).split(" · ")[0],
    level: text(session.level),
    sequence,
    title: text(session.title),
    competency: boundedText(session.competency, 180),
    context: boundedText(session.context, 360),
    primarySkill,
    practiceMode: practiceModeFor(primarySkill, sequence),
    grammarFocus: list(session.grammar_focus_json, 2),
    recentTargets: list(session.target_phrases_json, 4),
    avoidExact: Number.isFinite(sequence) && sequence === 6 &&
        (primarySkill === "speaking" || primarySkill === "roleplay" || primarySkill === "free_talk")
      ? ["Bonjour.", "Je m'appelle.", "Je viens de."]
      : [],
  };
  const base = `Create one compact French-learning ${kind} lesson from this frozen brief:\n${JSON.stringify(brief)}\n`;
  const rules = `Return only valid JSON. Keep all French exactly at ${brief.level || "A1"}. Use the learner goal and the small recent-evidence context naturally; treat any transcript excerpt as a hint, never as a script to copy. Avoid generic travel/cafe filler unless the brief asks for it, and do not mention AI. ${unitBalanceLine(sequence)} Never return a phrase listed in avoidExact verbatim; make the new lesson a genuinely new card while keeping the same small CEFR-appropriate interaction.\n${cefrRules(brief.level || "A1")}\n${earlyPhaseRules(brief.level || "A1", brief.sequence, brief.primarySkill)}`;
  if (kind === "speaking") {
    const lineShape = brief.practiceMode === "guidedConversation"
      ? `{"fr":"short learner phrase","en":"exact English meaning"}`
      : `{"fr":"short learner response or frame","en":"exact English meaning","partnerFr":"one short tutor line","partnerEn":"exact English meaning","openResponse":true}`;
    return `${base}${rules}\nThe exact Course Practice mode is ${brief.practiceMode}; never merge it with another interaction. Return exactly: {"practiceMode":"${brief.practiceMode}","lines":[3 to 5 ${lineShape}]}. Every line must be useful for the competency and fully bilingual. This Course speaking lesson is hear/repeat/repair phrase practice only: no live tutor conversation, Free Talk, Roleplay, word selection, or open response. Each French line must be the phrase the learner repeats, with no prefix such as "Répétez", "Repeat", or "Say". Keep all lines distinct. Reuse suitable targets, but correct mixed-language or incomplete targets instead of copying them.`;
  }
  if (kind === "vocabulary") {
    const candidateText = vocabularyCandidates.length === 0
      ? "No client lexicon slice was supplied; use only safe, common vocabulary and do not repeat the fixed Unit 2 words."
      : vocabularyCandidates
        .map((candidate) => `${candidate.id}|${candidate.fr}|${candidate.en}|${candidate.phonetic}|${candidate.role}`)
        .join("; ");
    return `${base}${rules}\nChoose every entry from this app lexicon slice only. Each candidate is marked review or new. Aim for two reviewed words and three new words when the supplied pools allow it; never invent a French word or id. LEXICON: ${candidateText}\nReturn exactly: {"entries":[exactly 5 {"id":"stable-short-id","fr":"word or short phrase","en":"English","phonetic":"simple pronunciation"}],"storyExamples":{"same-id":{"fr":"sentence","en":"translation"}}}. The five example sentences must form one connected mini-story in order. Each sentence must naturally use its matching French entry.`;
  }
  if (kind === "reading" || kind === "listening") {
    return `${base}${rules}\nReturn exactly: {"passage":{"id":"passage","title":"French title","titleEn":"English title","segments":[4 to 6 {"fr":"French sentence","en":"English translation","grammarNote":"short useful note","pronunciationTip":"short useful tip"}],"fullText":"the exact French segments joined in order"},"quiz":[2 or 3 {"q":"French question","q_en":"English question","choices":[3 French choices],"choices_en":[3 English choices],"answerIndex":0}],"keywords":[up to 5 {"id":"id","fr":"French","en":"English","phonetic":"pronunciation"}]}. Every answerIndex must be 0, 1, or 2 and point to the correct choice.`;
  }
  if (kind === "writing") {
    const mode = brief.practiceMode;
    const count = mode === "roleplay" ? 4 : 5;
    const step = mode === "guided"
      ? `{"prompt":"short French instruction","prompt_english":"short English instruction","target":"one complete French sentence","kind":"arrange","tokens":["every","target","token","in","exact","order"],"token_meanings":["one English meaning for each matching token"],"tip":"short English hint"}`
      : mode === "complete"
      ? `{"prompt":"one French sentence containing exactly one ___ blank","prompt_english":"exact English meaning","target":"the missing answer","kind":"choice","choices":["exactly three choices including target"],"choice_meanings":["one English meaning per matching choice"],"tip":"short English hint"}`
      : `{"prompt":"short French reply instruction","prompt_english":"short English instruction","target":"short model French reply","kind":"text","partner_french":"short partner message","partner_english":"exact English meaning","goal":"one clear reply goal","suggestions":["up to three short French supports"],"suggestion_meanings":["one English meaning per support"],"tip":"short English hint"}`;
    const guidedRule = mode === "guided"
      ? "For guided arrange steps, target and tokens contain words or short chunks only: do not include commas, periods, question marks, or other sentence punctuation anywhere. Do not emit punctuation-only tokens or attach punctuation to a token. Keep each target to one short sentence."
      : "";
    return `${base}${rules}\nThe exact Writing Practice mode is ${mode}; never mix it with Speaking or another Writing mode. Return exactly: {"practiceMode":"${mode}","lesson":{"id":"writing-${text(session.id)}","title":"short learner-facing title","title_en":"short English title","subtitle":"one short English subtitle","level":"${brief.level || "A1"}","mode":"${mode}","goal":"one short goal","steps":[exactly ${count} ${step}]}}. ${guidedRule} For arrange steps, cleaned tokens joined with spaces must reconstruct the target words in order and token_meanings must have the same length with one meaning per selectable token. Keep output short and controlled at every CEFR level.`;
  }
  const mode = brief.practiceMode;
  const count = mode === "roleplay" ? 4 : 5;
  const grammarStep = mode === "guided"
    ? `{"label":"unique short label","prompt":"French sentence with exactly one ___ blank","prompt_english":"English meaning","target":"complete French sentence","answer":"missing form","choices":["exactly three choices including answer"],"tokens":[],"tip":"short English rule"}`
    : mode === "complete"
    ? `{"label":"unique short label","prompt":"short instruction","prompt_english":"English instruction","target":"complete French sentence","answer":"same complete French sentence","choices":[],"tokens":["every","target","token","in","exact","order"],"tip":"short English rule"}`
    : `{"label":"unique short label","prompt":"reply goal in French","prompt_english":"reply goal in English","target":"correct learner reply","answer":"same correct learner reply","choices":["exactly three replies including answer"],"tokens":[],"tip":"short English rule","partner_french":"short partner line","partner_english":"exact English meaning"}`;
  return `${base}${rules}\nThe exact Grammar Practice mode is ${mode}; never combine modes. Return exactly: {"practiceMode":"${mode}","session":{"id":"grammar-${text(session.id)}","title":"short title","subtitle":"short English subtitle","level":"${brief.level || "A1"}","tense":"Present, Past, Future, or Mixed","grammar_focus":"one small level-correct pattern","icon_key":"sparkles","mode":"${mode}","goal":"one short goal","source":"generated","steps":[exactly ${count} ${grammarStep}]}}. Tokens joined with spaces must reconstruct target exactly. Keep one grammar pattern throughout.`;
}

function validateArtifact(
  artifact: Json,
  session: Json,
  kind: string,
  vocabularyCandidates: VocabularyCandidate[] = [],
) {
  if (kind === "speaking") {
    validateSpeaking(
      artifact,
      text(session.level) || "A1",
      practiceModeFor(text(session.primary_skill), Number(session.sequence ?? 0)),
    );
  }
  if (kind === "vocabulary") validateVocabulary(
    artifact,
    text(session.level) || "A1",
    vocabularyCandidates,
  );
  if (kind === "reading" || kind === "listening") validateStory(artifact, text(session.level) || "A1", Number(session.sequence ?? 0));
  if (kind === "writing") validateWriting(artifact, text(session.level) || "A1");
  if (kind === "grammar") validateGrammar(artifact, text(session.level) || "A1");
}

// Course normally uses one provider request. If the model returns JSON that
// the local validator rejects, give the same model one repair turn containing
// the exact rejection reason and the rejected JSON. This is bounded at two
// total calls so a malformed artifact can self-correct without becoming a
// retry storm or silently multiplying spend.
const MAX_GENERATION_ATTEMPTS = 2;

async function generateArtifact(
  supabaseUrl: string,
  serviceRoleKey: string,
  session: Json,
  kind: string,
  vocabularyCandidates: VocabularyCandidate[] = [],
): Promise<Json> {
  if (kind === "deterministic") {
    return {
      ...baseArtifact(session, kind),
      targetPhrases: list(session.target_phrases_json),
    };
  }
  // Course authoring deliberately follows Practice's text route for every
  // skill. The old split sent Reading/Listening through a separate Gemini
  // path while the rest used Practice's OpenRouter path; that made Course
  // more expensive without improving the saved artifact. Gemini remains
  // reserved for explicit Live/audio work, not ordinary lesson JSON.
  const provider = "openrouter";
  const messages: Array<{ role: string; content: string }> = [
    {
      role: "system",
      content: "You prepare one small, coherent French lesson at a time. Follow the requested JSON schema exactly and keep the learner context minimal.",
    },
    { role: "user", content: promptFor(session, kind, vocabularyCandidates) },
  ];

  let lastError: Error | null = null;
  for (let attempt = 1; attempt <= MAX_GENERATION_ATTEMPTS; attempt++) {
    let rawText = "";
    try {
      console.info(JSON.stringify({
        event: "course_artifact_attempt",
        session_id: text(session.id),
        kind,
        provider,
        attempt,
        max_attempts: MAX_GENERATION_ATTEMPTS,
      }));
      const aiResponse = await fetch(`${supabaseUrl}/functions/v1/ai-text`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          provider,
          traceFeature: `course_${kind}`,
          messages,
          // Vocabulary is deliberately a small five-card artifact. Keep its
          // authoring budget separate from story/reading lessons so a verbose
          // model response cannot turn one queued card set into an expensive
          // text request.
          maxTokens: kind === "vocabulary"
            ? 1200
            : kind === "writing"
            ? 2200
            : 2600,
          temperature: 0.35,
          responseFormat: { type: "json_object" },
          retryPolicy: "none",
        }),
      });
      const aiData = await aiResponse.json().catch(() => ({}));
      if (!aiResponse.ok) {
        throw new Error(text(aiData.error) || "Lesson generation failed");
      }
      rawText = text(aiData.text);
      const generated = parseModelJson(rawText);
      const artifact = normalizeGuidedWritingArtifact({
        ...baseArtifact(session, kind),
        ...generated,
      });
      validateArtifact(artifact, session, kind, vocabularyCandidates);
      console.info(JSON.stringify({
        event: "course_artifact_ready",
        session_id: text(session.id),
        kind,
        provider,
        attempt,
      }));
      return artifact;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      console.warn(JSON.stringify({
        event: "course_artifact_attempt_failed",
        session_id: text(session.id),
        kind,
        provider,
        attempt,
        error_type: lastError.name,
      }));
      if (attempt === MAX_GENERATION_ATTEMPTS) break;
      // Hand the exact problem back to the same model so it can repair its
      // own output, instead of the caller silently retrying blind.
      messages.push({ role: "assistant", content: rawText || "{}" });
      messages.push({
        role: "user",
        content: `That JSON was rejected: ${lastError.message}. Return corrected JSON only, following the exact schema from the first message. Do not add commentary.`,
      });
    }
  }
  throw lastError ?? new Error("Lesson generation failed");
}

async function attachListeningAudio(
  sessionId: string,
  artifact: Json,
): Promise<Json> {
  // Course stores sentence-level PCM on the device and mirrors those exact
  // clips through GeminiLiveAudioService. A marker keeps the existing course
  // readiness contract compatible while ensuring this function never pays to
  // generate a non-seekable full-track WAV without word timings.
  return {
    ...artifact,
    audioPath: `pcm-deck-v1:${idPart(sessionId)}`,
    audioMode: "pcm_deck_v1",
    musicBackgroundUrl:
      "asset:assets/images/listening/the_garden_key_background.png",
  };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return response({ error: "POST required" }, 405);

  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return response({ error: "Authentication required" }, 401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: callerData, error: callerError } = await caller.auth.getUser();
  if (callerError || !callerData.user) {
    return response({ error: "Invalid session" }, 401);
  }

  const userId = callerData.user.id;
  const admin = createClient(supabaseUrl, serviceRoleKey);
  // The development Course harness can constrain this single foreground
  // preparation request to one skill. Production callers omit the field and
  // keep the normal queue behavior. This is a filter only; it never creates,
  // rewrites, or retries a row.
  let harnessSkill = "";
  let vocabularyCandidates: VocabularyCandidate[] = [];
  try {
    const body = await request.json() as Json;
    const requested = text(body.harness_skill).replace('-', '_');
    if (["speaking", "vocabulary", "reading", "listening", "writing"].includes(requested)) {
      harnessSkill = requested;
    }
    if (Array.isArray(body.vocabulary_candidates)) {
      vocabularyCandidates = body.vocabulary_candidates
        .map((raw) => {
          const candidate = object(raw);
          const role = text(candidate.role);
          if (!text(candidate.id) || !text(candidate.fr) || !text(candidate.en) ||
              !text(candidate.phonetic) || (role !== "review" && role !== "new")) {
            return null;
          }
          return {
            ...candidate,
            id: text(candidate.id),
            fr: text(candidate.fr),
            en: text(candidate.en),
            phonetic: text(candidate.phonetic),
            role: role as "review" | "new",
          } as VocabularyCandidate;
        })
        .filter((candidate): candidate is VocabularyCandidate => candidate != null)
        .slice(0, 24);
    }
  } catch {
    // An empty body is the normal production request.
  }
  const staleBefore = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  const { error: recoveryError } = await admin
    .from("adaptive_course_sessions")
    .update({ generation_status: "queued", generation_error: "Recovered interrupted preparation" })
    .eq("user_id", userId)
    .eq("generation_status", "generating")
    .lt("updated_at", staleBefore);
  if (recoveryError) {
    console.error(JSON.stringify({
      event: "course_preparation_recovery_failed",
      userId,
      error: recoveryError.message,
    }));
    return response({ error: recoveryError.message }, 500);
  }

  // Course growth has exactly one rule that matters here: never run two
  // generations at once. There is no cap on how many lessons may sit ready
  // ahead of the learner — the app keeps a small lookahead buffer topped up
  // (see adaptiveCourseLookahead in lib/data/database/adaptive_course_store.dart)
  // and simply queues one more row whenever it wants one; this endpoint's only
  // job is to pick up the oldest queued/failed row and generate it, forever,
  // unlimited. This must only ever see real AI-generated lessons (sequence
  // 11+) — Unit 2 (6-10) is fixed, authored, permanent content for every
  // learner, never part of this accounting.
  // A plan can end up orphaned "active" on the server when a device's local
  // retirement of its own previous plan never reaches a remote-only plan it
  // has no record of (a reinstall wiping local state, or a second device).
  // Every query below has no other reason to know about plan_id, so without
  // this an orphaned plan's stuck-"generating" row could block this
  // endpoint from ever touching the learner's actual current plan, or this
  // endpoint could just as happily generate real content the learner will
  // never see as content for the plan they are actually on. Scope
  // everything below to the single newest active plan only.
  const { data: activePlans, error: activePlanError } = await admin
    .from("adaptive_course_plans")
    .select("id")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1);
  if (activePlanError) return response({ error: activePlanError.message }, 500);
  const activePlanId = activePlans?.[0]?.id as string | undefined;
  if (!activePlanId) {
    console.info(JSON.stringify({
      event: "course_lesson_preparation_noop",
      userId,
      reason: "no_active_plan",
    }));
    return response({ processed: false, remaining: 0 });
  }

  let activePersonalizedQuery = admin
    .from("adaptive_course_sessions")
    .select("id, sequence, status, generation_status, updated_at, primary_skill, title, artifact_json")
    .eq("user_id", userId)
    .eq("plan_id", activePlanId)
    .gt("sequence", AUTHORED_SEQUENCE_CEILING)
    .in("status", ["planned", "active"])
    .is("deleted_at", null)
    .order("sequence", { ascending: true });
  const { data: activePersonalized, error: reserveError } = await activePersonalizedQuery;
  if (reserveError) return response({ error: reserveError.message }, 500);

  // REMOVED: this used to reset a specific, narrowly-detected historical
  // guided-speaking defect (needsGuidedSpeakingRefresh, still defined
  // above for reference) back to queued/no-artifact so it would
  // regenerate. Explicit product decision: a ready lesson with a real
  // artifact is never touched again, through any path, for any reason --
  // not even a targeted repair. The database's own
  // prevent_generation_status_regression trigger now rejects this
  // unconditionally regardless of what code attempts it, so leaving this
  // block in would only silently no-op against the trigger while lying
  // to this function's own in-memory view of the row. If a specific
  // artifact genuinely needs manual repair in the future, that must be a
  // deliberate, explicit, out-of-band operation, never a routine
  // background code path that runs on every Course open.

  const generating = (activePersonalized ?? []).some((row) =>
    text(row.generation_status) === "generating"
  );
  if (generating) {
    // Visibility into every "did nothing" outcome, not just failures: this
    // is the only way to tell "another generation is already running" apart
    // from a lesson that is quietly stuck for longer than it should.
    console.info(JSON.stringify({
      event: "course_lesson_preparation_noop",
      userId,
      reason: "already_generating",
    }));
    return response({ processed: false, remaining: 0 });
  }

  let candidatesQuery = admin
    .from("adaptive_course_sessions")
    .select("*")
    .eq("user_id", userId)
    .eq("plan_id", activePlanId)
    .gt("sequence", AUTHORED_SEQUENCE_CEILING)
    .in("generation_status", ["queued", "failed"])
    .in("status", ["planned", "active"])
    .is("deleted_at", null)
    .order("sequence", { ascending: true })
    .limit(1);
  if (harnessSkill) candidatesQuery = candidatesQuery.eq("primary_skill", harnessSkill);
  const { data: candidates, error: findError } = await candidatesQuery;
  if (findError) return response({ error: findError.message }, 500);
  const candidate = candidates?.[0] as Json | undefined;
  if (!candidate) {
    console.info(JSON.stringify({
      event: "course_lesson_preparation_noop",
      userId,
      reason: "nothing_queued",
    }));
    return response({ processed: false, remaining: 0 });
  }

  const sessionId = text(candidate.id);
  const attempts = Number(candidate.generation_attempts ?? 0);
  const { data: claimed, error: claimError } = await admin
    .from("adaptive_course_sessions")
    .update({
      generation_status: "generating",
      generation_attempts: attempts + 1,
      generation_error: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", sessionId)
    .eq("user_id", userId)
    .in("generation_status", ["queued", "failed"])
    .select("*")
    .maybeSingle();
  if (claimError) return response({ error: claimError.message }, 500);
  if (!claimed) {
    console.info(JSON.stringify({
      event: "course_lesson_preparation_noop",
      userId,
      sessionId,
      reason: "claim_conflict",
    }));
    return response({ processed: false, conflict: true }, 409);
  }

  const kind = artifactKind(text(claimed.primary_skill));
  console.info(JSON.stringify({
    event: "course_lesson_preparation_started",
    userId,
    sessionId,
    sequence: claimed.sequence,
    kind,
    harnessSkill: harnessSkill || null,
    attempt: attempts + 1,
  }));
  try {
    // Unit 2's listening lesson is authored on the device, not generated:
    // its text (passage + quiz) is already pushed here as the queued row's
    // artifact. When that fixed text is already present and valid, skip the
    // lesson-authoring model entirely and go straight to rendering audio for
    // it — this call must never re-author text that is already final.
    const preauthoredText = kind === "listening"
      ? (() => {
        const existing = claimed.artifact_json;
        if (!existing || typeof existing !== "object" || Array.isArray(existing)) {
          return null;
        }
        try {
          validateStory(existing as Json, text(claimed.level) || "A1", Number(claimed.sequence ?? 0));
          return existing as Json;
        } catch {
          return null;
        }
      })()
      : null;
    let artifact = preauthoredText ?? await generateArtifact(
      supabaseUrl,
      serviceRoleKey,
      claimed as Json,
      kind,
      vocabularyCandidates,
    );
    if (kind === "listening") {
      // Persist the finished text the moment it exists, before the slower
      // audio render/upload/verify round trip. The row's generation_status
      // stays "generating" (still correctly unclaimable), but any concurrent
      // reader of this exact row — the client's own background sync pull —
      // can now see the passage and quiz while audio is still cooking,
      // instead of the whole lesson being invisible until every step
      // finishes. This never widens what counts as "ready" for Practice.
      if (!preauthoredText) {
        const { error: textOnlyError } = await admin
          .from("adaptive_course_sessions")
          .update({ artifact_json: artifact, updated_at: new Date().toISOString() })
          .eq("id", sessionId)
          .eq("user_id", userId);
        if (textOnlyError) throw new Error(textOnlyError.message);
      }
      artifact = await attachListeningAudio(sessionId, artifact);
    }
    const { error: saveError } = await admin
      .from("adaptive_course_sessions")
      .update({
        artifact_kind: kind,
        artifact_json: artifact,
        generation_status: "ready",
        generation_error: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", sessionId)
      .eq("user_id", userId);
    if (saveError) throw new Error(saveError.message);

    let remainingQuery = admin
      .from("adaptive_course_sessions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("plan_id", activePlanId)
      .gt("sequence", AUTHORED_SEQUENCE_CEILING)
      .in("generation_status", ["queued", "failed"])
      .in("status", ["planned", "active"])
      .is("deleted_at", null);
    if (harnessSkill) remainingQuery = remainingQuery.eq("primary_skill", harnessSkill);
    const { count } = await remainingQuery;
    console.info(JSON.stringify({
      event: "course_lesson_preparation_succeeded",
      userId,
      sessionId,
      sequence: claimed.sequence,
      kind,
      harnessSkill: harnessSkill || null,
      remaining: count ?? 0,
    }));
    return response({ processed: true, sessionId, kind, remaining: count ?? 0 });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const { error: persistError } = await admin
      .from("adaptive_course_sessions")
      .update({
        generation_status: "failed",
        generation_error: message.slice(0, 500),
        updated_at: new Date().toISOString(),
      })
      .eq("id", sessionId)
      .eq("user_id", userId);
    console.error(JSON.stringify({
      event: "course_lesson_preparation_failed",
      userId,
      sessionId,
      sequence: claimed.sequence,
      kind,
      attempt: attempts + 1,
      error: message.slice(0, 500),
      persistError: persistError?.message ?? null,
    }));
    return response({ error: message, sessionId, retryable: true }, 502);
  }
});
