import { ArrowRight, Quote } from "lucide-react";

const testimonials = [
  {
    quote: "The hints don't hand me the sentence. They nudge me until I find it myself.",
    author: "Founding cohort, writing practice",
  },
  {
    quote: "Marie stayed in character as the baker the whole scene. I forgot I was being taught.",
    author: "Founding cohort, roleplay",
  },
  {
    quote: "First app that tells me what to do today instead of a mountain of lessons.",
    author: "Starting from zero",
  },
  {
    quote: "I finally know if I'm close to TCF-ready instead of guessing.",
    author: "Working toward Canada",
  },
];

const liveNow = [
  "Daily pathway: vocabulary, grammar, listening, writing",
  "Live speaking calls with Marie, your personal tutor",
  "In-character roleplay scenes built from your material",
  "Spaced-repetition review that never lets a word go stale",
];

const comingNext = [
  "Expanded TCF/TEF-calibrated mock sessions",
  "A progress dashboard across all five skills",
  "Public launch on iOS, Android, and web",
];

export function ProofSection() {
  return (
    <>
      <section className="py-24 overflow-hidden bg-[#F8F9FA]">
        <div className="max-w-7xl mx-auto px-6 mb-16 text-center">
          <h2 className="text-3xl md:text-4xl font-extrabold text-[#1C1E21] tracking-tight">
            Built for learners who mean it.
          </h2>
          <p className="text-[#6b7280] mt-4 text-lg">What early pilot conversations keep surfacing.</p>
        </div>

        <div className="marquee-container">
          <div className="marquee-content">
            {[...testimonials, ...testimonials].map((t, idx) => (
              <div key={idx} className="w-[400px] p-8 rounded-3xl bg-white border border-[#e5e7eb] shadow-sm whitespace-normal inline-block align-top">
                <div className="flex items-center gap-1 mb-4 text-[#007BFF]">
                  <Quote className="w-5 h-5 fill-current" />
                </div>
                <p className="text-lg font-semibold text-[#1C1E21] leading-relaxed mb-6">
                  &ldquo;{t.quote}&rdquo;
                </p>
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-gradient-to-br from-[#e5f1ff] to-[#17A2B8] flex items-center justify-center font-bold text-[#007BFF]">
                    {t.author.charAt(0)}
                  </div>
                  <div>
                    <div className="font-bold text-sm text-[#1C1E21]">{t.author}</div>
                    <div className="text-xs font-medium text-[#6b7280]">Early Learner</div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="py-24 bg-white border-t border-[#e5e7eb]">
        <div className="max-w-7xl mx-auto px-6">
          <div className="max-w-2xl mb-16">
            <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Where we are</div>
            <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight mb-6">
              Built in the open.<br />You shape what ships next.
            </h2>
          </div>

          <div className="grid md:grid-cols-2 gap-8 mb-12">
            <div className="p-8 rounded-3xl border border-[#e5e7eb]">
              <div className="inline-flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-[#28A745] mb-5">
                <span className="w-2 h-2 rounded-full bg-[#28A745]" /> Live in the pilot
              </div>
              <ul className="space-y-3">
                {liveNow.map((item, idx) => (
                  <li key={idx} className="text-[#33383F] font-medium">{item}</li>
                ))}
              </ul>
            </div>
            <div className="p-8 rounded-3xl border border-[#e5e7eb] bg-[#F8F9FA]">
              <div className="inline-flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-[#6b7280] mb-5">
                <span className="w-2 h-2 rounded-full bg-[#9ca3af]" /> Coming next
              </div>
              <ul className="space-y-3">
                {comingNext.map((item, idx) => (
                  <li key={idx} className="text-[#33383F] font-medium">{item}</li>
                ))}
              </ul>
            </div>
          </div>

          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6 p-8 rounded-3xl bg-[#1C1E21] text-white">
            <p className="text-lg font-medium text-[#d1d5db] max-w-xl">
              Founding cohort members keep their price locked and get direct input on what we build next, before this opens to everyone.
            </p>
            <a href="#join" className="shrink-0 bg-[#007BFF] hover:bg-[#0062CC] text-white px-6 py-3 rounded-full font-bold text-sm hover:shadow-[0_8px_30px_rgba(0,123,255,0.3)] transition-all flex items-center gap-2">
              Join the early list <ArrowRight className="w-4 h-4" />
            </a>
          </div>
        </div>
      </section>
    </>
  );
}
