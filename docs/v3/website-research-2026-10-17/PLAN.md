# ParleSprint free-first website plan

Research and implementation: 2026-10-17. The website is the entry point to the ParleSprint learning system: people can start a useful French exercise immediately, then choose whether to save progress with an account. The rebuilt site is live at <https://parlesprint.com>; all 35 sitemap URLs returned HTTP 200 in production verification. This plan records the shipped product, operating boundaries and next safe steps; it does not promise store approval, scores or learning outcomes.

## Product shape

| Surface | Job | What the learner can do |
|---|---|---|
| Website | Give people a free place to practise French every day | Use a daily A1–B2 challenge, ten guided lessons, seven focused practice tools, a local word notebook and private feedback form. |
| Chrome extension | Bring French learning to a video | Follow available YouTube French captions, tap a phrase, replay a line, save vocabulary, or import a personal SRT/VTT subtitle file. It does not promise universal caption access or transcription. |
| iPhone and iPad app | Provide a guided course and conversation practice | Follow authored lessons, review vocabulary and practise with Marie. |

The website is the main funnel and a product in its own right. Every public page should say what the learner can do in plain language. No payment structure is part of this release. Accounts are optional and requested when the learner chooses to sync or continue with account-backed features.

## Website flow

1. The homepage explains who ParleSprint helps and offers an interactive French sample without signup.
2. A learner can open daily practice immediately or start the optional three-step setup: current level (A1–B2), the tool they want now, and preferred daily pace.
3. The chosen level is saved locally and the learner is sent directly to the matching tool. Choices remain in that browser; the flow is skippable and does not request an email.
4. The tools directory offers ten free starting points: daily practice, ten guided lessons, verb practice, the writing desk, short reading, the accent keyboard, listening dictation, sentence building, everyday text roleplay, and the local word notebook.
5. Sign-in is available for people who want account sync. The website, iOS app and extension have separate secure sessions; no client shares another client's refresh token.
6. The extension and app have distinct pages with real availability and setup limits. The extension is an early-access unpacked ZIP, not a Chrome Web Store listing.
7. The homepage reserves a feedback area for the five 5-star ratings reported by the owner. It does not invent review text; learner quotes remain a clearly labelled placeholder until the owner supplies approved feedback.

## Product and design rules

- Make the first useful action visible without scrolling or creating an account.
- Use calm, confident language for adult beginners. Keep the tone warm and lively without cartoon characters or corporate jargon.
- Use the v3 app's restrained blue, cool white and warm-neutral palette, consistent typography, generous spacing and simple controls.
- Keep motion brief and purposeful. Respect `prefers-reduced-motion`, keyboard focus and touch sizes.
- Use original CSS product diagrams and genuine ParleSprint product screenshots. Do not ship generated concept artwork, competitor screenshots or visual mockups that imply unbuilt features.
- State tool scope, level, time and storage behavior where a learner makes a choice. Never imply an exercise is an official TCF/TEF exam or score.
- Avoid fake user counts, invented testimonials, guaranteed outcomes and unsupported availability claims.

## Current website tools

| Route | Learner value | Runtime model calls |
|---|---|---|
| `/today` | Three short authored questions for A1, A2, B1 or B2, with explanations and a save-phrase action | None |
| `/tools/french-verb-practice` | Twelve common present-tense verbs and their forms | None |
| `/tools/french-writing` | Original prompts, a draft saved in the browser, word count and French accent keys | None |
| `/tools/french-reading` | Short authored readings with level context and vocabulary support | None |
| `/tools/french-keyboard` | Type and copy French accents | None |
| `/tools/french-dictation` | Listen to short authored sentences with a device French voice, type what was heard and compare | Device speech synthesis only; no recording or paid model |
| `/tools/french-sentence-builder` | Arrange authored words into useful A1–B2 sentences with a concise grammar hint | None |
| `/tools/french-conversation` | Work through three-turn everyday roleplays with authored response feedback at A1–B2 | None; explicitly text-only and does not score speech |
| `/words` | Search, export and remove saved phrases locally; optional account sync | None for local use |
| `/feedback` | Send product feedback; reply address is optional | No LLM |

The directory contains ten entries when the daily challenge, guided lesson library, seven focused tools and notebook are counted. Most exercises are deterministic so the free path stays available without model keys, signup, or per-answer costs. Dictation uses the learner's own browser speech voice; it offers a visible transcript if a browser cannot synthesize French speech.

