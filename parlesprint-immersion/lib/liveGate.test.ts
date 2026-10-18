import { describe, expect, it } from "vitest";
import { decideLiveEligibility, guessTextLanguage } from "./liveGate";

const track = (languageCode: string, kind?: string) => ({ baseUrl: "https://www.youtube.com/api/timedtext", languageCode, ...(kind ? { kind } : {}) });

describe("live caption eligibility", () => {
  it("blocks live captions when French captions already exist", () => {
    const d = decideLiveEligibility({ tracks: [track("fr", "asr")] });
    expect(d).toMatchObject({ allowed: false, reason: "has_french_captions" });
    expect(decideLiveEligibility({ tracks: [track("en"), track("fr-CA")] }).reason).toBe("has_french_captions");
  });
  it("blocks videos whose automatic captions are another language", () => {
    const d = decideLiveEligibility({ tracks: [track("en"), track("en", "asr"), track("de-DE")] });
    expect(d).toMatchObject({ allowed: false, reason: "not_french" });
    expect(d.message).toContain("English");
    expect(decideLiveEligibility({ tracks: [track("ko", "asr")] }).message).toContain("Korean");
  });
  it("blocks manual-only non-French tracks when the title is clearly English", () => {
    const d = decideLiveEligibility({ tracks: [track("en"), track("de")], title: "Me at the zoo", description: "The first video on YouTube. It is a short clip of the elephants and they are very big." });
    expect(d).toMatchObject({ allowed: false, reason: "not_french" });
  });
  it("allows a French video that only has English subtitles", () => {
    const d = decideLiveEligibility({ tracks: [track("en")], title: "Bonjour, nous allons apprendre le français avec des amis", description: "Une vidéo pour les débutants qui est très simple et pour tous." });
    expect(d).toMatchObject({ allowed: true, reason: "ok_french" });
  });
  it("allows videos with no tracks and an unclear language, with a hint", () => {
    const d = decideLiveEligibility({ tracks: [], title: "Vlog", description: "" });
    expect(d).toMatchObject({ allowed: true, reason: "unknown" });
    expect(d.message).toContain("could not confirm");
  });
  it("allows other sites declared as French and does not block on English text without tracks", () => {
    expect(decideLiveEligibility({ htmlLang: "fr-CA" })).toMatchObject({ allowed: true, reason: "ok_french" });
    expect(decideLiveEligibility({ tracks: [], title: "French listening practice with the family and you", description: "Watch this video for your learning and for fun with the team." }).allowed).toBe(true);
  });
  it("guesses language conservatively", () => {
    expect(guessTextLanguage("Je voudrais un café pour ce matin avec des amis et nous").language).toBe("fr");
    expect(guessTextLanguage("Go").reliable).toBe(false);
  });
});
