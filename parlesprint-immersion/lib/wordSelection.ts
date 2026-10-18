/** Stable token indices identify occurrences, even when the same word repeats. */
export interface CaptionToken {
  index: number;
  kind: "word" | "space" | "punctuation";
  text: string;
  /** UTF-16 offsets suitable for String.slice and DOM text offsets. End is exclusive. */
  start: number;
  end: number;
}
/** Inclusive token indices. */
export interface TokenRange {
  start: number;
  end: number;
}
export interface PhraseSelection extends TokenRange {
  text: string;
}

// Apostrophes and hyphens connect words only when surrounded by letters/numbers.
const WORD =
  "[\\p{L}\\p{N}][\\p{L}\\p{M}\\p{N}]*(?:['’ʼ‐‑-][\\p{L}\\p{N}][\\p{L}\\p{M}\\p{N}]*)*";

export function tokenizeCaption(text: string): CaptionToken[] {
  const pattern = new RegExp(`${WORD}|\\s+|[^\\p{L}\\p{N}\\s]+`, "gu");
  return Array.from(text.matchAll(pattern), (match, index) => ({
    index,
    kind: /^\s+$/u.test(match[0])
      ? "space"
      : /^[\p{L}\p{N}]/u.test(match[0])
        ? "word"
        : "punctuation",
    text: match[0],
    start: match.index!,
    end: match.index! + match[0].length,
  }));
}

/** Estimate the word currently being spoken within one timed caption cue.
 * Cue-level subtitle tracks do not expose word timings, so syllable-weighted
 * progress gives a useful read-along highlight without pretending to be exact.
 */
export function wordAtCaptionProgress(
  tokens: readonly CaptionToken[],
  progress: number,
): number | undefined {
  if (!Number.isFinite(progress)) return undefined;
  const words = tokens.filter((token) => token.kind === "word");
  if (!words.length) return undefined;
  if (progress <= 0) return words[0]!.index;
  if (progress >= 1) return words.at(-1)!.index;
  const weights = words.map((word) => {
    const normalized = word.text
      .normalize("NFD")
      .replace(/\p{M}/gu, "")
      .toLocaleLowerCase("fr");
    return Math.max(1, normalized.match(/[aeiouy]+/g)?.length ?? 0);
  });
  const total = weights.reduce((sum, weight) => sum + weight, 0);
  let target = progress * total;
  for (let index = 0; index < words.length; index++) {
    target -= weights[index]!;
    if (target < 0) return words[index]!.index;
  }
  return words.at(-1)!.index;
}

/** Accents remain meaningful: ou and où must not match. */
export function normalizeFrench(text: string): string {
  return text
    .normalize("NFC")
    .toLocaleLowerCase("fr")
    .replace(/[’ʼ]/g, "'")
    .replace(/[‐‑]/g, "-");
}

/** Select words by occurrence, preserving exact punctuation/spacing inside the phrase. */
export function selectTokenRange(
  tokens: readonly CaptionToken[],
  first: number,
  last: number,
): PhraseSelection | undefined {
  if (
    !Number.isInteger(first) ||
    !Number.isInteger(last) ||
    first < 0 ||
    last < 0 ||
    first >= tokens.length ||
    last >= tokens.length
  )
    return undefined;
  let start = Math.min(first, last);
  let end = Math.max(first, last);
  while (start <= end && tokens[start]?.kind !== "word") start++;
  while (end >= start && tokens[end]?.kind !== "word") end--;
  if (start > end) return undefined;
  return {
    start,
    end,
    text: tokens
      .slice(start, end + 1)
      .map((token) => token.text)
      .join(""),
  };
}

/** Match contiguous words; return every occurrence and deduplicate identical ranges. */
export function savedPhraseRanges(
  tokens: readonly CaptionToken[],
  savedPhrases: readonly string[],
): TokenRange[] {
  const words = tokens.filter((token) => token.kind === "word");
  const normalized = words.map((token) => normalizeFrench(token.text));
  const ranges = new Map<string, TokenRange>();
  for (const phrase of savedPhrases) {
    const wanted = tokenizeCaption(phrase)
      .filter((token) => token.kind === "word")
      .map((token) => normalizeFrench(token.text));
    if (!wanted.length || wanted.length > words.length) continue;
    for (let start = 0; start <= words.length - wanted.length; start++) {
      if (!wanted.every((word, index) => normalized[start + index] === word))
        continue;
      const range = {
        start: words[start]!.index,
        end: words[start + wanted.length - 1]!.index,
      };
      ranges.set(`${range.start}:${range.end}`, range);
    }
  }
  return [...ranges.values()].sort(
    (a, b) => a.start - b.start || a.end - b.end,
  );
}
