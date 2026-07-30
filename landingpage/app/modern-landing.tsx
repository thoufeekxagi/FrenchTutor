"use client";

import React, { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowRight, BookOpen, Brain, Check, Clock, GraduationCap, Headphones, MapPin, MessageCircle, Mic, PenLine, Briefcase, Repeat, RotateCcw, Smartphone, Monitor, X } from "lucide-react";
import { Logo, LogoMark } from "./logo";
import { SiteNav } from "./SiteNav";
import { SiteFooter } from "./SiteFooter";
import { ProblemSection } from "./problem-section";
import { ExperienceSection } from "./experience-section";
import { ProofSection } from "./proof-section";
import { FaqSection } from "./faq-section";
import { getSortedPosts } from "./blog/data";

// ----------------------------------------------------------------------
// SCROLL REVEAL COMPONENT (SEO Friendly "Pan In")
// ----------------------------------------------------------------------
function Reveal({ children, delay = 0, className = "" }: { children: React.ReactNode, delay?: number, className?: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [isVisible, setIsVisible] = useState(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsVisible(true);
          observer.disconnect();
        }
      },
      { threshold: 0.1, rootMargin: "0px 0px -50px 0px" }
    );
    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      className={className}
      style={{
        opacity: isVisible ? 1 : 0,
        transform: isVisible ? "translateY(0)" : "translateY(30px)",
        transition: `opacity 0.8s cubic-bezier(0.16, 1, 0.3, 1) ${delay}s, transform 0.8s cubic-bezier(0.16, 1, 0.3, 1) ${delay}s`,
        willChange: "opacity, transform"
      }}
    >
      {children}
    </div>
  );
}

