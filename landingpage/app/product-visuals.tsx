import { BookOpen, Check, Headphones, Mic, PenLine, RotateCcw, Volume2 } from "lucide-react";

export function HeroProduct() {
  return (
    <div className="hero-product" aria-label="ParleSprint connected learning pathway preview">
      <div className="product-note note-top">One session remembers the last</div>
      <div className="phone-shell">
        <div className="phone-top"><span>9:41</span><i /></div>
        <div className="phone-brand"><span>Today’s path</span><strong>14 min</strong></div>
        <h2>Build it. Hear it.<br />Use it.</h2>
        <div className="pathway-list">
          <PathItem icon={<BookOpen size={15} />} label="Vocabulary" detail="5 useful words" state="done" />
          <PathItem icon={<Volume2 size={15} />} label="Grammar" detail="Ask for information" state="active" />
          <PathItem icon={<Headphones size={15} />} label="Listen & read" detail="A short exchange" />
          <PathItem icon={<PenLine size={15} />} label="Writing" detail="Put it in your words" />
          <PathItem icon={<Mic size={15} />} label="Speak with Marie" detail="Use today’s French" />
        </div>
        <button type="button" tabIndex={-1}>Continue grammar</button>
      </div>
      <div className="voice-card">
        <div className="voice-card-head"><span className="avatar">M</span><div><strong>Marie</strong><small>Listening to you</small></div><span className="live-wave"><i /><i /><i /></span></div>
        <p>“Très bien. Now use <em>pourriez-vous</em> in your own question.”</p>
      </div>
      <div className="memory-card"><RotateCcw size={16} /><div><strong>4 reviews ready</strong><small>Timed to your memory</small></div></div>
    </div>
  );
}

function PathItem({ icon, label, detail, state = "" }: { icon: React.ReactNode; label: string; detail: string; state?: string }) {
  return (
    <div className={`path-item ${state}`}>
      <span className="path-icon">{state === "done" ? <Check size={14} /> : icon}</span>
      <div><strong>{label}</strong><small>{detail}</small></div>
      {state === "active" && <span className="path-now">Now</span>}
    </div>
  );
}

export function FeedbackLoopVisual() {
  const items = [
    ["01", "Learn", "A useful word or pattern"],
    ["02", "Attempt", "Say it or write it yourself"],
    ["03", "Feedback", "Correct it while it matters"],
    ["04", "Apply", "Use it in real context"],
    ["05", "Remember", "Review at the right time"],
  ];

  return (
    <div className="loop-visual" aria-label="The ParleSprint adaptive learning feedback loop">
      <div className="orbit-glow" aria-hidden="true" />
      <div className="orbit-ring orbit-ring-outer" aria-hidden="true" />
      <div className="orbit-ring orbit-ring-inner" aria-hidden="true" />
      <div className="loop-core"><span>Your next session</span><strong>adapts</strong><small>to what happened here</small><i /></div>
      {items.map(([index, title, copy], position) => (
        <div className={`orbit-slot orbit-${position + 1}`} key={title}>
          <div className="loop-item">
            <span>{index}</span><div><strong>{title}</strong><small>{copy}</small></div>
          </div>
        </div>
      ))}
      <p className="orbit-caption">Learn → attempt → feedback → apply → remember</p>
    </div>
  );
}

export function MarieDemo() {
  return (
    <div className="marie-demo">
      <div className="call-header"><span className="avatar avatar-large">M</span><div><strong>Marie</strong><small><span className="signal-dot" /> Live voice practice</small></div><span>04:32</span></div>
      <div className="transcript tutor"><small>Marie</small><p>Tu préfères travailler le matin ou le soir&nbsp;?</p></div>
      <div className="transcript learner"><small>You</small><p>Je préfère travaille le soir.</p></div>
      <div className="feedback-correction"><span><Check size={14} /></span><p><strong>Good answer.</strong> Say “je préfère <em>travailler</em>” after préférer.</p></div>
      <div className="audio-orb"><Mic size={22} /><span /><span /></div>
      <p className="listening-label">Marie is listening…</p>
    </div>
  );
}
