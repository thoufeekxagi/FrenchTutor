"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft, ArrowRight, X } from "lucide-react";
import { useLearner } from "./learner-provider";
import { levels, type Level } from "../lib/practice";

const goals = [
  { label: "Daily practice", href: "/today" },
  { label: "Writing", href: "/tools/french-writing" },
  { label: "Reading", href: "/tools/french-reading" },
  { label: "Verb practice", href: "/tools/french-verb-practice" },
];
const timeOptions = [5, 10, 15] as const;

export function FirstVisitPlan() {
  const router = useRouter();
  const { prefs, setPreferences } = useLearner();
  const [open, setOpen] = useState(false);
  const [step, setStep] = useState(0);
  const [level, setLevel] = useState<Level>("A1");
  const [goal, setGoal] = useState(goals[0].label);
  const [minutes, setMinutes] = useState<(typeof timeOptions)[number]>(5);
  const dialog = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    dialog.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") setOpen(false);
      if (event.key === "Tab") {
        const controls = dialog.current?.querySelectorAll<HTMLElement>("button:not([disabled]), a[href], [tabindex]:not([tabindex='-1'])");
        if (!controls?.length) return;
        const first = controls[0];
        const last = controls[controls.length - 1];
        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault();
          last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }
    };
    const oldOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.body.style.overflow = oldOverflow;
      document.removeEventListener("keydown", onKeyDown);
      previous?.focus();
    };
  }, [open]);

  function begin() {
    setLevel(prefs.level);
    setStep(0);
    setOpen(true);
  }

  function startPractice() {
    const firstStop = goals.find((item) => item.label === goal) ?? goals[0];
    try {
      localStorage.setItem("ps.onboarding.v1", JSON.stringify({ level, goal, minutes, completedAt: new Date().toISOString() }));
    } catch {
      // The plan remains usable even when browser storage is unavailable.
    }
    setPreferences({ level });
    setOpen(false);
    router.push(firstStop.href);
  }

  return (
    <>
      <button className="button button-primary" type="button" onClick={begin}>
        Make my free plan <ArrowRight size={17} />
      </button>

      {open && (
        <div className="plan-overlay" onMouseDown={(event) => { if (event.target === event.currentTarget) setOpen(false); }}>
          <section
            className="plan-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="plan-title"
            aria-describedby="plan-description"
            tabIndex={-1}
            ref={dialog}
          >
            <div className="plan-dialog-top">
              <span className="eyebrow">A STARTING POINT, NOT A TEST</span>
              <button className="icon-button" type="button" aria-label="Close setup" onClick={() => setOpen(false)}><X size={19} /></button>
            </div>

            <div className="plan-progress" aria-label={`Step ${step + 1} of 3`}>
              {steps.map((label, index) => <span key={label} className={index <= step ? "active" : ""} />)}
            </div>

            <p className="plan-step-label">STEP 0{step + 1} / 03</p>
            <h2 id="plan-title">{steps[step]}</h2>
            <p className="plan-description" id="plan-description">
              {step === 0 && "Choose a comfortable place to begin. You can change it whenever you like."}
              {step === 1 && "Choose a tool. We’ll take you straight there."}
              {step === 2 && "A few minutes is enough to make a start. This is your pace, not a promise."}
            </p>

            {step === 0 && (
              <div className="plan-choices level-choices" role="group" aria-label="Choose your French level">
                {levels.map((item) => (
                  <button key={item} type="button" aria-pressed={level === item} onClick={() => setLevel(item)}>
                    <strong>{item}</strong>
                    <span>{levelDescriptions[item]}</span>
                  </button>
                ))}
              </div>
            )}

            {step === 1 && (
              <div className="plan-choices reason-choices" role="group" aria-label="Choose what you want to practise">
                {goals.map((item) => <button key={item.label} type="button" aria-pressed={goal === item.label} onClick={() => setGoal(item.label)}>{item.label}</button>)}
              </div>
            )}

            {step === 2 && (
              <>
                <div className="plan-choices time-choices" role="group" aria-label="Choose daily practice time">
                  {timeOptions.map((item) => <button key={item} type="button" aria-pressed={minutes === item} onClick={() => setMinutes(item)}><strong>{item}</strong><span>minutes a day</span></button>)}
                </div>
                <p className="plan-summary">Your first stop: <strong>{level} · {goal} · {minutes} minutes a day</strong></p>
              </>
            )}

            <div className="plan-dialog-actions">
              {step > 0 ? <button className="button button-secondary" type="button" onClick={() => setStep(step - 1)}><ArrowLeft size={16} /> Back</button> : <span />}
              {step < 2 ? (
                <button className="button button-primary" type="button" onClick={() => setStep(step + 1)}>Continue <ArrowRight size={16} /></button>
              ) : (
                <button className="button button-primary" type="button" onClick={startPractice}>Start today’s practice <ArrowRight size={16} /></button>
              )}
            </div>
            <div className="plan-dialog-foot">
              <span>No account needed. Your choices stay in this browser.</span>
              <button type="button" className="text-link" onClick={() => { setOpen(false); router.push("/today"); }}>Skip setup</button>
            </div>
          </section>
        </div>
      )}
    </>
  );
}

const steps = ["Where are you starting?", "What would you like to practise?", "How much time feels right?"];
const levelDescriptions: Record<Level, string> = {
  A1: "Starting fresh",
  A2: "Know a few basics",
  B1: "Can manage a conversation",
  B2: "Ready for more nuance",
};
