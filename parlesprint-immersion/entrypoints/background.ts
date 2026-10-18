import { translateFrench } from "../lib/freeTranslate";
import { limitMessage } from "../lib/plan";
import { browser } from "wxt/browser";
import { defineBackground } from "wxt/utils/define-background";
import {
  normalizePreferences as preferences,
  applyPreferencesPatch,
  type Explanation,
  type Word,
} from "../lib/types";
import {
  isCurrentPlaybackTranscript,
  playbackHoldReason,
  type PlaybackClock,
} from "../lib/playbackClock";
const base = import.meta.env.WXT_PUBLIC_SUPABASE_URL as string | undefined;
const anon = import.meta.env.WXT_PUBLIC_SUPABASE_ANON_KEY as string | undefined;
const chromeApis = browser as any;
interface LiveSession {
  tabId: number;
  hostname: string;
  status: "connecting" | "listening";
  holdReason?: ReturnType<typeof playbackHoldReason>;
}
let liveSession: LiveSession | undefined;
let offscreenTask: Promise<void> | undefined;
let liveStartTask: Promise<unknown> | undefined;
const videoClocks = new Map<number, PlaybackClock>();
let storageQueue: Promise<unknown> = Promise.resolve();
function serialize<T>(action: () => Promise<T>): Promise<T> {
  const result = storageQueue.then(action, action);
  storageQueue = result.catch(() => {});
  return result;
}
const inFlight = new Map<string, Promise<unknown>>();
// Invalidates network work when auth changes or consent is withdrawn.
let generation = 0;
let refreshTask: { generation: number; promise: Promise<string> } | undefined;
const invalidated = () =>
  Error("Your account or AI consent changed. Please try again.");
