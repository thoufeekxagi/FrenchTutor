import { Check } from "lucide-react";
import { FoundingForm } from "./founding-form";
import { faqs } from "./faq-data";

export function FaqSection() {
  return (
    <>
      <section className="py-24 bg-[#F8F9FA] border-t border-[#e5e7eb]">
        <div className="max-w-4xl mx-auto px-6">
          <div className="text-center mb-14">
            <div className="text-[#007BFF] font-bold tracking-widest text-xs uppercase mb-4">Questions</div>
            <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight">
              Before you join
            </h2>
          </div>
          <div className="divide-y divide-[#e5e7eb] border-y border-[#e5e7eb]">
            {faqs.map((item, idx) => (
              <details key={idx} className="group py-6">
                <summary className="flex items-center justify-between gap-6 cursor-pointer list-none font-bold text-lg text-[#1C1E21]">
                  {item.q}
                  <span className="shrink-0 text-2xl font-light text-[#007BFF] transition-transform group-open:rotate-45">+</span>
                </summary>
                <p className="mt-3 text-[#6b7280] leading-relaxed max-w-2xl">{item.a}</p>
              </details>
            ))}
          </div>
        </div>
      </section>

      <section id="for-canada" className="py-24 bg-[#1C1E21] text-white">
        <div className="max-w-7xl mx-auto px-6">
          <div className="bg-gradient-to-br from-[#1f2937] to-[#1C1E21] rounded-[40px] border border-[rgba(255,255,255,0.1)] p-12 md:p-20 grid lg:grid-cols-2 gap-16 items-center shadow-2xl">
            <div>
              <div className="text-[#17A2B8] font-bold tracking-widest text-sm uppercase mb-6">For Canada</div>
              <h2 className="text-4xl md:text-5xl font-extrabold leading-tight tracking-tight mb-6">
                Learn the language.<br />Then train for the test.
              </h2>
              <p className="text-[#9ca3af] text-xl mb-10 leading-relaxed">
                Build everyday foundations across listening, speaking, reading, and writing, then move into TCF- and TEF-oriented practice calibrated to where you actually are, not a generic curriculum.
              </p>
              <ul className="space-y-4 mb-12">
                <li className="flex items-center gap-3 text-lg font-medium"><Check className="w-6 h-6 text-[#28A745]" /> Foundation</li>
                <li className="flex items-center gap-3 text-lg font-medium"><Check className="w-6 h-6 text-[#28A745]" /> Application</li>
                <li className="flex items-center gap-3 text-lg font-medium"><Check className="w-6 h-6 text-[#28A745]" /> Exam practice</li>
              </ul>
              <p className="text-sm font-semibold text-[#6b8fc4]">Founding seats are limited to keep every learner&apos;s feedback loop fast.</p>
            </div>

            <div id="join" className="bg-white rounded-3xl p-8 text-[#1C1E21]">
              <h3 className="text-2xl font-bold mb-2">Join the early list</h3>
              <p className="text-[#6b7280] font-medium mb-8">Help shape the first complete learning path, and lock in founding pricing before public launch.</p>
              <FoundingForm />
            </div>
          </div>
        </div>
      </section>
    </>
  );
}
