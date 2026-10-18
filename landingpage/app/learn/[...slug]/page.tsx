import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowRight, Bookmark, CheckCircle2, Clock3, Headphones, Sparkles } from "lucide-react";
import { SiteFooter } from "../../SiteFooter";
import { SiteNav } from "../../SiteNav";
import { BlogProse, headingId } from "../../blog/BlogProse";
import { ReadingProgress } from "../../blog/ReadingProgress";
import { getLessonBySlug, getLessonRoute, lessons } from "../lesson-data";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export function generateStaticParams() {
  return lessons.map((lesson) => ({ slug: lesson.slug.split("/") }));
}

export async function generateMetadata({ params }: { params: Promise<{ slug: string[] }> }): Promise<Metadata> {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug.join("/"));
  if (!lesson) return {};
  const route = getLessonRoute(lesson.slug);
  return {
    title: `${lesson.title} | ParleSprint Learn`,
    description: lesson.description,
    keywords: ["learn French online", "French lesson", "French speaking practice", lesson.title, lesson.category, lesson.level],
    alternates: { canonical: route },
    openGraph: { type: "article", url: route, siteName: "ParleSprint", title: lesson.title, description: lesson.description },
    twitter: { card: "summary_large_image", title: lesson.title, description: lesson.description },
  };
}

export default async function LearningLessonPage({ params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params;
  const lesson = getLessonBySlug(slug.join("/"));
  if (!lesson) notFound();

  const headings = lesson.blocks.reduce<{ text: string; id: string }[]>((result, block) => {
    if (block.type === "h2") result.push({ text: block.text, id: headingId(block.text) });
    return result;
  }, []);
  const related = lessons.filter((candidate) => candidate.slug !== lesson.slug && candidate.kind === lesson.kind).slice(0, 3);
  const structuredData = {
    "@context": "https://schema.org",
    "@type": "LearningResource",
    name: lesson.title,
    description: lesson.description,
    url: `${siteUrl}${getLessonRoute(lesson.slug)}`,
    learningResourceType: lesson.kind === "story" ? "Short story lesson" : lesson.kind === "vocabulary" ? "Vocabulary lesson" : "Grammar lesson",
    educationalLevel: lesson.level,
    isPartOf: { "@type": "CollectionPage", name: "ParleSprint French learning library", url: `${siteUrl}/learn` },
    publisher: { "@type": "Organization", name: "ParleSprint", url: siteUrl },
  };
  const breadcrumbData = {
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: "ParleSprint", item: siteUrl },
      { "@type": "ListItem", position: 2, name: "Learn French", item: `${siteUrl}/learn` },
      { "@type": "ListItem", position: 3, name: lesson.title, item: `${siteUrl}${getLessonRoute(lesson.slug)}` },
    ],
  };

  return (
    <main className="content-page lesson-page">
      <ReadingProgress />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(structuredData).replace(/</g, "\\u003c") }} />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(breadcrumbData).replace(/</g, "\\u003c") }} />
      <SiteNav />
      <section className="lesson-hero">
        <div className="page-width">
          <nav className="lesson-breadcrumbs" aria-label="Lesson breadcrumbs"><Link href="/learn">Learn French</Link><span>›</span><span>{lesson.category.split(" · ")[0]}</span><span>›</span><strong>{lesson.title}</strong></nav>
          <div className="lesson-hero-grid">
            <div className="lesson-hero-copy">
              <div className="lesson-kicker"><span>{lesson.category}</span><span>·</span><span>{lesson.level}</span></div>
              <h1>{lesson.title}</h1>
              <p className="lesson-description">{lesson.description}</p>
              <div className="lesson-meta"><span><Clock3 size={15} /> {lesson.readingTime}</span><span><Bookmark size={15} /> Save the lesson</span><span><Headphones size={15} /> Read + say it</span></div>
              <a href="#lesson" className="button button-primary lesson-start-button">Start the lesson <ArrowRight size={17} /></a>
            </div>
            <div className={`lesson-hero-art lesson-hero-art-${lesson.kind}`} aria-label="Lesson overview">
              <div className="lesson-art-grid" />
              <div className="lesson-art-top"><span>PARLESPRINT / LEARNING LIBRARY</span><Sparkles size={17} /></div>
              <div className="lesson-art-index">{lesson.kind === "story" ? "03" : lesson.kind === "vocabulary" ? "02" : "01"}</div>
              <div className="lesson-art-note"><span>{lesson.kind === "story" ? "READ · NOTICE · RETELL" : "NOTICE · BORROW · USE"}</span><strong>{lesson.intro}</strong></div>
              <div className="lesson-art-footer"><span>{lesson.level}</span><span>{lesson.readingTime}</span></div>
            </div>
          </div>
        </div>
      </section>

      <section id="lesson" className="lesson-reading page-width">
        <div className="lesson-layout">
          <aside className="lesson-rail" aria-label="Lesson navigation">
            <div className="lesson-rail-card lesson-rail-map">
              <p className="lesson-rail-label">In this lesson</p>
              <nav>{headings.map((heading, index) => <a key={heading.id} href={`#${heading.id}`}><span>{String(index + 1).padStart(2, "0")}</span>{heading.text}</a>)}</nav>
            </div>
            <div className="lesson-rail-card lesson-rail-remember">
              <p className="lesson-rail-label">Keep this close</p>
              <ul>{lesson.remember.map((note) => <li key={note}>{note}</li>)}</ul>
            </div>
            <div className="lesson-rail-note"><CheckCircle2 size={17} /><p>Read once for the idea. Come back to say one sentence without looking.</p></div>
          </aside>

          <article className="lesson-body">
            <div className="lesson-intro-card"><p className="lesson-block-label">The point of this lesson</p><p>{lesson.intro}</p></div>
            <div className="lesson-map-wide"><div><p className="lesson-block-label">A useful rhythm</p><h2>Read it. Notice it. Use it.</h2></div><div className="lesson-map-steps"><span><b>01</b>Read for meaning</span><span><b>02</b>Notice the pattern</span><span><b>03</b>Say one true sentence</span></div></div>
            <BlogProse content={lesson.blocks} />
            <div className="lesson-next"><div><p className="lesson-block-label">Keep the thread going</p><p>One lesson becomes useful when it connects to another small action.</p></div><Link href="/today" className="button button-primary">Try daily practice <ArrowRight size={16} /></Link></div>
          </article>
        </div>
      </section>

      <section className="lesson-related page-width"><div className="lesson-related-heading"><div><p className="eyebrow eyebrow-teal">Next in the library</p><h2>Keep one useful idea moving.</h2></div><Link href="/learn" className="text-link">See all lessons <ArrowRight size={16} /></Link></div><div className="lesson-related-grid">{related.map((candidate) => <Link key={candidate.slug} href={getLessonRoute(candidate.slug)} className="lesson-related-card"><div className="lesson-related-top"><span>{candidate.category}</span><span>{candidate.readingTime}</span></div><h3>{candidate.title}</h3><p>{candidate.description}</p><span className="text-link">Open lesson <ArrowUpRightIcon /></span></Link>)}</div></section>
      <SiteFooter />
    </main>
  );
}

function ArrowUpRightIcon() {
  return <ArrowRight size={16} />;
}
