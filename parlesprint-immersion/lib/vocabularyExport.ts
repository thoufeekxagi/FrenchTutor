import type { Word } from "./types";

/** Search the notebook without making French accents a keyboard requirement. */
export function normalizeSearch(value: string): string {
  return value
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase("fr")
    .replace(/œ/g, "oe")
    .replace(/æ/g, "ae");
}
export function matchesVocabulary(word: Word, query: string): boolean {
  const terms = normalizeSearch(query).trim().split(/\s+/).filter(Boolean);
  const content = normalizeSearch(
    [word.text, word.sentence, word.explanation?.meaning ?? ""].join(" "),
  );
  return terms.every((term) => content.includes(term));
}
function csvCell(value: string): string {
  const cleaned = value.replace(/\0/g, "");
  // CSV quoting does not stop spreadsheet formulas. Neutralize dangerous leading
  // characters even behind whitespace, while preserving the original text.
  const safe =
    /^[\s\uFEFF]*[=+\-@]/u.test(cleaned) || /^[\t\r\n]/.test(cleaned)
      ? `'${cleaned}`
      : cleaned;
  return `"${safe.replace(/"/g, '""')}"`;
}
/** Anki recognizes these import directives; no HTML is interpreted in cards. */
export function vocabularyCsv(words: readonly Word[]): string {
  return (
    [
      "#separator:Comma",
      "#html:false",
      "#columns:Front,Back,Context",
      ...words.map((word) =>
        [word.text, word.explanation?.meaning ?? "", word.sentence]
          .map(csvCell)
          .join(","),
      ),
    ].join("\r\n") + "\r\n"
  );
}
