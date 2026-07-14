"use client";

import Image from "next/image";
import { FormEvent, useState } from "react";
import {
  ArrowRight,
  ArrowUpRight,
  BookOpen,
  Check,
  ChevronDown,
  Headphones,
  Languages,
  LockKeyhole,
  Menu,
  PenLine,
  Route,
  Sparkles,
  Timer,
  Volume2,
  X,
} from "lucide-react";

type DemoKey = "path" | "speaking" | "listening" | "writing";

const demoContent: Record<DemoKey, { label: string; title: string; description: string }> = {
  path: {
    label: "The route",
    title: "Know what to learn next.",
    description:
      "A visible route turns a huge French goal into the next useful step — from first phrases to exam-ready practice.",
  },
  speaking: {
    label: "Speaking",
    title: "Practise before pressure arrives.",
    description:
      "Short, guided conversations help you build a sentence, hear a response, and try again with less hesitation.",
  },
  listening: {
    label: "Listening",
    title: "Train your ear in layers.",
    description:
      "Start with a clear voice, then move toward the speed and texture of real French conversations.",
  },
  writing: {
    label: "Writing",
    title: "Turn grammar into something you can use.",
    description:
      "Build short answers first, then work toward the structured written tasks used in TCF and TEF preparation.",
  },
};

const faqs = [
  {
    question: "Is ParleSprint for complete beginners?",
    answer:
      "Yes. The first path is designed to start with the basics and build useful French in a deliberate order. You do not need to arrive already knowing French grammar or exam strategy.",
  },
  {
    question: "Will it prepare me for TCF and TEF?",
    answer:
      "That is the goal. ParleSprint teaches the underlying French first, then layers in exam-specific listening, speaking, reading, and writing practice for both TCF Canada and TEF Canada.",
  },
  {
    question: "Does ParleSprint guarantee NCLC 7 or permanent residence?",
    answer:
      "No. No app can guarantee a test score or immigration outcome. ParleSprint is built to give you a clearer learning route and focused preparation, while your result depends on your progress and the official test.",
  },
  {
    question: "When will it launch?",
    answer:
      "We are building the first learning path now. Join the early list to see the product take shape and get an invite when the first version is ready to try.",
  },
];

function WaitlistForm({ compact = false }: { compact?: boolean }) {
  const [email, setEmail] = useState("");
  const [status, setStatus] = useState<"idle" | "loading" | "success" | "error">("idle");
  const [message, setMessage] = useState("");

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!email || !email.includes("@")) {
      setStatus("error");
      setMessage("Enter a valid email address to join the list.");
      return;
    }

    setStatus("loading");
    setMessage("");
    try {
      const response = await fetch("/api/waitlist", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const data = (await response.json()) as { ok?: boolean; message?: string };
      if (!response.ok || !data.ok) throw new Error(data.message ?? "Something went wrong.");
      setStatus("success");
      setMessage("You’re on the early list. We’ll keep you posted.");
      setEmail("");
    } catch {
      setStatus("error");
      setMessage("We couldn’t save that just now. Try again in a moment.");
    }
  }

  if (status === "success") {
    return (
      <div className={`form-success ${compact ? "form-success-compact" : ""}`} role="status">
        <span className="success-icon"><Check size={16} strokeWidth={3} /></span>
        <span>{message}</span>
      </div>
    );
  }

  return (
    <form className={`waitlist-form ${compact ? "waitlist-form-compact" : ""}`} onSubmit={handleSubmit} noValidate>
      <label className="sr-only" htmlFor={compact ? "email-compact" : "email-hero"}>Email address</label>
      <input
        id={compact ? "email-compact" : "email-hero"}
        name="email"
        type="email"
        autoComplete="email"
        inputMode="email"
        placeholder="you@example.com"
        value={email}
        onChange={(event) => setEmail(event.target.value)}
        aria-describedby={status === "error" ? `${compact ? "email-compact" : "email-hero"}-error` : undefined}
        aria-invalid={status === "error"}
        required
      />
      <button type="submit" className="button button-primary" disabled={status === "loading"}>
        {status === "loading" ? "Joining…" : compact ? "Join the list" : "Get early access"}
        <ArrowRight size={17} />
      </button>
      {status === "error" && <p id={`${compact ? "email-compact" : "email-hero"}-error`} className="form-error" role="alert">{message}</p>}
    </form>
  );
}

