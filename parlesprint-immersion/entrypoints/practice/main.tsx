import "../../lib/font";
/** Screen: First practice. Primary: play the original French sample.
 * Success: hear matched captions, reveal authored meaning, repeat and save.
 * No account needed. Optional AI remains behind consent and connection. */
import { createRoot } from "react-dom/client";
import { useEffect, useState } from "react";
import { browser } from "wxt/browser";
import { Immersion, type Practice } from "../../lib/Immersion";
import { Brand, Arrow, Headphones } from "../../lib/Brand";
import { useStore } from "../../lib/store";
import "../../lib/style.css";
function FirstPractice() {
  const [data, setData] = useState<
    Practice & { title: string; disclosure: string }
  >();
  const [error, setError] = useState("");
  const { prefs, update } = useStore();
  useEffect(() => {
    void fetch(browser.runtime.getURL("/practice.json"))
      .then((r) => {
        if (!r.ok) throw Error("Sample unavailable");
        return r.json();
      })
      .then((d) =>
        setData({ ...d, source: "ParleSprint original listening sample" }),
      )
      .catch(() =>
        setError(
          "The practice sample could not load. Reload this page to try again.",
        ),
      );
  }, []);
  return (
    <main className="ps practice-page">
      <header className="app-topbar">
        <Brand />
        <span className="badge">Free practice · No account needed</span>
      </header>
      <div className="practice-shell">
        <section className="practice-main stack">
          <div className="practice-intro stack">
            <span className="badge">YOUR FIRST LISTENING PRACTICE</span>
            <h1>A little French. A real first step.</h1>
            <p className="muted">
              Listen closely. Discover a useful phrase. Make it yours.
              <br />A short moment of French, at your own pace.
            </p>
          </div>
          {error && (
            <p role="alert" className="error">
              {error}
            </p>
          )}
          {data && (
            <>
              <div className="practice-media">
                <video
                  aria-label="Original French listening sample"
                  controls
                  preload="metadata"
                  poster={browser.runtime.getURL("/practice-poster.svg")}
                  src={browser.runtime.getURL("/practice.webm")}
                />
              </div>
              <div className="practice-meta">
                <div>
                  <h2>{data.title}</h2>
                  <p className="muted">
                    Original listening sample · 41 seconds · Beginner friendly
                  </p>
                </div>
                <span className="icon-tile">
                  <Headphones />
                </span>
              </div>
              <div className="practice-steps">
                {[
                  [
                    "01",
                    "Listen",
                    "Press play and follow the French captions.",
                  ],
                  [
                    "02",
                    "Notice",
                    "Tap a word, or reveal the sentence meaning.",
                  ],
                  ["03", "Keep", "Repeat a sentence and save a useful phrase."],
                ].map(([n, title, copy]) => (
                  <div className="practice-step" key={n}>
                    <span className="step-number">{n}</span>
                    <div>
                      <h3>{title}</h3>
                      <p className="muted">{copy}</p>
                    </div>
                  </div>
                ))}
              </div>
              <p className="muted field-note">{data.disclosure}</p>
              {!prefs.enabled && (
                <button
                  className="primary"
                  onClick={() => void update({ enabled: true })}
                >
                  Enable learning companion
                </button>
              )}
              <div className="practice-next">
                <div>
                  <h3>Bring your own French.</h3>
                  <p className="muted">
                    On YouTube, import matching French SRT or VTT subtitles to
                    keep practising.
                  </p>
                </div>
                <a
                  className="action"
                  href="https://www.youtube.com/"
                  target="_blank"
                  rel="noreferrer"
                >
                  Continue on YouTube <Arrow />
                </a>
              </div>
            </>
          )}
        </section>
        <aside className="practice-sidebar">
          {data && <Immersion practice={data} />}
        </aside>
      </div>
    </main>
  );
}
createRoot(document.getElementById("root")!).render(<FirstPractice />);
