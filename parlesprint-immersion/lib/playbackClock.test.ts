import { describe, expect, it } from "vitest";
import {
  isCurrentPlaybackTranscript,
  isPlaybackDiscontinuity,
  playbackHoldReason,
  shouldCapturePlaybackAudio,
  type PlaybackClock,
} from "./playbackClock";

function clock(overrides: Partial<PlaybackClock> = {}): PlaybackClock {
  return {
    currentTime: 20,
    paused: false,
    muted: false,
    playbackRate: 1,
    seeking: false,
    adShowing: false,
    epoch: 4,
    videoKey: "youtube:video-a",
    observedAt: 10_000,
    ...overrides,
  };
}

describe("YouTube playback boundaries", () => {
  it.each([10, 15, -10, -15])("detects a %s second player seek", (jump) => {
    expect(isPlaybackDiscontinuity(
      clock(),
      clock({ currentTime: 20 + jump, observedAt: 10_100 }),
    )).toBe(true);
  });

  it("does not mistake ordinary 1x or 2x playback for a seek", () => {
    expect(isPlaybackDiscontinuity(
      clock(),
      clock({ currentTime: 21, observedAt: 11_000 }),
    )).toBe(false);
    expect(isPlaybackDiscontinuity(
      clock({ playbackRate: 2 }),
      clock({ currentTime: 22, playbackRate: 2, observedAt: 11_000 }),
    )).toBe(false);
  });

  it("starts a new transcript segment when an ad starts, ends, or the video changes", () => {
    expect(isPlaybackDiscontinuity(clock(), clock({ adShowing: true }))).toBe(true);
    expect(isPlaybackDiscontinuity(clock(), clock({ muted: true }))).toBe(true);
    expect(isPlaybackDiscontinuity(
      clock({ adShowing: true }),
      clock({ adShowing: false }),
    )).toBe(true);
    expect(isPlaybackDiscontinuity(
      clock(),
      clock({ videoKey: "youtube:video-b" }),
    )).toBe(true);
  });

  it("recognizes the start of a seek even before the playhead settles", () => {
    expect(isPlaybackDiscontinuity(clock(), clock({ seeking: true }))).toBe(true);
  });

  it("does not send audio during ads, seeks, pauses, or muted playback", () => {
    expect(shouldCapturePlaybackAudio(clock())).toBe(true);
    expect(shouldCapturePlaybackAudio(clock({ adShowing: true }))).toBe(false);
    expect(shouldCapturePlaybackAudio(clock({ seeking: true }))).toBe(false);
    expect(shouldCapturePlaybackAudio(clock({ paused: true }))).toBe(false);
    expect(shouldCapturePlaybackAudio(clock({ muted: true }))).toBe(false);
    expect(playbackHoldReason(clock({ adShowing: true }))).toBe("ad");
    expect(playbackHoldReason(clock({ seeking: true }))).toBe("seek");
    expect(playbackHoldReason(clock({ paused: true }))).toBe("paused");
    expect(playbackHoldReason(clock({ muted: true }))).toBe("muted");
  });

  it("drops delayed transcript results from before an ad or seek boundary", () => {
    expect(isCurrentPlaybackTranscript(4, clock())).toBe(true);
    expect(isCurrentPlaybackTranscript(3, clock())).toBe(false);
    expect(isCurrentPlaybackTranscript(4, clock({ seeking: true }))).toBe(false);
    expect(isCurrentPlaybackTranscript(4, clock({ adShowing: true }))).toBe(false);
    expect(isCurrentPlaybackTranscript(4, clock({ muted: true }))).toBe(false);
  });
});