## Competitor and design research

Competitor walkthrough screenshots and the research method are indexed in the standalone site's `references/research/README.md`. Busuu, Babbel and Praktika were examined in Chrome from their public landing pages through their signup, onboarding or login gates. No account was created and no contact details were submitted. The captured states showed useful patterns: say what the learner gets before signup, let them choose a learning level or goal, and make the transition into practice obvious. Praktika's longer quiz gates its result behind login; ParleSprint will keep its setup short and let people start first. Praktika's public help page describes a free tier with three avatars, limited speaking and basic feedback, with daily speaking challenges and advanced feedback listed under premium. We use that only as a signal that guided speaking is a useful format; ParleSprint's text roleplay and device-voice dictation are original and available without an AI request. Webflow's free Starter plan is a web design/hosting tier, not a French-learning resource, so it informs no learner-tool feature decision.

Research sources: [Praktika free and premium features](https://intercom.help/praktika-ai/en/articles/12008580-is-there-a-free-version-of-the-app-available-or-do-i-need-a-subscription) and [Webflow plans](https://webflow.com/pricing). Availability and plan details can change; this is a product-format comparison, not a traffic or market-size estimate.

Website-only Mobbin references:

- [Duolingo website hero section](https://mobbin.com/sites/sections/ac10aadd-d55a-4144-ab7d-8777e3bb4e5e)
- [Duolingo website section](https://mobbin.com/sites/sections/ec38afdb-ca3a-4034-9222-e7776f624170)
- [Babbel: adding a learning language](https://mobbin.com/flows/83309ca5-7fe9-4010-ae45-779274121c68)
- [Babbel onboarding](https://mobbin.com/flows/332ff84d-d0f2-4669-bed6-7f1992729eb4)

These references inform page hierarchy and choice flow only. Their images, logos and copy are not product assets. The Rosetta Stone and CutNoodle HTML references supplied by the owner are also stored in the standalone references folder; use them to assess section clarity and task descriptions, never to copy protected content.

Search-intent data is exploratory, not market sizing. Raw Google autocomplete responses for 14 French-learning prefixes and their retrieval metadata are in this folder's `autocomplete.json`. Ahrefs did not return search volume on the available plan. The Hermes SEO checkout was inspected without printing credentials; it integrates Brave, and its Brave/Jev keys were empty. No Google Ads Keyword Planner access was verified, no traffic estimates were obtained, and no scheduled scraping was run.

## Account, privacy and operating cost

The site can be useful before sign-in. Preferences, daily attempts, drafts and guest vocabulary are stored locally. The optional web account uses the existing ParleSprint Supabase project. Email and password is the shared sign-in path across the website, iPhone app and Chrome extension. Apple sign-in remains available in the iPhone app only; Apple-only accounts are not linked to web access yet, so learners should contact support instead of creating a duplicate account. Google sign-in is not configured as a common identity across all three products, so the website does not offer it. The web notebook syncs between signed-in browsers to `web_learning_items` under user-scoped RLS; lesson progress and extension/mobile vocabulary do not sync yet. Never place provider secrets in browser code. Keep service calls bounded, explain when selected text leaves the device, and keep privacy disclosures aligned with the actual extension and backend. Do not scrape third-party learning content for redistribution; write original exercises or record a verifiable license.

The core web exercises use authored content and deterministic feedback so they do not consume LLM tokens. The iOS app's `ai-text` Edge Function uses provider credentials stored by Supabase, never in website or extension bundles. Routine web exercises do not call that paid function. The function now requires a verified signed-in user session or the exact service-role credentials used by the internal course-preparation function; the public anonymous project key alone is rejected. Any future web explanation service must authenticate and enforce a server-side quota before launch. AI provider pricing and monetization remain deferred.

## Release and verification

Source of truth: `FrenchTutor/landingpage/`. The reviewed site source is synced to the standalone `ParleSprintWebsite/` folder, which preserves its `.netlify/`, `references/`, `netlify.toml`, standalone `next.config.ts` and npm lockfile. Both copies pass lint, TypeScript, content tests and production builds. The Netlify production release was deployed manually from the standalone folder; it is live and verified. The connected GitHub `main` branch was not changed, so sync the source into that repository before a future Git-triggered deploy.

The implementation and hosting steps for this release are complete. Remaining product work is approved iOS feedback wording and future cross-product progress/notebook sync. Never commit secrets, modify mobile course progress as a side effect, or push without explicit authorization.
