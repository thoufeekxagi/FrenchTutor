import { SUBTITLE_LIMITS, subtitlePlainText, type Cue } from "./captions";

export interface CaptionTrack {
  baseUrl: string;
  languageCode: string;
  kind?: string;
}

const MAX_WORDS = 12;
const MAX_SECONDS = 6;
const GAP_SECONDS = 0.9;
const TAIL_SECONDS = 0.7;

interface Word {
  start: number;
  text: string;
}

function attr(attrs: string, name: string): number | undefined {
  const match = new RegExp(`(?:^|\\s)${name}="(-?\\d+)"`).exec(attrs);
  return match ? Number(match[1]) : undefined;
}

/** Group word-level timing into readable caption lines. */
function groupWords(words: Word[]): Cue[] {
  const cues: Cue[] = [];
  let line: Word[] = [];
  const flush = (nextStart?: number) => {
    if (!line.length) return;
    const start = line[0]!.start;
    const last = line[line.length - 1]!;
    const natural = last.start + TAIL_SECONDS;
    const end = Math.max(
      start + 0.4,
      nextStart !== undefined ? Math.min(natural + 1, Math.max(natural, nextStart)) : natural,
    );
    const text = line.map((word) => word.text).join(" ").replace(/\s+([,.;:!?])/g, "$1").trim();
    if (text) cues.push({ id: `yt-${cues.length}`, start, end, text });
    line = [];
  };
  for (const word of words) {
    const previous = line[line.length - 1];
    const endsSentence = previous && /[.!?…]$/.test(previous.text);
    if (
      previous &&
      (word.start - previous.start > GAP_SECONDS + 0.6 ||
        line.length >= MAX_WORDS ||
        word.start - line[0]!.start > MAX_SECONDS ||
        (endsSentence && line.length >= 3))
    )
      flush(word.start);
    line.push(word);
  }
  flush();
  return cues;
}

/** Parse YouTube timed text (srv3 word timing, or plain line timing). */
export function parseTimedText(xml: string): Cue[] {
  const words: Word[] = [];
  const lines: Cue[] = [];
  const paragraph = /<p\b([^>]*)>([\s\S]*?)<\/p>/g;
  for (let match = paragraph.exec(xml); match; match = paragraph.exec(xml)) {
    const start = attr(match[1] ?? "", "t");
    const duration = attr(match[1] ?? "", "d");
    if (start === undefined) continue;
    const body = match[2] ?? "";
    const pieces = [...body.matchAll(/<s\b([^>]*)>([\s\S]*?)<\/s>/g)];
    if (pieces.length) {
      for (const piece of pieces) {
        const text = subtitlePlainText(piece[2] ?? "");
        if (!text) continue;
        const offset = attr(piece[1] ?? "", "t") ?? 0;
        words.push({ start: (start + offset) / 1000, text });
      }
    } else {
      const text = subtitlePlainText(body.replace(/<br\s*\/?>/gi, " "));
      if (text && duration && duration > 0)
        lines.push({
          id: `yt-${lines.length}`,
          start: start / 1000,
          end: (start + duration) / 1000,
          text,
        });
    }
  }
  const raw = words.length ? groupWords(words.sort((a, b) => a.start - b.start)) : lines;
  return raw
    .filter((cue) => cue.text.length <= SUBTITLE_LIMITS.textLength)
    .sort((a, b) => a.start - b.start)
    .slice(0, SUBTITLE_LIMITS.cues);
}

/** Prefer a human-written French track over automatic speech recognition. */
export function pickFrenchTrack(tracks: readonly CaptionTrack[]): CaptionTrack | undefined {
  const french = tracks.filter((track) => /^fr(?:[-_]|$)/i.test(track.languageCode));
  return french.find((track) => track.kind !== "asr") ?? french[0];
}

async function playerCaptionTracks(videoId: string): Promise<CaptionTrack[]> {
  // The ANDROID client returns caption URLs that serve text without a page-bound token.
  const response = await fetch("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      context: { client: { clientName: "ANDROID", clientVersion: "20.10.38", androidSdkVersion: 30, hl: "en" } },
      videoId,
    }),
    signal: AbortSignal.timeout(12000),
  });
  if (!response.ok) throw Error(`player ${response.status}`);
  const data = await response.json();
  const tracks = data?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
  return Array.isArray(tracks)
    ? tracks.filter(
        (track: CaptionTrack) =>
          typeof track?.baseUrl === "string" && typeof track?.languageCode === "string",
      )
    : [];
}

/** Returns French caption cues for a YouTube video, or [] when it has no French track. */
export async function fetchYoutubeCues(videoId: string): Promise<Cue[]> {
  if (!/^[\w-]{6,20}$/.test(videoId)) return [];
  const track = pickFrenchTrack(await playerCaptionTracks(videoId));
  if (!track) return [];
  const url = new URL(track.baseUrl);
  if (!/(^|\.)youtube\.com$/.test(url.hostname)) return [];
  const response = await fetch(url.href, { signal: AbortSignal.timeout(12000) });
  if (!response.ok) throw Error(`captions ${response.status}`);
  const text = await response.text();
  if (new TextEncoder().encode(text).length > SUBTITLE_LIMITS.bytes * 4) return [];
  return parseTimedText(text);
}
