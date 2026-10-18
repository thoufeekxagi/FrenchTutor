"use client";

import Link from "next/link";
import { useState } from "react";
import { ArrowRight, Bookmark, Check, RotateCcw } from "lucide-react";
import { useLearner } from "./learner-provider";

const answers = ["I would like", "I already have", "I don’t like"];

export function HomePractice() {
  const [answer, setAnswer] = useState<number | null>(null);
  const [saved, setSaved] = useState(false);
  const { saveWord } = useLearner();

  return (
    <section className="hero-practice" aria-label="Try a sample French question">
      <div className="practice-card-top">
        <span><i aria-hidden="true" /> A TASTE OF EVERYDAY FRENCH</span>
        <span className="level-pill">A1 · Beginner</span>
      </div>

      <div className="sample-context">
        <span className="sample-index">01</span>
        <div>
          <span className="sample-eyebrow">A SMALL MOMENT</span>
          <strong>At the café</strong>
        </div>
        <span className="sample-duration">2 min</span>
      </div>

      <div className="practice-card-body">
        <p className="mini-label">ONE USEFUL PHRASE</p>
        <p className="sample-phrase" lang="fr">« Je voudrais un café,<br />s’il vous plaît. »</p>
        <p className="sample-question">What does <strong lang="fr">je voudrais</strong> mean?</p>

        <div className="mini-options" role="group" aria-label="Choose the meaning">
          {answers.map((label, index) => (
            <button
              key={label}
              type="button"
              onClick={() => setAnswer(index)}
              className={answer === index ? (index === 0 ? "correct" : "incorrect") : ""}
              aria-pressed={answer === index}
            >
              <span>{answer === index && index === 0 ? <Check size={14} /> : String.fromCharCode(65 + index)}</span>
              {label}
            </button>
          ))}
        </div>

        {answer !== null && (
          <div className="inline-result" role="status">
            <strong>{answer === 0 ? "Exactly." : "Here’s the useful bit."}</strong>
            <span> <span lang="fr">Je voudrais</span> means “I would like”. It’s a polite way to ask for something.</span>
            <button
              className="text-link"
              type="button"
              onClick={() => {
                saveWord("Je voudrais", "I would like", "Je voudrais un café, s’il vous plaît.");
                setSaved(true);
              }}
            >
              <Bookmark size={14} />{saved ? "Saved to My words" : "Keep this phrase"}
            </button>
          </div>
        )}

        <div className="practice-card-bottom">
          <span>{answer === null ? "A small start is still a start." : "Your words stay on this device."}</span>
          {answer === null ? (
            <span className="tiny-clock">Free · no account</span>
          ) : (
            <div className="sample-next-actions">
              <button
                className="icon-button"
                type="button"
                aria-label="Reset sample question"
                onClick={() => { setAnswer(null); setSaved(false); }}
              >
                <RotateCcw size={15} />
              </button>
              <Link href="/today" aria-label="Continue to daily practice"><ArrowRight size={18} /></Link>
            </div>
          )}
        </div>
      </div>
    </section>
  );
}
