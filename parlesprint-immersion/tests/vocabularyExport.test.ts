import { describe, expect, it } from "vitest";
import { matchesVocabulary, vocabularyCsv } from "../lib/vocabularyExport";
import type { Word } from "../lib/types";
const word = (
  text: string,
  sentence = "Contexte.",
  meaning = "Meaning",
): Word => ({
  id: text,
  text,
  sentence,
  savedAt: 1,
  level: "A1",
  explanation: { meaning, grammar: "", example: "", exampleTranslation: "" },
});
describe("notebook search", () => {
  it("finds French accents, decomposed accents, ligatures, meaning, and context", () => {
    const entry = word(
      "À bientôt, cœur",
      "Le café est au Québec.",
      "See you soon",
    );
    for (const query of [
      "a bientot",
      "BIENTÔT",
      "coeur",
      "quebec",
      "soon",
      "cafe see",
    ])
      expect(matchesVocabulary(entry, query), query).toBe(true);
    expect(matchesVocabulary(entry, "demain")).toBe(false);
    expect(matchesVocabulary(entry, "  ")).toBe(true);
    expect(
      matchesVocabulary({ ...entry, explanation: undefined }, "soon"),
    ).toBe(false);
  });
});
describe("Anki CSV export", () => {
  it("declares columns without importing the header as a vocabulary card", () => {
    expect(vocabularyCsv([])).toBe(
      "#separator:Comma\r\n#html:false\r\n#columns:Front,Back,Context\r\n",
    );
    expect(
      vocabularyCsv([{ ...word("été"), explanation: undefined }]),
    ).toContain('"été","","Contexte."\r\n');
  });
  it("quotes commas, quotes, newlines, and French accents losslessly", () => {
    expect(
      vocabularyCsv([
        word('il dit "été"', "Ligne 1, ici.\nLigne 2.", "summer, season"),
      ]),
    ).toContain(
      '"il dit ""été""","summer, season","Ligne 1, ici.\nLigne 2."\r\n',
    );
  });
  it("neutralizes formulas in every field, including whitespace and control prefixes", () => {
    for (const value of [
      "=1+1",
      "+SUM(A1)",
      "-2+3",
      "@SUM(1)",
      "  =cmd()",
      "\t=1",
      "\r=1",
      "\n=1",
      "\uFEFF=1",
    ]) {
      const row = vocabularyCsv([word(value, value, value)]).split(
        "#columns:Front,Back,Context\r\n",
      )[1]!;
      expect(row.startsWith(`"'${value}`), JSON.stringify(value)).toBe(true);
      expect(row.split(`"'${value}`).length).toBe(4);
    }
  });
  it("removes NUL and leaves ordinary punctuation and HTML as literal text", () => {
    expect(
      vocabularyCsv([word("bon\0jour", "<b>contexte</b>", "C'est bien !")]),
    ).toContain('"bonjour","C\'est bien !","<b>contexte</b>"');
  });
});
