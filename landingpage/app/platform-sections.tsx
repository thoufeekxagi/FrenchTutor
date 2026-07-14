import Image, { StaticImageData } from "next/image";
import { ArrowRight, BookOpen, Check, Clock3, Headphones, Mic, PenLine, SlidersHorizontal, Volume2 } from "lucide-react";
import callImage from "../../marketing/ad/marie_live_call.png";
import flashcardImage from "../../marketing/ad/flashcard_bus_stop.png";
import grammarImage from "../../marketing/ad/grammar_drill_train.png";
import writingImage from "../../marketing/ad/cozy_writing_task.png";
import { MarieDemo } from "./product-visuals";

const modes: { label: string; title: string; copy: string; image: StaticImageData; icon: React.ReactNode }[] = [
  { label: "A few free minutes", title: "Recall what matters.", copy: "Use focused flashcards and spaced repetition while you wait.", image: flashcardImage, icon: <Clock3 size={16} /> },
  { label: "Moving through your day", title: "Listen and follow.", copy: "Use narrated lessons and guided listening when audio fits the moment.", image: grammarImage, icon: <Headphones size={16} /> },
  { label: "Ready to interact", title: "Speak and respond.", copy: "Practise live with Marie using the material already in your path.", image: callImage, icon: <Mic size={16} /> },
  { label: "Focused at a desk", title: "Write, refine, understand.", copy: "Work through structured tasks and turn correction into the next attempt.", image: writingImage, icon: <PenLine size={16} /> },
];

export function PracticeModes() {
  return (
    <section className="modes-section shell section-space" id="modes">
      <div className="section-heading split-heading light-heading">
        <div><p className="eyebrow"><span /> Meet the moment</p><h2>French practice that fits the time and attention you have.</h2></div>
        <p>No single mode works for every day. Choose quick recall, guided audio, live interaction, or deeper focused work—without leaving the same learning system.</p>
      </div>
      <div className="mode-grid">
        {modes.map((mode, index) => (
          <article className={`mode-card mode-${index + 1}`} key={mode.title}>
            <Image src={mode.image} alt="" fill sizes="(max-width: 760px) 100vw, 50vw" />
            <div className="mode-shade" />
            <div className="mode-copy"><span>{mode.icon}{mode.label}</span><h3>{mode.title}</h3><p>{mode.copy}</p></div>
          </article>
        ))}
      </div>
    </section>
  );
}

export function PathwaySection() {
  const stages = [
    ["01", "Vocabulary", "Recall and pronounce useful words"],
    ["02", "Grammar", "Build a pattern with those words"],
    ["03", "Read & listen", "Recognize them inside context"],
    ["04", "Writing", "Produce the idea independently"],
    ["05", "Speaking", "Use today’s French with Marie"],
  ];
  return (
    <section className="pathway-section">
      <div className="shell section-space pathway-layout">
        <div className="pathway-copy">
          <p className="eyebrow"><span /> Today’s pathway</p>
          <h2>Know what to do next—without giving up control.</h2>
          <p>Follow one connected pathway when you want guidance. Open a focused Lab when you already know what you want to improve.</p>
          <div className="choice-row"><span><Check size={14} /> Guided when you need direction</span><span><Check size={14} /> Flexible when you want control</span></div>
          <a href="#founding" className="text-link">Help shape the first pathway <ArrowRight size={16} /></a>
        </div>
        <div className="pathway-board">
          <div className="board-head"><div><small>Today · Standard pace</small><strong>Use French to ask for information</strong></div><span>14 min</span></div>
          <div className="board-progress"><i /></div>
          {stages.map(([number, title, copy], index) => (
            <div className={index === 1 ? "board-stage current" : index === 0 ? "board-stage done" : "board-stage"} key={title}>
              <span>{index === 0 ? <Check size={14} /> : number}</span><div><strong>{title}</strong><small>{copy}</small></div>{index === 1 && <em>Continue</em>}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export function MarieSection() {
  return (
    <section className="marie-section shell section-space" id="marie">
      <MarieDemo />
      <div className="marie-copy">
        <p className="eyebrow"><span /> Live, contextual voice</p>
        <h2>A tutor who already knows what you practised.</h2>
        <p>Marie is a live AI French tutor that adapts her language, pace, corrections, and questions to your level and the material in your current path. You do not begin every conversation from zero.</p>
        <ul>
          <li><Volume2 size={17} /><div><strong>Voice-to-voice interaction</strong><span>Speak naturally and hear a response in real time.</span></div></li>
          <li><BookOpen size={17} /><div><strong>Lesson-aware practice</strong><span>Use the vocabulary and patterns you just studied.</span></div></li>
          <li><SlidersHorizontal size={17} /><div><strong>Support that changes</strong><span>More English when needed, more French as you progress.</span></div></li>
        </ul>
      </div>
    </section>
  );
}

export function PersonalizationSection() {
  const abilities = ["Introduce yourself naturally", "Understand a short announcement", "Write a structured email", "Defend a simple opinion"];
  return (
    <section className="personal-section">
      <div className="shell section-space personal-layout">
        <div>
          <p className="eyebrow eyebrow-light"><span /> Progress with meaning</p>
          <h2>Self-paced does not mean directionless.</h2>
          <p>Go gently when life is busy. Push harder when you are ready. Your path can adjust its duration, difficulty, review timing, and language support without lowering the destination.</p>
        </div>
        <div className="ability-card">
          <div className="ability-head"><span>This week</span><strong>What you can now do</strong></div>
          {abilities.map((ability, index) => <div className="ability-row" key={ability}><span><Check size={13} /></span><p>{ability}</p><small>{index < 2 ? "Confident" : "Developing"}</small></div>)}
          <div className="next-session"><span>Next session</span><strong>4 reviews + a café roleplay</strong></div>
        </div>
      </div>
    </section>
  );
}
