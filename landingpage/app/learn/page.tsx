import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, ArrowUpRight, BookOpen, MessageCircle, PenLine } from "lucide-react";
import { SiteFooter } from "../SiteFooter";
import { SiteNav } from "../SiteNav";
import { getLessonRoute, lessons } from "./lesson-data";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export const metadata: Metadata = {
  title: "Learn French Online | 10 Practical Lessons | ParleSprint",
  description: "A structured French learning path with ten practical lessons for grammar, everyday French, and short stories you can retell.",
  keywords: ["learn French online", "French grammar lessons", "French vocabulary lessons", "French short stories", "French speaking practice"],
  alternates: { canonical: "/learn" },
  openGraph: { type: "website", url: "/learn", siteName: "ParleSprint", title: "Learn French with a clear, practical path", description: "Ten practical French lessons with reference tables, useful examples, and speaking practice." },
};

const lessonGroups = [
  {
    label: "01 / Foundations",
    title: "Build the sentence.",
    description: "Small grammar ideas that make your French more precise without turning practice into a worksheet.",
    icon: BookOpen,
    slugs: ["grammar/adverbs-of-time", "grammar/articles-un-une-le-la", "grammar/etre-avoir-aller-present"],
  },
  {
    label: "02 / Everyday French",
    title: "Handle the moment.",
    description: "Useful language for cafés, introductions, directions, and the ordinary conversations that make a place feel familiar.",
    icon: MessageCircle,
    slugs: ["vocabulary/ordering-coffee-in-french", "vocabulary/introduce-yourself-in-french", "vocabulary/asking-for-directions-in-french", "vocabulary/talk-about-your-daily-routine"],
  },
  {
    label: "03 / Stories to retell",
    title: "Remember the scene.",
    description: "Short stories with a beginning, a small change, and phrases you can borrow for your own life.",
    icon: PenLine,
    slugs: ["stories/a-morning-in-montreal", "stories/a-saturday-in-montreal", "stories/first-day-at-work-in-french"],
  },
];

function findLesson(slug: string) {
  return lessons.find((lesson) => lesson.slug === slug);
}

export default function LearnPage() {
  const firstLesson = lessons[0];
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "CollectionPage",
    name: "ParleSprint French Learning Lessons",
    description: metadata.description,
    url: `${siteUrl}/learn`,
    isPartOf: { "@type": "WebSite", name: "ParleSprint", url: siteUrl },
    numberOfItems: lessons.length,
    hasPart: lessons.map((lesson) => ({ "@type": "LearningResource", name: lesson.title, url: `${siteUrl}${getLessonRoute(lesson.slug)}`, educationalLevel: lesson.level })),
  };

  return (
    <main id="main-content" className="content-page library-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }} />
      <SiteNav />

      <section className="library-hero">
        <div className="page-width library-hero-grid">
          <div className="library-hero-copy">
            <p className="eyebrow"><span className="eyebrow-dot" /> A practical French learning path</p>
            <h1>Learn French in pieces you can <em>actually use.</em></h1>
            <p>Ten ordered lessons for adult learners: grammar that clarifies, phrases that work in the street, and short stories that give your French somewhere to live.</p>
            <div className="hero-actions"><Link href={getLessonRoute(firstLesson.slug)} className="button button-primary">Start with lesson 01 <ArrowRight size={17} /></Link><a href="#lessons" className="button button-quiet">Browse the path <ArrowRight size={17} /></a></div>
          </div>
          <div className="library-hero-card">
            <div className="library-hero-card-top"><span>THE PARLESPRINT PATH</span><span>01—10</span></div>
            <div className="library-method-line"><b>01</b><span>Understand the idea</span><small>Plain English, not a grammar wall.</small></div>
            <div className="library-method-line"><b>02</b><span>Borrow the shape</span><small>Tables and examples worth keeping.</small></div>
            <div className="library-method-line"><b>03</b><span>Say something true</span><small>One small action before you leave.</small></div>
            <div className="library-card-foot">Pick any lesson. Each one stands alone, and the sequence gives you a calm next step.</div>
          </div>
        </div>
      </section>

      <section id="lessons" className="library-curriculum section section-white">
        <div className="page-width">
          <div className="library-section-heading"><div><p className="eyebrow eyebrow-teal">The learning library</p><h2>Ten lessons. One clear way <em>forward.</em></h2></div><p>Start anywhere, or follow the order. Every lesson has a map, a reference section, and a speaking move.</p></div>
          <div className="library-path">
            {lessonGroups.map((group, groupIndex) => { const Icon = group.icon; return <section key={group.label} className="library-path-group">
              <div className="library-path-heading"><div className="library-path-icon"><Icon size={19} /></div><div><p className="eyebrow eyebrow-teal">{group.label}</p><h3>{group.title}</h3></div><p>{group.description}</p></div>
              <div className="library-path-list">{group.slugs.map((slug, lessonIndex) => { const lesson = findLesson(slug); if (!lesson) return null; const number = String(lessonGroups.slice(0, groupIndex).reduce((total, item) => total + item.slugs.length, 0) + lessonIndex + 1).padStart(2, "0"); return <Link href={getLessonRoute(lesson.slug)} key={lesson.slug} className="library-path-item"><span className="library-path-number">{number}</span><div><div className="resource-meta"><span>{lesson.category}</span><span>·</span><span>{lesson.readingTime}</span></div><h4>{lesson.title}</h4><p>{lesson.description}</p></div><ArrowUpRight size={17} className="library-path-arrow" /></Link>; })}</div>
            </section>; })}
          </div>
        </div>
      </section>

      <section className="library-practice section section-paper"><div className="page-width library-practice-grid"><div><p className="eyebrow eyebrow-teal">How to use a lesson</p><h2>Finish with a sentence, not another <em>bookmark.</em></h2></div><div className="library-practice-list"><div><span>01</span><p><strong>Read for the idea.</strong> Do not stop for every unknown word on the first pass.</p></div><div><span>02</span><p><strong>Keep one useful phrase.</strong> Choose the example you could imagine saying this week.</p></div><div><span>03</span><p><strong>Say it once without looking.</strong> That is where the lesson becomes available.</p></div></div></div></section>

      <section className="final-cta"><div className="page-width final-cta-inner"><div><p className="eyebrow eyebrow-coral">Keep going</p><h2>Read the idea.<br /><em>Then say the sentence.</em></h2><p>Try a short daily practice or choose another free tool when you are ready.</p></div><div className="final-cta-actions"><Link href="/today" className="button button-primary">Try daily practice <ArrowUpRight size={17} /></Link><Link href="/tools" className="button button-quiet">Explore free tools <ArrowRight size={17} /></Link></div></div></section>
      <SiteFooter />
    </main>
  );
}
