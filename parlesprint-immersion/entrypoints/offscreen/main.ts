import { browser } from "wxt/browser";
import { liveTranscriptionUrl, websocketMessageText } from "../../lib/geminiLive";
import { resamplePcm16, rms, SilenceGate, TRANSCRIPTION_SAMPLE_RATE } from "../../lib/pcm";
import {
  isCurrentPlaybackTranscript,
  shouldCapturePlaybackAudio,
  type PlaybackClock,
} from "../../lib/playbackClock";

type LiveSocket = WebSocket;
interface CaptureConfig {
  streamId: string;
  tabId: number;
  clock: PlaybackClock;
  installationId: string;
  supabaseUrl: string;
  anonKey: string;
}

// Matches the token lifetime issued by immersion-live-token.
const SESSION_SECONDS = 180;
declare const __QA__: boolean;
const qaStats: Record<string, any> = { sent: 0, skipped: 0, flushes: 0, interim: 0, final: 0, notes: [] as string[] };
const qaNote = (note: string) => { if (typeof __QA__ !== "undefined" && __QA__ && qaStats.notes.length < 12) qaStats.notes.push(note); };
if (typeof __QA__ !== "undefined" && __QA__)
  setInterval(() => void browser.runtime.sendMessage({ type: "qa-live-stats", stats: { ...qaStats } }).catch(() => undefined), 1000);
let silenceGate = new SilenceGate();
let leadIn: Int16Array | undefined;
let config: CaptureConfig | undefined;
let stream: MediaStream | undefined;
let context: AudioContext | undefined;
let source: MediaStreamAudioSourceNode | undefined;
let processor: ScriptProcessorNode | undefined;
let silence: GainNode | undefined;
let socket: LiveSocket | undefined;
let rotateTimer: number | undefined;
let segmentTimer: number | undefined;
let connectGeneration = 0;
let segmentGeneration = 0;
let segmentRetries = 0;
let activeSessionExpiresAt = 0;
let clock: PlaybackClock = {
  currentTime: 0,
  paused: true,
  muted: false,
  playbackRate: 1,
  seeking: false,
  adShowing: false,
  epoch: 0,
  videoKey: "",
  observedAt: 0,
};
let status: "idle" | "connecting" | "listening" | "stopped" = "idle";
const intentionallyClosed = new WeakSet<WebSocket>();

const runtimeMessage = (message: Record<string, unknown>) =>
  browser.runtime.sendMessage(message).catch(() => undefined);

function setStatus(next: typeof status, error?: string) {
  status = next;
  if (config) {
    void runtimeMessage({
      type: "live-transcription-status",
      tabId: config.tabId,
      status: next,
      ...(error ? { error } : {}),
    });
  }
}

function mono(samples: AudioBuffer): Float32Array {
  const first = samples.getChannelData(0);
  if (samples.numberOfChannels < 2) return first;
  const second = samples.getChannelData(1);
  const result = new Float32Array(first.length);
  for (let i = 0; i < result.length; i++) result[i] = (first[i]! + second[i]!) / 2;
  return result;
}

