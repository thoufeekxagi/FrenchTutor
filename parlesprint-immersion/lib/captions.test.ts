import { describe, expect, it } from "vitest";
import {
  activeCue,
  cuesFromTextTrack,
  estimatedLiveCueRange,
  parseSubtitles,
  subtitlePlainText,
} from "./captions";

describe("user subtitle ingestion", () => {
  it("parses BOM, CRLF, multiline SRT and sorts by time", () => {
    expect(
      parseSubtitles(
        "\uFEFF2\r\n00:00:04,000 --> 00:00:05,500\r\nSalut !\r\n\r\n1\r\n00:00:01,250 --> 00:00:03,000\r\n<i>Bonjour</i>\r\nles amis.",
      ),
    ).toEqual([
      { id: "cue-2", start: 1.25, end: 3, text: "Bonjour les amis." },
      { id: "cue-1", start: 4, end: 5.5, text: "Salut !" },
    ]);
  });
  it("parses VTT identifiers, settings and metadata without displaying markup", () => {
    const cues = parseSubtitles(
      "WEBVTT\nKind: captions\n\nNOTE private note\nignore this\n\nSTYLE\n::cue {color: red}\n\nspeaker\n00:01.000 --> 00:03.200 align:start\n<v Marie>J&#39;aime &amp; je comprends.</v>",
    );
    expect(cues[0]).toEqual({
      id: "cue-1",
      start: 1,
      end: 3.2,
      text: "J'aime & je comprends.",
    });
  });
  it("keeps untrusted markup inert text and handles Unicode entities", () => {
    expect(
      subtitlePlainText(
        "<img src=x onerror=alert(1)>Salut &#x1F44B; &lt;mot&gt;",
      ),
    ).toBe("Salut 👋 <mot>");
  });
  it.each([
    "",
    "not subtitles",
    "1\n00:61:00,000 --> 00:62:00,000\nHi",
    "1\n00:00:02,000 --> 00:00:01,000\nHi",
    "WEBVTT\n\nNOTE only metadata",
  ])("rejects invalid input: %s", (value) => {
    expect(() => parseSubtitles(value)).toThrow();
  });
  it("rejects oversized files and cues", () => {
    expect(() => parseSubtitles("a".repeat(2_000_001))).toThrow("2 MB");
    expect(() =>
      parseSubtitles(`1\n00:00:00,000 --> 00:00:01,000\n${"a".repeat(4001)}`),
    ).toThrow("4,000");
  });
  it("accepts multiple whitespace-only separators without inventing blocks", () => {
    const cues = parseSubtitles(
      "1\n00:00:00,000 --> 00:00:01,000\nBonjour\n\n \n\t\n2\n00:00:01,000 --> 00:00:02,000\nSalut",
    );
    expect(cues.map((cue) => cue.text)).toEqual(["Bonjour", "Salut"]);
  });
  it("rejects missing separators rather than displaying timestamps as French", () => {
    expect(() =>
      parseSubtitles(
        "1\n00:00:00,000 --> 00:00:01,000\nBonjour\n2\n00:00:01,000 --> 00:00:02,000\nSalut",
      ),
    ).toThrow("Missing blank line");
  });
  it("supports hours and exact millisecond boundaries", () => {
    expect(
      parseSubtitles("WEBVTT\n\n01:59:59.999 --> 02:00:00.001\nÀ demain")[0],
    ).toMatchObject({ start: 7199.999, end: 7200.001 });
  });
  it.each([
    "00:00:01.00",
    "00:00:60.000",
    "-00:01.000",
    "NaN",
    "00:00:01.000x",
  ])("rejects malformed timestamp %s", (value) => {
    expect(() => parseSubtitles(`${value} --> 02:00:00.000\nSalut`)).toThrow(
      "Invalid subtitle timestamp",
    );
  });
  it("limits UTF-8 bytes rather than characters", () => {
    expect(() => parseSubtitles("é".repeat(1_000_001))).toThrow("2 MB");
  });
  it("rejects imports beyond the cue count limit", () => {
    expect(() =>
      parseSubtitles(
        Array.from(
          { length: 20_001 },
          () => "00:00.000 --> 00:01.000\nSalut",
        ).join("\n\n"),
      ),
    ).toThrow("20,000");
  });
  it("drops invalid native track cues and cleans native markup", () => {
    const track = {
      cues: [
        { startTime: -1, endTime: 1, text: "negative" },
        { startTime: 0, endTime: Infinity, text: "infinite" },
        { startTime: 2, endTime: 2, text: "empty duration" },
        { startTime: 2, endTime: 3, text: "<v Marie>Bonjour</v>" },
      ],
    } as unknown as TextTrack;
    expect(cuesFromTextTrack(track)).toEqual([
      { id: "native-3", start: 2, end: 3, text: "Bonjour" },
    ]);
  });
});

describe("video timeline", () => {
  const cues = parseSubtitles(
    "1\n00:00:01,000 --> 00:00:04,000\nfirst\n\n2\n00:00:02,000 --> 00:00:03,000\nsecond",
  );
  it("uses seconds, handles gaps and exclusive ends", () => {
    expect(activeCue(cues, 0)).toBeUndefined();
    expect(activeCue(cues, 1)?.text).toBe("first");
    expect(activeCue(cues, 2)?.text).toBe("second");
    expect(activeCue(cues, 3)?.text).toBe("first");
    expect(activeCue(cues, 4)).toBeUndefined();
    expect(activeCue(cues, NaN)).toBeUndefined();
  });

  it("shows a short live caption immediately when the provider returns while paused", () => {
    const range = estimatedLiveCueRange(12, 1, 1)!;
    expect(range.start).toBeLessThanOrEqual(12);
    expect(range.end).toBeGreaterThan(12);
    expect(activeCue([{ id: "live", text: "Oui.", ...range }], 12)?.text).toBe("Oui.");
  });

  it("scales estimated live timing with 2x playback and clamps invalid inputs", () => {
    const normal = estimatedLiveCueRange(20, 8, 1)!;
    const fast = estimatedLiveCueRange(20, 8, 2)!;
    expect(fast.end - fast.start).toBeGreaterThan(normal.end - normal.start);
    expect(estimatedLiveCueRange(0, 0, 1)).toBeUndefined();
    expect(estimatedLiveCueRange(-1, 2, 1)).toBeUndefined();
  });
});
