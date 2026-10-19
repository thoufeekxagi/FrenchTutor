import Link from "next/link";
import { ArrowRight, Captions, Clapperboard, ExternalLink, MessageSquareText, Play, ShieldCheck, SkipForward } from "lucide-react";

const chromeStoreUrl = "https://chromewebstore.google.com/detail/parlesprint-immersion/ijclgmkoljddlalgcnpodeemcmcipolb";

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
          <p className="eyebrow">PARLESPRINT IMMERSION · 0.2.0</p>
          <h2>Turn French video into active listening practice.</h2>
          <ul className="feature-list">
            <li><Captions size={17} />Start live French captions for a video tab when you choose and consent.</li>
            <li><MessageSquareText size={17} />Translate words as you read; request an AI explanation when you need one.</li>
            <li><SkipForward size={17} />Replay a sentence, then save useful words to your vocabulary notebook.</li>
            <li><ShieldCheck size={17} />Your video audio streams directly to Google Gemini, not ParleSprint.</li>
          </ul>
          <a className="button button-primary" href={chromeStoreUrl} target="_blank" rel="noreferrer">Install from the Chrome Web Store <ExternalLink size={17} /></a>
          <p className="product-note">Available for desktop Chrome. Live captions are off until you accept the audio notice and start them. You can also use available page captions or import an SRT or VTT subtitle file.</p>
        </div>
      </section>

      <section className="panel" style={{ marginTop: 32 }}>
        <h2>Install on desktop Chrome in about a minute.</h2>
        <ol className="step-list">
          <li>Install ParleSprint Immersion from the Chrome Web Store in desktop Chrome.</li>
          <li>Open a French video, click the extension, review the audio notice, and choose <strong>Start live captions on this tab</strong>.</li>
          <li>For available subtitles, open the extension&apos;s other subtitle options instead. You can stop live captions from the extension popup.</li>
        </ol>
        <p className="product-note">Chrome captures only the active tab&apos;s audio after your action; the microphone and video frames are not used. Audio streams to Google&apos;s Gemini service and is not received or stored by ParleSprint. Google may handle audio differently on free and paid API tiers, so review the consent notice before use. Translation text is sent to Google Translate. AI explanations send the selected phrase, nearby caption context, and your level to ParleSprint&apos;s service and Google Gemini; connect an account for this feature. Captions, transcripts, preferences, and saved vocabulary are stored in Chrome on your device.</p>
        <p className="product-note"><a href="/extension/privacy">Read the extension privacy policy</a>.</p>
      </section>

      <section className="feedback-invite" style={{ paddingBlock: "40px 8px" }}>
        <div><p className="eyebrow">KEEP THE GOOD BITS</p><h2>Bring your new words back to your notebook.</h2><p>Save a phrase here and review your list anytime.</p></div>
        <Link className="button button-secondary" href="/words">Open my words <ArrowRight size={16} /></Link>
      </section>
    </>
  );
}
