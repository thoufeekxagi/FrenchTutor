import { describe, expect, it } from "vitest";
import { parseTimedText, pickFrenchTrack } from "./youtubeCaptions";

const asr = `<?xml version="1.0"?><timedtext format="3"><body>
<p t="280" d="7440" w="1"><s ac="0">bonjour</s><s t="720" ac="0"> les</s><s t="960" ac="0"> amis</s><s t="1600" ac="0"> et</s></p>
<p t="3869" d="3851" w="1" a="1">
</p>
<p t="3879" d="7241" w="1"><s ac="0">nouvel</s><s t="1281" ac="0"> épisode</s><s t="2281" ac="0"> aujourd&#39;hui</s></p>
</body></timedtext>`;

describe("parseTimedText", () => {
  it("builds ordered cues from word timing and decodes entities", () => {
    const cues = parseTimedText(asr);
    expect(cues.length).toBeGreaterThan(0);
    expect(cues[0]!.start).toBeCloseTo(0.28);
    expect(cues.map((cue) => cue.text).join(" ")).toBe("bonjour les amis et nouvel épisode aujourd'hui");
    for (let i = 1; i < cues.length; i++) expect(cues[i]!.start).toBeGreaterThanOrEqual(cues[i - 1]!.start);
    for (const cue of cues) expect(cue.end).toBeGreaterThan(cue.start);
  });

  it("reads plain line captions", () => {
    const cues = parseTimedText(`<timedtext><body><p t="1000" d="2000">Salut<br/>tout le monde</p></body></timedtext>`);
    expect(cues).toEqual([{ id: "yt-0", start: 1, end: 3, text: "Salut tout le monde" }]);
  });

  it("splits long speech into short lines", () => {
    const body = Array.from({ length: 40 }, (_, i) => `<s t="${i * 300}">mot${i}</s>`).join("");
    const cues = parseTimedText(`<p t="0" d="20000">${body}</p>`);
    expect(cues.length).toBeGreaterThan(2);
    for (const cue of cues) expect(cue.text.split(" ").length).toBeLessThanOrEqual(12);
  });

  it("returns nothing for empty input", () => {
    expect(parseTimedText("<timedtext></timedtext>")).toEqual([]);
  });
});

describe("pickFrenchTrack", () => {
  it("prefers human captions over automatic ones and ignores other languages", () => {
    const tracks = [
      { baseUrl: "a", languageCode: "en" },
      { baseUrl: "b", languageCode: "fr", kind: "asr" },
      { baseUrl: "c", languageCode: "fr-CA" },
    ];
    expect(pickFrenchTrack(tracks)?.baseUrl).toBe("c");
    expect(pickFrenchTrack([tracks[0]!])).toBeUndefined();
  });
});

import { spokenWordAt } from "./captions";
describe("word timing and sentence splitting", () => {
  it("finds the spoken word from per-word start times", () => {
    const [cue] = parseTimedText(asr);
    expect(spokenWordAt(cue, 0.1)).toBe(-1);
    expect(spokenWordAt(cue, 0.3)).toBe(0);
    expect(spokenWordAt(cue, 1.0)).toBe(1);
  });
  it("splits separate sentences in one caption but keeps wrapped ones whole", () => {
    const cues = parseTimedText(`<p t="0" d="4000">Patrick, c'est fini.
Ne m'appelle plus!</p><p t="5000" d="2000">Salut<br/>tout le monde</p>`);
    expect(cues.map((c) => c.text)).toEqual(["Patrick, c'est fini.", "Ne m'appelle plus!", "Salut tout le monde"]);
    expect(cues[0]!.end).toBeLessThanOrEqual(cues[1]!.start + 0.001);
  });
});
