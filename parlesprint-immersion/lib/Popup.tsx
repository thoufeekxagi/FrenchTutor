/** Screen: Popup. Local practice, notebook, and optional account connection. */
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { browser } from "wxt/browser";
import { Arrow, Book, Brand, Headphones } from "./Brand";
import { useStore } from "./store";
import type { Level } from "./types";
import { matchesVocabulary, vocabularyCsv } from "./vocabularyExport";

type Tab = "practice" | "notebook" | "account";
const tabs: { id: Tab; label: string }[] = [
  { id: "practice", label: "Practice" },
  { id: "notebook", label: "Notebook" },
  { id: "account", label: "Account" },
];
interface Account {
  displayName?: string;
  email?: string;
  provider?: string;
}
interface Capabilities {
  google: boolean;
  apple: boolean;
  googleReason?: string;
  appleReason?: string;
  error?: string;
}
const unavailable: Capabilities = { google: false, apple: false };
const errorText = (e: unknown) =>
  e instanceof Error ? e.message : "Please try again.";
export function Popup() {
  const { prefs, words, ready, load, update, remove, storageError } =
    useStore();
  const [tab, setTab] = useState<Tab>(() =>
    location.hash === "#account" ? "account" : "practice",
  );
  const tabButtons = useRef<(HTMLButtonElement | null)[]>([]);
  const [query, setQuery] = useState("");
  const filteredWords = words.filter((word) => matchesVocabulary(word, query));
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [linked, setLinked] = useState(false);
  const [account, setAccount] = useState<Account>();
  const [authReady, setAuthReady] = useState(false);
  const [capabilities, setCapabilities] = useState<Capabilities>(unavailable);
  const [capabilitiesReady, setCapabilitiesReady] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState<string>();
  const [liveConsent, setLiveConsent] = useState(false);
  const [liveSession, setLiveSession] = useState<{
    tabId: number;
    hostname: string;
    status: "connecting" | "listening";
  }>();
  const [liveBusy, setLiveBusy] = useState(false);

  async function readAuth() {
    const result = await browser.runtime.sendMessage({ type: "auth-status" });
    if (result?.error) throw Error(result.error);
    setLinked(result?.linked === true);
    const raw = result?.account;
    setAccount(
      raw && typeof raw === "object"
        ? {
            displayName:
              typeof raw.displayName === "string"
                ? raw.displayName.slice(0, 120)
                : undefined,
            email:
              typeof raw.email === "string"
                ? raw.email.slice(0, 254)
                : undefined,
            provider:
              typeof raw.provider === "string" ? raw.provider : undefined,
          }
        : undefined,
    );
    setAuthReady(true);
    return result?.linked === true;
  }
  useEffect(() => {
    void load();
    void browser.storage.local.get(["transcriptionLiveConsent", "liveSession"]).then((raw) => {
      const data = raw as Record<string, unknown>;
      setLiveConsent(data.transcriptionLiveConsent === true);
      const session = data.liveSession;
      if (session && typeof session === "object" &&
          typeof (session as any).tabId === "number" && typeof (session as any).hostname === "string")
        setLiveSession(session as typeof liveSession);
    });
    void readAuth().catch(() => {
      setAuthReady(true);
      setError("Account status is unavailable. Reopen the popup to try again.");
    });
    void browser.runtime
      .sendMessage({ type: "auth-capabilities" })
      .then((result) => {
        setCapabilities({
          google: result?.google === true,
          apple: result?.apple === true,
          googleReason:
            typeof result?.googleReason === "string"
              ? result.googleReason
              : undefined,
          appleReason:
            typeof result?.appleReason === "string"
              ? result.appleReason
              : undefined,
          error: typeof result?.error === "string" ? result.error : undefined,
        });
      })
      .catch(() =>
        setCapabilities({
          ...unavailable,
          error:
            "Account providers could not be checked. Try reopening the popup.",
        }),
      )
      .finally(() => setCapabilitiesReady(true));
    const listener = (changes: Record<string, unknown>, area: string) => {
      if (area !== "local") return;
      if ("session" in changes)
        void readAuth().catch(() =>
          setError("Could not refresh account status."),
        );
      if ("transcriptionLiveConsent" in changes) {
        const change = changes.transcriptionLiveConsent as { newValue?: unknown };
        setLiveConsent(change?.newValue === true);
      }
      if ("liveSession" in changes) {
        const change = changes.liveSession as { newValue?: unknown };
        const session = change?.newValue;
        setLiveSession(
          session && typeof session === "object" &&
            typeof (session as any).tabId === "number" && typeof (session as any).hostname === "string"
            ? session as typeof liveSession
            : undefined,
        );
      }
    };
    browser.storage.onChanged.addListener(listener);
    return () => browser.storage.onChanged.removeListener(listener);
  }, []);

  async function auth(
    type: "password" | "oauth" | "sign-out",
    provider?: "google" | "apple",
  ) {
    setBusy(provider ?? type);
    setMessage("");
    setError("");
    try {
      const result = await browser.runtime.sendMessage({
        type,
        ...(type === "password" ? { email: email.trim(), password } : {}),
        ...(provider ? { provider } : {}),
      });
      if (result?.error) throw Error(result.error);
      if (result?.ok !== true)
        throw Error("Account connection did not complete. Please try again.");
      setPassword("");
      if (type === "sign-out") {
        setLinked(false);
        setAccount(undefined);
        setMessage("Signed out. Your local vocabulary is still saved.");
      } else {
        if (!(await readAuth()))
          throw Error("Account connection did not complete. Please try again.");
        setMessage(
          "Connected. You can request explanations while you practise.",
        );
      }
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(undefined);
    }
  }
  function exportWords(csv = false) {
    const blob = new Blob(
      [
        csv
          ? vocabularyCsv(words)
          : JSON.stringify({ version: 1, words }, null, 2),
      ],
      {
        type: csv ? "text/csv;charset=utf-8" : "application/json",
      },
    );
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = csv
      ? "parlesprint-vocabulary-anki.csv"
      : "parlesprint-vocabulary.json";
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  function changeTab(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let next: number;
    if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
    else if (event.key === "ArrowLeft")
      next = (index + tabs.length - 1) % tabs.length;
    else if (event.key === "Home") next = 0;
    else if (event.key === "End") next = tabs.length - 1;
    else return;
    event.preventDefault();
    setTab(tabs[next]!.id);
    tabButtons.current[next]?.focus();
  }
  function updatePrefs(patch: Parameters<typeof update>[0]) {
    void update(patch).catch((e) => setError(errorText(e)));
  }
  async function updateLiveConsent(accepted: boolean) {
    setLiveBusy(true);
    setError("");
    try {
      const result = await browser.runtime.sendMessage({
        type: "set-live-transcription-consent",
        accepted,
      });
      if (result?.error) throw Error(result.error);
      setLiveConsent(accepted);
    } catch (e) {
      setError(errorText(e));
    } finally {
      setLiveBusy(false);
    }
  }
  async function toggleLiveTranscription() {
    setLiveBusy(true);
    setError("");
    try {
      const result = await browser.runtime.sendMessage({
        type: liveSession ? "stop-live-transcription" : "start-live-transcription",
      });
      if (result?.error) throw Error(result.error);
      if (!liveSession && result?.ok !== true)
        throw Error("Live captions did not start. Try again.");
      setMessage(liveSession ? "Live captions stopped." : "Starting live French captions…");
    } catch (e) {
      setError(errorText(e));
    } finally {
      setLiveBusy(false);
    }
  }
  const accountName =
    account?.displayName || account?.email || "ParleSprint account";
  return (
    <main className="ps popup" aria-label="ParleSprint Immersion">
      <header className="popup-head">
        <Brand />
        <span className="pill">French, every day</span>
      </header>
      <nav className="tab-bar" role="tablist" aria-label="Immersion sections">
        {tabs.map(({ id, label }, index) => (
          <button
            key={id}
            ref={(element) => {
              tabButtons.current[index] = element;
            }}
            id={`tab-${id}`}
            role="tab"
            aria-selected={tab === id}
            aria-controls={`panel-${id}`}
            tabIndex={tab === id ? 0 : -1}
            onClick={() => setTab(id)}
            onKeyDown={(event) => changeTab(event, index)}
          >
            {label}
          </button>
        ))}
      </nav>
      {storageError && (
        <p className="error" role="alert">
          {storageError}
        </p>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      {!ready ? (
        <p className="muted" role="status">
          Loading your notebook…
        </p>
      ) : (
        <>
          <section
            id="panel-practice"
            role="tabpanel"
            aria-labelledby="tab-practice"
            hidden={tab !== "practice"}
          >
            <div className="stack">
              <div className="card stack live-card" aria-label="Live French captions">
                <div className="section-title">
                  <div>
                    <div className="badge">Automatic on YouTube</div>
                    <h2 style={{ marginTop: 6 }}>Videos without captions</h2>
                  </div>
                  {liveSession && <span className="pill">{liveSession.status === "listening" ? "Listening" : "Connecting"}</span>}
                </div>
                <p className="muted">
                  French captions appear under YouTube videos by themselves. If a video has none, start live captions and ParleSprint transcribes the tab audio instead.
                  {liveSession ? ` Current tab: ${liveSession.hostname}.` : ""}
                </p>
                <label className="stack" style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
                  <input
                    type="checkbox"
                    checked={liveConsent}
                    disabled={liveBusy || !!liveSession}
                    onChange={(event) => void updateLiveConsent(event.target.checked)}
                  />
                  <span>
                    Send this tab’s audio to Google for live French transcription. Google may use submitted audio to improve its products, and people may review it. Do not use with sensitive content.
                  </span>
                </label>
                <p className="field-note">
                  ParleSprint does not receive or store the audio. The Gemini key stays on the server; the extension receives a short-lived token.
                </p>
                <button
                  className={liveSession ? "action" : "action primary"}
                  disabled={liveBusy || (!liveSession && !liveConsent)}
                  onClick={() => void toggleLiveTranscription()}
                >
                  {liveBusy
                    ? "Working…"
                    : liveSession
                      ? "Stop live captions"
                      : "Start live captions on this tab"}
                  {!liveSession && <Arrow />}
                </button>
                <p className="field-note" role="status">
                  Captions appear as the video plays; timing can be approximate.
                </p>
              </div>
              <div className="popup-hero">
                <span className="icon-tile">
                  <Headphones />
                </span>
                <div className="badge">Your next little step</div>
                <h1>
                  A little listening.
                  <br />A little more confidence.
                </h1>
                <p className="muted">
                  Start with an original French story. Listen, reveal a
                  sentence, and save something new.
                </p>
                <a
                  className="action primary"
                  href={browser.runtime.getURL("/practice.html")}
                  target="_blank"
                  rel="noreferrer"
                >
                  Try your first practice <Arrow />
                </a>
                <span className="field-note">
                  41 seconds · No account needed
                </span>
              </div>
              <div className="card stack">
                <div className="section-title">
                  <label htmlFor="level">Your French</label>
                  <select
                    id="level"
                    value={prefs.level}
                    onChange={(event) =>
                      updatePrefs({ level: event.target.value as Level })
                    }
                  >
                    {["A1", "A2", "B1", "B2"].map((level) => (
                      <option key={level}>{level}</option>
                    ))}
                  </select>
                </div>
                <label>
                  <input
                    type="checkbox"
                    checked={prefs.enabled}
                    onChange={(event) =>
                      updatePrefs({ enabled: event.target.checked })
                    }
                  />
                  Show companion on video pages
                </label>
                <h3>Your setup</h3>
                <ol
                  className="muted"
                  style={{
                    margin: 0,
                    paddingLeft: 20,
                    display: "grid",
                    gap: 8,
                  }}
                >
                  <li>Open a video in a regular browser tab and play it.</li>
                  <li>Open the extension popup, accept the audio notice, and start live captions.</li>
                  <li>Select a word or phrase, then repeat the sentence.</li>
                </ol>
                <p className="field-note">
                  Live transcription works from tab audio on video sites. Your notebook stays in this browser.
                </p>
                <details>
                  <summary>Reading preferences</summary>
                  <div className="stack" style={{ marginTop: 8 }}>
                    <label>
                      <input
                        type="checkbox"
                        checked={prefs.highlightSaved}
                        onChange={(event) =>
                          updatePrefs({ highlightSaved: event.target.checked })
                        }
                      />
                      Highlight saved vocabulary
                    </label>
                    <label>
                      <input
                        type="checkbox"
                        checked={prefs.highlightSpokenWords}
                        onChange={(event) =>
                          updatePrefs({ highlightSpokenWords: event.target.checked })
                        }
                      />
                      Highlight words as the video plays
                    </label>
                    <label htmlFor="caption-size">Caption size</label>
                    <select
                      id="caption-size"
                      value={prefs.captionSize}
                      onChange={(event) =>
                        updatePrefs({
                          captionSize: event.target.value as
                            "comfortable" | "large",
                        })
                      }
                    >
                      <option value="comfortable">Comfortable</option>
                      <option value="large">Large</option>
                    </select>
                    <label htmlFor="caption-placement">Caption placement</label>
                    <select
                      id="caption-placement"
                      value={prefs.placement}
                      onChange={(event) =>
                        updatePrefs({
                          placement: event.target.value as "overlay" | "below" | "floating",
                        })
                      }
                    >
                      <option value="below">Under the video (recommended)</option>
                      <option value="overlay">On the video</option>
                      <option value="floating">Floating overlay</option>
                    </select>
                  </div>
                </details>
                <a
                  className="action"
                  href="https://www.youtube.com/"
                  target="_blank"
                  rel="noreferrer"
                >
                  Open YouTube <Arrow />
                </a>
                <a
                  className="field-note"
                  href={browser.runtime.getURL("/practice-fr.srt")}
                  download="practice-fr.srt"
                >
                  Download practice subtitles
                </a>
              </div>
            </div>
          </section>
          <section
            id="panel-notebook"
            role="tabpanel"
            aria-labelledby="tab-notebook"
            hidden={tab !== "notebook"}
          >
            <div className="stack">
              <div className="section-title">
                <div>
                  <div className="badge">Words worth keeping</div>
                  <h2 style={{ marginTop: 6 }}>Your notebook</h2>
                </div>
                <span className="pill">
                  {words.length} {words.length === 1 ? "phrase" : "phrases"}
                </span>
              </div>
              {!words.length ? (
                <div className="card empty-notebook">
                  <span className="icon-tile">
                    <Book />
                  </span>
                  <h3>A place for your discoveries</h3>
                  <p className="muted">
                    Save a word or sentence while you watch. It will appear
                    here.
                  </p>
                  <button
                    className="primary"
                    onClick={() => setTab("practice")}
                  >
                    Start practising
                  </button>
                </div>
              ) : (
                <>
                  <label htmlFor="notebook-search">
                    Search your notebook
                    <input
                      id="notebook-search"
                      type="search"
                      value={query}
                      onChange={(event) => setQuery(event.target.value)}
                      placeholder="Word, meaning, or sentence"
                    />
                  </label>
                  <div className="section-title">
                    <p className="field-note" role="status">
                      {query.trim()
                        ? `${filteredWords.length} of ${words.length} phrases`
                        : `${words.length} saved ${words.length === 1 ? "phrase" : "phrases"}`}
                    </p>
                    {query && (
                      <button onClick={() => setQuery("")}>Clear search</button>
                    )}
                  </div>
                  <div className="row">
                    <button onClick={() => exportWords()}>
                      Export vocabulary
                    </button>
                    <button onClick={() => exportWords(true)}>
                      Export Anki CSV
                    </button>
                  </div>
                  <p className="field-note">
                    Exports include every saved phrase, even while searching.
                  </p>
                  <details>
                    <summary>Using your CSV in Anki</summary>
                    <p className="field-note">
                      Map Front to the French phrase, Back to its meaning, and
                      Context to the subtitle sentence. Choose a note type with
                      a Context field to keep all three.
                    </p>
                  </details>
                  {filteredWords.length === 0 ? (
                    <div className="card stack">
                      <h3>No matching phrases</h3>
                      <p className="muted">
                        Try another word, meaning, or sentence. French accents
                        are optional.
                      </p>
                      <button onClick={() => setQuery("")}>
                        Show all phrases
                      </button>
                    </div>
                  ) : (
                    <div>
                      {filteredWords.map((word) => (
                        <article key={word.id} className="notebook-item">
                          <div className="section-title">
                            <h3 lang="fr">{word.text}</h3>
                            <span className="pill">{word.level}</span>
                          </div>
                          <p className="muted" lang="fr">
                            {word.sentence}
                          </p>
                          {word.explanation && (
                            <p style={{ fontSize: 13 }}>
                              {word.explanation.meaning}
                            </p>
                          )}
                          <button
                            style={{ justifySelf: "start", fontSize: 12 }}
                            onClick={() =>
                              void remove(word.id).catch((e) =>
                                setError(errorText(e)),
                              )
                            }
                          >
                            Remove phrase
                          </button>
                        </article>
                      ))}
                    </div>
                  )}
                </>
              )}
              <p className="field-note">
                Saved on this device. Export a copy before uninstalling. Account
                connection does not sync vocabulary yet.
              </p>
            </div>
          </section>
          <section
            id="panel-account"
            role="tabpanel"
            aria-labelledby="tab-account"
            hidden={tab !== "account"}
          >
            <div className="stack">
              <div>
                <div className="badge">Your ParleSprint connection</div>
                <h2 style={{ marginTop: 6 }}>
                  {linked
                    ? "You're connected"
                    : "A little help when you need it"}
                </h2>
                <p className="muted" style={{ marginTop: 10 }}>
                  Connect for optional AI explanations of French words and
                  phrases. Local practice is always available.
                </p>
              </div>
              {!authReady ? (
                <p className="muted" role="status">
                  Checking your account…
                </p>
              ) : linked ? (
                <div className="card stack">
                  <div className="account-card">
                    <span className="account-avatar" aria-hidden="true">
                      {accountName.charAt(0).toLocaleUpperCase()}
                    </span>
                    <div style={{ minWidth: 0 }}>
                      <h3>{accountName}</h3>
                      {account?.email && account.email !== accountName && (
                        <p className="muted">{account.email}</p>
                      )}
                      <span className="success-label">
                        <span className="status-dot" /> Connected for
                        explanations
                      </span>
                    </div>
                  </div>
                  <button
                    disabled={!!busy}
                    onClick={() => void auth("sign-out")}
                  >
                    {busy === "sign-out" ? "Signing out…" : "Sign out"}
                  </button>
                </div>
              ) : (
                <>
                  {(capabilities.google || capabilities.apple) && (
                    <div className="stack" style={{ gap: 10 }}>
                      {capabilities.google && (
                        <button
                          className="provider-button"
                          disabled={!!busy || !capabilitiesReady}
                          onClick={() => void auth("oauth", "google")}
                        >
                          {busy === "google"
                            ? "Opening Google…"
                            : "Continue with Google"}
                        </button>
                      )}
                      {capabilities.apple && (
                        <button
                          className="provider-button"
                          disabled={!!busy || !capabilitiesReady}
                          onClick={() => void auth("oauth", "apple")}
                        >
                          {busy === "apple"
                            ? "Opening Apple…"
                            : "Continue with Apple"}
                        </button>
                      )}
                    </div>
                  )}
                  <form
                    className="line stack"
                    onSubmit={(event) => {
                      event.preventDefault();
                      if (!busy) void auth("password");
                    }}
                  >
                    <h3>Use your existing account</h3>
                    <label htmlFor="account-email">
                      Email
                      <input
                        id="account-email"
                        type="email"
                        value={email}
                        onChange={(event) => setEmail(event.target.value)}
                        autoComplete="email"
                        maxLength={254}
                        required
                        disabled={!!busy}
                      />
                    </label>
                    <label htmlFor="account-password">
                      Password
                      <input
                        id="account-password"
                        type="password"
                        value={password}
                        onChange={(event) => setPassword(event.target.value)}
                        autoComplete="current-password"
                        maxLength={256}
                        required
                        disabled={!!busy}
                      />
                    </label>
                    <button
                      type="submit"
                      className="primary"
                      disabled={!!busy || !email.includes("@") || !password}
                    >
                      {busy === "password"
                        ? "Connecting…"
                        : "Connect existing account"}
                    </button>
                  </form>
                </>
              )}
              {message && (
                <p role="status" className="success-label">
                  {message}
                </p>
              )}
              <div className="line stack" style={{ gap: 8 }}>
                <h3>Optional AI explanations</h3>
                <label>
                  <input
                    type="checkbox"
                    checked={prefs.aiConsent}
                    onChange={(event) =>
                      updatePrefs({ aiConsent: event.target.checked })
                    }
                  />
                  Allow sending selected text for AI explanations
                </label>
                <p className="muted">
                  When you request an explanation, selected text and its
                  sentence go to ParleSprint and Google Gemini. No microphone
                  access. No vocabulary sync in this version.
                </p>
              </div>
            </div>
          </section>
        </>
      )}
      <footer
        className="line"
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: 12,
        }}
      >
        <a
          className="field-note"
          href={browser.runtime.getURL("/privacy.html")}
          target="_blank"
          rel="noreferrer"
        >
          Privacy &amp; data
        </a>
        <span className="field-note">Made for small steps</span>
      </footer>
    </main>
  );
}
