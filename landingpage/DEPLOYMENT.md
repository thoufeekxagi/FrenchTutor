# ParleSprint website build and release guide

The free-first site is maintained in two local folders:

- Canonical source: `/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/landingpage/`
- Netlify deployment copy: `/Users/thoufeekx/Desktop/Millionaire/ParleSprintWebsite/`

The standalone copy preserves its own `netlify.toml`, `next.config.ts`, `package-lock.json`, `.netlify/`, and owner references. Sync only intended website source files. Never use a destructive mirror or remove files just to make the folders identical.

The latest production release was built and published from the standalone folder to <https://parlesprint.com> on 2026-10-17 (Netlify deploy `6ad3f97d77664f5c500e1c90`). The site is connected to the private GitHub repository on `main`; pushing the reviewed deployment copy triggers a Netlify production build.

## 2026-10-19 app and extension handoff

The owner confirms ParleSprint Immersion is already live in the Chrome Web Store. The website's `/extension` page links directly to the existing listing; `/extension/privacy` describes the current local source behavior. This handoff does not rebuild or submit an extension package and does not edit the Chrome Web Store listing. The exact published package version, listing fields and store privacy answers have not been independently verified.

The extension page and policy in the standalone deployment copy are synced from this canonical source before deployment. Pushing the standalone repository's `main` branch triggers Netlify. The app's 1.0.3 (327) archive upload is handled in App Store Connect and is separate from the website deployment.

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

The 2026-10-17 editorial refresh keeps all ten lesson detail routes indexable while showing each lesson only once in the `/learn` library. The blog archive supports search and topic filters across every article, and its article pages use a dedicated reading layout. Homepage type, free-tool cards, product explanations, and footer follow the current v3 Inter-based design. Lucide icons come from the existing dependency; no generated promotional art was introduced.

## Release checklist

1. Make and lint changes in the canonical source.
2. Build the source and visually check the relevant desktop and mobile routes.
3. Sync intended files into the standalone folder while preserving its Netlify configuration, lockfile, references, and `.netlify/` output.
4. Run `npm ci`, `npm run lint`, and `npm run build` in the standalone copy; inspect the Chrome extension ZIP if it changed.
5. Check key routes, auth configuration, feedback validation, sitemap, and robots file. Never send a valid feedback smoke-test message unless a real note in the team inbox is expected.
6. Review `git diff` and `git status`. Do not commit or push without an explicit request. A push to the connected branch triggers Netlify's production deployment.
7. If deployment is requested, verify the Netlify deploy state and the specific changed behavior on `https://parlesprint.com`; a successful build alone does not prove the live page is updated.

## Security and dependency notes

Production dependency audit was clean on 2026-10-17. Full development dependency audit still reports an upstream `braces` advisory with no patched version available in its current ESLint toolchain. Do not force-downgrade Next.js or `eslint-config-next` to make that advisory disappear; recheck when the upstream chain publishes a fix.
