---
name: parlesprint-landing-page
description: Build and critique the ParleSprint marketing site as a conversion-focused, accessible Next.js landing page for English-speaking beginners learning French for TCF/TEF and Canadian immigration.
---

# ParleSprint Landing Page Skill

## Product truth

ParleSprint is not a speaking-only drill app and it is not affiliated with IRCC, TCF, or TEF. It teaches French from beginner level toward TCF/TEF readiness for people pursuing a Canadian immigration goal. Never claim that ParleSprint guarantees a score, PR, NCLC level, or three-times-faster learning without evidence.

## Audience

Primary person: an English-speaking immigrant or prospective immigrant in Canada who has just decided French could materially improve their options. They are anxious about starting from zero, confused by NCLC/CLB and TCF/TEF requirements, short on time, and suspicious of vague AI promises. Five minutes before the page they are comparing apps, tutors, and YouTube playlists. Five minutes after a successful visit they should understand the path, trust the product, and join the waitlist.

## The page's single job

Turn qualified visitors into waitlist signups. Every section must reduce one of these doubts:

1. Is this for someone starting from zero?
2. Does it teach real French rather than only exam tricks?
3. Will it support listening, speaking, reading, and writing?
4. Does it understand TCF/TEF and the Canadian context?
5. What happens after I join?

## Design direction: the French learning route

Use a calm, editorial study-desk world: warm paper surfaces, ink navy, Parle violet, and one orange route marker. The visual signature is a "niveau route" that moves from A1 to B2/NCLC 7 and appears in the hero demo and process section. It should feel like a well-made passport/study map, not a generic SaaS gradient.

Reject:
- Giant abstract purple blob -> use a product-like progress route and concrete lesson cards.
- Generic three-card feature grid -> use a learner journey with observable outputs.
- Fake testimonials and unsupported outcome numbers -> use honest product preview, proof of method, and transparent "launching soon" status.

## Design tokens

- Ink: #17203D
- Ink soft: #46506D
- Paper: #F8F7F2
- Paper warm: #F1EFE7
- Violet: #6C4CF1
- Violet dark: #4C1D95
- Orange route marker: #F08A4B
- Blue note: #DCE7FF
- Green completion: #79B99C
- Hairline: #E7E4DA

Typography uses a distinctive display serif for the thesis and a readable sans for interface copy. Prefer the local/brand-safe font setup in the app; use next/font only when the build can fetch fonts reliably. Keep body text at readable sizes and avoid oversized copy that hides the value proposition.

## Copy rules

Use plain English, active verbs, and specific outcomes:
- "Start with the French you actually need."
- "A guided path from beginner French to TCF and TEF readiness."
- "Learn the language. Then train for the test."

Do not say:
- "Guaranteed NCLC 7"
- "Approved by IRCC"
- "3x faster" unless a study proves it
- "Pass with zero effort"
- "The easiest exam"

## Conversion structure

1. Announcement bar: launch status and one clear action.
2. Header: logo, path anchors, waitlist CTA.
3. Hero: thesis, audience qualifier, waitlist form, product route preview.
4. Trust strip: four abilities plus TCF/TEF/Canadian immigration context without implying endorsement.
5. Problem: explain why isolated flashcards and exam cramming fail.
6. Method: learn -> practise -> measure, with concrete lesson outputs.
7. Interactive demo: tabs for pathway, speaking, listening, writing; keep it lightweight and fast.
8. Roadmap: what is launching now and what comes next.
9. FAQ: handle beginner level, TCF vs TEF, time expectations, privacy, and launch status.
10. Final waitlist CTA: repeat the value proposition and set expectations.

## UX and accessibility

- One primary CTA label: "Join the early list".
- Use a real form with a labelled email field, autocomplete=email, inputMode=email, required, and visible validation.
- Never hide success or error messages from assistive technology; use role=status or role=alert.
- Keep focus states visible and keyboard navigation complete.
- Respect prefers-reduced-motion.
- Use semantic section headings, a skip link, descriptive alt text, and sufficient contrast.
- Keep all interactive elements at least 44px high on mobile.

## Technical defaults

- Next.js App Router, TypeScript, React, Tailwind v4, Bun.
- Use Server Components by default; isolate client state to the interactive demo and waitlist form.
- Use lucide-react for interface icons; do not add icon packages casually.
- Prefer CSS transitions and keyframes over a large animation dependency.
- Keep the page statically renderable and avoid client-only rendering for SEO copy.
- Add metadata, Open Graph metadata, robots, sitemap, and JSON-LD only for claims that are true.
- Do not add analytics or third-party waitlist services without explicit configuration and consent.

## Quality gate

Before declaring the page complete:

- Run `bun run lint` and `bun run build`.
- Test at 375px, 768px, and 1440px widths.
- Test tab navigation and reduced-motion mode.
- Verify form validation and the configured waitlist boundary.
- Check that no unsupported claims, fake social proof, or IRCC/TEF/TCF endorsement language appears.
- Review the page in a browser and remove one decorative element if the design feels crowded.

## Sources used to shape this skill

- Anthropic frontend-design: https://github.com/anthropics/skills/tree/main/skills/frontend-design
- ConardLi web-design-engineer: https://github.com/ConardLi/garden-skills/tree/main/skills/web-design-engineer
- Vercel skills CLI: https://github.com/vercel-labs/skills
- Next.js SEO playbook: https://vercel.com/blog/nextjs-seo-playbook
- shadcn/ui Next.js guidance: https://ui.shadcn.com/docs/installation/next
