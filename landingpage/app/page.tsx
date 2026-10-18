import Link from "next/link";
import Image from "next/image";
import { ArrowRight, ArrowUpRight, BookOpen, Captions, Sprout } from "lucide-react";
import { SiteNav } from "./SiteNav";
import { SiteFooter } from "./SiteFooter";
import { HomePractice } from "../components/home-practice";
import { ToolCards } from "../components/site-ui";
import { FirstVisitPlan } from "../components/first-visit-plan";
import { Reveal } from "../components/reveal";

const appStoreReviews = [
  { quote: "Simple, engaging, and easy to use.", author: "Gopi 124" },
  { quote: "Good app for french learning.", author: "Kaithakal" },
  { quote: "Recommended for French learning.", author: "AnvinAndrews" },
  { quote: "Great app for French study.", author: "Aaadhira" },
];

export default function Home() {
  return (
    <>
      <SiteNav />
      <main id="main-content" className="home-main">
        <section className="home-hero site-container">
          <div className="home-copy">
            <div className="home-eyebrow"><span aria-hidden="true" /> FRENCH FOR REAL LIFE</div>
            <h1>A little French.<br /><span>A little more</span><br />every day.</h1>
            <p>Practise the French you can use today. Read a short line, find a useful phrase, and build confidence one small step at a time.</p>
            <div className="home-actions">
              <FirstVisitPlan />
              <Link className="home-quiet-link" href="/today">Go straight to today’s practice <ArrowUpRight size={16} /></Link>
            </div>
            <div className="home-reassurance">
              <span><CheckMark />Free to use</span>
              <span><CheckMark />No account needed</span>
              <span><CheckMark />A1 to B2</span>
            </div>
          </div>

          <Reveal className="home-practice-wrap">
            <div className="practice-float-note"><Sprout size={15} /><span>Start small. Come back when you can.</span></div>
            <HomePractice />
            <div className="practice-orbit" aria-hidden="true"><span>bonjour</span><span>ça va ?</span><span>à bientôt</span></div>
          </Reveal>
        </section>

        <div className="home-trust-strip">
          <div className="site-container trust-inner">
            <span>Made for the French you use outside a classroom.</span>
            <span className="trust-divider" aria-hidden="true" />
            <span>Start now. Sign in only when you want to sync.</span>
          </div>
        </div>

        <Reveal className="home-section site-container">
          <div className="home-section-heading">
            <div>
              <p className="eyebrow">FREE TOOLS, READY WHEN YOU ARE</p>
              <h2>What would help with your French today?</h2>
              <p>Each tool has one clear job. Open it, use it, and keep what helps.</p>
            </div>
            <Link className="home-quiet-link" href="/tools">See all free tools <ArrowRight size={16} /></Link>
          </div>
          <ToolCards />
        </Reveal>

        <section className="home-products-band">
          <div className="site-container">
            <Reveal>
              <div className="home-section-heading product-heading">
                <div>
                  <p className="eyebrow">THREE WAYS TO MAKE FRENCH PART OF YOUR DAY</p>
                  <h2>Practice French in the moments you already have.</h2>
                  <p>Try a free tool here. Learn from a video in Chrome. Follow a guided course on your phone.</p>
                </div>
              </div>
            </Reveal>

            <div className="home-product-grid">
              <Reveal className="home-product-card extension-product">
                <div className="product-copy">
                  <span className="product-icon"><Captions size={20} /></span>
                  <p className="eyebrow">PARLESPRINT IMMERSION · CHROME</p>
                  <h3>Learn from a line in a video.</h3>
                  <p>Follow French captions on YouTube, tap a word, and save the phrase with its context. Import your own SRT or VTT when captions aren’t available.</p>
                  <Link className="button button-primary" href="/extension">See the Chrome extension <ArrowRight size={16} /></Link>
                  <p className="product-caption">Caption availability depends on the video. No universal transcription.</p>
                </div>
                <figure className="product-visual extension-visual">
                  <div className="product-screenshot-frame">
                    <Image
                      src="/product-screenshots/immersion-youtube-companion.png"
                      width={1280}
                      height={800}
                      alt="A real Chrome session with ParleSprint Immersion open over a TV5MONDE French video on YouTube. The companion is ready to start live captions."
                      sizes="(min-width: 1600px) 42vw, (min-width: 761px) 44vw, 100vw"
                    />
                  </div>
                  <figcaption><span>Chrome · real YouTube session</span><span>Companion ready for captions</span></figcaption>
                </figure>
              </Reveal>

              <Reveal className="home-product-card app-product">
                <div className="product-copy">
                  <span className="product-icon"><BookOpen size={20} /></span>
                  <p className="eyebrow">PARLESPRINT FOR IPHONE</p>
                  <h3>A guided path, with Marie beside you.</h3>
                  <p>Move through authored lessons for everyday French and TCF Canada practice. Bring each lesson into a live conversation when you’re ready.</p>
                  <Link className="button button-secondary" href="/app">Explore the iPhone app <ArrowUpRight size={16} /></Link>
                  <p className="product-caption">One email and password connects the iPhone app, Chrome extension and website.</p>
                </div>
                <figure className="product-visual app-visual">
                  <div className="app-device">
                    <Image
                      src="/product-screenshots/iphone-today.png"
                      width={1206}
                      height={2622}
                      alt="A real iPhone simulator capture of ParleSprint Today, with an A1 level, a guided course, review, Stories and Listening."
                      sizes="(min-width: 761px) 180px, 46vw"
                    />
                  </div>
                  <figcaption><span>iPhone · Today screen</span><span>From the ParleSprint app</span></figcaption>
                </figure>
              </Reveal>
            </div>
          </div>
        </section>

        <section className="home-feedback review-proof site-container" aria-labelledby="review-proof-title">
          <div className="review-heading">
            <div className="review-heading-copy">
              <p className="eyebrow">EARLY APP STORE FEEDBACK</p>
              <h2 id="review-proof-title">A five-star start, in learners’ own words.</h2>
              <p>Small steps are adding up. Here are a few notes from people learning with ParleSprint.</p>
            </div>
            <aside className="review-score" aria-label="5.0 out of 5 from 5 App Store ratings">
              <strong className="review-score-value">5.0</strong>
              <span className="review-score-stars" aria-hidden="true">★★★★★</span>
              <span className="review-score-caption">5 App Store ratings</span>
              <a className="review-score-link" href="https://apps.apple.com/ca/app/parlesprint-french-clb7/id6788485664?platform=iphone&see-all=reviews" target="_blank" rel="noreferrer">
                See all ratings <ArrowUpRight size={16} aria-hidden="true" />
              </a>
            </aside>
          </div>
          <div className="review-grid" aria-label="Written App Store reviews">
            {appStoreReviews.map((review) => (
              <figure className="review-card" key={review.author}>
                <span className="review-card-stars" role="img" aria-label="5 out of 5 stars">★★★★★</span>
                <blockquote>“{review.quote}”</blockquote>
                <figcaption>
                  <span>{review.author}</span>
                  <span>App Store</span>
                </figcaption>
              </figure>
            ))}
          </div>
          <div className="review-footer">
            <p>Five ratings. Four written notes. Every word is from the App Store.</p>
            <Link className="home-quiet-link" href="/feedback">Share what would help you learn <ArrowRight size={16} aria-hidden="true" /></Link>
          </div>
        </section>

        <section className="home-final-cta site-container">
          <div>
            <p className="eyebrow">YOUR NEXT FRENCH MOMENT</p>
            <h2>Start with one useful phrase.</h2>
            <p>Today’s practice is open. Your place stays on this browser.</p>
          </div>
          <Link className="button button-primary" href="/today">Start today’s practice <ArrowRight size={17} /></Link>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}

function CheckMark() {
  return <span className="tiny-check" aria-hidden="true">✓</span>;
}
