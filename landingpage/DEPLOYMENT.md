# Deployment, sync, and verification guide

This is the reference for any agent or session (human or LLM) working on this site later. It
documents the actual working process, not an idealized one, based on how this project has really
been built and shipped. Follow it exactly. Don't improvise a different process without a reason.

## Safety guarantees, failure behavior, and edge cases — read this first

These are the questions that matter most before you trust this process with real content, so
they're answered directly, not buried in a checklist.

### If a build fails, does the live site break or go down?

**No.** Netlify deploys are atomic: a new deploy only replaces the live site if it finishes
successfully. If the build fails for any reason (a type error, a secrets-scan false positive, a
missing dependency), **the previous successful deploy keeps serving parlesprint.com exactly as
it was**, untouched. This happened for real during development: a doc file accidentally contained
a literal Supabase URL, Netlify's secrets scanner correctly failed the build, and the site kept
serving the prior good deploy the whole time. Nothing broke for a single visitor. The only
consequence of a failed build is that *your latest change* isn't live yet, not that anything
existing is damaged.

### How do you know if a build failed, instead of assuming it worked?

**Never assume. Always check.** After every push:

1. Poll the live site for the specific new content you added (not just a 200 status — a 200 on
   an unrelated page tells you nothing about whether *your* change deployed).
2. If the expected new content doesn't show up after a few minutes, check the actual Netlify
   deploy log before doing anything else. It will say `published`/`completed` or `failed` in
   plain language, plus the specific error (secrets scan, type error, missing env var, etc.).
3. Fix the specific reported error, then push again. Don't guess at unrelated causes.

If you're an agent without direct Netlify dashboard access, ask the user to paste the deploy log
— they've done this before, and it's the fastest way to diagnose a failed build precisely.

### Does adding new content delete or overwrite old content?

**No, it only adds.** Blog posts and story updates are plain objects appended to arrays in
`app/blog/data.ts` and `app/stories/data.ts`, tracked in git. Adding a new post means adding a new
object to an array — every existing post/story object stays exactly where it is, untouched,
unless someone explicitly deletes or edits that specific object. The sitemap, IndexNow submission,
and the blog/stories index pages are all generated *from* those arrays at build time, so they
automatically include everything that's in the array, old and new. There's no separate database
of "already published" content that could get out of sync or wiped — the array in the git file
*is* the full list, always.

The one genuine way to lose content: someone edits `data.ts` and deletes or overwrites an existing
object instead of adding a new one. Git history means this is always recoverable (`git log` +
`git revert` or checking out the prior version of the file), but it's worth being deliberate: when
adding content, add a new array entry, don't replace an existing one, unless a correction is
specifically intended.

### Never commit a literal secret value into any file, including docs

This is the mistake that caused the real build failure referenced above. Netlify's secrets
scanner checks build output and repo files for the literal value of any environment variable it
knows about, including in markdown/doc files, not just code. Before committing any `.md` file
that discusses configuration:

```bash
grep -rn "$(grep SUPABASE_URL .env.local | cut -d= -f2)" . --include="*.md"
```

If that or a similar check for any other secret value returns anything, redact it — describe
*where to find the value* (Supabase dashboard, Netlify dashboard), never paste the value itself
into a doc, comment, or commit message. `NEXT_PUBLIC_SITE_URL` is the one exception, since it's
designed to be public.

## The two-repo setup, and why it exists

There are two copies of this codebase:

- **`FrenchLearning/landingpage/`** — the source of truth, nested inside the main product
  monorepo (which also contains the Flutter app and backend server, unrelated to this site).
- **`ParleSprintWebsite/`** — a standalone sibling repo, pushed to
  `github.com/thoufeekxagi/ParleSprintWebsite` (private), connected to Netlify for continuous
  deployment. **This is the repo that's actually live at parlesprint.com.**

Every change has to end up in both places: edit and test in `landingpage/`, then sync the same
files into `ParleSprintWebsite/`, then commit and push there. Editing only one side and forgetting
the other is the single most common mistake to avoid here — always finish with the diff check
below before considering a change "done."

### Known, expected differences between the two repos

