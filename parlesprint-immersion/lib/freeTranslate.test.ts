import { describe, expect, it } from "vitest";
import { parseTranslation } from "./freeTranslate";

describe("parseTranslation", () => {
  it("joins segments and keeps dictionary alternatives", () => {
    const data = [[["I ", "je"], ["am", "suis"]], [["pronoun", ["I", "me"], []], ["noun", [], []]], "fr"];
    expect(parseTranslation("je suis", data)).toEqual({
      text: "je suis",
      translation: "I am",
      alternatives: [{ pos: "pronoun", terms: ["I", "me"] }],
    });
  });
  it("rejects malformed payloads", () => {
    expect(parseTranslation("x", null)).toBeUndefined();
    expect(parseTranslation("x", [[]])).toBeUndefined();
  });
});