function assertGeneration(expected: number) {
  if (expected !== generation) throw invalidated();
}
function object(value: unknown): value is Record<string, any> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
function validSession(value: unknown): value is Session {
  return (
    object(value) &&
    typeof value.access_token === "string" &&
    value.access_token.length > 0 &&
    value.access_token.length <= 16384 &&
    typeof value.refresh_token === "string" &&
    value.refresh_token.length > 0 &&
    value.refresh_token.length <= 16384 &&
    typeof value.expires_at === "number" &&
    Number.isFinite(value.expires_at)
  );
}
function word(raw: unknown): Word | undefined {
  if (
    !object(raw) ||
    typeof raw.id !== "string" ||
    !raw.id ||
    raw.id.length > 512 ||
    typeof raw.text !== "string" ||
    !raw.text.trim() ||
    raw.text.length > 4000 ||
    typeof raw.sentence !== "string" ||
    raw.sentence.length > 4000 ||
    !["A1", "A2", "B1", "B2"].includes(raw.level) ||
    typeof raw.savedAt !== "number" ||
    !Number.isFinite(raw.savedAt) ||
    raw.savedAt < 0 ||
    (raw.explanation !== undefined && !validExplanation(raw.explanation))
  )
    return;
  return {
    id: raw.id,
    text: raw.text,
    sentence: raw.sentence,
    level: raw.level,
    savedAt: raw.savedAt,
    ...(raw.explanation ? { explanation: raw.explanation } : {}),
  };
}
function explanationCache(raw: unknown): Record<string, Explanation> {
  return Object.fromEntries(
    object(raw)
      ? Object.entries(raw)
          .filter(
            ([key, value]) => key.length <= 12000 && validExplanation(value),
          )
          .slice(-300)
      : [],
  );
}
function validTranslation(value: unknown): value is { translation: string } {
  return object(value) && typeof value.translation === "string" &&
    !!value.translation.trim() && value.translation.length <= 4000;
}
function translationCache(raw: unknown): Record<string, string> {
  return Object.fromEntries(
    object(raw)
      ? Object.entries(raw)
          .filter(([key, value]) => key.length <= 12000 && typeof value === "string" && value.trim().length > 0 && value.length <= 4000)
          .slice(-300)
      : [],
  );
}
function email(raw: unknown): raw is string {
  return (
    typeof raw === "string" &&
    raw.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw)
  );
}
async function ensureOffscreen() {
  if (offscreenTask) return offscreenTask;
  offscreenTask = (async () => {
    const contexts = await chromeApis.runtime.getContexts({
      contextTypes: ["OFFSCREEN_DOCUMENT"],
      documentUrls: [chromeApis.runtime.getURL("/offscreen.html")],
    });
    if (!contexts.length) {
      await chromeApis.offscreen.createDocument({
        url: "/offscreen.html",
        reasons: ["USER_MEDIA"],
        justification: "Capture audio from the active video tab for live French transcription.",
      });
    }
  })().finally(() => {
    offscreenTask = undefined;
  });
  return offscreenTask;
}
async function installationId() {
  const current = (await browser.storage.local.get("transcriptionInstallationId"))
    .transcriptionInstallationId;
  if (typeof current === "string" && /^[0-9a-f-]{36}$/i.test(current)) return current;
  const next = crypto.randomUUID();
  await browser.storage.local.set({ transcriptionInstallationId: next });
  return next;
}
async function stopLiveTranscription() {
  const previous = liveSession;
  liveSession = undefined;
  if (previous) videoClocks.delete(previous.tabId);
  try {
    await browser.runtime.sendMessage({ type: "live-offscreen-stop" });
  } catch { /* the offscreen page may already be closed */ }
  await browser.storage.local.remove("liveSession");
  if (previous) {
    await browser.tabs.sendMessage(previous.tabId, {
      type: "live-transcription-status",
      tabId: previous.tabId,
      status: "stopped",
    }).catch(() => undefined);
  }
}
async function startLiveTranscription() {
  if (liveStartTask) return liveStartTask;
  liveStartTask = (async () => {
    const consent = (await browser.storage.local.get("transcriptionLiveConsent"))
      .transcriptionLiveConsent;
    if (consent !== true) throw Error("Review and accept the audio transcription notice first.");
    if (!base || !anon) throw Error("Live transcription is not configured in this build.");
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    if (!tab?.id || !tab.url || !/^https?:\/\//i.test(tab.url))
      throw Error("Open a video in a regular website tab, then start again.");
    const pageUrl = new URL(tab.url);

    if (liveSession) await stopLiveTranscription();
    try {
      await chromeApis.scripting.insertCSS({
        target: { tabId: tab.id },
        files: ["content-scripts/content.css"],
      });
      await chromeApis.scripting.executeScript({
        target: { tabId: tab.id },
        files: ["content-scripts/content.js"],
      });
    } catch {
      throw Error("This browser page does not allow extensions. Try a normal video page.");
    }
    let clock = videoClocks.get(tab.id) ?? {
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
    try {
      const fromPage = await browser.tabs.sendMessage(tab.id, { type: "live-get-clock" });
      if (fromPage?.hasVideo !== true)
        throw Error("Start a video on this page first. ParleSprint captures the current tab’s audio.");
      if (typeof fromPage?.currentTime === "number" && Number.isFinite(fromPage.currentTime)) {
        clock = {
          currentTime: Math.max(0, fromPage.currentTime),
          paused: fromPage.paused === true,
          muted: fromPage.muted === true,
          playbackRate: Number.isFinite(fromPage.playbackRate) ? fromPage.playbackRate : 1,
          seeking: fromPage.seeking === true,
          adShowing: fromPage.adShowing === true,
          epoch: Number.isSafeInteger(fromPage.epoch) ? Math.max(0, fromPage.epoch) : 0,
          videoKey: typeof fromPage.videoKey === "string" ? fromPage.videoKey.slice(0, 200) : "",
          observedAt: Number.isFinite(fromPage.observedAt) ? Number(fromPage.observedAt) : 0,
        };
      }
    } catch { /* the video may not be on the page yet; start at zero */ }

    await ensureOffscreen();
    const streamId = await chromeApis.tabCapture.getMediaStreamId({ targetTabId: tab.id });
    liveSession = {
      tabId: tab.id,
      hostname: pageUrl.hostname,
      status: "connecting",
      holdReason: playbackHoldReason(clock),
    };
    await browser.storage.local.set({ liveSession });
    videoClocks.set(tab.id, clock);
    await browser.runtime.sendMessage({
      type: "live-offscreen-start",
      streamId,
      tabId: tab.id,
      clock,
      installationId: await installationId(),
      supabaseUrl: base,
      anonKey: anon,
    });
    return { ok: true, status: "connecting", hostname: pageUrl.hostname };
  })().catch(async (error) => {
    await browser.storage.local.remove("liveSession");
    liveSession = undefined;
    throw error;
  }).finally(() => {
    liveStartTask = undefined;
  });
  return liveStartTask;
}
interface Account {
  id: string;
  email?: string;
  displayName?: string;
  provider: string;
}
function safeAccount(raw: unknown): Account | undefined {
  if (!object(raw) || typeof raw.id !== "string" || raw.id.length > 128) return;
  const metadata = object(raw.user_metadata) ? raw.user_metadata : {};
  const app = object(raw.app_metadata) ? raw.app_metadata : {};
  const name = metadata.full_name ?? metadata.name;
  return {
    id: raw.id,
    ...(email(raw.email) ? { email: raw.email } : {}),
    ...(typeof name === "string" && name.trim()
      ? { displayName: name.trim().slice(0, 120) }
      : {}),
    provider: ["google", "apple", "email"].includes(app.provider)
      ? app.provider
      : "email",
  };
}
interface Session {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  account?: Account;
}
async function api(path: string, body: unknown, token?: string) {
  if (!base || !anon)
    throw Error(
      "AI is not configured in this build. You can still save and replay subtitles.",
    );
  const response = await fetch(`${base}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: anon,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(25000),
  });
  const result = response.status === 204 ? {} : await response.json();
  if (!response.ok)
    throw Error(
      result.error === "daily_explanation_limit_reached"
        ? limitMessage("explain")
        : response.status === 429
        ? "The AI service is busy right now. Please try again shortly."
        : (result.error_description ??
            result.msg ??
            result.error ??
            "Explanation service is unavailable. Please try again."),
    );
  return result;
}
async function storeSession(
  raw: unknown,
  expected: number,
  clearCache = false,
) {
  if (
    !object(raw) ||
    typeof raw.expires_in !== "number" ||
    !Number.isFinite(raw.expires_in) ||
    raw.expires_in <= 0 ||
    raw.expires_in > 31536000
  )
    throw Error("Sign-in did not return a valid session.");
  const session = {
    access_token: raw.access_token,
    refresh_token: raw.refresh_token,
    expires_at: Date.now() + raw.expires_in * 1000,
    ...(safeAccount(raw.user) ? { account: safeAccount(raw.user) } : {}),
  };
  if (!validSession(session)) throw Error("Sign-in did not return a session.");
  return serialize(async () => {
    assertGeneration(expected);
    if (clearCache) await browser.storage.local.remove(["explanationCache", "translationCache"]);
    assertGeneration(expected);
    await browser.storage.local.set({ session });
    assertGeneration(expected);
    return session;
  });
}
async function token(expected: number) {
  assertGeneration(expected);
  const data = await browser.storage.local.get("session");
  assertGeneration(expected);
  const session = data.session;
  if (!validSession(session))
    throw Error(
      "Connect your ParleSprint account in the extension popup to use explanations.",
    );
  if (session.expires_at > Date.now() + 60000) return session.access_token;
  if (refreshTask?.generation === expected) return refreshTask.promise;
  const promise = (async () => {
    try {
      return (
        await storeSession(
          await api("/auth/v1/token?grant_type=refresh_token", {
            refresh_token: session.refresh_token,
          }),
          expected,
        )
      ).access_token;
    } catch (error) {
      assertGeneration(expected);
      // A transient offline failure must not destroy a valid refresh token.
      throw Error(
        "Unable to refresh your session. Check your connection or sign in again.",
      );
    }
  })();
  const task = { generation: expected, promise };
  refreshTask = task;
  try {
    return await promise;
  } finally {
    if (refreshTask === task) refreshTask = undefined;
  }
}
function validExplanation(value: unknown): value is Explanation {
  return (
    !!value &&
    typeof value === "object" &&
    ["meaning", "grammar", "example", "exampleTranslation"].every(
      (k) =>
        typeof (value as any)[k] === "string" &&
        (value as any)[k].length <= 4000,
    )
  );
}
type Provider = "google" | "apple";
let pendingOAuth:
  | {
      generation: number;
      redirect: string;
      verifier: string;
      state: string;
      started: number;
      consumed: boolean;
    }
  | undefined;
function base64url(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}
async function authCapabilities() {
  if (!base || !anon)
    return {
      google: false,
      apple: false,
      error: "Account connection is not configured in this build.",
    };
  const response = await fetch(`${base}/auth/v1/settings`, {
    headers: { apikey: anon },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok)
    throw Error("Unable to check account providers. Try again shortly.");
  const settings = await response.json();
  return {
    google:
      settings.external?.google === true &&
      import.meta.env.WXT_PUBLIC_GOOGLE_OAUTH_ENABLED === "true",
    googleReason:
      "Google account connection is waiting for the secure extension callback configuration. Use your existing email account for now.",
    // Native Apple ID tokens work, but the current web authorize endpoint was
    // verified to lack its OAuth secret. Never advertise native-only settings.
    apple:
      settings.external?.apple === true &&
      import.meta.env.WXT_PUBLIC_APPLE_OAUTH_ENABLED === "true",
    appleReason:
      "Apple browser sign-in needs additional provider configuration. Use Google or your existing email account.",
  };
}
async function connectOAuth(provider: Provider) {
  if (pendingOAuth)
    throw Error("A sign-in window is already open. Finish or close it first.");
  const before = generation;
  const capabilities = await authCapabilities();
  assertGeneration(before);
  if (!capabilities[provider])
    throw Error(
      provider === "apple"
        ? capabilities.appleReason
        : (capabilities.googleReason ??
            "Google sign-in is currently unavailable."),
    );
  if (pendingOAuth)
    throw Error("A sign-in window is already open. Finish or close it first.");
  if (!browser.identity?.launchWebAuthFlow)
    throw Error("This browser cannot open secure account sign-in.");
  const state = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = base64url(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)),
    ),
  );
  assertGeneration(before);
  if (pendingOAuth)
    throw Error("A sign-in window is already open. Finish or close it first.");
  const redirect = new URL(browser.identity.getRedirectURL("oauth"));
  redirect.searchParams.set("state", state);
  const flow = {
    generation: ++generation,
    redirect: redirect.href,
    verifier,
    state,
    started: Date.now(),
    consumed: false,
  };
  pendingOAuth = flow;
  inFlight.clear();
  try {
    const authorize = new URL(`${base}/auth/v1/authorize`);
    authorize.searchParams.set("provider", provider);
    authorize.searchParams.set("redirect_to", flow.redirect);
    authorize.searchParams.set("code_challenge", challenge);
    authorize.searchParams.set("code_challenge_method", "s256");
    let returned: string | undefined;
    try {
      returned = await browser.identity.launchWebAuthFlow({
        url: authorize.href,
        interactive: true,
      });
    } catch {
      throw Error(
        "Sign-in was cancelled or could not finish. Try again when ready.",
      );
    }
    assertGeneration(flow.generation);
    if (!returned || Date.now() - flow.started > 10 * 60 * 1000)
      throw Error("Sign-in expired or was cancelled. Please try again.");
    const callback = new URL(returned);
    if (
      callback.origin !== redirect.origin ||
      callback.pathname !== redirect.pathname ||
      callback.hash ||
      callback.searchParams.getAll("state").length !== 1 ||
      callback.searchParams.get("state") !== flow.state
    )
      throw Error(
        "The sign-in response could not be verified. Please try again.",
      );
    if (callback.searchParams.has("error"))
      throw Error("The provider did not complete sign-in. Please try again.");
    const codes = callback.searchParams.getAll("code");
    if (
      codes.length !== 1 ||
      !codes[0] ||
      codes[0].length > 2048 ||
      [...callback.searchParams.keys()].some(
        (key) => !["state", "code"].includes(key),
      )
    )
      throw Error(
        "The sign-in response could not be verified. Please try again.",
      );
    // Consume local flow before exchanging the one-use server authorization code.
    if (flow.consumed)
      throw Error("This sign-in response was already used. Please try again.");
    flow.consumed = true;
    const verifier = flow.verifier;
    flow.verifier = "";
    const raw = await api("/auth/v1/token?grant_type=pkce", {
      auth_code: codes[0],
      code_verifier: verifier,
    });
    assertGeneration(flow.generation);
    await storeSession(raw, flow.generation, true);
    return { ok: true };
  } finally {
    if (pendingOAuth === flow) pendingOAuth = undefined;
  }
}
export default defineBackground(() => {
  browser.runtime.onInstalled.addListener((details) => {
    if (details.reason !== "install") return;
    // A local marker and serialized check protect against duplicate install events.
    return serialize(async () => {
      if (
        (await browser.storage.local.get("firstPracticeOpened"))
          .firstPracticeOpened === true
      )
        return;
      await browser.tabs.create({
        url: browser.runtime.getURL("/practice.html"),
      });
      await browser.storage.local.set({ firstPracticeOpened: true });
    }).catch(() => {});
  });
  browser.runtime.onMessage.addListener((message, sender) => {
    if (sender.id !== browser.runtime.id) return;
    if (!object(message) || typeof message.type !== "string")
      return Promise.resolve({ error: "Invalid request." });
    const offscreenUrl = chromeApis.runtime.getURL("/offscreen.html");
    const fromOffscreen = sender.url === offscreenUrl;
    if (message.type === "live-video-clock") {
      const tabId = sender.tab?.id;
      if (typeof tabId === "number" && liveSession?.tabId === tabId &&
          Number.isFinite(message.currentTime) && typeof message.paused === "boolean") {
        const value: PlaybackClock = {
          currentTime: Math.max(0, Number(message.currentTime)),
          paused: message.paused,
          muted: message.muted === true,
          playbackRate: Number.isFinite(message.playbackRate)
            ? Math.max(0.1, Math.min(4, Number(message.playbackRate)))
            : 1,
          seeking: message.seeking === true,
          adShowing: message.adShowing === true,
          epoch: Number.isSafeInteger(message.epoch) ? Math.max(0, Number(message.epoch)) : 0,
          videoKey: typeof message.videoKey === "string" ? message.videoKey.slice(0, 200) : "",
          observedAt: Number.isFinite(message.observedAt) ? Number(message.observedAt) : 0,
        };
        videoClocks.set(tabId, value);
        const holdReason = playbackHoldReason(value);
        const holdChanged = liveSession.holdReason !== holdReason;
        liveSession.holdReason = holdReason;
        if (holdChanged) {
          void browser.tabs.sendMessage(tabId, {
            type: "live-transcription-status",
            status: liveSession.status,
            holdReason,
            epoch: value.epoch,
          }).catch(() => undefined);
        }
        return browser.runtime.sendMessage({ type: "live-offscreen-clock", tabId, ...value });
      }
      return Promise.resolve({ ok: true });
    }
    if (message.type === "live-transcription-status" && fromOffscreen) {
      const tabId = Number(message.tabId);
      if (!liveSession || liveSession.tabId !== tabId) return Promise.resolve({ ok: true });
      if (message.status === "listening" || message.status === "connecting") {
        liveSession.status = message.status;
        void browser.storage.local.set({ liveSession });
      } else {
        liveSession = undefined;
        void browser.storage.local.remove("liveSession");
      }
      const holdReason = videoClocks.get(tabId)
        ? playbackHoldReason(videoClocks.get(tabId)!)
        : null;
      return browser.tabs.sendMessage(tabId, { ...message, holdReason }).catch(() => undefined);
    }
    if ((message.type === "live-transcription-interim" || message.type === "live-transcription-final") && fromOffscreen) {
      const tabId = Number(message.tabId);
      if (!liveSession || liveSession.tabId !== tabId || typeof message.text !== "string" ||
          !message.text.trim() || message.text.length > 2000) return Promise.resolve({ ok: true });
      const clock = videoClocks.get(tabId);
      if (!clock || !isCurrentPlaybackTranscript(message.epoch, clock))
        return Promise.resolve({ ok: true });
      const at = clock.currentTime;
      return browser.tabs.sendMessage(tabId, {
        type: message.type,
        tabId,
        text: message.text.trim(),
        at: Number.isFinite(at) ? at : 0,
        epoch: clock.epoch,
      }).catch(() => undefined);
    }
    // Invalidate immediately, before awaiting either storage or a network request.
    if (
      message.type === "update-prefs" &&
      object(message.patch) &&
      message.patch.aiConsent === false
    ) {
      generation++;
      inFlight.clear();
    }
    return (async () => {
      try {
        if (["update-prefs", "save-word", "remove-word"].includes(message.type))
          return await serialize(async () => {
            if (message.type === "update-prefs") {
              const old = (await browser.storage.local.get("prefs")).prefs;
              if (!object(message.patch)) throw Error("Invalid preferences.");
              const prefs = applyPreferencesPatch(old, message.patch);
              await browser.storage.local.set({ prefs });
              return { prefs };
            }
            const data = await browser.storage.local.get("words");
            let words = Array.isArray(data.words)
              ? data.words
                  .map(word)
                  .filter((w): w is Word => !!w)
                  .slice(0, 2000)
              : [];
            if (message.type === "save-word") {
              const w = word(message.word);
              if (!w) throw Error("Invalid vocabulary.");
              words = [w, ...words.filter((x) => x.id !== w.id)].slice(0, 2000);
            } else {
              if (
                typeof message.id !== "string" ||
                !message.id ||
                message.id.length > 512
              )
                throw Error("Invalid vocabulary identifier.");
              words = words.filter((w) => w.id !== message.id);
            }
            await browser.storage.local.set({ words });
            return { words };
          });
        if (message.type === "lookup") {
          if (typeof message.text !== "string" || !message.text.trim() || message.text.length > 600)
            throw Error("Nothing to translate.");
          const meaning = await translateFrench(message.text);
          if (!meaning) throw Error("No translation found.");
          return { meaning };
        }
        if (message.type === "open-practice") {
          await browser.tabs.create({
            url: browser.runtime.getURL("/practice.html"),
          });
          return { ok: true };
        }
        if (message.type === "open-connection") {
          await browser.tabs.create({
            url: browser.runtime.getURL("/popup.html") + "#account",
          });
          return { ok: true };
        }
        const popupURL = browser.runtime.getURL("/popup.html");
        const fromPopup =
          sender.url === popupURL || sender.url === `${popupURL}#account`;
        if (message.type === "start-live-transcription") {
          if (!fromPopup) throw Error("Open the extension popup and press Start from there.");
          return await startLiveTranscription();
        }
        if (message.type === "stop-live-transcription") {
          if (!fromPopup) throw Error("Open the extension popup to stop transcription.");
          await stopLiveTranscription();
          return { ok: true };
        }
        if (message.type === "set-live-transcription-consent") {
          if (!fromPopup) throw Error("Open the extension popup to change audio consent.");
          const accepted = message.accepted === true;
          if (!accepted) await stopLiveTranscription();
          await browser.storage.local.set({ transcriptionLiveConsent: accepted });
          return { ok: true };
        }
        if (message.type === "auth-status") {
          const session = (await browser.storage.local.get("session")).session;
          if (!validSession(session)) return { linked: false };
          // Identity is display-only and never becomes model input or authorization.
          const saved = session.account;
          const account =
            object(saved) && typeof saved.id === "string"
              ? {
                  id: saved.id.slice(0, 128),
                  ...(email(saved.email) ? { email: saved.email } : {}),
                  ...(typeof saved.displayName === "string"
                    ? { displayName: saved.displayName.slice(0, 120) }
                    : {}),
                  provider: ["google", "apple", "email"].includes(
                    saved.provider,
                  )
                    ? saved.provider
                    : "email",
                }
              : undefined;
          return { linked: true, ...(fromPopup && account ? { account } : {}) };
        }
        if (message.type === "auth-capabilities")
          return await authCapabilities();
        if (
          ["sign-in", "verify", "sign-out", "password", "oauth"].includes(
            message.type,
          ) &&
          !fromPopup
        )
          throw Error("Open the extension popup to connect your account.");
        if (message.type === "oauth") {
          if (message.provider !== "google" && message.provider !== "apple")
            throw Error("Choose a supported account provider.");
          return await connectOAuth(message.provider);
        }
        if (message.type === "password") {
          if (
            !email(message.email) ||
            typeof message.password !== "string" ||
            !message.password ||
            message.password.length > 256
          )
            throw Error("Enter your account email and password.");
          const expected = ++generation;
          inFlight.clear();
          await storeSession(
            await api("/auth/v1/token?grant_type=password", {
              email: message.email,
              password: message.password,
            }),
            expected,
            true,
          );
          return { ok: true };
        }
        if (message.type === "sign-in") {
          if (!email(message.email))
            throw Error("Enter a valid email address.");
          await api("/auth/v1/otp", {
            email: message.email,
            create_user: true,
          });
          return { ok: true };
        }
        if (message.type === "verify") {
          if (
            !email(message.email) ||
            typeof message.token !== "string" ||
            !/^\d{6,10}$/.test(message.token)
          )
            throw Error("Enter a valid email and verification code.");
          const expected = ++generation;
          inFlight.clear();
          await storeSession(
            await api("/auth/v1/verify", {
              email: message.email,
              token: message.token,
              type: "email",
            }),
            expected,
            true,
          );
          return { ok: true };
        }
        if (message.type === "sign-out") {
          generation++;
          inFlight.clear();
          const s = await serialize(async () => {
            const current = (await browser.storage.local.get("session"))
              .session;
            await browser.storage.local.remove(["session", "explanationCache", "translationCache"]);
            return current;
          });
          // Local sign-out succeeds offline and does not wait for the server.
          if (validSession(s))
            void api("/auth/v1/logout", {}, s.access_token).catch(() => {});
          return { ok: true };
        }
        const translationMode = message.type === "translate";
        if (!translationMode && message.type !== "explain") throw Error("Unsupported request.");
        const expected = generation;
        if (
          typeof message.text !== "string" ||
          !message.text.trim() ||
          message.text.length > (translationMode ? 1600 : 240) ||
          typeof message.sentence !== "string" ||
          message.sentence.length > 1600 ||
          !["A1", "A2", "B1", "B2"].includes(message.level)
        )
          throw Error("Choose a shorter word or phrase to explain.");
        const key = JSON.stringify([
          4,
          translationMode ? "translation" : "explanation",
          message.text,
          message.sentence,
          message.level,
        ]);
        const cacheData = await browser.storage.local.get(
          translationMode ? "translationCache" : "explanationCache",
        );
        assertGeneration(expected);
        if (translationMode) {
          const cached = translationCache(cacheData.translationCache);
          if (cached[key]) return { translation: cached[key] };
        } else {
          const cached = explanationCache(cacheData.explanationCache);
          if (validExplanation(cached[key])) return { explanation: cached[key] };
        }
        if (inFlight.has(key)) return await inFlight.get(key);
        const task = (async () => {
          const result = await api(
            "/functions/v1/immersion-explain",
            {
              text: message.text,
              sentence: message.sentence,
              level: message.level,
              installationId: await installationId(),
              ...(translationMode ? { mode: "translation" } : {}),
            },
            anon,
          );
          if (translationMode ? !validTranslation(result) : !validExplanation(result))
            throw Error(translationMode
              ? "The translation was incomplete. Please try again."
              : "The explanation was incomplete. Please try again.");
          await serialize(async () => {
            assertGeneration(expected);
            const data = await browser.storage.local.get([
              "prefs",
              "explanationCache",
              "translationCache",
            ]);
            assertGeneration(expected);
            if (translationMode) {
              const cache = translationCache(data.translationCache);
              cache[key] = result.translation;
              await browser.storage.local.set({
                translationCache: Object.fromEntries(Object.entries(cache).slice(-300)),
              });
            } else {
              const cache = explanationCache(data.explanationCache);
              cache[key] = result;
              await browser.storage.local.set({
                explanationCache: Object.fromEntries(Object.entries(cache).slice(-300)),
              });
            }
          });
          assertGeneration(expected);
          return translationMode ? { translation: result.translation } : { explanation: result };
        })();
        inFlight.set(key, task);
        try {
          return await task;
        } finally {
          if (inFlight.get(key) === task) inFlight.delete(key);
        }
      } catch (e) {
        return {
          error:
            e instanceof Error
              ? e.message
              : "Something went wrong. Please try again.",
        };
      }
    })();
  });
});