Do not try to eliminate these — they exist on purpose:

| File | Why it differs |
|---|---|
| `bun.lock` | Only in `landingpage/`. Removed from `ParleSprintWebsite` because having both `bun.lock` and `package-lock.json` in the same directory triggered a Next.js "multiple lockfiles" warning and a bad `turbopack.root` workaround. `ParleSprintWebsite` uses npm only. |
| `netlify.toml` | Only in `ParleSprintWebsite`. Declares the build command and the `@netlify/plugin-nextjs` plugin explicitly. |
| `next.config.ts` | `landingpage/`'s version has a `turbopack.root` override pointing one directory above itself, needed inside the monorepo. `ParleSprintWebsite`'s version has this removed — it's a standalone repo, so that override would point outside the repo entirely and break the Netlify build. |
| `next-env.d.ts`, `package-lock.json` | Auto-generated, minor drift is normal and harmless. |

## Making a change: the full process

1. **Edit and test in `FrenchLearning/landingpage/` first.** Never edit `ParleSprintWebsite`
   directly as the primary copy — it should only ever receive synced files.
2. **Build locally** before syncing anything:
   ```bash
   cd landingpage
   rm -rf .next && npm run build
   ```
   Confirm it says `✓ Compiled successfully`, TypeScript passes, and the `Route (app)` table
   lists the pages you expect. Fix errors here, not after pushing.
3. **Visually verify with the preview tools** (`preview_start`, `preview_screenshot`,
   `preview_console_logs`, `preview_click`, etc.) for anything UI-visible. Check the browser
   console for errors, not just that the build succeeded.
4. **Sync the changed files** to `ParleSprintWebsite/` with `rsync -a <source> <dest>` per
   changed file or directory. Be careful with destination paths — `rsync -a some/api/route
   dest/app/` copies it flattened as `dest/app/route`, not `dest/app/api/route`. Match the
   destination directory to the source's parent, or mkdir the exact nested path first.
5. **Confirm parity** before moving on:
   ```bash
   diff -rq --exclude=node_modules --exclude=.next --exclude=.git --exclude='.env*' \
     landingpage/ ../ParleSprintWebsite/
   ```
   The only lines that should appear are the known differences listed above. Anything else means
   a file didn't sync, or synced to the wrong path — fix it before continuing.
6. **Build the deployed copy too**, not just the source:
   ```bash
   cd ../ParleSprintWebsite
   rm -rf .next && npm run build
   ```
   This has caught real bugs before (a type error only visible after `getClient()`'s return type
   was used a certain way, for one). Don't skip it just because the source copy built fine.
7. **Commit and push:**
   ```bash
   git add -A
   git commit -m "Clear, specific message describing the change and why"
   git push
   ```
   Netlify auto-deploys on every push to `main`. No manual deploy trigger needed.
8. **Poll production until the new deploy is live**, don't assume it's instant:
   ```bash
   for i in $(seq 1 20); do
     status=$(curl -sS -o /dev/null -w "%{http_code}" https://parlesprint.com/some-path --max-time 10)
     echo "attempt $i: $status"
     [ "$status" = "200" ] && break
     sleep 15
   done
   ```
   A build typically takes 30-90 seconds. If it's still old after ~5 minutes, check the Netlify
   deploy log for a build failure before assuming it's just slow.
9. **Verify the live site, not just that it returns 200.** Check the specific thing you changed
   actually rendered/works — grep the response body for new text, hit new API routes with curl,
   or take a screenshot if it's visual. "The deploy succeeded" is not the same as "the feature
   works in production."

## Verification checklist after any deploy

Run through whichever of these are relevant to the change:

- **Sitemap:** `curl -sS https://parlesprint.com/sitemap.xml | grep -o '<loc>[^<]*</loc>'` —
  confirm every expected URL is present, including new blog posts or story updates.
- **Robots:** `curl -sS https://parlesprint.com/robots.txt` — confirm it still allows the major
  crawlers (GPTBot, ClaudeBot, PerplexityBot, Google-Extended, Applebot-Extended, Bingbot, etc.)
  and `Disallow: /api/`.
