import { ArrowRight, Check, ShieldCheck, Target, Users } from "lucide-react";
import { FoundingForm } from "./founding-form";

export function ExamSection() {
  return (
    <section className="exam-section shell section-space" id="exams">
      <div className="exam-card">
        <div className="exam-copy">
          <p className="eyebrow"><span /> A focused destination</p>
          <h2>Building toward TEF or TCF? Train the language and the exam.</h2>
          <p>Build foundations across all four skills, then move into exam-oriented listening, speaking, reading, and writing practice when those patterns become useful.</p>
          <a className="text-link" href="#founding">Join as a Canada-focused learner <ArrowRight size={16} /></a>
        </div>
        <div className="exam-ticket">
          <div><span>ParleSprint pathway</span><strong>French for Canada</strong></div>
          <dl><dt>Direction</dt><dd>CLB / NCLC 7</dd><dt>Skills</dt><dd>Listening · Speaking<br />Reading · Writing</dd><dt>Approach</dt><dd>Foundation → application → exam practice</dd></dl>
          <small>ParleSprint cannot guarantee a test score or immigration outcome.</small>
        </div>
      </div>
    </section>
  );
}

export function FounderSection() {
  return (
    <section className="founder-section shell section-space">
      <div className="founder-mark">“</div>
      <div className="founder-copy">
        <p className="eyebrow"><span /> Why we are building this</p>
        <h2>Built by a learner who needed a more complete way to practise.</h2>
        <blockquote>I did not need another app asking me to protect a streak. I needed one serious place to practise every part of French, receive useful feedback, and continue from where I left off—even when the time available changed from day to day.</blockquote>
        <p>ParleSprint is being shaped with its first learners, not handed down as a finished theory of how everyone should learn.</p>
        <span className="founder-signature">— Founder, ParleSprint</span>
      </div>
    </section>
  );
}

export function FoundingSection() {
  return (
    <section className="founding-section" id="founding">
      <div className="shell section-space founding-layout">
        <div className="founding-copy">
          <p className="eyebrow eyebrow-light"><span /> Founding learner cohort</p>
          <h2>Help shape the first complete learning path.</h2>
          <p>We are inviting a small group of serious learners to use ParleSprint, tell us where the practice breaks down, and help make the core learning loop genuinely useful.</p>
          <ul>
            <li><Check size={15} /> Early access to the developing product</li>
            <li><Check size={15} /> A pathway shaped around your level and goal</li>
            <li><Check size={15} /> Direct influence through honest feedback</li>
            <li><Check size={15} /> Preferential founding offer when paid access opens</li>
          </ul>
          <div className="founding-note"><Users size={19} /><div><strong>Small by design</strong><span>We want to learn from each founding member, not collect an anonymous list.</span></div></div>
        </div>
        <FoundingForm />
      </div>
    </section>
  );
}

const faqs = [
  ["Is ParleSprint suitable for complete beginners?", "Yes. The pathway can begin with foundational vocabulary, pronunciation, and simple sentence patterns, with English support that reduces as your French develops."],
  ["Is this only for TEF or TCF learners?", "No. Serious French learners can use the complete practice system for work, everyday communication, travel, or personal goals. TEF and TCF Canada are focused pathways within the broader platform."],
  ["What makes it different from a normal language app?", "ParleSprint is designed as a connected feedback loop. Vocabulary, grammar, listening, writing, and speaking share context so a lesson does not end when you tap the last card."],
  ["Is Marie a real person?", "Marie is an AI voice tutor. She can respond in real time and use your lesson context, but she is not presented as a human teacher and does not replace qualified instruction in every situation."],
  ["Do I need to use live voice every day?", "No. You can use flashcards, narrated lessons, listening, reading, grammar, and writing independently. Live voice is one important practice mode, not the entire product."],
  ["How much time do I need?", "The goal is to support the time you genuinely have. A quick session may focus on review, while a standard or deep session can move through more of the connected pathway."],
  ["What is included in the founding pilot?", "Selected learners receive early access to the current core experience and a direct feedback channel. Features may change during the pilot, and no payment is collected through this application."],
  ["Does ParleSprint guarantee CLB/NCLC 7 or an immigration outcome?", "No. No learning product can guarantee an official test result or immigration decision. ParleSprint helps you practise deliberately and see what needs work next."],
];

export function FaqSection() {
  const faqSchema = {
    "@context": "https://schema.org",
    "@type": "FAQPage",
    mainEntity: faqs.map(([question, answer]) => ({
      "@type": "Question",
      name: question,
      acceptedAnswer: { "@type": "Answer", text: answer },
    })),
  };

  return (
    <section className="faq-section shell section-space" id="faq">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(faqSchema).replace(/</g, "\\u003c") }} />
      <div className="faq-heading"><p className="eyebrow"><span /> Honest answers</p><h2>Before you apply.</h2><p>Still deciding whether this is the right kind of practice for you? Start here.</p></div>
      <div className="faq-list">
        {faqs.map(([question, answer], index) => <details key={question} open={index === 0}><summary>{question}<span>+</span></summary><p>{answer}</p></details>)}
      </div>
    </section>
  );
}

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div className="shell footer-top"><div><strong>Parle<span>Sprint</span></strong><p>Connected French practice for serious learners.</p></div><a className="button button-primary" href="#founding">Apply for access <ArrowRight size={16} /></a></div>
      <div className="shell footer-bottom"><span>© {new Date().getFullYear()} ParleSprint</span><div><a href="#faq">FAQ</a><span><ShieldCheck size={13} /> Honest claims. Learner-first design.</span><span><Target size={13} /> Built toward useful French.</span></div></div>
    </footer>
  );
}
