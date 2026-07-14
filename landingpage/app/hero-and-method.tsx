import { ArrowRight, Check, Compass, Gauge, Sparkles } from "lucide-react";
import { FeedbackLoopVisual, HeroProduct } from "./product-visuals";

export function HeroSection() {
  return (
    <section className="hero shell" id="top">
      <div className="hero-copy">
        <p className="eyebrow"><span /> Personalized French practice</p>
        <h1>Turn French practice into <em>real progress.</em></h1>
        <p className="hero-lede">ParleSprint connects vocabulary, grammar, listening, writing, and live speaking in one personalized feedback loop—so what you learn becomes French you can actually use.</p>
        <div className="hero-actions">
          <a className="button button-primary" href="#founding">Apply for founding access <ArrowRight size={17} /></a>
          <a className="text-link" href="#method">See how the loop works</a>
        </div>
        <div className="hero-trust">
          <span><Check size={14} /> Beginner-friendly</span>
          <span><Check size={14} /> Self-paced</span>
          <span><Check size={14} /> Built for serious learners</span>
        </div>
      </div>
      <HeroProduct />
    </section>
  );
}

export function PurposeStrip() {
  return (
    <section className="purpose-strip">
      <div className="shell purpose-inner">
        <p>One platform. Every major French skill. One connected path.</p>
        <div><span>Vocabulary</span><i /><span>Grammar</span><i /><span>Listening</span><i /><span>Writing</span><i /><span>Speaking</span></div>
      </div>
    </section>
  );
}

export function LearnerIdentity() {
  const reasons = ["A Canadian future", "A professional opportunity", "A conversation that matters", "A personal goal you refuse to abandon"];
  return (
    <section className="identity-section shell section-space">
      <div className="identity-copy">
        <p className="eyebrow"><span /> Built for learners who mean it</p>
        <h2>You bring the reason.<br /><em>We build the practice around it.</em></h2>
        <p>Whether your reason is practical or deeply personal, your learning should adapt to the goal—not force you through an unrelated feed.</p>
      </div>
      <div className="reason-grid">
        {reasons.map((reason, index) => <div className="reason-card" key={reason}><span>0{index + 1}</span><p>{reason}</p></div>)}
      </div>
    </section>
  );
}

export function MethodSection() {
  return (
    <section className="method-section" id="method">
      <div className="shell section-space">
        <div className="section-heading split-heading">
          <div><p className="eyebrow eyebrow-light"><span /> The ParleSprint method</p><h2>Close the distance between learning and using.</h2></div>
          <p>Vocabulary in one place, grammar in another, and speaking left until later creates knowledge you recognize but cannot use. ParleSprint connects every attempt to the next useful step.</p>
        </div>
        <FeedbackLoopVisual />
        <div className="method-principles">
          <article><Compass size={20} /><strong>Connected context</strong><p>Today’s words return in sentences, passages, writing, and conversation.</p></article>
          <article><Gauge size={20} /><strong>Adaptive pressure</strong><p>Slow down when you need support. Push further when you are ready.</p></article>
          <article><Sparkles size={20} /><strong>Useful feedback</strong><p>Corrections become the material your next practice is built around.</p></article>
        </div>
      </div>
    </section>
  );
}