// ----------------------------------------------------------------------
// SLEEK DEVICE MOCKUPS (Properly Scaled)
// ----------------------------------------------------------------------
function SleekDevice({ type, title, subtitle, active }: { type: "ios" | "android" | "web", title: string, subtitle: string, active: string }) {
  const isWeb = type === "web";

  return (
    <div className={`relative flex flex-col mx-auto ${isWeb ? 'w-full max-w-lg aspect-[4/3]' : 'w-[260px] aspect-[1/2.1]'} bg-white border border-[#e5e7eb] rounded-[2rem] shadow-2xl overflow-hidden`}>
      {/* Device Header */}
      {isWeb ? (
        <div className="h-10 bg-[#EEF0F2] border-b border-[#e5e7eb] flex items-center px-4 gap-2">
          <div className="flex gap-1.5">
            <div className="w-3 h-3 rounded-full bg-[#ff5f56]" />
            <div className="w-3 h-3 rounded-full bg-[#ffbd2e]" />
            <div className="w-3 h-3 rounded-full bg-[#27c93f]" />
          </div>
          <div className="ml-4 bg-white rounded-md h-6 w-48 text-[10px] text-center font-medium text-[#6b7280] leading-6 border border-[#e5e7eb]">parlesprint.app</div>
        </div>
      ) : (
        <div className="h-7 w-full flex justify-between items-center px-6 pt-2">
          <span className="text-[10px] font-bold text-[#1C1E21]">9:41</span>
          <div className="w-16 h-4 bg-black rounded-b-xl absolute top-0 left-1/2 -translate-x-1/2" />
        </div>
      )}

      {/* Device Screen Content */}
      <div className="flex-1 p-6 flex flex-col">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <LogoMark size={22} />
            <span className="font-bold text-xs text-[#1C1E21]">{isWeb ? "Your French path" : "Today"}</span>
          </div>
          <span className="text-[10px] font-medium text-[#6b7280]">Week 02</span>
        </div>

        <div className="mt-2">
          <h4 className="text-lg font-bold text-[#1C1E21] tracking-tight leading-tight">{title}</h4>
          <p className="text-[#6b7280] text-xs font-medium mt-1">{subtitle}</p>
        </div>

        <div className="mt-6 flex flex-col gap-3">
          <div className="flex items-center gap-3 p-3 rounded-xl border border-[#e5e7eb] bg-white">
            <div className="w-8 h-8 rounded-full bg-[#e7f6ec] flex items-center justify-center">
              <Check className="w-4 h-4 text-[#28A745]" />
            </div>
            <div>
              <div className="text-xs font-bold text-[#1C1E21]">Review essentials</div>
              <div className="text-[10px] text-[#6b7280]">4 min • Complete</div>
            </div>
          </div>

          <div className="flex items-center gap-3 p-3 rounded-xl border-2 border-[#007BFF] bg-[#f8fbff] shadow-[0_4px_12px_rgba(0,123,255,0.1)]">
            <div className="w-8 h-8 rounded-full bg-[#007BFF] flex items-center justify-center">
              <Headphones className="w-4 h-4 text-white" />
            </div>
            <div>
              <div className="text-xs font-bold text-[#1C1E21]">{active}</div>
              <div className="text-[10px] text-[#007BFF] font-medium">Grammar • 8 min</div>
            </div>
          </div>

          <div className="flex items-center gap-3 p-3 rounded-xl border border-[#e5e7eb] bg-white opacity-60">
            <div className="w-8 h-8 rounded-full bg-[#EEF0F2] flex items-center justify-center">
              <Mic className="w-4 h-4 text-[#6b7280]" />
            </div>
            <div>
              <div className="text-xs font-bold text-[#1C1E21]">Speak with Marie</div>
              <div className="text-[10px] text-[#6b7280]">Roleplay • 5 min</div>
            </div>
          </div>
        </div>

        {!isWeb && (
          <div className="mt-auto pt-4 flex justify-center">
            <div className="w-1/3 h-1 bg-[#1C1E21] rounded-full opacity-20" />
          </div>
        )}
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------
// TUTOR COMPARISON (price anchor: private tutor vs ParleSprint)
// ----------------------------------------------------------------------
const tutorComparison = [
  {
    label: "Availability",
    tutor: "Booked days ahead, 1–2 hours a week",
    us: "24/7. Practise at 6 a.m. before work or 11 p.m. after the kids sleep",
  },
  {
    label: "Memory of you",
    tutor: "Notes, if you're lucky",
    us: "Every session, every recurring mistake, your whole vocabulary state",
  },
  {
    label: "Judgment",
    tutor: "A real person watching you struggle",
    us: "No embarrassment. Make the same mistake ten times and Marie won't sigh",
  },
  {
    label: "Speaking time",
    tutor: "Split with explanations and small talk",
    us: "You speak from minute one, every single day",
  },
  {
    label: "Cost",
    tutor: "$40–70 per hour, $400+ a month for real momentum",
    us: "A fraction of one lesson's price, for daily practice",
  },
];

function TutorComparisonSection() {
  return (
    <section id="vs-tutor" className="py-24 bg-[#1C1E21] text-white relative z-10">
      <div className="max-w-5xl mx-auto px-6">
        <Reveal className="text-center max-w-2xl mx-auto mb-14">
          <div className="inline-flex items-center gap-2 rounded-full bg-[rgba(0,123,255,0.15)] px-3 py-1.5 text-xs font-semibold uppercase tracking-widest text-[#4da3ff] mb-6">
            <Clock className="h-3.5 w-3.5" /> Tutor-level attention, app-level price
          </div>
          <h2 className="text-4xl md:text-5xl font-extrabold tracking-tight mb-6">
            A private tutor costs $400 a month.
          </h2>
          <p className="text-xl text-[#9ca3af]">
            And even the best one isn&apos;t there at 6 a.m., doesn&apos;t remember every mistake you&apos;ve ever made, and can&apos;t practise with you every single day. Marie is, does, and can.
          </p>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="rounded-3xl border border-[rgba(255,255,255,0.12)] overflow-hidden">
            <div className="grid grid-cols-[110px_1fr_1fr] sm:grid-cols-[160px_1fr_1fr] text-xs sm:text-sm font-bold uppercase tracking-wider">
              <div className="px-4 sm:px-6 py-4 text-[#6b7280]"></div>
              <div className="px-4 sm:px-6 py-4 text-[#9ca3af]">Private tutor</div>
              <div className="px-4 sm:px-6 py-4 bg-[#007BFF] text-white flex items-center gap-2"><LogoMark size={18} /> ParleSprint</div>
            </div>
            {tutorComparison.map((row) => (
              <div key={row.label} className="grid grid-cols-[110px_1fr_1fr] sm:grid-cols-[160px_1fr_1fr] border-t border-[rgba(255,255,255,0.08)]">
                <div className="px-4 sm:px-6 py-5 text-xs sm:text-sm font-bold text-[#9ca3af] uppercase tracking-wide">{row.label}</div>
                <div className="px-4 sm:px-6 py-5 flex items-start gap-2 text-sm text-[#9ca3af] font-medium">
                  <X className="w-4 h-4 text-[#4b5563] shrink-0 mt-0.5" />
                  <span>{row.tutor}</span>
                </div>
                <div className="px-4 sm:px-6 py-5 flex items-start gap-2 text-sm font-semibold bg-[rgba(0,123,255,0.08)]">
                  <Check className="w-4 h-4 text-[#4da3ff] shrink-0 mt-0.5" />
                  <span>{row.us}</span>
                </div>
              </div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  );
}

// ----------------------------------------------------------------------
// PRICING (founding-cohort tiers, priced against the tutor comparison above)
// ----------------------------------------------------------------------
const pricingTiers = [
  {
    name: "Free",
    price: "$0",
    period: "forever",
    highlight: false,
    features: [
      "60 minutes of live speaking with Marie, every day",
      "Full daily loop: vocabulary, grammar, listening, writing",
      "Spaced-repetition review",
      "Basic exam-prep resources",
    ],
    cta: "Start free",
  },
  {
    name: "Founding Starter",
    price: "$9.99",
    period: "one-time · 3 months",
    highlight: false,
    features: [
      "Everything in Free",
      "Full TEF/TCF exam-prep resource library",
      "Early access to new features as they ship",
      "No recurring charge, no auto-renewal",
    ],
    cta: "Lock in this price",
  },
  {
    name: "Founding Year",
    price: "$49.99",
    period: "one-time · 12 months",
    highlight: true,
    features: [
      "2 hours of live speaking with Marie, every day",
      "Full TEF/TCF exam-prep resource library",
      "Early access to new features as they ship",
      "No recurring charge, no auto-renewal",
    ],
    cta: "Lock in this price",
  },
];

function PricingSection() {
  return (
    <section id="pricing" className="py-24 bg-[#F8F9FA] relative z-10">
      <div className="max-w-6xl mx-auto px-6">
        <Reveal className="text-center max-w-2xl mx-auto mb-16">
          <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Founding pricing</div>
          <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight mb-6">
            Pay once. No surprise charges.
          </h2>
          <p className="text-xl text-[#6b7280] leading-relaxed">
            No monthly billing, no auto-renewal to remember to cancel. Founding-cohort prices are locked in for as
            long as your access lasts, before public pricing opens.
          </p>
        </Reveal>

        <div className="grid md:grid-cols-3 gap-6 items-stretch">
          {pricingTiers.map((tier, idx) => (
            <Reveal key={tier.name} delay={idx * 0.1} className="h-full">
              <div
                className={`h-full flex flex-col rounded-3xl p-8 border-2 transition-all text-[#1C1E21] ${
                  tier.highlight
                    ? "bg-[#F8FBFF] border-[#007BFF] shadow-xl md:-translate-y-3"
                    : "bg-white border-[#e5e7eb]"
                }`}
              >
                {tier.highlight && (
                  <span className="inline-flex self-start items-center rounded-full bg-[#007BFF] px-3 py-1 text-xs font-bold uppercase tracking-widest text-white mb-5">
                    Best value
                  </span>
                )}
                <h3 className="text-lg font-bold mb-1 text-[#1C1E21]">{tier.name}</h3>
                <div className="flex items-baseline gap-2 mb-1">
                  <span className="text-4xl font-extrabold tracking-tight">{tier.price}</span>
                </div>
                <p className="text-sm font-semibold mb-6 text-[#6b7280]">{tier.period}</p>

                <ul className="flex flex-col gap-3 mb-8 flex-1">
                  {tier.features.map((feature) => (
                    <li key={feature} className="flex items-start gap-3 text-sm font-medium">
                      <Check className="w-4 h-4 shrink-0 mt-0.5 text-[#007BFF]" />
                      <span className="text-[#33383F]">{feature}</span>
                    </li>
                  ))}
                </ul>

                <a
                  href="#join"
                  className={`inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 font-bold text-sm transition-all ${
                    tier.highlight
                      ? "bg-[#007BFF] hover:bg-[#0062CC] text-white"
                      : "bg-[#1C1E21] hover:bg-[#33383F] text-white"
                  }`}
                >
                  {tier.cta} <ArrowRight className="w-4 h-4" />
                </a>
              </div>
            </Reveal>
          ))}
        </div>

        <Reveal delay={0.3} className="mt-10 text-center">
          <p className="text-sm font-medium text-[#9ca3af] max-w-2xl mx-auto">
            No payment today. Joining the early list reserves these prices for when paid access opens, it does not
            charge your card.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

// ----------------------------------------------------------------------
// SEGMENTS (highest-intent visitors get their own doorway)
// ----------------------------------------------------------------------
const segments = [
  {
    icon: <GraduationCap className="w-6 h-6" />,
    title: "TEF / TCF for Canada",
    body: "The oral is the section everyone fears: no time to think, you have to be spontaneous. Practise it every single day, on real everyday French first, exam format second.",
    tag: "CLB 7 · Express Entry",
  },
  {
    icon: <MapPin className="w-6 h-6" />,
    title: "New to Canada or Quebec",
    body: "Francisation classes full, cancelled, or clashing with your shift? Your tutor is available before work and after the kids are asleep. No waitlist.",
    tag: "No schedule, no waitlist",
  },
  {
    icon: <Briefcase className="w-6 h-6" />,
    title: "Professionals",
    body: "You don't need tourist French. You need to hold your own in a meeting, an interview, a call. Roleplay the exact situations your week throws at you.",
    tag: "French for the job you have",
  },
];

function SegmentsSection() {
  return (
    <section id="who-its-for" className="py-24 bg-[#F8F9FA] relative z-10">
      <div className="max-w-7xl mx-auto px-6">
        <Reveal className="max-w-2xl mb-14">
          <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Who it&apos;s for</div>
          <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight mb-6">
            Built for people with a real reason to speak French.
          </h2>
          <p className="text-xl text-[#6b7280]">Not points, not streaks. A deadline, a move, a career. Your path calibrates to yours.</p>
        </Reveal>

        <div className="grid md:grid-cols-3 gap-6">
          {segments.map((s, idx) => (
            <Reveal key={s.title} delay={idx * 0.1} className="h-full">
              <div className="h-full p-8 rounded-3xl bg-white border border-[#e5e7eb] flex flex-col gap-4 hover:border-[#007BFF]/40 transition-colors">
                <div className="w-12 h-12 rounded-2xl bg-[#e5f1ff] text-[#007BFF] flex items-center justify-center">{s.icon}</div>
                <h3 className="text-xl font-bold text-[#1C1E21]">{s.title}</h3>
                <p className="text-[#6b7280] leading-relaxed flex-1">{s.body}</p>
                <span className="inline-flex self-start items-center rounded-full bg-[#F8F9FA] border border-[#e5e7eb] px-3 py-1 text-xs font-bold text-[#33383F]">{s.tag}</span>
              </div>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

// ----------------------------------------------------------------------
// MAIN PAGE COMPONENT
// ----------------------------------------------------------------------
export function ModernLanding() {
  return (
    <main className="min-h-screen bg-[#F8F9FA] relative overflow-hidden font-sans">
      <div className="glow-bg" />

      {/* Announcement bar */}
      <div className="relative z-50 flex min-h-[40px] items-center justify-center gap-2 bg-[#1C1E21] px-4 py-2 text-center text-xs font-semibold text-white sm:text-sm">
        <span className="inline-flex h-2 w-2 flex-none animate-pulse rounded-full bg-[#3bd363]" />
        <span>Founding cohort now forming. Lock in founding pricing before public launch.</span>
        <a href="#join" className="inline-flex items-center gap-1 underline underline-offset-2 hover:text-[#4da3ff]">
          Apply now <ArrowRight className="h-3 w-3" />
        </a>
      </div>

      {/* Navigation */}
      <SiteNav />

      {/* Hero Section */}
      <section className="pt-20 pb-20 px-6 max-w-7xl mx-auto grid lg:grid-cols-2 gap-16 items-center min-h-[80vh]">
        <Reveal className="max-w-xl">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#e5f1ff] text-[#007BFF] font-semibold text-xs mb-8 uppercase tracking-widest">
            <Brain className="w-3.5 h-3.5" />
            The French tutor that remembers you
          </div>
          <h1 className="text-6xl sm:text-7xl font-extrabold text-[#1C1E21] leading-[1.05] tracking-tighter mb-8">
            You&apos;ve studied French. <br />
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-[#007BFF] to-[#17A2B8]">
              Now speak it.
            </span>
          </h1>
          <p className="text-xl text-[#6b7280] leading-relaxed mb-10 font-medium">
            A live tutor who remembers every mistake you make and builds tomorrow&apos;s lesson around it. Vocabulary, grammar, listening, writing, and real conversation, in one daily loop.
          </p>
          <div className="flex flex-col sm:flex-row items-start sm:items-center gap-6">
            <a href="#join" className="bg-[#007BFF] hover:bg-[#0062CC] text-white px-8 py-4 rounded-full font-bold text-lg hover:shadow-[0_8px_30px_rgba(0,123,255,0.3)] hover:-translate-y-1 transition-all flex items-center gap-2">
              Start speaking, join free <ArrowRight className="w-5 h-5" />
            </a>
            <div className="flex flex-col gap-2 text-sm font-semibold text-[#33383F]">
              <span className="flex items-center gap-2"><Check className="w-4 h-4 text-[#28A745]" /> Start from true zero</span>
              <span className="flex items-center gap-2"><Check className="w-4 h-4 text-[#28A745]" /> All 5 skills, one loop</span>
              <span className="flex items-center gap-2"><Check className="w-4 h-4 text-[#28A745]" /> No judgment, ever</span>
            </div>
          </div>
        </Reveal>

        {/* The Orbital Animation */}
        <Reveal delay={0.2} className="relative hidden lg:block">
          <div className="orbit-container scale-90 origin-center">
            {/* Center Core */}
            <div className="orbit-center">
              <span className="font-bold text-3xl tracking-tight text-[#1C1E21]">Today</span>
              <span className="text-[#007BFF] font-bold text-sm mt-1">14 min</span>
            </div>

            {/* Orbit Rings */}
            <div className="orbit-ring orbit-ring-1">
              <div className="orbit-item item-1">
                <BookOpen className="w-4 h-4 text-[#17A2B8]" /> Learn
              </div>
              <div className="orbit-item item-2">
                <PenLine className="w-4 h-4 text-[#17A2B8]" /> Write
              </div>
            </div>

            <div className="orbit-ring orbit-ring-2">
              <div className="orbit-item item-1">
                <Mic className="w-4 h-4 text-[#28A745]" /> Speak
              </div>
              <div className="orbit-item item-2">
                <Headphones className="w-4 h-4 text-[#007BFF]" /> Listen
              </div>
            </div>

            <div className="orbit-ring orbit-ring-3">
              <div className="orbit-item item-1">
                <MessageCircle className="w-4 h-4 text-[#007BFF]" /> Apply
              </div>
              <div className="orbit-item item-2">
                <RotateCcw className="w-4 h-4 text-[#28A745]" /> Remember
              </div>
            </div>
          </div>
        </Reveal>
      </section>

      {/* Problem: mirror the visitor's failed history with other apps */}
      <ProblemSection />

      {/* The Method: the ParleSprint Loop */}
      <section id="how-it-works" className="py-24 bg-white border-y border-[#e5e7eb] relative z-10">
        <div className="max-w-7xl mx-auto px-6">
          <div className="grid lg:grid-cols-2 gap-16 items-end mb-16">
            <Reveal>
              <div className="inline-flex items-center gap-2 rounded-full bg-[#e5f1ff] px-3 py-1.5 text-xs font-semibold uppercase tracking-widest text-[#007BFF] mb-6">
                <Repeat className="h-3.5 w-3.5" /> The ParleSprint Loop
              </div>
              <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight leading-tight">
                One day. Five skills. Zero stranded knowledge.
              </h2>
            </Reveal>
            <Reveal delay={0.1}>
              <p className="text-lg text-[#6b7280] font-medium leading-relaxed">
                This morning&apos;s vocabulary shows up in today&apos;s grammar. You hear it in the listening passage, write with it in a micro-task, and this evening, Marie makes you <em>say it</em> in a live roleplay. She logs what tripped you up, and tomorrow is rebuilt around it.
              </p>
            </Reveal>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-5 gap-4">
            {[
              { step: "01", title: "Learn", copy: "Today's words and grammar, introduced in real context.", icon: <BookOpen className="h-5 w-5" /> },
              { step: "02", title: "Attempt", copy: "Say it or write it yourself, right away.", icon: <PenLine className="h-5 w-5" /> },
              { step: "03", title: "Feedback", copy: "Corrected in the moment, not in a quiz three days later.", icon: <Check className="h-5 w-5" /> },
              { step: "04", title: "Apply", copy: "Use it live, in a real conversation with Marie.", icon: <MessageCircle className="h-5 w-5" /> },
              { step: "05", title: "Remember", copy: "Spaced review at the right time, automatically.", icon: <RotateCcw className="h-5 w-5" /> },
            ].map((item, idx) => (
              <Reveal key={item.step} delay={idx * 0.08} className="h-full">
                <div className="h-full rounded-2xl border border-[#e5e7eb] bg-[#F8F9FA] p-6 flex flex-col gap-4 hover:border-[#007BFF]/40 hover:bg-white transition-colors">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-[#9ca3af]">{item.step}</span>
                    <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-[#e5f1ff] text-[#007BFF]">{item.icon}</div>
                  </div>
                  <div>
                    <h3 className="text-base font-bold text-[#1C1E21]">{item.title}</h3>
                    <p className="text-sm text-[#6b7280] font-medium mt-1 leading-relaxed">{item.copy}</p>
                  </div>
                </div>
              </Reveal>
            ))}
          </div>

          {/* The memory claim, made concrete */}
          <Reveal delay={0.3} className="mt-12">
            <div className="rounded-3xl bg-[#F8F9FA] border border-[#e5e7eb] p-8 md:p-10 flex flex-col md:flex-row items-start md:items-center gap-6">
              <div className="w-14 h-14 rounded-2xl bg-[#e5f1ff] text-[#007BFF] flex items-center justify-center shrink-0">
                <Brain className="w-7 h-7" />
              </div>
              <div>
                <h3 className="text-xl font-bold text-[#1C1E21] mb-2">A tutor with an actual memory.</h3>
                <p className="text-lg text-[#6b7280] font-medium leading-relaxed">
                  Marie remembers that you mixed up <em>passé composé</em> on Tuesday and steers Friday&apos;s conversation right into it. Every session summary, every recurring mistake, and your entire vocabulary state shape what you practise next. That&apos;s not a feature of any flashcard app.
                </p>
              </div>
            </div>
          </Reveal>
        </div>
      </section>

      {/* Experience: what the loop feels like */}
      <ExperienceSection />

      {/* Price anchor: vs a private tutor */}
      <TutorComparisonSection />

      {/* Founding-cohort pricing tiers */}
      <PricingSection />

      {/* Cross-Platform Experience (iOS, Android, Web) */}
      <section id="platforms" className="py-24 bg-white border-b border-[#e5e7eb] relative z-10 overflow-hidden">
        <div className="max-w-7xl mx-auto px-6">
          <Reveal className="text-center max-w-2xl mx-auto mb-20">
            <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight mb-6">
              Pick up where you left off.
            </h2>
            <p className="text-xl text-[#6b7280]">
              iOS is live in the pilot today. Android and Web launch with the same guided learning system, and your progress stays perfectly in sync.
            </p>
          </Reveal>

          <div className="grid lg:grid-cols-3 gap-12 items-end justify-center">
            <Reveal delay={0.1} className="flex flex-col items-center">
              <SleekDevice type="ios" title="Your next useful step" subtitle="Daily path" active="Ask for information" />
              <div className="mt-8 text-center">
                <div className="flex items-center justify-center gap-2 mb-2">
                  <Smartphone className="text-[#007BFF] w-5 h-5" />
                  <h4 className="font-bold text-lg text-[#1C1E21]">iOS</h4>
                </div>
                <p className="text-sm text-[#6b7280]">Live in the pilot now</p>
              </div>
            </Reveal>

            <Reveal delay={0.3} className="flex flex-col items-center lg:order-last">
              <SleekDevice type="android" title="Your next useful step" subtitle="Daily path" active="Listen and respond" />
              <div className="mt-8 text-center">
                <div className="flex items-center justify-center gap-2 mb-2">
                  <Smartphone className="text-[#28A745] w-5 h-5" />
                  <h4 className="font-bold text-lg text-[#1C1E21]">Android</h4>
                </div>
                <p className="text-sm text-[#6b7280]">Coming at public launch</p>
              </div>
            </Reveal>

            <Reveal delay={0.2} className="flex flex-col items-center lg:-translate-y-12">
              <SleekDevice type="web" title="Use French to ask for information" subtitle="Personal practice plan" active="Guided lesson" />
              <div className="mt-8 text-center">
                <div className="flex items-center justify-center gap-2 mb-2">
                  <Monitor className="text-[#17A2B8] w-5 h-5" />
                  <h4 className="font-bold text-lg text-[#1C1E21]">Web</h4>
                </div>
                <p className="text-sm text-[#6b7280]">Deep work on a larger screen</p>
              </div>
            </Reveal>
          </div>
        </div>
      </section>

      {/* Who it's for: TEF/TCF, newcomers, professionals */}
      <SegmentsSection />

      {/* Proof: pilot voices + built in the open */}
      <ProofSection />

      {/* From the blog: two latest posts, drives to the full blog for SEO/content marketing */}
      <section className="py-24 bg-white border-y border-[#e5e7eb] relative z-10">
        <div className="max-w-7xl mx-auto px-6">
          <Reveal className="flex flex-wrap items-end justify-between gap-6 mb-12">
            <div>
              <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">From the blog</div>
              <h2 className="text-3xl md:text-4xl font-extrabold text-[#1C1E21] tracking-tight max-w-xl">
                Honest writing on learning French as an adult.
              </h2>
            </div>
            <Link href="/blog" className="inline-flex items-center gap-2 text-sm font-bold text-[#007BFF] shrink-0">
              Read all articles <ArrowRight className="w-4 h-4" />
            </Link>
          </Reveal>

          <div className="grid md:grid-cols-2 gap-6">
            {getSortedPosts().slice(0, 2).map((post, idx) => (
              <Reveal key={post.slug} delay={idx * 0.1}>
                <Link
                  href={`/blog/${post.slug}`}
                  className="group flex flex-col h-full rounded-3xl bg-[#F8F9FA] border border-[#e5e7eb] p-8 hover:border-[#007BFF]/40 hover:bg-white hover:shadow-md transition-all"
                >
                  <div className="flex flex-wrap items-center gap-2 mb-4 text-xs font-bold uppercase tracking-widest">
                    <span className="text-[#007BFF]">{post.category}</span>
                    <span className="text-[#9ca3af]">&middot;</span>
                    <span className="text-[#9ca3af]">{post.readingTime}</span>
                  </div>
                  <h3 className="text-xl font-extrabold text-[#1C1E21] tracking-tight mb-3 group-hover:text-[#007BFF] transition-colors">
                    {post.title}
                  </h3>
                  <p className="text-[#6b7280] leading-relaxed mb-4 flex-1">{post.description}</p>
                  <span className="inline-flex items-center gap-2 text-sm font-bold text-[#007BFF]">
                    Read the article <ArrowRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                  </span>
                </Link>
              </Reveal>
            ))}
          </div>
        </div>
      </section>

      {/* FAQ + Canada CTA + founding form */}
      <FaqSection />

      {/* Footer */}
      <SiteFooter />
    </main>
  );
}
