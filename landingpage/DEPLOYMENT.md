# ParleSprint website build and release guide

The free-first site is maintained in two local folders:

- Canonical source: `/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/landingpage/`
- Netlify deployment copy: `/Users/thoufeekx/Desktop/Millionaire/ParleSprintWebsite/`

The standalone copy preserves its own `netlify.toml`, `next.config.ts`, `package-lock.json`, `.netlify/`, and owner references. Sync only intended website source files. Never use a destructive mirror or remove files just to make the folders identical.

The latest successful production release was built from the standalone folder to <https://parlesprint.com> on 2026-10-17 (Netlify deploy `6ad3f97d77664f5c500e1c90`). The site is associated with the private GitHub repository on `main`. The October 19 push and API-triggered deploy attempts did not replace this production version; verify the deployment integration before assuming a push went live.

## 2026-10-19 app and extension handoff

The owner confirms ParleSprint Immersion is already live in the Chrome Web Store. The website's `/extension` page links directly to the existing listing; `/extension/privacy` describes the current local source behavior. This release does not rebuild or submit an extension package and does not edit the Chrome Web Store listing. The exact published package version, listing fields and store privacy answers have not been independently verified.

The extension page and policy are synced from the canonical source. The app's 1.0.3 (327) archive upload is handled in App Store Connect and is separate from this website deployment.

Netlify deployment status on October 19: the repository `main` push completed, but the published deploy remained `6ad3f97d77664f5c500e1c90`. Two API-triggered deploys (`6ad693b4cca0afacb04fb27e` and `6ad693ffa667bb7772275422`) failed with: `Build blocked: This commit is from an unrecognized Git contributor. This plan allows only verified account members to push to private repos.` The follow-up commit used the authenticated GitHub/Netlify account email and was still rejected. The live `/extension` route returned 200 but did not contain the new Chrome Web Store CTA; `/extension/privacy` returned 404. Do not claim the website changes are live until Netlify's contributor/repository verification is resolved and the route is checked again.

## 2026-10-17 editorial refresh

The current candidate makes the homepage type easier to read, gives the ten free tools clearer icon-led cards, explains the three ParleSprint surfaces, and replaces the compressed footer with grouped navigation. The `/learn` library lists each of its ten lessons once while retaining every lesson detail URL and search metadata. The journal has searchable, working topic filters and a dedicated article reading layout. Styling uses the current Inter-based v3 design and the Lucide dependency already in the project; no generated artwork or added icon package is used.

The standalone candidate passed lint and the Next.js production build, the authored free-tool checks passed 3/3, and `npm audit --omit=dev` reported zero vulnerabilities. Netlify generated all 51 routes and IndexNow accepted the 35 sitemap URLs. The home, learn, lesson, journal, article, tools, today, robots, and sitemap routes return HTTP 200 in production. Desktop and mobile layouts at 1440px and 390px were visually checked with no document-level horizontal overflow. The mobile menu opens, navigates, and closes correctly. The live journal filter was tested with the TEF & TCF Canada category and restores all five articles when cleared. The below-the-fold phone preview was verified after scrolling into view; its source image loads and displays correctly. The editorial refresh is live as deploy `6ad3f6c77c3fe7f3d36b8450` at <https://parlesprint.com>.

The focused App Store proof update is live as deploy `6ad3f97d77664f5c500e1c90`. The homepage displays the current 5.0 score from five ratings and four written review excerpts sourced from Apple's public Canada listing, linked directly from the score card. Local and production screenshots were checked at 1440px and 390px; the four cards remain within the viewport.

## Local checks

Use Node 20 or newer and npm in the standalone folder. Install from its lockfile with `npm ci`, then run:

```bash
npm run lint
npm run build
npm run start -- --port 4317
```

Open `http://localhost:4317`. The build generates 51 page routes and a sitemap with 35 public URLs. Use a localhost `NEXT_PUBLIC_SITE_URL` for local builds so the post-build IndexNow hook skips submitting production URLs.

Run the same lint and build from the canonical source before syncing changes. The source and standalone folder each have a package lockfile. The focused authored-content checks live in `lib/free-tools.test.ts`; if Bun is not globally installed, run them with `npm exec --yes --package=bun@1.4.3 -- bun test lib/free-tools.test.ts`.

## Production settings

Set these in Netlify's environment variables for production. Use the existing ParleSprint Supabase project; the website and iOS app configuration were verified to share that project. The Chrome extension's public project configuration also matches it.

| Variable | Purpose |
| --- | --- |
| `NEXT_PUBLIC_SITE_URL` | Public canonical host, `https://parlesprint.com` |
| `SUPABASE_URL` | Existing ParleSprint Supabase project URL |
| `SUPABASE_ANON_KEY` | Public Supabase client key for optional accounts and browser sync |
| `RESEND_API_KEY` | Server-only key used to deliver learner feedback |
| `NEXT_PUBLIC_GA_MEASUREMENT_ID` | Optional analytics measurement ID |

Never add a service-role key, Resend key, or model-provider key to client code, extension files, documentation, or version control. `.env.local` is ignored by git and should be readable only by the owner. The website account API returns only the public Supabase URL and anonymous key. Email/password is the common account sign-in across all three products; Apple-only accounts are not linked to website access yet. The signed-in website notebook syncs between browsers. App progress and app/extension vocabulary do not sync across products yet, and the interface says so.

A valid feedback form submission sends its message to the ParleSprint team. Use an invalid payload or blocked cross-origin request for smoke testing; do not submit a valid test note unless the team inbox may receive it.

## Content and design

Core practice is authored and deterministic. Daily practice, ten lessons, and the seven focused tools do not need paid model calls. Public promotional pages use the real app screenshot and CSS-built interface illustrations. Do not add generated promotional artwork. The homepage shows the 5.0 score from five App Store ratings and four attributed written-review excerpts from Apple's public listing; the fifth rating has no written note.

Competitor screenshots, Mobbin references, and owner-supplied files are research material under `references/`, not production assets. See `references/research/README.md` and the project notes at `/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/docs/v3/website-rebuild-2026-10-17/WORKLOG.md`.

## Release checklist

1. Make and lint changes in the canonical source.
2. Build the source and visually check the relevant desktop and mobile routes.
3. Sync intended files into the standalone folder while preserving its Netlify configuration, lockfile, references, and `.netlify/` output.
4. Run `npm ci`, `npm run lint`, and `npm run build` in the standalone copy; inspect the Chrome extension ZIP if it changed.
5. Check key routes, auth configuration, feedback validation, sitemap, and robots file. Never send a valid feedback smoke-test message unless a real note in the team inbox is expected.
6. Review `git diff` and `git status`. Do not commit or push without an explicit request. A push may trigger Netlify's production deployment; check the actual deploy state because the Git integration may not publish automatically.
7. If deployment is requested, verify the Netlify deploy state and the specific changed behavior on `https://parlesprint.com`; a successful build alone does not prove the live page is updated.

On the current private Netlify plan, build requests can be blocked by strict contributor verification. The October 19 API deploy attempts were rejected with the error above, including one made after using the authenticated account's verified email. Do not bypass this gate or rewrite/force-push history. Resolve the repo/team contributor verification in Netlify before trying another production deploy.

## Security and dependency notes

Production dependency audit was clean on 2026-10-17. Full development dependency audit still reports an upstream `braces` advisory with no patched version available in its current ESLint toolchain. Do not force-downgrade Next.js or `eslint-config-next` to make that advisory disappear; recheck when the upstream chain publishes a fix.