function Logo() {
  return (
    <a className="logo" href="#top" aria-label="ParleSprint home">
      <Image src="/parle-mark.svg" alt="" width={34} height={34} priority />
      <span>Parle<span className="logo-accent">Sprint</span></span>
    </a>
  );
}

export default function Home() {
  const [menuOpen, setMenuOpen] = useState(false);
  const [activeDemo, setActiveDemo] = useState<DemoKey>("path");
  const [openFaq, setOpenFaq] = useState<number | null>(0);
  const activeContent = demoContent[activeDemo];

  return (
    <main id="top">
      <div className="announcement">
        <span className="announcement-dot" />
        <span>ParleSprint is launching soon</span>
        <a href="#waitlist">Join the early list <ArrowUpRight size={13} /></a>
      </div>

      <header className="site-header shell">
        <Logo />
        <nav className={`desktop-nav ${menuOpen ? "mobile-nav-open" : ""}`} aria-label="Main navigation">
          <a href="#method" onClick={() => setMenuOpen(false)}>How it works</a>
          <a href="#preview" onClick={() => setMenuOpen(false)}>Preview</a>
          <a href="#faq" onClick={() => setMenuOpen(false)}>FAQ</a>
          <a className="nav-cta" href="#waitlist" onClick={() => setMenuOpen(false)}>Join the list <ArrowUpRight size={15} /></a>
        </nav>
        <button className="menu-button" type="button" aria-label={menuOpen ? "Close menu" : "Open menu"} aria-expanded={menuOpen} onClick={() => setMenuOpen(!menuOpen)}>
          {menuOpen ? <X size={22} /> : <Menu size={22} />}
        </button>
      </header>

      <section className="hero shell section-space">
        <div className="hero-copy">
          <p className="eyebrow"><span className="eyebrow-line" /> French for the future you’re building</p>
          <h1>Start at zero.<br /><em>Move toward NCLC 7.</em></h1>
          <p className="hero-lede">ParleSprint is the structured path from beginner French to TCF and TEF readiness — with every next step made clear.</p>
          <WaitlistForm />
          <p className="form-note"><LockKeyhole size={13} /> Free to join · No spam · Built for English-speaking beginners</p>
        </div>

        <div className="route-preview" aria-label="Preview of the ParleSprint learning route">
          <div className="route-topline">
            <span className="preview-label"><span className="live-dot" /> Early product preview</span>
            <span className="preview-kicker">Your French route</span>
          </div>
          <div className="route-heading">
            <div>
              <p className="micro-label">Next up</p>
              <h2>Introducing yourself</h2>
            </div>
            <span className="route-time"><Timer size={14} /> 8 min</span>
          </div>
          <div className="route-map">
            <div className="route-line"><span className="route-progress" /></div>
            <div className="route-stop stop-active"><span>A1</span><small>Begin</small></div>
            <div className="route-stop stop-complete"><span>✓</span><small>Basics</small></div>
            <div className="route-stop"><span>A2</span><small>Build</small></div>
            <div className="route-stop"><span>B1</span><small>Connect</small></div>
            <div className="route-stop stop-target"><span>7</span><small>NCLC</small></div>
          </div>
          <div className="lesson-card">
            <div className="lesson-icon"><Volume2 size={20} /></div>
            <div className="lesson-copy">
              <span className="micro-label">Lesson 04 · Listen + say</span>
              <strong>Je m’appelle…</strong>
              <span>Hear it. Shape it. Use it.</span>
            </div>
            <button type="button" className="play-button" aria-label="Preview lesson audio"><ArrowRight size={17} /></button>
          </div>
          <div className="route-footer"><span><Sparkles size={14} /> Built around your next useful win</span><span>01 / 12</span></div>
        </div>
      </section>

      <section className="proof-strip">
        <div className="shell proof-inner">
          <span className="proof-intro">One path. Four skills.</span>
          <span><Headphones size={16} /> Listening</span>
          <span><Languages size={16} /> Speaking</span>
          <span><BookOpen size={16} /> Reading</span>
          <span><PenLine size={16} /> Writing</span>
          <span className="proof-end">TCF + TEF ready</span>
        </div>
      </section>

      <section className="problem-section shell section-space" id="method">
        <div className="section-intro split-intro">
          <div>
            <p className="eyebrow"><span className="eyebrow-line" /> The problem with “just practise”</p>
            <h2>French is easier to start when the route is visible.</h2>
          </div>
          <p>Most apps give you a streak. Most exam books give you a pile of tasks. ParleSprint connects the two: learn the language, practise the skill, see what comes next.</p>
        </div>
        <div className="method-grid">
          <article className="method-card method-card-featured">
            <span className="card-index">01</span>
            <div className="method-icon route-icon"><Route size={22} /></div>
            <h3>A route, not a random feed.</h3>
            <p>Move through a sequence built for real beginners — with small milestones that make a long-term goal feel close enough to take today.</p>
            <div className="mini-route"><span className="mini-active" /><span /><span /><span /><i>→</i></div>
          </article>
          <article className="method-card">
            <span className="card-index">02</span>
            <div className="method-icon orange-icon"><Volume2 size={22} /></div>
            <h3>Practice the whole language.</h3>
            <p>Listen, speak, read, and write in the same learning loop — so the French you recognise becomes French you can use.</p>
            <div className="skill-chips"><span>écouter</span><span>parler</span><span>écrire</span></div>
          </article>
          <article className="method-card">
            <span className="card-index">03</span>
            <div className="method-icon blue-icon"><Sparkles size={22} /></div>
            <h3>Exam-ready without exam-only.</h3>
            <p>Build the foundation first, then layer in TCF and TEF patterns when they become useful — not before you know what they mean.</p>
            <div className="nclc-chip"><span className="nclc-dot" /> NCLC 7 is a direction, not a shortcut</div>
          </article>
        </div>
      </section>

      <section className="dark-section" id="preview">
        <div className="shell section-space demo-section">
          <div className="section-intro demo-intro">
            <div>
              <p className="eyebrow eyebrow-light"><span className="eyebrow-line" /> A small look ahead</p>
              <h2>The practice loop that keeps you moving.</h2>
            </div>
            <p>Every exercise has a reason to be there. Choose a part of the route to see how ParleSprint turns a skill into a next step.</p>
          </div>
          <div className="demo-window">
            <div className="demo-sidebar">
              <div className="demo-sidebar-brand"><span className="sidebar-mark">P</span><span>ParleSprint</span></div>
              <div className="demo-side-label">Today’s route</div>
              <div className="demo-side-lesson active"><span>01</span><div><strong>Meet & greet</strong><small>In progress</small></div></div>
              <div className="demo-side-lesson"><span>02</span><div><strong>Daily rhythm</strong><small>Next</small></div></div>
              <div className="demo-side-lesson muted"><span>03</span><div><strong>Make a plan</strong><small>Locked</small></div></div>
              <div className="demo-sidebar-bottom"><span className="streak-badge">4</span><div><strong>day route</strong><small>Keep the habit small</small></div></div>
            </div>
            <div className="demo-main">
              <div className="demo-topbar"><span className="demo-breadcrumb">Path / A1 / Meet & greet</span><span className="demo-progress">12% complete</span></div>
              <div className="demo-main-content">
                <div className="demo-copy">
                  <span className="demo-label">{activeContent.label}</span>
                  <h3>{activeContent.title}</h3>
                  <p>{activeContent.description}</p>
                  <button type="button" className="demo-action">Try the next step <ArrowRight size={16} /></button>
                </div>
                <div className="demo-artifact">
                  {activeDemo === "path" && <div className="artifact-route"><div className="artifact-route-line" /><div className="artifact-node done"><Check size={13} /></div><div className="artifact-node current">A1</div><div className="artifact-node">A2</div><div className="artifact-node">B1</div><div className="artifact-node target">7</div><div className="artifact-label one">Start here</div><div className="artifact-label two">Next useful win</div><div className="artifact-label three">Your destination</div></div>}
                  {activeDemo === "speaking" && <div className="artifact-speaking"><div className="speech-bubble">Bonjour, je m’appelle Marie.<span>Good start.</span></div><div className="speech-bubble reply">Et toi, comment tu t’appelles ?<span>Now you.</span></div><div className="mic-orb"><Volume2 size={22} /></div></div>}
                  {activeDemo === "listening" && <div className="artifact-listening"><div className="sound-bars"><span /><span /><span /><span /><span /><span /><span /><span /><span /></div><div className="listening-word">écouter</div><div className="listening-note"><Headphones size={15} /> Hear the shape of the sentence</div></div>}
                  {activeDemo === "writing" && <div className="artifact-writing"><div className="writing-line">Je voudrais réserver une table<span className="writing-caret" /></div><div className="writing-line faint">pour deux personnes, s’il vous plaît.</div><div className="writing-check"><Check size={14} /> Structure is getting clearer</div></div>}
                </div>
              </div>
              <div className="demo-tabs" role="tablist" aria-label="Practice areas">
                {(Object.keys(demoContent) as DemoKey[]).map((key) => <button key={key} type="button" role="tab" aria-selected={activeDemo === key} className={activeDemo === key ? "active" : ""} onClick={() => setActiveDemo(key)}>{demoContent[key].label}</button>)}
              </div>
            </div>
          </div>
          <p className="demo-disclaimer">Product preview — the first version is being shaped with early learners.</p>
        </div>
      </section>

      <section className="roadmap-section shell section-space">
        <div className="section-intro split-intro">
          <div>
            <p className="eyebrow"><span className="eyebrow-line" /> What we’re building</p>
            <h2>Small steps. A serious destination.</h2>
          </div>
          <p>ParleSprint is launching in layers so the foundation feels as considered as the exam practice built on top of it.</p>
        </div>
        <div className="roadmap">
          <div className="roadmap-line" />
          <article className="roadmap-item current"><div className="roadmap-dot"><span /></div><div className="roadmap-copy"><span className="roadmap-status">Building now</span><h3>The beginner route</h3><p>Essential grammar, useful vocabulary, clear listening, and the confidence to say your first real sentences.</p></div><span className="roadmap-tag">A1 → A2</span></article>
          <article className="roadmap-item"><div className="roadmap-dot"><span /></div><div className="roadmap-copy"><span className="roadmap-status">Next on the route</span><h3>TCF + TEF practice rooms</h3><p>Focused training for the four skills, with mock tasks that make the format familiar without replacing real learning.</p></div><span className="roadmap-tag">B1 → B2</span></article>
          <article className="roadmap-item"><div className="roadmap-dot"><span /></div><div className="roadmap-copy"><span className="roadmap-status">The long game</span><h3>Your study plan, made personal</h3><p>Progress signals and a daily rhythm that help you understand what to practise next and why it matters.</p></div><span className="roadmap-tag">NCLC 7</span></article>
        </div>
      </section>

      <section className="faq-section shell section-space" id="faq">
        <div className="faq-heading"><p className="eyebrow"><span className="eyebrow-line" /> Questions worth asking</p><h2>No mystery language.</h2><p>What ParleSprint is, what it isn’t, and where it’s going next.</p></div>
        <div className="faq-list">
          {faqs.map((faq, index) => <div className={`faq-item ${openFaq === index ? "open" : ""}`} key={faq.question}><button type="button" className="faq-question" aria-expanded={openFaq === index} onClick={() => setOpenFaq(openFaq === index ? null : index)}><span>{faq.question}</span><ChevronDown size={19} /></button>{openFaq === index && <p className="faq-answer">{faq.answer}</p>}</div>)}
        </div>
      </section>

      <section className="final-cta shell" id="waitlist">
        <div className="final-cta-inner">
          <div><p className="eyebrow eyebrow-light"><span className="eyebrow-line" /> Come build the route with us</p><h2>Your next French chapter starts here.</h2><p>Join the early list for the first look at ParleSprint and a clearer way to prepare for the French you need.</p></div>
          <div className="final-form-wrap"><WaitlistForm compact /><p className="form-note form-note-light"><LockKeyhole size={13} /> No noise. Just useful launch updates.</p></div>
        </div>
      </section>

      <footer className="site-footer shell"><Logo /><p>Learn French. Move forward.</p><div className="footer-links"><a href="#method">How it works</a><a href="#preview">Preview</a><a href="#faq">FAQ</a><span>© 2026 ParleSprint</span></div></footer>
    </main>
  );
}
