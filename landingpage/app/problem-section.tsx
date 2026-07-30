import { Check, X } from "lucide-react";

const learnerVoices = [
  "“1,000 days of Duolingo, and I still can’t hold a conversation.”",
  "“I can read French. I freeze the moment it’s my turn to talk.”",
  "“Classes don’t fit my shift, and the waitlist is months long.”",
  "“Flashcards taught me words. Nobody taught me to use them.”",
];

const problems = [
  {
    title: "Isolated skills",
    body: "Vocabulary, grammar, and listening live in separate mini-games that never talk to each other. What you memorized on Monday isn't the sentence you're asked to produce on Tuesday.",
  },
  {
    title: "No one is listening",
    body: "You can ace a flashcard and still freeze the first time a real question comes at you. Without correction in the moment, the same mistake just quietly repeats.",
  },
  {
    title: "Generic by default",
    body: "Course content built for tourists doesn't calibrate to a TCF or TEF conversation, or to what a Canadian immigration interview actually sounds like.",
  },
];

const comparisons = [
  {
    them: "Flashcards, then you're on your own to speak.",
    us: "Every skill feeds directly into your next live session.",
  },
  {
    them: "Mistakes get flagged in a quiz, days later.",
    us: "Corrected the moment you say or type it.",
  },
  {
    them: "One generic course, same for every learner.",
    us: "Calibrated to your level from your first session.",
  },
  {
    them: "“Speaking practice” means talking to yourself.",
    us: "Live roleplay. Marie plays the other character, in character, every time.",
  },
  {
    them: "Exam prep bolted on as an afterthought.",
    us: "Built toward TCF/TEF Canada readiness from day one.",
  },
];

export function ProblemSection() {
  return (
    <section id="the-problem" className="py-24 bg-white border-y border-[#e5e7eb] relative z-10">
      <div className="max-w-7xl mx-auto px-6">
        <div className="max-w-2xl mb-10 fade-up">
          <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Sound familiar?</div>
          <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight mb-6">
            Flashcards taught you words.<br />They never taught you French.
          </h2>
          <p className="text-xl text-[#6b7280] leading-relaxed">
            The problem isn&apos;t you. It&apos;s that every tool teaches one skill in isolation, and nobody is listening when it&apos;s finally your turn to speak.
          </p>
        </div>

        <div className="flex flex-wrap gap-3 mb-20">
          {learnerVoices.map((quote, idx) => (
            <span
              key={idx}
              className="inline-flex items-center rounded-full border border-[#e5e7eb] bg-[#F8F9FA] px-5 py-2.5 text-sm font-semibold text-[#33383F]"
            >
              {quote}
            </span>
          ))}
        </div>

        <div className="grid md:grid-cols-3 gap-6 mb-24">
          {problems.map((p, idx) => (
            <div key={idx} className="p-8 rounded-3xl bg-[#F8F9FA] border border-[#e5e7eb]">
              <h3 className="text-lg font-bold text-[#1C1E21] mb-3">{p.title}</h3>
              <p className="text-[#6b7280] leading-relaxed">{p.body}</p>
            </div>
          ))}
        </div>

        <div className="text-center max-w-2xl mx-auto mb-14">
          <h2 className="text-3xl md:text-4xl font-extrabold text-[#1C1E21] tracking-tight mb-4">
            This isn&apos;t five apps stapled together.
          </h2>
          <p className="text-lg text-[#6b7280]">One connected feedback loop, built around what actually gets you speaking.</p>
        </div>

        <div className="max-w-4xl mx-auto rounded-3xl border border-[#e5e7eb] overflow-hidden">
          <div className="grid grid-cols-2 text-sm font-bold uppercase tracking-wider">
            <div className="px-6 py-4 bg-[#F8F9FA] text-[#9ca3af]">Typical apps</div>
            <div className="px-6 py-4 bg-[#1C1E21] text-white">ParleSprint</div>
          </div>
          {comparisons.map((row, idx) => (
            <div key={idx} className="grid grid-cols-2 border-t border-[#e5e7eb]">
              <div className="px-6 py-5 flex items-start gap-3 text-[#6b7280] font-medium">
                <X className="w-5 h-5 text-[#d1d5db] shrink-0 mt-0.5" />
                <span>{row.them}</span>
              </div>
              <div className="px-6 py-5 flex items-start gap-3 text-[#1C1E21] font-semibold bg-[#f7fafd]">
                <Check className="w-5 h-5 text-[#007BFF] shrink-0 mt-0.5" />
                <span>{row.us}</span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
