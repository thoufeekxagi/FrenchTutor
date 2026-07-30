import Image from "next/image";
import { BookOpen, Headphones, Mic, PenLine } from "lucide-react";

const features = [
  {
    title: "Every word gets its own room",
    description: "No timer, no streak forcing you along. Marie stays on one word until you say when, then walks it into a real sentence before you move on.",
    image: "/flashcard_bus_stop.png",
    icon: <BookOpen className="text-[#007BFF] w-5 h-5" />,
  },
  {
    title: "Hints that get louder only if you're stuck",
    description: "Start typing and ParleSprint watches your pause, not your keystrokes. A gentle nudge comes first. It only says more once it's clear you're actually stuck.",
    image: "/cozy_writing_task.png",
    icon: <PenLine className="text-[#007BFF] w-5 h-5" />,
  },
  {
    title: "Marie plays the other character, not the tutor",
    description: "In the roleplay, you're the customer, she's the baker, fully in character. Freeze, and she steps out for one coaching line, then steps right back in.",
    image: "/marie_live_call.png",
    icon: <Mic className="text-[#007BFF] w-5 h-5" />,
  },
  {
    title: "One instruction, then it waits for you",
    description: "No lecture, no wall of grammar rules. Grammar and listening move one step at a time, react to exactly what you did, then pause until you're ready.",
    image: "/grammar_drill_train.png",
    icon: <Headphones className="text-[#007BFF] w-5 h-5" />,
  },
];

export function ExperienceSection() {
  return (
    <section id="experience" className="py-24 bg-white border-y border-[#e5e7eb] relative z-10">
      <div className="max-w-7xl mx-auto px-6">
        <div className="text-center max-w-2xl mx-auto mb-20 fade-up delay-2">
          <h2 className="text-4xl md:text-5xl font-extrabold text-[#1C1E21] tracking-tight mb-6">
            This isn&apos;t five apps. It&apos;s one loop.
          </h2>
          <p className="text-xl text-[#6b7280]">
            Vocabulary, grammar, listening, and writing all feed the same live conversation with your tutor, so nothing you practise gets forgotten the moment you close the lesson.
          </p>
        </div>

        <div className="grid md:grid-cols-2 gap-8">
          {features.map((feature, idx) => (
            <div key={idx} className="bento-card group">
              <div className="p-10 pb-0">
                <div className="w-12 h-12 rounded-2xl bg-[#e5f1ff] flex items-center justify-center mb-6">
                  {feature.icon}
                </div>
                <h3 className="text-2xl font-bold text-[#1C1E21] mb-3">{feature.title}</h3>
                <p className="text-[#6b7280] text-lg font-medium leading-relaxed mb-10">{feature.description}</p>
              </div>
              <div className="px-10 pb-0 mt-auto flex justify-center">
                <div className="relative w-[300px] h-[340px] translate-y-6 group-hover:translate-y-2 transition-transform duration-500 rounded-t-3xl overflow-hidden shadow-2xl border-x border-t border-[#e5e7eb]">
                  <Image
                    src={feature.image}
                    alt={feature.title}
                    fill
                    className="object-cover object-top"
                  />
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
