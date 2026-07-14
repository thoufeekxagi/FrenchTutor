# ParleSprint landing page

A pre-launch, conversion-focused marketing site for ParleSprint: a structured French-learning path for English-speaking beginners preparing for TCF or TEF and a Canadian immigration goal.

## Stack

- Next.js App Router
- TypeScript
- Tailwind CSS v4
- Bun
- lucide-react

## Run locally

```bash
cd landingpage
bun install
bun dev
```

Open http://localhost:3000.

## Verify

```bash
bun run lint
bun run build
```

## Environment

Copy `.env.example` to `.env.local` before deployment and set `NEXT_PUBLIC_SITE_URL` to the real domain. The default local URL keeps metadata and sitemap generation valid during development.

## Waitlist integration

The current form validates email and provides a pre-launch demo flow. Before launch, connect `app/api/waitlist/route.ts` to a real provider through `WAITLIST_WEBHOOK_URL` or replace the route with a transactional email/database integration. Do not put provider keys in the client. Without a webhook, the API intentionally returns a preview success and does not persist addresses.

## Product/marketing decisions

See:

- `brand-spec.md` for the design read and asset contract
- `../.devin/skills/parlesprint-landing-page/SKILL.md` for the reusable design, UX, SEO, and quality workflow
- `../.devin/skills/parlesprint-landing-page/references/marketing-brief.md` for positioning and funnel assumptions

## Planned launch evolution

1. Validate the waitlist and message with real visitors.
2. Add a welcome email and source attribution only after choosing a privacy-safe provider.
3. Add real product screenshots or a recorded demo once the Flutter app flow is stable.
4. Add TCF/TEF SEO pages only when their content is accurate and maintained against current official guidance.
