import { pickFrenchTrack, type CaptionTrack } from "./youtubeCaptions";

export type GateReason = "has_french_captions" | "not_french" | "ok_french" | "unknown";
export interface GateDecision {
  allowed: boolean;
  reason: GateReason;
  message: string;
}
export interface GateInput {
  /** Caption tracks from YouTube; undefined for other sites or when the lookup failed. */
  tracks?: CaptionTrack[];
  title?: string;
  description?: string;
  htmlLang?: string;
  /** Result of a language detector on the title and description, if one ran. */
  textLanguage?: { language: string; reliable: boolean };
}

const FRENCH_WORDS = new Set("le la les de des du un une et est que qui dans pour avec sur pas je tu il elle nous vous ils elles ce cette mon ma mes au aux en ne se sa son leur très bonjour français".split(" "));
const ENGLISH_WORDS = new Set("the and is are of to in you for with on not it this that your we they have from by at as or be".split(" "));

/** Cheap fallback when no detector is available. */
export function guessTextLanguage(text: string): { language: string; reliable: boolean } {
  const words = text.toLowerCase().normalize("NFC").match(/[a-zàâçéèêëîïôûùüÿœ']+/g) ?? [];
  let fr = 0;
  let en = 0;
  for (const word of words) {
    if (FRENCH_WORDS.has(word)) fr++;
    if (ENGLISH_WORDS.has(word)) en++;
  }
  if (words.length < 6 || Math.abs(fr - en) < 3) return { language: "und", reliable: false };
  return fr > en ? { language: "fr", reliable: true } : { language: "en", reliable: true };
}

export function languageName(code: string): string {
  try {
    return new Intl.DisplayNames(["en"], { type: "language" }).of(code.split("-")[0]!) ?? code;
  } catch {
    return code;
  }
}

const isFrench = (code?: string) => /^fr(?:[-_]|$)/i.test(code ?? "");

/**
 * Live captions cost money, so they are only for French speech that has no captions.
 * Block only on positive evidence; stay open when the language cannot be told.
 */
export function decideLiveEligibility(input: GateInput): GateDecision {
  const tracks = input.tracks ?? [];
  if (pickFrenchTrack(tracks))
    return { allowed: false, reason: "has_french_captions", message: "This video already has French captions. They appear under the video automatically." };

  const spoken = tracks.find((track) => track.kind === "asr" && !isFrench(track.languageCode));
  if (spoken)
    return { allowed: false, reason: "not_french", message: `YouTube detects ${languageName(spoken.languageCode)} speech in this video, not French. Live captions are for French videos only.` };

  const text = input.textLanguage ?? guessTextLanguage(`${input.title ?? ""} ${input.description ?? ""}`);
  if (tracks.length && text.reliable && !isFrench(text.language))
    return { allowed: false, reason: "not_french", message: `This video looks like ${languageName(text.language)}, not French. Live captions are for French videos only.` };

  if ((text.reliable && isFrench(text.language)) || isFrench(input.htmlLang))
    return { allowed: true, reason: "ok_french", message: "" };
  return { allowed: true, reason: "unknown", message: "We could not confirm this video is in French. Live captions only work for French speech." };
}
