# ParleSprint free-learning website

The public website is a free-first learning funnel for ParleSprint. Visitors can start a short daily exercise, browse authored A1–B2 lessons, and use focused reading, writing, verb, keyboard, and vocabulary tools without an account. The site also explains the Chrome extension and iPhone app, supports optional account sync, and collects learner feedback.

## Local development

Run the canonical source like this:

```bash
cd /Users/thoufeekx/Desktop/Millionaire/FrenchTutor/landingpage
npm ci
npm run dev
```

Or run the separate Netlify-ready copy:

```bash
cd /Users/thoufeekx/Desktop/Millionaire/ParleSprintWebsite
npm ci
npm run dev
```

Open <http://localhost:3000>. Validate with:

```bash
npm run lint
npm run build
```

This `landingpage/` folder is the canonical website source. The Netlify deployment copy is `/Users/thoufeekx/Desktop/Millionaire/ParleSprintWebsite/`. Sync intended source files and test both copies before release; preserve the deployment copy's Netlify configuration, lockfile, references, and other standalone-only files. See `DEPLOYMENT.md` for the two-copy workflow.

## Main routes

- `/today` — a three-question daily challenge with authored explanations
- `/learn` — ten guided lessons
- `/tools` — ten free entries: daily practice, lessons, seven focused tools, and the local vocabulary notebook
- `/tools/french-verb-practice`, `/tools/french-writing`, `/tools/french-reading`, `/tools/french-keyboard`, `/tools/french-dictation`, `/tools/french-sentence-builder`, `/tools/french-conversation` — focused A1–B2 practice
- `/extension` — Chrome Web Store install page for ParleSprint Immersion
- `/extension/privacy` — extension privacy policy
- `/app` — iPhone app overview
- `/account` — optional sign-in and account settings
- `/feedback` — private learner feedback form

## Services and configuration

`NEXT_PUBLIC_SITE_URL` sets canonical links and sitemap metadata. Optional account sync uses the existing ParleSprint Supabase project. Email/password is the common sign-in path across the website, iPhone app and Chrome extension. Apple sign-in is iPhone-only; Apple-only accounts are not linked to web access yet. The web vocabulary notebook syncs between signed-in browsers; mobile and extension learning data remain separate. The public site’s feedback endpoint requires server-only `RESEND_API_KEY`; without it, the form explains that delivery is not configured and shows the support email. `NEXT_PUBLIC_GA_MEASUREMENT_ID` is optional. Keep secret values in ignored local environment files or host settings, never in source or documentation.

ParleSprint Immersion is owner-confirmed live in the [Chrome Web Store](https://chromewebstore.google.com/detail/parlesprint-immersion/ijclgmkoljddlalgcnpodeemcmcipolb). The website links to its existing listing; website changes do not publish or update the extension package or store metadata.

Core practice is authored and does not require paid model calls. The seven focused tools are verb practice, writing, reading, French accents, dictation, sentence building, and short conversations. The product pages describe actual current behavior and limitations. Generated promotional images are not used; the homepage uses the real app screenshot and CSS-built interface examples.

Research, UX direction, and validation notes are in `../docs/v3/website-research-2026-10-17/PLAN.md` and `../docs/v3/website-rebuild-2026-10-17/WORKLOG.md`.
