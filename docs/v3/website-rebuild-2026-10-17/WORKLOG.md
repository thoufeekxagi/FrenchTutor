# Website restructure and QA work log

Date: 2026-10-17. Source: `/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/landingpage/`. Standalone test/deployment copy: `/Users/thoufeekx/Desktop/Millionaire/ParleSprintWebsite/`.

## Scope

Owner authorized a complete free-first website restructure, using ParleSprint v3 as the product and design reference. The site should be useful without signup, explain its free tools, connect the website to the Chrome extension and iOS app, invite feedback, and leave monetization decisions for later. The owner reported five 5-star ratings; the [public Canada App Store listing](https://apps.apple.com/ca/app/parlesprint-french-clb7/id6788485664) now confirms a 5.0 score from five ratings and displays four written reviews.

## Reference research

The owner's saved Rosetta Stone, Busuu, Babbel and CutNoodle pages are in the standalone `references/` folder. Chrome screenshots for Busuu, Babbel and Praktika are in `ParleSprintWebsite/references/research/chrome-screenshots/`. The captures cover public landing pages, onboarding/sign-up screens and login gates. No accounts were created and no contact information was entered. Praktika age and demographic questions were skipped where possible. See the standalone `references/research/README.md` index.

Website-specific Mobbin references inspected:

- https://mobbin.com/sites/sections/ac10aadd-d55a-4144-ab7d-8777e3bb4e5e
- https://mobbin.com/sites/sections/ec38afdb-ca3a-4034-9222-e7776f624170
- https://mobbin.com/flows/83309ca5-7fe9-4010-ae45-779274121c68
- https://mobbin.com/flows/332ff84d-d0f2-4669-bed6-7f1992729eb4

The resulting direction: show the value before account creation, keep the first-run setup short, let the learner start immediately, and explain each product surface plainly. No competitor imagery or copy ships in the product.

## Implementation completed locally

- Rebuilt the homepage around an interactive French sample, free-tool directory, concise extension and iPhone explanations, current authentic app screenshot, App Store proof section, and direct practice CTA.
- Added an optional three-step setup for level, desired tool and preferred daily pace. It saves the plan locally and routes directly to the selected live tool. The learner can close or skip it. The dialog traps keyboard focus, closes with Escape and prevents background scroll.
- Added restrained page reveal and button transitions with reduced-motion support in `landingpage/app/premium.css`.
- Added exactly ten free directory entries: a daily challenge, ten guided lessons, seven focused A1–B2 tools (verbs, writing, reading, accent keyboard, dictation, sentence building and conversation), and the guest vocabulary notebook. The authored practice does not need paid model calls.
- Kept the experience local-first: guest words, settings and drafts stay in the browser. Email/password is the common sign-in across the website, iPhone app and extension. The website no longer offers Google OAuth because Google sign-in is not configured consistently across all three products. Apple sign-in remains iPhone-only; Apple-only accounts are not linked to website access. Website notebook sync is limited to signed-in browsers; app and extension learning data do not sync across products yet.
- Removed six generated promotional mockup images from the website public assets. The authentic `app-today-preview.png` remains. No product page references the removed images.
- Replaced paid-content copy on the iOS page and clarified when selected caption text is sent from the extension for an explanation.
- Rewrote the product/research plan and saved competitor screenshot index in the references folder.
- Replaced the website's retired black-and-gold bolt and hand-drawn blue bolt with the exact current v3 iOS App Store icon. The website header, signup confirmation, PWA/install icon, browser favicon, and structured data now share the iOS AppIcon source. The branding note records this source of truth.

## Product boundaries

- Homepage proof uses the current Apple-listed 5.0 score and five ratings, plus four short, attributed excerpts from the four written App Store reviews. The fifth rating has no public written note, so no quote is invented. The score links directly to Apple's review page.
- The extension is labelled early-access and not yet reviewed by the Chrome Web Store. Its page discloses that YouTube caption access varies and supports user-supplied SRT/VTT files.
- The iOS page uses the real app screenshot and avoids claims about unverified Android availability.
- Core exercises are authored and deterministic. No LLM call is needed to answer daily practice, verb, reading, writing or keyboard tasks.
- No payment structure or monetization gate is being implemented.

## Validation and release completed

- Canonical source `/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/landingpage/` and standalone deployment folder `/Users/thoufeekx/Desktop/Millionaire/ParleSprintWebsite/` both pass ESLint, TypeScript, and a Next.js 16.4.2 production build. The build generated 51 page routes and IndexNow accepted 35 sitemap URLs. Focused authored-content tests pass 3/3 in each folder. `npm audit --omit=dev` reports zero vulnerabilities.
- The Netlify preview build succeeded. All 35 sitemap routes returned HTTP 200 on preview and again on production. The Chrome preview and live homepage were visually inspected. The live `/tools` directory shows all ten entries, and the account page shows email/password sign-in without a Google button. The live dictation flow revealed an A1 sentence, accepted the matching answer, and returned its explanation.
- Earlier local Chrome QA exercised the first-run setup, daily challenge, verb feedback, reading controls, writing draft save/clear, accent insertion, notebook save/remove, sentence-builder correct/retry paths, and all three turns of an A1 conversation. Test words and drafts were removed. The QA browser profile retains a 2/3 daily-practice result from that test run.
- Production `/api/auth-config` returns only the public Supabase URL and anonymous key for project `oxfnrsjskdjbroekxdco`. The website, iOS app and extension use that Supabase project. A direct anonymous call to the deployed `ai-text` Edge Function returns HTTP 401 before any provider request; the function accepts a verified user session or the exact internal service-role caller. Provider secrets remain in Supabase function secrets and are not in browser code.
- Production feedback validation returns HTTP 400 for malformed input and HTTP 403 for a cross-origin POST. `RESEND_API_KEY` is configured in Netlify production for server-side delivery. An earlier valid-shape feedback smoke test returned 200 and may have sent a test note to the team inbox; no valid feedback submission was made during this release validation.
- The extension ZIP passes `unzip -t` and contains no environment file or service-role key. The website uses the authentic Today-screen capture and CSS-built product examples; generated promotional images were removed. The original five-star feedback placeholder was replaced by the verified Apple listing summary and real review excerpts in the focused testimonial refresh.
- Netlify production deploy `6ad3f2ebfb10b8fe12f2253f` is live at <https://parlesprint.com>. It was built and published from the standalone folder after the official iOS app icon update; the Netlify build completed, the Next.js runtime deployed, and IndexNow accepted all 35 sitemap URLs. The connected GitHub `main` branch was not changed; a later GitHub-triggered production build can replace this CLI release, so sync the reviewed source into that repo before its next release.
- Logo release verification passed in both canonical and standalone folders: ESLint, `tsc --noEmit`, and the Next.js production build (51 routes). On the deployed site, `/icon.png`, `/apple-icon.png`, `/favicon.ico`, `/icon-512.png`, `/manifest.webmanifest`, `/opengraph-image`, `/parle-mark.svg`, and `/` all returned HTTP 200. Chrome screenshots confirmed the current iOS mark in the 440×956 mobile view and the live homepage; no console or build errors remained.
- No commit or push was made. The only remaining owner input noted at that release was future cross-product notebook sync.

## Existing repository state

The parent FrenchTutor repository has unrelated user-owned mobile, backend and documentation edits. Keep all commands, diffs and any future commit scope limited to `landingpage/` and the two website documentation directories. Never stage the whole monorepo.

## Editorial and readability refresh

On 2026-10-17, the website's lesson library, journal, free-tool cards, homepage product explanation, and footer were refined to match the current v3 visual language. Inter is used consistently with larger body and headline sizes for readability. Free-tool cards use the already-installed Lucide icon set with restrained color accents; no icon dependency or generated artwork was added. The extension and iPhone panels explain the distinct role of each product, and the footer now groups links into two readable columns.

The `/learn` index now presents each of the ten lessons once in three ordered groups. All individual lesson URLs and metadata remain available for search indexing. The `/blog` archive separates the featured story from searchable/filterable article results; topic filters search all posts. Article pages now use a wider editorial headline and a narrower reading column. The editorial structure was informed by the practical topic grouping and internal discovery used by [Babbel Magazine's French Basics hub](https://www.babbel.com/en/magazine/french-basics), while retaining original ParleSprint copy and authored content.

Refresh verification: canonical and standalone lint and production builds pass; the focused free-tool tests pass 3/3; `npm audit --omit=dev` reports zero vulnerabilities. The standalone production preview returns HTTP 200 for `/`, `/learn`, an individual lesson, `/blog`, a real article, `/tools`, `/today`, `/robots.txt`, and `/sitemap.xml`; its sitemap contains 35 public URLs. Headless Chrome checks at 390px and 1440px found no document-level horizontal overflow. The desktop and mobile home, lesson library, journal, article, and footer were visually reviewed. The blog topic filter was exercised in-browser. A first smoke check used a guessed blog slug and returned 404; checking the generated route list identified the actual slug, which returned 200.

The refreshed website is live at <https://parlesprint.com> as Netlify deploy `6ad3f97d77664f5c500e1c90`. Netlify's production build generated all 51 routes and IndexNow accepted all 35 sitemap URLs. The production home, learn index, a lesson page, journal index, a real article, tools, daily practice, robots file, and sitemap all return HTTP 200. A live desktop and mobile browser pass confirmed the document width matches the viewport. The mobile navigation opens, exposes seven links, navigates to `/tools`, and closes afterward. The journal filter was exercised live: selecting TEF & TCF Canada shows its matching article, and clearing the filter restores all five posts. The initial full-page screenshot left the below-the-fold iPhone screenshot lazy-loaded; scrolling the product section into view loaded the 1206px image and showed the current Today screen correctly. This was a capture timing issue, not a missing production asset. The connected GitHub branch was not changed.

## App Store social proof block

On 2026-10-17, only the homepage learner-feedback section was replaced. It now shows Apple's 5.0 score from five ratings and four short, attributed text excerpts, with a direct link to the official listing. Apple displays four written reviews; the fifth rating has no written text. The four short excerpts remain under 25 quoted words total. The section uses the existing typography and gold star accent, responsive cards, and no testimonial photography or generated imagery. The local and live 1440px and 390px Chrome checks confirmed all four cards fit without horizontal overflow. Netlify published this section-only update as deploy `6ad3f97d77664f5c500e1c90`; the production homepage shows the verified score, four quote cards, and working App Store link. The App Store source and current wording should be rechecked before future edits.
