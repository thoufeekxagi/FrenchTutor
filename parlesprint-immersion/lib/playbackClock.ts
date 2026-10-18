export interface PlaybackClock {
  currentTime: number;
  paused: boolean;
  muted: boolean;
  playbackRate: number;
  seeking: boolean;
  adShowing: boolean;
  epoch: number;
  videoKey: string;
  observedAt: number;
}

export type PlaybackHoldReason = "ad" | "seek" | "paused" | "muted" | null;

export function playbackHoldReason(clock: Pick<PlaybackClock, "paused" | "muted" | "seeking" | "adShowing">): PlaybackHoldReason {
  if (clock.adShowing) return "ad";
  if (clock.seeking) return "seek";
  if (clock.paused) return "paused";
  if (clock.muted) return "muted";
  return null;
}

/** Do not spend transcription audio on an ad or while the player is paused/seeking. */
export function shouldCapturePlaybackAudio(clock: Pick<PlaybackClock, "paused" | "muted" | "seeking" | "adShowing">): boolean {
  return !clock.paused && !clock.muted && !clock.seeking && !clock.adShowing;
}

/**
 * A new epoch separates unrelated audio segments. It also detects a missed
 * seek event by comparing media-time movement to elapsed wall time.
 */
export function isPlaybackDiscontinuity(previous: PlaybackClock, next: PlaybackClock): boolean {
  if (
    previous.videoKey !== next.videoKey ||
    previous.adShowing !== next.adShowing ||
    previous.muted !== next.muted ||
    (!previous.seeking && next.seeking)
  ) return true;

  if (!Number.isFinite(previous.currentTime) || !Number.isFinite(next.currentTime)) return false;
  const wallSeconds = Math.max(0, (next.observedAt - previous.observedAt) / 1000);
  const expectedSeconds = previous.paused || previous.seeking || previous.adShowing
    ? 0
    : wallSeconds * Math.max(0.1, Math.min(4, previous.playbackRate));
  const mediaSeconds = next.currentTime - previous.currentTime;
  return Math.abs(mediaSeconds - expectedSeconds) > Math.max(3, expectedSeconds + 1.5);
}

/** Drop provider output belonging to audio captured before a seek/ad/video boundary. */
export function isCurrentPlaybackTranscript(
  transcriptEpoch: unknown,
  clock: Pick<PlaybackClock, "epoch" | "seeking" | "adShowing" | "muted">,
): boolean {
  return Number.isSafeInteger(transcriptEpoch) &&
    transcriptEpoch === clock.epoch &&
    !clock.seeking &&
    !clock.adShowing &&
    !clock.muted;
}