- **IndexNow key file:** `curl -sS https://parlesprint.com/<key>.txt` — should return the raw key,
  no HTML wrapper, no trailing whitespace issues.
- **API routes:** hit them directly with curl (see the waitlist and blog-feedback routes for the
  pattern), confirm the JSON response, then verify the row actually landed with a Supabase
  `execute_sql` query, then **delete the test row** — don't leave test data in production tables.
- **Structured data:** `fetch('URL').then(r=>r.text())` or a browser eval on
  `document.querySelectorAll('script[type="application/ld+json"]')` to confirm JSON-LD is present
  and parses.

## Environment variables

Set in **both** places: `landingpage/.env.local` (gitignored, for local dev/build) and the
Netlify dashboard (**Project configuration → Environment variables**, for production):

| Variable | Value | Used for |
|---|---|---|
| `SUPABASE_URL` | (project URL — look this up in the Supabase dashboard, never paste the literal value into a markdown/doc file, see the warning below) | Waitlist form, blog feedback |
| `SUPABASE_ANON_KEY` | (anon key from the Supabase dashboard) | Same as above |
| `NEXT_PUBLIC_SITE_URL` | `https://parlesprint.com` | Canonical URLs, sitemap, structured data, IndexNow |
| `NEXT_PUBLIC_GA_MEASUREMENT_ID` | GA4 Measurement ID, e.g. `G-XXXXXXXXXX` (from analytics.google.com) | Loads Google Analytics via `@next/third-parties/google` in `app/layout.tsx`. Entirely optional — if unset, no GA script loads at all and the site works normally (confirmed: `sendGAEvent` no-ops with a console warning instead of erroring). |
| `SECRETS_SCAN_OMIT_KEYS` | `NEXT_PUBLIC_SITE_URL` | Stops Netlify's secrets scanner from false-flagging this variable — it's supposed to be public, that's what `NEXT_PUBLIC_` means, but the scanner doesn't know that convention and will fail the build without this |

If you add a new environment variable in code, remember: **it only takes effect on builds created
after it's added to Netlify.** Adding it and not triggering a fresh deploy is a common way to
think something is "not working" when it's actually just not deployed yet.

## SEO infrastructure map

| What | Where | Notes |
|---|---|---|
| Sitemap | `app/sitemap.ts` | Auto-includes every blog post and story update — no manual step needed when adding content |
| Robots / crawler allowlist | `app/robots.ts` | Explicitly allows major AI crawlers by name |
| IndexNow | `scripts/indexnow-submit.mjs`, key file in `public/` | Runs as an npm `postbuild` hook automatically on every build. Reads URLs straight from the built sitemap file (`.next/server/app/sitemap.xml.body`), so it also needs zero manual updates. Only affects Bing/Yandex — Google isn't in the IndexNow consortium. |
| Structured data | `app/layout.tsx` (site-wide Organization/SoftwareApplication/FAQPage), each blog/story page (BlogPosting/ProfilePage) | |
| `llms.txt` | `public/llms.txt` | Low actual impact as of 2026 — Google has explicitly said it doesn't support it, most crawlers skip fetching it. Harmless to keep, don't expect it to move rankings. |
| Google Search Console | Verified via meta tag in `app/layout.tsx`'s `metadata.verification.google` | |
| Bing Webmaster Tools | Verified via Google Search Console import | Submit sitemap separately here too — Bing does not share sitemap submissions with Google |

## Content authoring

- New blog post: see `app/blog/AUTHORING.md`
- New story or story update: see `app/stories/AUTHORING.md`

Both are self-contained references for adding content that matches the site's existing structure,
components, and brand voice without re-deriving conventions from scratch.

## Brand voice — applies everywhere on this site, not just blog/stories

- Never the word "AI" in visible copy. Say "personal tutor," "digital tutor," or "Marie."
- No em dashes anywhere. Rewrite with a period, comma, or colon.
- No fake statistics or invented percentages.
- No fluency-timeline overclaiming ("fluent in 3 months," etc.).
- Be explicit about non-affiliation with IRCC/TEF/TCF where relevant.
- One typeface (system sans, no serif) — this is global CSS, don't override it per-page.
