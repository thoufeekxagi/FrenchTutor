/**
 * Screen: YouTube subtitle companion. Key prefix: immersion.
 * User arrived to: watch a French video and understand useful words.
 * They must understand: what was said, which word is being spoken, and how to
 * reveal a translation or word details without covering the player.
 * Primary action: follow the two-line French caption below the video.
 * Secondary action: translate a sentence, study a word, replay, move or resize.
 * Success state: captions stay synchronized when the layout or player changes.
 * Must not contain: mandatory subtitle uploads or a panel covering the video by default.
 * States: waiting, empty, loading, listening, loaded, translating, explaining, error.
 */
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { browser } from "wxt/browser";
import {
  activeCue,
  cuesFromTextTrack,
  estimatedLiveCueRange,
  parseSubtitles,
  type Cue,
} from "./captions";
import { useStore } from "./store";
import { Brand, Headphones } from "./Brand";
import {
  tokenizeCaption,
  savedPhraseRanges,
  selectTokenRange,
  type TokenRange,
  wordAtCaptionProgress,
} from "./wordSelection";
import type { Explanation, Level } from "./types";
const levelCopy = {
  A1: "Start with the meaning, then notice one useful pattern.",
  A2: "Follow the sentence and explore unfamiliar phrases.",
  B1: "Listen first. Reveal help when you need it.",
  B2: "Focus on nuance, idioms, and natural phrasing.",
};
export interface PracticeCue extends Cue {
  translation?: string;
  grammar?: string;
}
export interface Practice {
  cues: PracticeCue[];
  source: string;
}
interface FloatingBox {
  left: number;
  top: number;
  width: number;
  height: number;
}
function boxFromPreferences(
  rect: { left: number; top: number; width: number; height: number },
  viewport: { width: number; height: number },
): FloatingBox {
  const width = Math.min(Math.max(280, rect.width * viewport.width), viewport.width - 16);
  const height = Math.min(Math.max(150, rect.height * viewport.height), viewport.height * 0.85);
  return {
    left: Math.max(8, Math.min(viewport.width - width - 8, rect.left * viewport.width)),
    top: Math.max(8, Math.min(viewport.height - Math.min(height, viewport.height - 16) - 8, rect.top * viewport.height)),
    width,
    height,
  };
}
function normalizedBox(box: FloatingBox, viewport: { width: number; height: number }) {
  return {
    left: box.left / viewport.width,
    top: box.top / viewport.height,
    width: box.width / viewport.width,
    height: box.height / viewport.height,
  };
}
function clampBox(box: FloatingBox, viewport: { width: number; height: number }): FloatingBox {
  const width = Math.max(Math.min(280, viewport.width - 16), Math.min(box.width, viewport.width - 16));
  const height = Math.max(Math.min(150, viewport.height - 16), Math.min(box.height, viewport.height * 0.85));
  return {
    left: Math.max(8, Math.min(viewport.width - width - 8, box.left)),
    top: Math.max(8, Math.min(viewport.height - height - 8, box.top)),
    width,
    height,
  };
}
function watchKey(): string | null {
  const url = new URL(location.href);
  const id = url.searchParams.get("v");
  if (url.hostname.endsWith("youtube.com")) {
    if (url.pathname === "/watch" && id && /^[\w-]{1,100}$/.test(id)) return id;
    const shortsId = url.pathname.match(/^\/shorts\/([\w-]{1,100})/)?.[1];
    return shortsId ? `shorts-${shortsId}` : null;
  }
  if (!document.querySelector("video")) return null;
  url.hash = "";
  // Keep separate local transcripts by page URL without persisting the full URL.
  let hash = 2166136261;
  for (const char of `${url.origin}${url.pathname}${url.search}`) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return `site-${(hash >>> 0).toString(16)}`;
}
export function Immersion({ practice }: { practice?: Practice } = {}) {
  const { prefs, ready, load, update, save, words, storageError } = useStore();
  const [video, setVideo] = useState<HTMLVideoElement | null>(null);
  const [viewport, setViewport] = useState(() => ({ width: window.innerWidth, height: window.innerHeight }));
  const [floatingBox, setFloatingBox] = useState<FloatingBox>(() =>
    boxFromPreferences(useStore.getState().prefs.floatRect, { width: window.innerWidth, height: window.innerHeight }),
  );
  const floatingTransform = useRef<{
    pointerId: number;
    mode: "move" | "resize";
    startX: number;
    startY: number;
    initial: FloatingBox;
    current: FloatingBox;
  } | null>(null);
  const [setupOpen, setSetupOpen] = useState(false);
  const [cues, setCues] = useState<Cue[]>([]);
  const [source, setSource] = useState("");
  const [liveInterim, setLiveInterim] = useState("");
  const [liveCaptureActive, setLiveCaptureActive] = useState(false);
  const [liveHoldReason, setLiveHoldReason] = useState<"ad" | "seek" | "paused" | "muted" | null>(null);
  const [playerAdShowing, setPlayerAdShowing] = useState(false);
  const [playerSeeking, setPlayerSeeking] = useState(false);
  const cuesRef = useRef<Cue[]>([]);
  const [heldCue, setHeldCue] = useState<Cue>();
  const [selection, setSelection] = useState<{
    cue: string;
    range: TokenRange;
  }>();
  const [phraseMode, setPhraseMode] = useState(false);
  const [phraseAnchor, setPhraseAnchor] = useState<number>();
  const [playbackRate, setPlaybackRate] = useState(1);
  const [offset, setOffset] = useState(0);
  const [now, setNow] = useState(0);
  const [collapsed, setCollapsed] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const [selected, setSelected] = useState("");
  const [sentence, setSentence] = useState("");
  const [explanation, setExplanation] = useState<Explanation>();
  const [translation, setTranslation] = useState("");
  const [translationVisible, setTranslationVisible] = useState(false);
  const [translationBusy, setTranslationBusy] = useState(false);
  const [translationNeedsConsent, setTranslationNeedsConsent] = useState(false);
  const [error, setError] = useState("");
  const [subtitleNotice, setSubtitleNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const [consentBusy, setConsentBusy] = useState(false);
  const [captionRevealed, setCaptionRevealed] = useState(false);
  const [meaningRevealed, setMeaningRevealed] = useState(false);
  const [videoId, setVideoId] = useState<string | null>(() =>
    practice ? "practice-v1" : watchKey(),
  );
  const videoIdRef = useRef(videoId);
  const revision = useRef(0);
  const importSerial = useRef(0);
  const request = useRef(0);
  const translationRequest = useRef(0);
  const [transcriptOpen, setTranscriptOpen] = useState(false);
  const [transcriptPage, setTranscriptPage] = useState(0);
  const [fullscreen, setFullscreen] = useState(!!document.fullscreenElement);
  const replayWindow = useRef<{ start: number; end: number } | null>(null);
  const replayFrame = useRef(0);
  function cancelReplay() {
    replayWindow.current = null;
    cancelAnimationFrame(replayFrame.current);
  }
  function beginFloatingTransform(mode: "move" | "resize", event: React.PointerEvent<HTMLButtonElement>) {
    if (event.button !== 0 || practice) return;
    event.preventDefault();
    floatingTransform.current = {
      pointerId: event.pointerId,
      mode,
      startX: event.clientX,
      startY: event.clientY,
      initial: floatingBox,
      current: floatingBox,
    };
  }
  function nudgeFloating(mode: "move" | "resize", dx: number, dy: number) {
    const box = mode === "move"
      ? { ...floatingBox, left: floatingBox.left + dx, top: floatingBox.top + dy }
      : { ...floatingBox, width: floatingBox.width + dx, height: floatingBox.height + dy };
    const next = clampBox(box, viewport);
    setFloatingBox(next);
    void update({ floatRect: normalizedBox(next, viewport) });
  }
  useEffect(() => {
    void load();
  }, [load]);
  useEffect(() => {
    const resize = () => setViewport({ width: window.innerWidth, height: window.innerHeight });
    const move = (event: PointerEvent) => {
      const active = floatingTransform.current;
      if (!active || active.pointerId !== event.pointerId) return;
      const dx = event.clientX - active.startX;
      const dy = event.clientY - active.startY;
      const raw = active.mode === "move"
        ? { ...active.initial, left: active.initial.left + dx, top: active.initial.top + dy }
        : { ...active.initial, width: active.initial.width + dx, height: active.initial.height + dy };
      active.current = clampBox(raw, viewport);
      setFloatingBox(active.current);
    };
    const finish = (event: PointerEvent) => {
      const active = floatingTransform.current;
      if (!active || active.pointerId !== event.pointerId) return;
      floatingTransform.current = null;
      setFloatingBox(active.current);
      void update({ floatRect: normalizedBox(active.current, viewport) });
    };
    window.addEventListener("resize", resize);
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", finish);
    window.addEventListener("pointercancel", finish);
    return () => {
      window.removeEventListener("resize", resize);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", finish);
      window.removeEventListener("pointercancel", finish);
    };
  }, [update, viewport]);
  useEffect(() => {
    setFloatingBox(boxFromPreferences(prefs.floatRect, viewport));
  }, [prefs.floatRect, viewport]);
  useEffect(() => {
    cuesRef.current = cues;
  }, [cues]);
  useEffect(() => {
    const handleLive = (event: Event) => {
      const message = (event as CustomEvent<Record<string, unknown>>).detail;
      if (!message) return;
      if (message.type === "live-transcription-status") {
        const active = message.status === "connecting" || message.status === "listening";
        setLiveCaptureActive(active);
        const reason = message.holdReason === "ad" || message.holdReason === "seek" || message.holdReason === "paused" || message.holdReason === "muted"
          ? message.holdReason
          : null;
        setLiveHoldReason(active ? reason : null);
        if (!active || reason) setLiveInterim("");
        if (typeof message.error === "string") setError(message.error);
        return;
      }
      if (message.type === "live-transcription-interim") {
        if (typeof message.text === "string") setLiveInterim(message.text.slice(0, 2000));
        if (typeof message.at === "number" && Number.isFinite(message.at)) setNow(message.at);
        return;
      }
      if (message.type !== "live-transcription-final" || typeof message.text !== "string") return;
      const text = message.text.trim().slice(0, 2000);
      const at = typeof message.at === "number" && Number.isFinite(message.at)
        ? Math.max(0, message.at)
        : video?.currentTime ?? 0;
      if (!text || !videoIdRef.current || playerAdShowing || playerSeeking) return;
      setLiveInterim("");
      setNow(at);
      cancelReplay();
      setSelected("");
      setExplanation(undefined);
      setError("");
      const wordsInLine = text.split(/\s+/).length;
      const range = estimatedLiveCueRange(at, wordsInLine, video?.playbackRate ?? 1);
      if (!range) return;
      const cue: Cue = {
        id: `live-${crypto.randomUUID()}`,
        text,
        ...range,
      };
      const key = videoIdRef.current;
      const previous = cuesRef.current;
      const duplicate = previous.slice(-8).some((item) =>
        item.text.toLocaleLowerCase("fr") === text.toLocaleLowerCase("fr") &&
        Math.abs(item.start - cue.start) < 14
      );
      if (duplicate) return;
      const next = [...previous, cue].sort((a, b) => a.start - b.start).slice(-1200);
      cuesRef.current = next;
      setCues(next);
      setSource("Automatic live French transcription");
      void browser.storage.local.set({
        [`captions:${key}`]: { cues: next, source: "Automatic live French transcription", offset: 0 },
      }).catch(() => setError("Captions are visible, but could not be saved in this browser."));
    };
    window.addEventListener("parlesprint-live-event", handleLive);
    return () => window.removeEventListener("parlesprint-live-event", handleLive);
  }, [video, playerAdShowing, playerSeeking]);
  useEffect(() => {
    const sync = () => {
      const id = practice ? "practice-v1" : watchKey();
      videoIdRef.current = id;
      setVideoId(id);
      setVideo(id ? document.querySelector("video") : null);
      const player = document.querySelector<HTMLElement>("#movie_player, .html5-video-player");
      setPlayerAdShowing(!!player?.classList.contains("ad-showing"));
    };
    sync();
    const timer = setInterval(sync, 250);
    const full = () => setFullscreen(!!document.fullscreenElement);
    document.addEventListener("fullscreenchange", full);
    return () => {
      clearInterval(timer);
      document.removeEventListener("fullscreenchange", full);
      cancelReplay();
    };
  }, [practice]);
  useEffect(() => {
    cancelReplay();
    cuesRef.current = [];
    setCues([]);
    setSource("");
    setLiveInterim("");
    setOffset(0);
    setSelected("");
    setSentence("");
    setExplanation(undefined);
    setError("");
    setSubtitleNotice("");
    setBusy(false);
    setTranscriptPage(0);
    request.current++;
    importSerial.current++;
    const ticket = ++revision.current;
    if (!videoId) return;
    if (practice) {
      cuesRef.current = practice.cues;
      setCues(practice.cues);
      setSource(practice.source);
      return;
    }
    void browser.storage.local
      .get(`captions:${videoId}`)
      .then((data) => {
        if (ticket !== revision.current || videoId !== videoIdRef.current)
          return;
        const stored = data[`captions:${videoId}`] as
          { cues?: Cue[]; source?: string; offset?: number } | undefined;
        if (
          stored &&
          Array.isArray(stored.cues) &&
          stored.cues.length &&
          stored.cues.every(
            (c) =>
              typeof c.text === "string" &&
              Number.isFinite(c.start) &&
              Number.isFinite(c.end) &&
              c.start >= 0 &&
              c.end > c.start,
          )
        ) {
          cuesRef.current = stored.cues;
          setCues(stored.cues);
          setSource(
            typeof stored.source === "string"
              ? stored.source
              : "Saved subtitles",
          );
          setOffset(
            typeof stored.offset === "number" && Number.isFinite(stored.offset)
              ? Math.max(-600, Math.min(600, stored.offset))
              : 0,
          );
        }
      })
      .catch(() =>
        setError("Could not restore subtitles. Import them again to continue."),
      );
  }, [videoId, practice]);
  useEffect(() => {
    cancelReplay();
    if (!video) return;
    const tick = () => setNow(video.currentTime);
    const seek = () => {
      setHeldCue(undefined);
      if (
        replayWindow.current &&
        Math.abs(video.currentTime - replayWindow.current.start) > 0.15
      )
        cancelReplay();
    };
    const stop = () => cancelReplay();
    const play = () => { setHeldCue(undefined); tick(); };
    const rate = () => { setPlaybackRate(video.playbackRate); };
    const clock = () => { tick(); };
    const seeking = () => { setPlayerSeeking(true); seek(); tick(); };
    const seeked = () => { setPlayerSeeking(false); tick(); };
    const pause = () => { stop(); tick(); };
    video.addEventListener("play", play);
    video.addEventListener("ratechange", rate);
    rate();
    video.addEventListener("timeupdate", clock);
    video.addEventListener("seeking", seeking);
    video.addEventListener("seeked", seeked);
    video.addEventListener("pause", pause);
    video.addEventListener("ended", stop);
    tick();
    setPlayerSeeking(video.seeking);
    return () => {
      cancelReplay();
      video.removeEventListener("play", play);
      video.removeEventListener("ratechange", rate);
      video.removeEventListener("timeupdate", clock);
      video.removeEventListener("seeking", seeking);
      video.removeEventListener("seeked", seeked);
      video.removeEventListener("pause", pause);
      video.removeEventListener("ended", stop);
    };
  }, [video]);
  useEffect(() => {
    cancelReplay();
  }, [prefs.enabled, videoId, offset]);
  useEffect(() => {
    setHeldCue(undefined);
  }, [videoId, cues, offset]);
  const cue = playerAdShowing || playerSeeking
    ? undefined
    : video?.paused && heldCue && Math.abs(now - heldCue.end - offset) < 0.3
      ? heldCue
      : activeCue(cues, now - offset);
  const cueKey = `${videoId}:${cue?.id}`;
  const tokens = useMemo(() => tokenizeCaption(cue?.text ?? ""), [cue?.text]);
  const spokenWordIndex =
    prefs.highlightSpokenWords &&
    cue &&
    video &&
    !video.paused &&
    (!prefs.hidden || captionRevealed)
      ? wordAtCaptionProgress(
          tokens,
          (now - offset - cue.start) / Math.max(0.05, cue.end - cue.start),
        )
      : undefined;
  const savedRanges = useMemo(
    () =>
      prefs.highlightSaved
        ? savedPhraseRanges(
            tokens,
            words.map((w) => w.text),
          )
        : [],
    [tokens, words, prefs.highlightSaved],
  );
  const selectedRange = selection?.cue === cueKey ? selection.range : undefined;
  const selectedWordCount = useMemo(
    () => tokenizeCaption(selected).filter((token) => token.kind === "word").length,
    [selected],
  );
  const selectedId = `${selected.toLocaleLowerCase("fr")}|${sentence}|${prefs.level}`;
  const savedEntry = words.find((word) => word.id === selectedId);
  const saved =
    !!savedEntry &&
    (!explanation ||
      JSON.stringify(savedEntry.explanation) === JSON.stringify(explanation));

  useEffect(() => {
    setCaptionRevealed(false);
    setSelection(undefined);
    setPhraseAnchor(undefined);
    setPhraseMode(false);
    translationRequest.current++;
    setTranslation("");
    setTranslationVisible(false);
    setTranslationBusy(false);
    setTranslationNeedsConsent(false);
  }, [cueKey]);
  useLayoutEffect(() => {
    request.current++;
    setExplanation(undefined);
    setBusy(false);
    setError("");
    setMeaningRevealed(false);
  }, [prefs.level, prefs.aiConsent]);
  const currentKey = () => (practice ? "practice-v1" : watchKey());
  async function install(
    next: Cue[],
    name: string,
    key: string,
    ticket: number,
  ) {
    if (key !== currentKey() || ticket !== importSerial.current) return;
    revision.current++;
    cancelReplay();
    request.current++;
    cuesRef.current = next;
    setCues(next);
    setSource(name);
    setOffset(0);
    setError("");
    setSelected("");
    setExplanation(undefined);
    setCaptionRevealed(false);
    setBusy(false);
    setSubtitleNotice("");
    setTranscriptPage(0);
    try {
      await browser.storage.local.set({
        [`captions:${key}`]: { cues: next, source: name, offset: 0 },
      });
    } catch {
      if (key === videoIdRef.current)
        setError(
          "Subtitles are loaded for this session, but could not be saved. Browser storage may be full.",
        );
    }
  }
  async function importFile(file?: File) {
    const key = videoIdRef.current;
    if (!file || !key) return;
    const ticket = ++importSerial.current;
    try {
      if (file.size > 2_000_000)
        throw Error("Subtitle file exceeds the 2 MB limit.");
      const parsed = parseSubtitles(await file.text());
      await install(parsed, file.name, key, ticket);
    } catch (e) {
      if (key === currentKey() && ticket === importSerial.current)
        setError(
          e instanceof Error ? e.message : "Unable to import subtitles.",
        );
    }
  }
  async function nativeCaptions() {
    const key = videoIdRef.current;
    if (!key) return;
    setSubtitleNotice("");
    setError("");
    try {
      if (!video) throw Error("Open a YouTube video first.");
      const track = Array.from(video.textTracks).find(
        (t) => /^fr\b/i.test(t.language) && t.cues?.length,
      );
      if (!track)
        return setSubtitleNotice(
          "YouTube does not expose a French text track here. Live French captions are still available from the ParleSprint toolbar; no file is needed.",
        );
      const next = cuesFromTextTrack(track);
      if (!next.length)
        return setSubtitleNotice(
          "No readable French text track was found. Live French captions are still available from the ParleSprint toolbar.",
        );
      await install(
        next,
        "French player captions",
        key,
        ++importSerial.current,
      );
    } catch (e) {
      setError((e as Error).message);
    }
  }
  async function clearSubtitles() {
    const key = videoIdRef.current;
    if (!key) return;
    cancelReplay();
    revision.current++;
    importSerial.current++;
    request.current++;
    cuesRef.current = [];
    setCues([]);
    setSource("");
    setSelected("");
    setExplanation(undefined);
    setBusy(false);
    setOffset(0);
    try {
      await browser.storage.local.remove(`captions:${key}`);
    } catch {
      setError("Could not remove saved subtitles. Please try again.");
    }
  }
  async function changeOffset(value: number) {
    const key = videoIdRef.current;
    if (!key || !Number.isFinite(value)) return;
    cancelReplay();
    const next = Math.max(-600, Math.min(600, value));
    setOffset(next);
    if (practice) return;
    try {
      await browser.storage.local.set({
        [`captions:${key}`]: { cues, source, offset: next },
      });
    } catch {
      setError("Timing changed for this session, but could not be saved.");
    }
  }
  function choose(text: string, line: string) {
    cancelReplay();
    request.current++;
    setBusy(false);
    setSelected(text);
    setSentence(line);
    setExplanation(undefined);
    setError("");
      setSubtitleNotice("");
    setMeaningRevealed(false);
    video?.pause();
  }
  async function requestExplanation(text: string, line: string) {
    if (!text.trim()) return;
    const seq = ++request.current;
    setBusy(true);
    setError("");
    try {
      const result = await browser.runtime.sendMessage({
        type: "explain",
        text,
        sentence: line,
        level: prefs.level,
      });
      if (seq !== request.current) return;
      if (result.error) throw Error(result.error);
      setExplanation(result.explanation);
      setMeaningRevealed(prefs.level === "A1" || prefs.level === "A2");
    } catch (e) {
      if (seq === request.current) setError((e as Error).message);
    } finally {
      if (seq === request.current) setBusy(false);
    }
  }
  function chooseToken(index: number, extend: boolean) {
    if (!cue) return;
    const first =
      phraseMode && phraseAnchor !== undefined
        ? phraseAnchor
        : extend && selectedRange
          ? selectedRange.start
          : index;
    const next = selectTokenRange(tokens, first, index);
    if (!next) return;
    choose(next.text, cue.text);
    setSelection({ cue: cueKey, range: next });
    if (prefs.aiConsent) void requestExplanation(next.text, cue.text);
    if (phraseMode) {
      if (phraseAnchor === undefined) setPhraseAnchor(index);
      else {
        setPhraseAnchor(undefined);
        setPhraseMode(false);
      }
    }
  }
  function chooseSentence() {
    if (!cue) return;
    choose(cue.text, cue.text);
    const range = selectTokenRange(tokens, 0, tokens.length - 1);
    if (range) setSelection({ cue: cueKey, range });
    if (prefs.aiConsent) void requestExplanation(cue.text, cue.text);
    setPhraseMode(false);
    setPhraseAnchor(undefined);
  }
  async function openPractice() {
    try {
      const response = await browser.runtime.sendMessage({
        type: "open-practice",
      });
      if (response.error) throw Error(response.error);
    } catch {
      setError("Open the extension popup and choose Try your first practice.");
    }
  }
  async function allowExplanations() {
    setConsentBusy(true);
    try {
      await update({ aiConsent: true });
      if (translationNeedsConsent) void translateSentence(true);
    } finally {
      setConsentBusy(false);
    }
  }
  async function openConnection() {
    try {
      const result = await browser.runtime.sendMessage({
        type: "open-connection",
      });
      if (result.error) throw Error(result.error);
    } catch {
      setError("Open the ParleSprint extension popup to connect your account.");
    }
  }
  async function explain() {
    await requestExplanation(selected, sentence);
  }
  async function translateSentence(approved = false) {
    if (!cue) return;
    if (translation && translationVisible) {
      setTranslationVisible(false);
      return;
    }
    if (!prefs.aiConsent && !approved) {
      setTranslationNeedsConsent(true);
      return;
    }
    const seq = ++translationRequest.current;
    setTranslationBusy(true);
    setTranslationNeedsConsent(false);
    setError("");
    try {
      const result = await browser.runtime.sendMessage({
        type: "translate",
        text: cue.text,
        sentence: cue.text,
        level: prefs.level,
      });
      if (seq !== translationRequest.current) return;
      if (result.error) throw Error(result.error);
      if (typeof result.translation !== "string" || !result.translation.trim())
        throw Error("The translation was incomplete. Please try again.");
      setTranslation(result.translation);
      setTranslationVisible(true);
    } catch (e) {
      if (seq === translationRequest.current) setError((e as Error).message);
    } finally {
      if (seq === translationRequest.current) setTranslationBusy(false);
    }
  }
  async function saveWord() {
    const seq = request.current;
    try {
      await save({
        id: `${selected.toLocaleLowerCase("fr")}|${sentence}|${prefs.level}`,
        text: selected,
        sentence,
        level: prefs.level,
        explanation,
        savedAt: Date.now(),
      });
    } catch {
      if (seq === request.current)
        setError(
          "Could not save this phrase. Your browser storage may be full.",
        );
    }
  }
  function replay(target: Cue) {
    if (!video) return;
    cancelReplay();
    const start = Math.max(0, target.start + offset);
    const end = target.end + offset;
    if (end <= start) {
      setError(
        "This sentence falls before the video starts. Adjust subtitle timing.",
      );
      return;
    }
    replayWindow.current = { start, end };
    video.currentTime = start;
    const check = () => {
      if (!replayWindow.current) return;
      if (video.currentTime >= replayWindow.current.end) {
        cancelReplay();
        video.pause();
        setHeldCue(target);
        setNow(video.currentTime);
        return;
      }
      replayFrame.current = requestAnimationFrame(check);
    };
    replayFrame.current = requestAnimationFrame(check);
    void video.play().catch(() => {
      cancelReplay();
      setError("Press play on the video to repeat this sentence.");
    });
  }
  if (!ready || !prefs.enabled || !videoId) return null;
  const pageSize = 100;
  const pageStart = transcriptPage * pageSize;
  const currentIndex = cue
    ? cues.findIndex((c) => c.id === cue.id)
    : cues.reduce((found, c, i) => (c.start <= now - offset ? i : found), -1);
  const practiceCue = practice?.cues.find(
    (c) => c.id === cue?.id && c.text === cue?.text,
  );
  const companionStyle = {
    display: fullscreen ? "none" : "block",
    ...(!practice && prefs.placement === "floating"
      ? {
          left: `${floatingBox.left}px`,
          right: "auto",
          top: `${floatingBox.top}px`,
          bottom: "auto",
          width: collapsed ? "260px" : `${floatingBox.width}px`,
          height: collapsed ? "auto" : `${floatingBox.height}px`,
          minWidth: `${Math.min(280, viewport.width - 16)}px`,
          minHeight: collapsed ? "0" : `${Math.min(150, viewport.height - 16)}px`,
        }
      : {}),
  };
  return (
    <aside
      className={`ps companion dock-${prefs.dock} caption-${prefs.captionSize}${!practice ? ` youtube-companion layout-${prefs.placement}` : ""}${!practice && moreOpen ? " tools-open" : ""}${collapsed ? " collapsed" : ""}`}
      aria-label="ParleSprint Immersion"
      style={companionStyle}
    >
      <div
        className="companion-head"
        style={
          collapsed
            ? { marginBottom: 0, paddingBottom: 0, borderBottom: 0 }
            : undefined
        }
      >
        {practice ? (
          <Brand />
        ) : (
          <div className="watch-caption-title">
            <span aria-hidden="true">FR</span>
            <span>French captions</span>
            <label className="visually-hidden" htmlFor="ps-level">
              Your French
            </label>
            <select
              id="ps-level"
              value={prefs.level}
              onChange={(e) => void update({ level: e.target.value as Level })}
            >
              {["A1", "A2", "B1", "B2"].map((l) => (
                <option key={l}>{l}</option>
              ))}
            </select>
            {!practice && (
              <button
                className="move-handle"
                aria-label="Move captions"
                title="Drag to move captions. Use arrow keys to nudge."
                onPointerDown={(event) => beginFloatingTransform("move", event)}
                onKeyDown={(event) => {
                  const movement = {
                    ArrowLeft: [-20, 0],
                    ArrowRight: [20, 0],
                    ArrowUp: [0, -20],
                    ArrowDown: [0, 20],
                  } as const;
                  const delta = movement[event.key as keyof typeof movement];
                  if (delta) {
                    event.preventDefault();
                    nudgeFloating("move", delta[0], delta[1]);
                  }
                }}
              >
                ⠿
              </button>
            )}
            <button
              className="watch-more-button"
              aria-label={moreOpen ? "Hide subtitle settings" : "More subtitle settings"}
              aria-expanded={moreOpen}
              onClick={() => setMoreOpen(!moreOpen)}
            >
              ···
            </button>
          </div>
        )}
        <button
          className="icon-button"
          aria-label={collapsed ? "Expand immersion" : "Minimize immersion"}
          onClick={() => setCollapsed(!collapsed)}
        >
          {collapsed ? "+" : "−"}
        </button>
      </div>
      {!collapsed && (
        <div className="stack">
          {practice && <div className="section-title">
            <div className="row">
              <label htmlFor="ps-level">Your French</label>
              <select
                id="ps-level"
                value={prefs.level}
                onChange={(e) =>
                  void update({ level: e.target.value as Level })
                }
              >
                {["A1", "A2", "B1", "B2"].map((l) => (
                  <option key={l}>{l}</option>
                ))}
              </select>
            </div>
            <span className="pill">{words.length} saved</span>
          </div>}
          {practice && <p className="muted">{levelCopy[prefs.level]}</p>}
          {!video && (
            <p className="card">Open a video on a website to start practising.</p>
          )}
          {!practice && !cues.length && (
            <div className="setup-card stack">
              <div className="row">
                <span className="step-number">01</span>
                <h3>{liveCaptureActive ? "Listening for French." : "Live French captions."}</h3>
              </div>
              <p className="muted">
                {liveInterim || (liveCaptureActive
                  ? liveHoldReason === "ad"
                    ? "Captions pause during ads and resume with the video."
                    : liveHoldReason === "seek"
                      ? "Syncing captions to the new position…"
                      : liveHoldReason === "paused"
                        ? "Captions are paused with your video."
                        : liveHoldReason === "muted"
                          ? "Unmute the video to continue live captions."
                          : "Your video audio is being transcribed as it plays."
                  : "Play a video, then click the ParleSprint toolbar button and choose Start live captions. No subtitle file needed.")}
              </p>
            </div>
          )}
          {!practice && (
            <details
              className="subtitle-manager"
              key={`${videoId}:${!!cues.length}`}
              open={false}
              onToggle={(e) => setSetupOpen(e.currentTarget.open)}
            >
              <summary>
                {source ? (
                  <>
                    <span>Source: {source}</span>
                    <span className="source-change">Change</span>
                  </>
                ) : (
                  "Optional subtitle alternatives"
                )}
              </summary>
              {!cues.length && (
                <div className="setup-card stack">
                  <div className="row">
                    <span className="step-number">02</span>
                    <h3>Check for French page captions.</h3>
                  </div>
                  <p className="muted">
                    Some YouTube captions are drawn into the video and are not exposed as text. Live transcription from the toolbar does not need a caption track.
                  </p>
                </div>
              )}
              <label className="subtitle-import">
                <span>
                  <strong>
                {cues.length ? "Replace captions" : "Optional subtitle file"}
                  </strong>
                  <small>SRT or VTT · Up to 2 MB · Stays on this device</small>
                </span>
                <span aria-hidden="true" className="import-plus">
                  +
                </span>
                <input
                  aria-label="Import French subtitles"
                  type="file"
                  accept=".srt,.vtt,text/vtt"
                  onChange={(e) => {
                    void importFile(e.target.files?.[0]);
                    e.target.value = "";
                  }}
                />
              </label>
              <div className="row">
                <button onClick={() => void nativeCaptions()} disabled={!video}>
                  Check for French page captions
                </button>
                {cues.length > 0 && (
                  <button onClick={() => void clearSubtitles()}>
                    Clear subtitles
                  </button>
                )}
                {cues.length > 0 && (
                  <span className="muted">{cues.length} sentences</span>
                )}
              </div>
              {subtitleNotice && (
                <p className="field-note subtitle-notice" role="status">
                  {subtitleNotice}
                </p>
              )}
            </details>
          )}
          {source && practice && <p className="field-note">Source: {source}</p>}
          {!cues.length && practice && (
            <p className="muted">
              Import subtitles you have permission to use. YouTube captions are
              available only when the player exposes a French track.
            </p>
          )}
          {(cues.length > 0 || liveInterim || liveCaptureActive) && (
            <>
              <div className="card caption-card stack">
                {practice && <div className="section-title">
                  <span className="badge">French listening</span>
                  <span className="pill">{prefs.level}</span>
                </div>}
                {liveInterim ? (
                  <p className="sentence" lang="fr" aria-live="polite">{liveInterim}</p>
                ) : cue ? (
                  <div className="sentence" lang="fr">
                    {prefs.hidden && !captionRevealed ? (
                      <button onClick={() => setCaptionRevealed(true)}>
                        Reveal French sentence
                      </button>
                    ) : (
                      tokens.map((token) => {
                        if (token.kind !== "word")
                          return <span key={token.index}>{token.text}</span>;
                        const isSelected =
                          !!selectedRange &&
                          token.index >= selectedRange.start &&
                          token.index <= selectedRange.end;
                        const isSaved = savedRanges.some(
                          (range) =>
                            token.index >= range.start &&
                            token.index <= range.end,
                        );
                        const isSpoken = token.index === spokenWordIndex;
                        return (
                          <button
                            key={token.index}
                            className={`word${isSelected ? " selected" : ""}${isSaved ? " notebook-word" : ""}${isSpoken ? " spoken" : ""}`}
                            aria-label={`Study ${token.text}`}
                            aria-pressed={isSelected}
                            aria-current={isSpoken ? "true" : undefined}
                            data-saved={isSaved || undefined}
                            title={
                              isSaved
                                ? "Saved in your notebook"
                                : "Select this word; Shift-click another to extend"
                            }
                            onClick={(event) =>
                              chooseToken(token.index, event.shiftKey)
                            }
                          >
                            {token.text}
                          </button>
                        );
                      })
                    )}
                  </div>
                ) : liveCaptureActive ? (
                  <p className="muted" role="status">
                    {liveHoldReason === "ad"
                      ? "Captions pause during ads and resume with the video."
                      : liveHoldReason === "seek"
                        ? "Syncing captions to the new position…"
                        : liveHoldReason === "paused"
                          ? "Captions are paused with your video."
                          : liveHoldReason === "muted"
                            ? "Unmute the video to continue live captions."
                            : "Listening… French captions will appear here."}
                  </p>
                ) : (
                  <p className="muted">
                    {playerAdShowing
                      ? "Captions pause during ads and resume with the video."
                      : playerSeeking
                        ? "Syncing captions to the new position…"
                        : now < (cues[0]?.start ?? 0) + offset
                      ? "Play the video. Your first subtitle is coming up."
                      : "No subtitle at this moment. Continue listening."}
                  </p>
                )}
                <div className="selection-tools">
                  <button
                    className="phrase-select"
                    aria-pressed={phraseMode}
                    disabled={!cue || (prefs.hidden && !captionRevealed)}
                    onClick={() => {
                      setPhraseMode(!phraseMode);
                      setPhraseAnchor(undefined);
                    }}
                  >
                    {phraseMode ? "Cancel phrase selection" : "Select a phrase"}
                  </button>
                  {(phraseMode || practice) && <span className="field-note" aria-live="polite">
                    {phraseMode
                      ? phraseAnchor === undefined
                        ? "Choose the first word."
                        : "Now choose the last word."
                      : "Tap a word · Shift-click to extend"}
                  </span>}
                </div>
                {practice && <div className="highlight-legend" aria-label="Highlight colors">
                  <span>
                    <i className="legend-selected" /> Selected
                  </span>
                  <span>
                    <i className="legend-saved" /> Saved in notebook
                  </span>
                </div>}
                <div className="caption-actions">
                  <button
                    className="primary"
                    disabled={!cue}
                    onClick={() => cue && replay(cue)}
                  >
                    ↻ Repeat
                  </button>
                  {practice ? (
                    <button disabled={!cue} onClick={chooseSentence}>
                      Study sentence
                    </button>
                  ) : (
                    <>
                      <button
                        className="translate-button"
                        aria-pressed={translationVisible}
                        disabled={!cue || translationBusy}
                        onClick={() => void translateSentence()}
                      >
                        {translationBusy
                          ? "Translating…"
                          : translationVisible
                            ? "Hide translation"
                            : "Translate sentence"}
                      </button>
                      <button
                        className="study-sentence-button"
                        disabled={!cue}
                        onClick={chooseSentence}
                      >
                        Study sentence
                      </button>
                    </>
                  )}
                </div>
                {!practice && translationVisible && translation && (
                  <p className="sentence-translation" lang="en" aria-live="polite">
                    {translation}
                  </p>
                )}
                {!practice && translationNeedsConsent && !prefs.aiConsent && (
                  <div className="translation-consent">
                    <span>Allow ParleSprint to send this sentence for an English translation.</span>
                    <button disabled={consentBusy} onClick={() => void allowExplanations()}>
                      {consentBusy ? "Allowing…" : "Allow & translate"}
                    </button>
                  </div>
                )}
                {practice ? <div className="sentence-navigation">
                  <button
                    aria-label="Previous sentence"
                    disabled={currentIndex <= 0}
                    onClick={() => replay(cues[currentIndex - 1]!)}
                  >
                    ← Previous
                  </button>
                  <span className="field-note">
                    {currentIndex >= 0
                      ? `${currentIndex + 1} / ${cues.length}`
                      : `${cues.length} sentences`}
                  </span>
                  <button
                    aria-label="Next sentence"
                    disabled={currentIndex >= cues.length - 1}
                    onClick={() => replay(cues[Math.max(0, currentIndex + 1)]!)}
                  >
                    Next →
                  </button>
                </div> : <details className="sentence-navigation-more">
                  <summary>More sentences</summary>
                  <div className="sentence-navigation">
                    <button aria-label="Previous sentence" disabled={currentIndex <= 0} onClick={() => replay(cues[currentIndex - 1]!)}>← Previous</button>
                    <span className="field-note">{currentIndex >= 0 ? `${currentIndex + 1} / ${cues.length}` : `${cues.length} sentences`}</span>
                    <button aria-label="Next sentence" disabled={currentIndex >= cues.length - 1} onClick={() => replay(cues[Math.max(0, currentIndex + 1)]!)}>Next →</button>
                  </div>
                </details>}
                {practiceCue?.translation && (
                  <details className="translation">
                    <summary>Reveal sentence translation</summary>
                    <p>{practiceCue.translation}</p>
                    {practiceCue.grammar && (
                      <p className="muted">{practiceCue.grammar}</p>
                    )}
                  </details>
                )}
              </div>
              <details className="reading-settings">
                <summary>Reading & playback</summary>
                <div className="stack">
                  <label>
                    <input
                      type="checkbox"
                      checked={prefs.hidden}
                      onChange={(e) => void update({ hidden: e.target.checked })}
                    />{" "}
                    Hide French until revealed
                  </label>
                  <label>
                    Caption size
                    <select
                      aria-label="Caption size"
                      value={prefs.captionSize}
                      onChange={(e) =>
                        void update({
                          captionSize: e.target.value as
                            "comfortable" | "large",
                        })
                      }
                    >
                      <option value="comfortable">Comfortable</option>
                      <option value="large">Large</option>
                    </select>
                  </label>
                  <label>
                    <input
                      type="checkbox"
                      checked={prefs.highlightSaved}
                      onChange={(e) =>
                        void update({ highlightSaved: e.target.checked })
                      }
                    />{" "}
                    Highlight saved words and phrases
                  </label>
                  {!practice && (
                    <label>
                      <input
                        type="checkbox"
                        checked={prefs.highlightSpokenWords}
                        onChange={(e) => void update({ highlightSpokenWords: e.target.checked })}
                      />{" "}
                      Highlight words as the video plays
                    </label>
                  )}
                  <label>
                    Playback speed
                    <select
                      aria-label="Playback speed"
                      value={playbackRate}
                      disabled={!video}
                      onChange={(e) => {
                        if (video) video.playbackRate = Number(e.target.value);
                      }}
                    >
                      {[0.5, 0.75, 1, 1.25, 1.5, 2].includes(
                        playbackRate,
                      ) ? null : (
                        <option value={playbackRate}>{playbackRate}×</option>
                      )}
                      {[0.5, 0.75, 1, 1.25, 1.5, 2].map((rate) => (
                        <option key={rate} value={rate}>
                          {rate}×{rate === 1 ? " · Normal" : ""}
                        </option>
                      ))}
                    </select>
                  </label>
                  {!practice && (
                    <label>
                      Caption placement
                      <select
                        aria-label="Caption placement"
                        value={prefs.placement}
                        onChange={(e) =>
                          void update({
                            placement: e.target.value as "below" | "floating",
                          })
                        }
                      >
                        <option value="below">Below the video</option>
                        <option value="floating">Floating overlay</option>
                      </select>
                    </label>
                  )}
                </div>
              </details>
              <details
                className="transcript-settings"
                onToggle={(e) => setTranscriptOpen(e.currentTarget.open)}
              >
                <summary>Timing & transcript</summary>
                <div className="stack" style={{ paddingTop: 12 }}>
                  <label>
                    Subtitle delay (seconds){" "}
                    <input
                      aria-label="Subtitle delay in seconds"
                      type="number"
                      min="-600"
                      max="600"
                      step="0.5"
                      value={offset}
                      onChange={(e) => {
                        const n = Number(e.target.value);
                        if (Number.isFinite(n)) void changeOffset(n);
                      }}
                    />
                  </label>
                  <p className="muted">
                    Positive values show subtitles later.{" "}
                    {practice
                      ? "Sample timing resets when you reopen this page."
                      : "Timing is saved for this video."}
                  </p>
                  <div className="row">
                    <button
                      disabled={transcriptPage === 0}
                      onClick={() => setTranscriptPage((p) => p - 1)}
                    >
                      Previous sentences
                    </button>
                    <button
                      disabled={pageStart + pageSize >= cues.length}
                      onClick={() => setTranscriptPage((p) => p + 1)}
                    >
                      Next sentences
                    </button>
                    <button
                      onClick={() =>
                        setTranscriptPage(
                          Math.floor(Math.max(0, currentIndex) / pageSize),
                        )
                      }
                    >
                      Jump to current sentence
                    </button>
                  </div>
                  <p className="muted">
                    Sentences {pageStart + 1}–
                    {Math.min(pageStart + pageSize, cues.length)} of{" "}
                    {cues.length}
                  </p>
                  <div style={{ maxHeight: 180, overflowY: "auto" }}>
                    {transcriptOpen &&
                      cues.slice(pageStart, pageStart + pageSize).map((c) => (
                        <button
                          style={{
                            display: "block",
                            width: "100%",
                            textAlign: "left",
                            marginBottom: 4,
                          }}
                          key={c.id}
                          onClick={() => replay(c)}
                        >
                          <small>
                            {Math.floor(c.start / 60)}:
                            {String(Math.floor(c.start % 60)).padStart(2, "0")}
                          </small>{" "}
                          {c.text}
                        </button>
                      ))}
                  </div>
                </div>
              </details>
            </>
          )}
          {selected && (
            <section className="line stack" aria-label="Selected phrase">
              <div className="selection-heading">
                <div>
                  <p className="explanation-label">
                    {selectedWordCount === 1 ? "Word study" : "Phrase study"}
                  </p>
                  <h2 lang="fr">{selected}</h2>
                </div>
              </div>
              <p className="muted">From: {sentence}</p>
              {!prefs.aiConsent && (
                <div className="card stack">
                  <p>
                    For translation or word study, the selected text, its
                    sentence, and your level are sent to ParleSprint and Google
                    Gemini. AI can make mistakes.
                  </p>
                  <button
                    disabled={consentBusy}
                    onClick={() => void allowExplanations()}
                  >
                    {consentBusy
                      ? "Enabling explanations…"
                      : "Allow explanations"}
                  </button>
                </div>
              )}
              <button onClick={() => void openConnection()}>
                Account connection for AI
              </button>
              <div className="caption-actions">
                <button
                  className="primary"
                  disabled={busy || consentBusy || !prefs.aiConsent}
                  onClick={() => void explain()}
                >
                  {busy ? "Explaining…" : "Explain in context"}
                </button>
                <button onClick={() => void saveWord()} disabled={saved}>
                  {saved ? "Saved ✓" : "Save phrase"}
                </button>
              </div>
              {explanation && (
                <div className="card stack">
                  {!meaningRevealed ? (
                    <button onClick={() => setMeaningRevealed(true)}>
                      Reveal meaning
                    </button>
                  ) : (
                    <>
                      <p className="muted">
                        AI explanations can make mistakes.
                      </p>
                      <div>
                        <p className="explanation-label">Meaning</p>
                        <p className="explanation-copy">
                          {explanation.meaning}
                        </p>
                      </div>
                      <div>
                        <p className="explanation-label">
                          {selectedWordCount === 1
                            ? "Part of speech & grammar"
                            : "Grammar & usage"}
                        </p>
                        <p className="explanation-copy">
                          {explanation.grammar}
                        </p>
                      </div>
                      <div>
                        <p className="explanation-label">
                          Try it in a sentence
                        </p>
                        <p className="explanation-copy" lang="fr">
                          {explanation.example}
                        </p>
                        <p className="muted">
                          {explanation.exampleTranslation}
                        </p>
                      </div>
                      <button onClick={() => setMeaningRevealed(false)}>
                        Hide meaning
                      </button>
                    </>
                  )}
                </div>
              )}
            </section>
          )}
          {(error || storageError) && (
            <p className="error" role="alert">
              {error || storageError}
            </p>
          )}
          {practice && <p className="muted">
            Fullscreen: leave fullscreen to use the companion. Subtitles stay on
            this device.
          </p>}
        </div>
      )}
      {!practice && prefs.placement === "floating" && !collapsed && (
        <button
          className="resize-handle"
          aria-label="Resize captions"
          title="Drag to resize captions. Use arrow keys to resize."
          onPointerDown={(event) => beginFloatingTransform("resize", event)}
          onKeyDown={(event) => {
            const delta = event.shiftKey ? 24 : 12;
            const directions = {
              ArrowLeft: [-delta, 0],
              ArrowRight: [delta, 0],
              ArrowUp: [0, -delta],
              ArrowDown: [0, delta],
            } as const;
            const change = directions[event.key as keyof typeof directions];
            if (change) {
              event.preventDefault();
              nudgeFloating("resize", change[0], change[1]);
            }
          }}
        >
          ↘
        </button>
      )}
    </aside>
  );
}
