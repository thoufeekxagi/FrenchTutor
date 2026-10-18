/** All cue times are seconds relative to the video timeline. */
export interface Cue {
  id: string;
  start: number;
  end: number;
  text: string;
  /** Start time (seconds) of each whitespace-separated word, when the source provides it. */
  wordStarts?: number[];
}

/** Index of the word being spoken at time t, or -1 without word timing. */
export function spokenWordAt(cue: Cue | undefined, time: number): number {
  const starts = cue?.wordStarts;
  if (!cue || !starts?.length || cue.text.split(/\s+/).length !== starts.length) return -1;
  let found = -1;
  for (let i = 0; i < starts.length; i++) if (starts[i]! <= time + 0.04) found = i;
  return found;
}

/** Approximate a provider's untimed text on the video timeline, including playback speed. */
export function estimatedLiveCueRange(
  at: number,
  wordCount: number,
  playbackRate = 1,
): { start: number; end: number } | undefined {
  if (!Number.isFinite(at) || at < 0 || !Number.isFinite(wordCount) || wordCount < 1) return;
  const rate = Number.isFinite(playbackRate) ? Math.max(0.25, Math.min(4, playbackRate)) : 1;
  const duration = Math.max(0.55, Math.min(10, (wordCount / 2.8) * rate));
  // The provider returns text after the audio arrives. A small tail keeps the
  // line visible when playback is paused as soon as it is recognized.
  const end = at + Math.min(0.3, 0.18 * rate);
  return { start: Math.max(0, end - duration), end };
}

export const SUBTITLE_LIMITS = {
  bytes: 2_000_000,
  cues: 20_000,
  textLength: 4_000,
} as const;

function timestamp(value: string): number {
  const match = /^(?:(\d{1,3}):)?(\d{2}):(\d{2})[.,](\d{3})$/.exec(value);
  if (!match || Number(match[2]) > 59 || Number(match[3]) > 59) {
    throw new Error(`Invalid subtitle timestamp: ${value}`);
  }
  return (
    Number(match[1] ?? 0) * 3600 +
    Number(match[2]) * 60 +
    Number(match[3]) +
    Number(match[4]) / 1000
  );
}

/** Convert markup to inert text. Consumers must render this as text, never HTML. */
export function subtitlePlainText(value: string): string {
  const entities: Record<string, string> = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
    nbsp: " ",
    lrm: "",
    rlm: "",
  };
  return value
    .replace(/<[^>]*>/g, "")
    .replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (whole, entity: string) => {
      if (entity.startsWith("#")) {
        const code =
          entity.charAt(1).toLowerCase() === "x"
            ? parseInt(entity.slice(2), 16)
            : Number(entity.slice(1));
        return code > 0 &&
          code <= 0x10ffff &&
          !(code >= 0xd800 && code <= 0xdfff)
          ? String.fromCodePoint(code)
          : "";
      }
      return entities[entity.toLowerCase()] ?? whole;
    })
    .replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

/** Parse user-owned SRT/WebVTT. Reject corrupt imports instead of guessing timing. */
export function parseSubtitles(input: string): Cue[] {
  if (new TextEncoder().encode(input).length > SUBTITLE_LIMITS.bytes)
    throw new Error("Subtitle file exceeds the 2 MB limit.");
  const normalized = input
    .replace(/^\uFEFF/, "")
    .replace(/\r\n?/g, "\n")
    .trim();
  if (!normalized)
    throw new Error("Subtitle file is empty. Import an SRT or VTT file.");
  const blocks = normalized.split(/\n[\t ]*\n(?:[\t ]*\n)*/);
  const cues: Cue[] = [];
  for (const block of blocks) {
    const lines = block.split("\n");
    if (
      /^(WEBVTT(?:\s|$)|NOTE(?:\s|$)|STYLE\s*$|REGION\s*$)/.test(lines[0] ?? "")
    )
      continue;
    const timingIndex = lines.findIndex((line) => line.includes("-->"));
    if (timingIndex < 0 || timingIndex > 1)
      throw new Error(
        `Invalid subtitle block near: ${(lines[0] ?? "").slice(0, 60)}`,
      );
    const match = /^\s*(\S+)\s+-->\s+(\S+)(?:\s+.*)?$/.exec(
      lines[timingIndex] ?? "",
    );
    if (!match)
      throw new Error(`Invalid timing in subtitle ${cues.length + 1}.`);
    const start = timestamp(match[1]!);
    const end = timestamp(match[2]!);
    if (end <= start)
      throw new Error(`Subtitle ${cues.length + 1} must end after it starts.`);
    if (lines.slice(timingIndex + 1).some((line) => line.includes("-->")))
      throw new Error(
        `Missing blank line between subtitles near subtitle ${cues.length + 1}.`,
      );
    const text = subtitlePlainText(lines.slice(timingIndex + 1).join("\n"));
    if (!text) continue;
    if (text.length > SUBTITLE_LIMITS.textLength)
      throw new Error(`Subtitle ${cues.length + 1} exceeds 4,000 characters.`);
    cues.push({ id: `cue-${cues.length + 1}`, start, end, text });
    if (cues.length > SUBTITLE_LIMITS.cues)
      throw new Error("Subtitle file exceeds 20,000 cues.");
  }
  if (!cues.length)
    throw new Error(
      "No readable subtitle cues found. Import a valid SRT or VTT file.",
    );
  return cues.sort((a, b) => a.start - b.start || a.end - b.end);
}

/** End is exclusive. For overlapping cues, prefer the most recently started cue. */
export function activeCue(cues: readonly Cue[], time: number): Cue | undefined {
  if (!Number.isFinite(time) || time < 0) return undefined;
  let active: Cue | undefined;
  for (const cue of cues) {
    if (
      cue.start <= time &&
      time < cue.end &&
      (!active || cue.start >= active.start)
    )
      active = cue;
  }
  return active;
}

/** Read only tracks already exposed by the video; no private YouTube endpoints. */
export function cuesFromTextTrack(track: TextTrack): Cue[] {
  return Array.from(track.cues ?? [])
    .flatMap((cue, index) => {
      const raw = "text" in cue ? String(cue.text) : "";
      const text = subtitlePlainText(raw);
      return text &&
        text.length <= SUBTITLE_LIMITS.textLength &&
        Number.isFinite(cue.startTime) &&
        Number.isFinite(cue.endTime) &&
        cue.startTime >= 0 &&
        cue.endTime > cue.startTime
        ? [
            {
              id: `native-${index}`,
              start: cue.startTime,
              end: cue.endTime,
              text,
            },
          ]
        : [];
    })
    .sort((a, b) => a.start - b.start || a.end - b.end)
    .slice(0, SUBTITLE_LIMITS.cues);
}
