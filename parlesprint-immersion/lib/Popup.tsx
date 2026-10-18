/** Screen: Popup. Settings, live-caption fallback, and notebook. */
import { useEffect, useRef, useState, type KeyboardEvent } from "react";
import { browser } from "wxt/browser";
import { Arrow, Book, Brand, Headphones } from "./Brand";
import { APP, feedbackUrl } from "./config";
import { useStore } from "./store";
import type { Level } from "./types";
import { matchesVocabulary, vocabularyCsv } from "./vocabularyExport";

type Tab = "practice" | "notebook";
const tabs: { id: Tab; label: string }[] = [
  { id: "practice", label: "Practice" },
  { id: "notebook", label: "Notebook" },
];
const errorText = (e: unknown) =>
  e instanceof Error ? e.message : "Please try again.";
export function Popup() {
  const { prefs, words, ready, load, update, remove, storageError } =
    useStore();
  const [tab, setTab] = useState<Tab>("practice");
  const tabButtons = useRef<(HTMLButtonElement | null)[]>([]);
  const [query, setQuery] = useState("");
  const filteredWords = words.filter((word) => matchesVocabulary(word, query));
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [liveConsent, setLiveConsent] = useState(false);
  const [liveSession, setLiveSession] = useState<{
    tabId: number;
    hostname: string;
    status: "connecting" | "listening";
  }>();
  const [liveBusy, setLiveBusy] = useState(false);

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
    const listener = (changes: Record<string, unknown>, area: string) => {
      if (area !== "local") return;
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
  return (
    <main className="ps popup" aria-label="ParleSprint Immersion">
      <header className="popup-head">
        <Brand />
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
              <div className="pop-hero">
                <h1>French captions,<br />right under the video.</h1>
                <p>Open a French YouTube video. Captions, word meanings and English translation appear under the player on their own.</p>
                <div className="pop-actions">
                  <a className="action primary" href="https://www.youtube.com/" target="_blank" rel="noreferrer">
                    Open YouTube <Arrow />
                  </a>
                  <a className="action" href={browser.runtime.getURL("/practice.html")} target="_blank" rel="noreferrer">
                    Try the 41-second sample
                  </a>
                </div>
              </div>
              <div className="group">
                <div className="row-item">
                  <label htmlFor="level">Your French</label>
                  <select id="level" value={prefs.level} onChange={(event) => updatePrefs({ level: event.target.value as Level })}>
                    {["A1", "A2", "B1", "B2"].map((level) => (
                      <option key={level}>{level}</option>
                    ))}
                  </select>
                </div>
                <div className="row-item">
                  <label htmlFor="show-companion">Show captions on videos</label>
                  <input id="show-companion" type="checkbox" checked={prefs.enabled} onChange={(event) => updatePrefs({ enabled: event.target.checked })} />
                </div>
                <div className="row-item">
                  <label htmlFor="caption-size">Caption size</label>
                  <select id="caption-size" value={prefs.captionSize} onChange={(event) => updatePrefs({ captionSize: event.target.value as "comfortable" | "large" })}>
                    <option value="comfortable">Comfortable</option>
                    <option value="large">Large</option>
                  </select>
                </div>
                <div className="row-item">
                  <label htmlFor="caption-placement">Caption placement</label>
                  <select id="caption-placement" value={prefs.placement} onChange={(event) => updatePrefs({ placement: event.target.value as "side" | "overlay" | "below" | "floating" })}>
                    <option value="side">Next to suggested videos</option>
                    <option value="below">Under the video</option>
                    <option value="overlay">On the video</option>
                    <option value="floating">Floating (movable)</option>
                  </select>
                </div>
                <div className="row-item">
                  <label htmlFor="hl-spoken">Highlight spoken words</label>
                  <input id="hl-spoken" type="checkbox" checked={prefs.highlightSpokenWords} onChange={(event) => updatePrefs({ highlightSpokenWords: event.target.checked })} />
                </div>
              </div>
              <div className="group">
                <a className="row-item link-row" href={feedbackUrl(browser.runtime.getManifest().version)} target="_blank" rel="noreferrer">
                  <span>Send feedback</span>
                  <span aria-hidden="true">›</span>
                </a>
                {APP.supportUrl && (
                  <a className="row-item link-row" href={APP.supportUrl} target="_blank" rel="noreferrer">
                    <span>Support ParleSprint</span>
                    <span aria-hidden="true">›</span>
                  </a>
                )}
                <div className="row-item">
                  <span>ParleSprint Pro</span>
                  <span className="pill">Coming soon</span>
                </div>
              </div>
              <details className="group live-card" aria-label="Live French captions">
                <summary>Video has no captions?</summary>
                <div className="stack">
                  <p className="muted">
                    ParleSprint can listen to this tab and transcribe the French instead.
                    {liveSession ? ` Current tab: ${liveSession.hostname}.` : ""}
                  </p>
                  <label style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
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
                  <button
                    className={liveSession ? "action" : "action primary"}
                    disabled={liveBusy || (!liveSession && !liveConsent)}
                    onClick={() => void toggleLiveTranscription()}
                  >
                    {liveBusy ? "Working…" : liveSession ? "Stop live captions" : "Start live captions on this tab"}
                  </button>
                  {liveSession && <span className="pill">{liveSession.status === "listening" ? "Listening" : "Connecting"}</span>}
                  <p className="field-note" role="status">Audio is sent only while live captions are running. Stop at any time.</p>
                </div>
              </details>
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
                Saved on this device. Export a copy before uninstalling.
              </p>
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