function base64Pcm(pcm: Int16Array): string {
  const bytes = new Uint8Array(pcm.buffer, pcm.byteOffset, pcm.byteLength);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

function sendAudio(event: AudioProcessingEvent) {
  if (event.outputBuffer.numberOfChannels) {
    event.outputBuffer.getChannelData(0).fill(0);
  }
  if (!config || status !== "listening" || !shouldCapturePlaybackAudio(clock)) return;
  const current = socket;
  if (!current || current.readyState !== WebSocket.OPEN) return;
  const samples = mono(event.inputBuffer);
  const pcm = resamplePcm16(samples, context?.sampleRate ?? 48000);
  if (!pcm.length) return;
  // Silence is billed by the minute, so it is not uploaded. A short lead-in keeps word starts.
  const step = silenceGate.push(rms(samples), performance.now());
  if (step.flush) {
    qaStats.flushes++;
    current.send(JSON.stringify({ realtimeInput: { audioStreamEnd: true } }));
    return;
  }
  if (!step.send) {
    qaStats.skipped++;
    leadIn = pcm;
    return;
  }
  const frame = (data: Int16Array) => JSON.stringify({
    realtimeInput: { audio: { data: base64Pcm(data), mimeType: `audio/pcm;rate=${TRANSCRIPTION_SAMPLE_RATE}` } },
  });
  if (step.resumed && leadIn) current.send(frame(leadIn));
  leadIn = undefined;
  qaStats.sent++;
  current.send(frame(pcm));
}

async function requestToken(): Promise<{ token: string; expiresAt: string }> {
  if (!config) throw Error("Transcription has stopped.");
  const response = await fetch(`${config.supabaseUrl}/functions/v1/immersion-live-token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: config.anonKey,
      Authorization: `Bearer ${config.anonKey}`,
    },
    body: JSON.stringify({ consent: true, installationId: config.installationId }),
    signal: AbortSignal.timeout(15000),
  });
  qaNote(`token ${response.status}`);
  const result = await response.json().catch(() => ({}));
  if (!response.ok) {
    const code = typeof result?.error === "string" ? result.error : "";
    if (response.status === 429 || code === "daily_transcription_limit_reached")
      throw Error("Today’s live transcription allowance has been used. Try again tomorrow.");
    if (code === "transcription_provider_unavailable")
      throw Error("Google transcription is temporarily unavailable. Try again shortly.");
    throw Error("Could not start live French transcription. Check your connection and try again.");
  }
  if (typeof result?.token !== "string" || typeof result?.expiresAt !== "string")
    throw Error("The transcription service returned an invalid session.");
  return { token: result.token, expiresAt: result.expiresAt };
}

function connect(token: string, generation: number, segment: number, epoch: number): Promise<LiveSocket> {
  return new Promise((resolve, reject) => {
    // Google's ephemeral token is locked to this exact constrained session.
    const ws = new WebSocket(liveTranscriptionUrl(token));
    let settled = false;
    const isCurrentSegment = () =>
      !!config && generation === connectGeneration && segment === segmentGeneration &&
      isCurrentPlaybackTranscript(epoch, clock);
    const timeout = window.setTimeout(() => {
      if (settled) return;
      settled = true;
      intentionallyClosed.add(ws);
      ws.close();
      reject(Error("Google transcription took too long to connect."));
    }, 20000);
    ws.onopen = () => {
      qaNote("ws open");
      if (!config || generation !== connectGeneration || segment !== segmentGeneration) {
        intentionallyClosed.add(ws);
        ws.close();
        return;
      }
      ws.send(JSON.stringify({
        setup: {
          model: "models/gemini-3.5-transcribe-live",
          generationConfig: { responseModalities: ["TEXT"] },
          inputAudioTranscription: { languageCodes: ["fr-FR"], mode: "VERBATIM" },
        },
      }));
    };
    ws.onmessage = async (event) => {
      let message: any;
      try {
        message = JSON.parse(await websocketMessageText(event.data));
      } catch {
        if (!settled) {
          settled = true;
          window.clearTimeout(timeout);
          reject(Error("Google returned an unreadable transcription response."));
        }
        return;
      }
      if (message?.error) {
        if (!settled) {
          settled = true;
          window.clearTimeout(timeout);
          reject(Error("Google could not start the transcription session."));
        } else if (generation === connectGeneration) {
          void fail("Google transcription stopped unexpectedly. Start it again to continue.");
        }
        return;
      }
      if (message?.setupComplete) qaNote("setupComplete");
      if (message?.setupComplete && !settled) {
        settled = true;
        window.clearTimeout(timeout);
        resolve(ws);
        return;
      }
      if (!isCurrentSegment() || (settled && socket !== ws)) return;
      const currentConfig = config;
      if (!currentConfig) return;
      const content = message?.serverContent;
      const interim = content?.interimInputTranscription?.text;
      const final = content?.inputTranscription?.text;
      if (typeof interim === "string" && interim.trim()) {
        qaStats.interim++;
        void runtimeMessage({
          type: "live-transcription-interim",
          tabId: currentConfig.tabId,
          text: interim.trim(),
          at: clock.currentTime,
          epoch,
        });
      }
      if (typeof final === "string" && final.trim()) {
        qaStats.final++;
        void runtimeMessage({
          type: "live-transcription-final",
          tabId: currentConfig.tabId,
          text: final.trim(),
          at: clock.currentTime,
          epoch,
        });
      }
    };
    ws.onerror = () => {
      if (!settled) {
        settled = true;
        window.clearTimeout(timeout);
        reject(Error("Google transcription could not connect. Check the network and try again."));
      }
    };
    ws.onclose = () => {
      if (!settled) {
        settled = true;
        window.clearTimeout(timeout);
        reject(Error("Google closed the transcription connection before it was ready."));
      } else if (generation === connectGeneration && segment === segmentGeneration && !intentionallyClosed.has(ws)) {
        void recoverConnection("The live transcription connection closed. Reconnecting…");
      }
    };
  });
}

function closeSocket(target?: LiveSocket) {
  if (!target) return;
  intentionallyClosed.add(target);
  if (target.readyState === WebSocket.OPEN || target.readyState === WebSocket.CONNECTING)
    target.close();
}

function scheduleRenewal(delay = (SESSION_SECONDS - 45) * 1000) {
  if (rotateTimer) window.clearTimeout(rotateTimer);
  rotateTimer = window.setTimeout(() => void renewSession(), delay);
}

function scheduleSegmentReconnect(delay = 450) {
  if (segmentTimer) window.clearTimeout(segmentTimer);
  segmentTimer = window.setTimeout(() => {
    segmentTimer = undefined;
    void connectSegment();
  }, delay);
}

async function connectSegment() {
  qaNote(`connectSegment status=${status} allowed=${shouldCapturePlaybackAudio(clock)} paused=${clock.paused}`);
  if (!config || status !== "listening" || !shouldCapturePlaybackAudio(clock)) return;
  if (socket?.readyState === WebSocket.OPEN) return;
  const generation = connectGeneration;
  const segment = segmentGeneration;
  const epoch = clock.epoch;
  try {
    const issued = await requestToken();
    if (!config || status !== "listening" || generation !== connectGeneration ||
        segment !== segmentGeneration || epoch !== clock.epoch || !shouldCapturePlaybackAudio(clock)) return;
    const replacement = await connect(issued.token, generation, segment, epoch);
    if (!config || status !== "listening" || generation !== connectGeneration ||
        segment !== segmentGeneration || epoch !== clock.epoch || !shouldCapturePlaybackAudio(clock)) {
      closeSocket(replacement);
      return;
    }
    const old = socket;
    socket = replacement;
    activeSessionExpiresAt = Date.parse(issued.expiresAt) || 0;
    segmentRetries = 0;
    closeSocket(old);
    scheduleRenewal();
  } catch (error) {
    qaNote(`connect error: ${error instanceof Error ? error.message : String(error)}`);
    if (!config || generation !== connectGeneration || segment !== segmentGeneration || epoch !== clock.epoch) return;
    if (segmentRetries < 2) {
      segmentRetries++;
      scheduleSegmentReconnect(900 * segmentRetries);
      return;
    }
    await fail(error instanceof Error ? error.message : "Could not reconnect live transcription.");
  }
}

async function renewSession() {
  if (!config || status !== "listening") return;
  if (!shouldCapturePlaybackAudio(clock)) {
    // Avoid spending a new provider session while the viewer is paused, seeking, or watching an ad.
    scheduleRenewal(20_000);
    return;
  }
  const generation = connectGeneration;
  const segment = segmentGeneration;
  const epoch = clock.epoch;
  try {
    const issued = await requestToken();
    const replacement = await connect(issued.token, generation, segment, epoch);
    if (!config || status !== "listening" || generation !== connectGeneration ||
        segment !== segmentGeneration || epoch !== clock.epoch) {
      closeSocket(replacement);
      return;
    }
    const old = socket;
    socket = replacement;
    activeSessionExpiresAt = Date.parse(issued.expiresAt) || 0;
    closeSocket(old);
    scheduleRenewal();
  } catch {
    if (socket?.readyState === WebSocket.OPEN) {
      scheduleRenewal(30_000);
      return;
    }
    recoverConnection("Could not renew live transcription. Reconnecting…");
  }
}

function invalidateSegment() {
  segmentGeneration++;
  silenceGate = new SilenceGate();
  leadIn = undefined;
  segmentRetries = 0;
  if (segmentTimer) window.clearTimeout(segmentTimer);
  segmentTimer = undefined;
  if (rotateTimer) window.clearTimeout(rotateTimer);
  rotateTimer = undefined;
  const old = socket;
  socket = undefined;
  closeSocket(old);
}

function recoverConnection(_message: string) {
  if (!config || status !== "listening") return;
  invalidateSegment();
  if (shouldCapturePlaybackAudio(clock)) scheduleSegmentReconnect(350);
}

function updateClock(data: Record<string, any>) {
  if (!config || data.tabId !== config.tabId) return;
  if (!Number.isFinite(data.currentTime) || typeof data.paused !== "boolean") return;
  const previous = clock;
  const next: PlaybackClock = {
    currentTime: Math.max(0, Number(data.currentTime)),
    paused: data.paused,
    muted: data.muted === true,
    playbackRate: Number.isFinite(data.playbackRate) ? Math.max(0.1, Math.min(4, Number(data.playbackRate))) : 1,
    seeking: data.seeking === true,
    adShowing: data.adShowing === true,
    epoch: Number.isSafeInteger(data.epoch) ? Math.max(0, Number(data.epoch)) : previous.epoch,
    videoKey: typeof data.videoKey === "string" ? data.videoKey.slice(0, 200) : previous.videoKey,
    observedAt: Number.isFinite(data.observedAt) ? Number(data.observedAt) : previous.observedAt,
  };
  clock = next;
  const wasAllowed = shouldCapturePlaybackAudio(previous);
  const nowAllowed = shouldCapturePlaybackAudio(next);
  const newSegment = next.epoch !== previous.epoch;
  const boundary = newSegment || previous.adShowing !== next.adShowing ||
    previous.seeking !== next.seeking || previous.muted !== next.muted;
  if (boundary) {
    invalidateSegment();
    if (nowAllowed) scheduleSegmentReconnect(450);
  } else if (wasAllowed && !nowAllowed && (next.seeking || next.adShowing)) {
    invalidateSegment();
  } else if (!wasAllowed && nowAllowed && (
    socket?.readyState !== WebSocket.OPEN ||
    (activeSessionExpiresAt > 0 && Date.now() + 15_000 >= activeSessionExpiresAt)
  )) {
    invalidateSegment();
    scheduleSegmentReconnect(250);
  }
  if (wasAllowed && nowAllowed && activeSessionExpiresAt && Date.now() + 15_000 >= activeSessionExpiresAt) {
    invalidateSegment();
    scheduleSegmentReconnect(250);
  }
}

async function stopCapture(send = true) {
  connectGeneration++;
  segmentGeneration++;
  if (rotateTimer) window.clearTimeout(rotateTimer);
  if (segmentTimer) window.clearTimeout(segmentTimer);
  rotateTimer = undefined;
  segmentTimer = undefined;
  activeSessionExpiresAt = 0;
  const oldSocket = socket;
  socket = undefined;
  closeSocket(oldSocket);
  if (processor) processor.onaudioprocess = null;
  try { processor?.disconnect(); } catch { /* already disconnected */ }
  try { silence?.disconnect(); } catch { /* already disconnected */ }
  try { source?.disconnect(); } catch { /* already disconnected */ }
  try { context?.close(); } catch { /* already closed */ }
  stream?.getTracks().forEach((track) => track.stop());
  processor = undefined;
  silence = undefined;
  source = undefined;
  context = undefined;
  stream = undefined;
  const oldConfig = config;
  config = undefined;
  status = "stopped";
  if (send && oldConfig) {
    void runtimeMessage({ type: "live-transcription-status", tabId: oldConfig.tabId, status: "stopped" });
  }
}

async function fail(error: string) {
  const tabId = config?.tabId;
  await stopCapture(false);
  if (typeof tabId === "number") {
    void runtimeMessage({ type: "live-transcription-status", tabId, status: "stopped", error });
  }
}

async function startCapture(next: CaptureConfig) {
  await stopCapture(false);
  config = next;
  clock = next.clock;
  status = "connecting";
  setStatus("connecting");
  try {
    const constraints = {
      audio: {
        mandatory: {
          chromeMediaSource: "tab",
          chromeMediaSourceId: next.streamId,
        },
      },
      video: false,
    } as unknown as MediaStreamConstraints;
    stream = await navigator.mediaDevices.getUserMedia(constraints);
    context = new AudioContext();
    source = context.createMediaStreamSource(stream);
    processor = context.createScriptProcessor(4096, 2, 1);
    silence = context.createGain();
    silence.gain.value = 0;
    processor.onaudioprocess = sendAudio;
    // Tab capture suppresses the original tab sound; route it back to speakers.
    source.connect(context.destination);
    source.connect(processor);
    processor.connect(silence);
    silence.connect(context.destination);
    await context.resume();

    status = "listening";
    setStatus("listening");
    if (shouldCapturePlaybackAudio(clock)) scheduleSegmentReconnect(0);
  } catch (error) {
    await fail(error instanceof Error ? error.message : "Unable to start transcription.");
  }
}

browser.runtime.onMessage.addListener((message) => {
  if (!message || typeof message !== "object") return;
  const data = message as Record<string, any>;
  if (data.type === "live-offscreen-start") {
    if (
      typeof data.streamId !== "string" ||
      !Number.isInteger(data.tabId) ||
      !data.clock || typeof data.clock !== "object" ||
      !Number.isFinite(data.clock.currentTime) || typeof data.clock.paused !== "boolean" ||
      typeof data.clock.muted !== "boolean" ||
      !Number.isSafeInteger(data.clock.epoch) ||
      typeof data.installationId !== "string" ||
      typeof data.supabaseUrl !== "string" ||
      typeof data.anonKey !== "string"
    ) return;
    void startCapture(data as CaptureConfig);
  } else if (data.type === "live-offscreen-stop") {
    void stopCapture();
  } else if (data.type === "live-offscreen-clock" && config && data.tabId === config.tabId) {
    updateClock(data);
  }
});
