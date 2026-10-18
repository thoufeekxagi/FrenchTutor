import Link from "next/link";
import { ArrowRight, Captions, Clapperboard, Download, MessageSquareText, Play, ShieldCheck, SkipForward } from "lucide-react";

const zip = "/downloads/parlesprint-immersion-0.1.0-chrome.zip";

export function ExtensionDetails() {
  return (
    <>
      <section className="product-grid">
        <div className="product-visual">
          <div className="video-visual">
            <div className="video-top"><Clapperboard size={33} strokeWidth={1.3} /><span><Play size={19} fill="currentColor" /></span></div>
            <div className="video-caption" lang="fr">Hier, j’ai <mark>rencontré</mark> mon voisin.<small>Yesterday, I met my neighbour. · A2</small></div>
          </div>
        </div>
        <div className="product-details">
          <p className="eyebrow">PARLESPRINT IMMERSION · 0.1.0</p>
          <h2>A little more French from the videos you already watch.</h2>
          <ul className="feature-list">
            <li><Captions size={17} />Follow time-synced French subtitles as you watch YouTube.</li>
            <li><MessageSquareText size={17} />Tap a word to see a short meaning, grammar note and example.</li>
            <li><SkipForward size={17} />Repeat one sentence. Hide the English and listen again.</li>
            <li><ShieldCheck size={17} />Save phrases on your device. Sign-in is optional.</li>
          </ul>
          <a className="button button-primary" href={zip} download>Download the Chrome extension <Download size={17} /></a>
          <p className="product-note">Early-access ZIP, version 0.1.0. Install in desktop Chrome with Developer mode. Google Web Store review has not been completed. YouTube automatic caption access varies by video; the extension also accepts your own SRT or VTT file.</p>
        </div>
      </section>

      <section className="panel" style={{ marginTop: 32 }}>
        <h2>Install on desktop Chrome in about a minute.</h2>
        <ol className="step-list">
          <li>Download the ZIP above, then extract it into a folder you can find.</li>
          <li>In Chrome, open <code>chrome://extensions</code> and switch on Developer mode.</li>
          <li>Choose “Load unpacked” and select the extracted folder containing <code>manifest.json</code>.</li>
          <li>Open a YouTube video with French captions. Choose the French transcript, then use ParleSprint Immersion to learn a line. Try the included demo SRT if captions are unavailable.</li>
        </ol>
        <p className="product-note">The ZIP asks for local extension storage and access to its ParleSprint sync service. Subtitles and video pages stay in your browser. If you request an explanation, only the selected French phrase and nearby caption context are sent to ParleSprint’s secure service, after you consent in the extension.</p>
      </section>

      <section className="feedback-invite" style={{ paddingBlock: "40px 8px" }}>
        <div><p className="eyebrow">KEEP THE GOOD BITS</p><h2>Bring your new words back to your notebook.</h2><p>Save a phrase here and review your list anytime.</p></div>
        <Link className="button button-secondary" href="/words">Open my words <ArrowRight size={16} /></Link>
      </section>
    </>
  );
}
