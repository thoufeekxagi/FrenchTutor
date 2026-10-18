import { describe, expect, it } from "vitest";
import {
  normalizeFrench,
  savedPhraseRanges,
  selectTokenRange,
  tokenizeCaption,
  wordAtCaptionProgress,
} from "../lib/wordSelection";

describe("French caption tokenization", () => {
  it("preserves every character and offsets while isolating punctuation", () => {
    const text = "« Bonjour,  Québec ! »";
    const tokens = tokenizeCaption(text);
    expect(tokens.map((t) => t.text).join("")).toBe(text);
    for (const token of tokens)
      expect(text.slice(token.start, token.end)).toBe(token.text);
    expect(tokens.filter((t) => t.kind === "word").map((t) => t.text)).toEqual([
      "Bonjour",
      "Québec",
    ]);
    expect(tokens.find((t) => t.text === ",")?.kind).toBe("punctuation");
  });
  it("keeps French apostrophes and compound hyphens in word buttons", () => {
    const tokens = tokenizeCaption(
      "Aujourd’hui, qu'est-ce qu’on fait à Sainte‑Anne ?",
    );
    expect(tokens.filter((t) => t.kind === "word").map((t) => t.text)).toEqual([
      "Aujourd’hui",
      "qu'est-ce",
      "qu’on",
      "fait",
      "à",
      "Sainte‑Anne",
    ]);
  });
  it("preserves decomposed accents and emoji without offset loss", () => {
    const text = "👋 E\u0301coute… déjà !";
    const tokens = tokenizeCaption(text);
    expect(tokens.map((t) => t.text).join("")).toBe(text);
    expect(tokens.filter((t) => t.kind === "word").map((t) => t.text)).toEqual([
      "E\u0301coute",
      "déjà",
    ]);
  });
  it("does not attach quote punctuation or dangling hyphens to words", () => {
    expect(
      tokenizeCaption("'bonjour' - oui-")
        .filter((t) => t.kind === "word")
        .map((t) => t.text),
    ).toEqual(["bonjour", "oui"]);
  });
});

describe("spoken word read-along timing", () => {
  it("advances in syllable-weighted steps and ignores punctuation", () => {
    const tokens = tokenizeCaption("Je comprends, maintenant !");
    const words = tokens.filter((token) => token.kind === "word");
    expect(wordAtCaptionProgress(tokens, 0)).toBe(words[0]!.index);
    expect(wordAtCaptionProgress(tokens, 0.2)).toBe(words[1]!.index);
    expect(wordAtCaptionProgress(tokens, 0.75)).toBe(words[2]!.index);
    expect(wordAtCaptionProgress(tokens, 1)).toBe(words[2]!.index);
  });
  it("returns no word for empty or punctuation-only captions", () => {
    expect(wordAtCaptionProgress([], 0.5)).toBeUndefined();
    expect(wordAtCaptionProgress(tokenizeCaption("… !"), 0.5)).toBeUndefined();
    expect(wordAtCaptionProgress(tokenizeCaption("bonjour"), Number.NaN)).toBeUndefined();
  });
});

describe("occurrence and range selection", () => {
  it("selects only the clicked repeated word occurrence", () => {
    const tokens = tokenizeCaption("Oui, oui, oui !");
    const words = tokens.filter((t) => t.kind === "word");
    expect(selectTokenRange(tokens, words[1]!.index, words[1]!.index)).toEqual({
      start: 3,
      end: 3,
      text: "oui",
    });
  });
  it("retains internal punctuation and whitespace but trims outside punctuation", () => {
    const tokens = tokenizeCaption("« Oui,  merci ! »");
    expect(selectTokenRange(tokens, 0, tokens.length - 1)).toEqual({
      start: 2,
      end: 5,
      text: "Oui,  merci",
    });
    expect(selectTokenRange(tokens, tokens.length - 1, 0)).toEqual(
      selectTokenRange(tokens, 0, tokens.length - 1),
    );
  });
  it("rejects punctuation-only and invalid selections", () => {
    const tokens = tokenizeCaption("Bonjour !");
    expect(selectTokenRange(tokens, 1, 2)).toBeUndefined();
    for (const value of [-1, 0.5, Infinity, NaN, 20])
      expect(selectTokenRange(tokens, value, 0)).toBeUndefined();
    expect(selectTokenRange([], 0, 0)).toBeUndefined();
  });
});

describe("saved phrase highlighting", () => {
  it("normalizes case, canonical accents, apostrophes and nonbreaking hyphens", () => {
    expect(normalizeFrench("E\u0301COUTE Aujourd’hui Sainte‑Anne")).toBe(
      "écoute aujourd'hui sainte-anne",
    );
    const tokens = tokenizeCaption("J’aime le Québec et j’aime le Québec.");
    const ranges = savedPhraseRanges(tokens, ["J'AIME LE QUÉBEC"]);
    expect(
      ranges.map(
        (range) => selectTokenRange(tokens, range.start, range.end)?.text,
      ),
    ).toEqual(["J’aime le Québec", "j’aime le Québec"]);
  });
  it("matches whole words and contiguous phrases only", () => {
    const tokens = tokenizeCaption("parler français et parler un peu français");
    expect(savedPhraseRanges(tokens, ["parle", "parler français"])).toEqual([
      { start: 0, end: 2 },
    ]);
  });
  it("does not erase meaningful French accent distinctions", () => {
    expect(savedPhraseRanges(tokenizeCaption("ou où"), ["où"])).toEqual([
      { start: 2, end: 2 },
    ]);
  });
  it("deduplicates repeated saved phrases and supports overlapping ranges", () => {
    const tokens = tokenizeCaption("un peu chaque jour");
    expect(
      savedPhraseRanges(tokens, ["un peu", "UN PEU!", "peu chaque"]),
    ).toEqual([
      { start: 0, end: 2 },
      { start: 2, end: 4 },
    ]);
  });
  it("ignores empty and punctuation-only saved entries", () => {
    expect(
      savedPhraseRanges(tokenizeCaption("Salut !"), ["", "!", "  "]),
    ).toEqual([]);
  });
});
