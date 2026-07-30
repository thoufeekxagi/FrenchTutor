# Writing a new story, or a new update to an existing story

Stories are structured differently from blog posts on purpose: a blog post is a one-time
article, a story is an ongoing, dated journey with new entries appended over time (weekly or
monthly). This reuses the exact same `ContentBlock` type and `BlogProse` renderer as the blog —
that's intentional, so a story page never looks or feels different from a blog page. Don't
introduce a second content format.

## Adding a new update to an existing story (the common case)

Open `data.ts`, find the `Story` object by its `slug`, and push a new object onto its `updates`
array:

```ts
{
  date: "YYYY-MM-DD",
  title: "Short, honest title for this update",
  content: [ /* ContentBlock[], same shape as blog posts, see app/blog/AUTHORING.md */ ],
}
```

That's it. `getStoryUpdatesSorted` always sorts newest-first for display, and the sitemap picks
up the new `lastModified` date automatically since it reads the latest update's date. No sitemap
edit, no new route, no new page.

## Adding a brand-new story (a different person)

Add a new `Story` object to the `stories` array in `data.ts`:

```ts
{
  slug: "kebab-case-unique-slug",
  name: "Full name",
  role: "How they should be described, e.g. 'Founder, ParleSprint' or 'Early learner'",
  tagline: "One sentence shown on the story card and at the top of their page",
  description: "1-2 sentence meta description",
  goal: "What they're actually trying to achieve, stated as a real commitment, not a vague aspiration",
  startingPoint: "Where they started, e.g. 'True beginner' or 'A2'",
  targetLevel: "Where they're aiming, e.g. 'B2'",
  category: "e.g. 'Founder Journey' or 'Learner Story'",
  keywords: ["relevant search phrases for this person's specific angle"],
  updates: [ /* at least one StoryUpdate to start */ ],
}
```

Everything else, the card on `/stories`, the individual page at `/stories/[slug]`, the sitemap
entry, is generated automatically from this array. No new files needed per story.

## Brand voice rules

Identical to the blog's rules in `app/blog/AUTHORING.md` — no "AI" in visible copy, no em dashes,
no fake statistics, no fluency-timeline overclaiming, honest about affiliation with TEF/TCF/IRCC
where relevant. A story is first-person and personal, but it still has to be honest: if a month
was slow or a level didn't move, say so. That honesty is the entire credibility of this section —
a founder-journey page that only reports good weeks reads as fake within two updates.

## After adding content

Same as the blog: run `npm run build` locally from `landingpage/` to confirm it compiles, sync the
change to the deployed repo, commit, and push. See the root `DEPLOYMENT.md` for the full,
step-by-step process, verification checklist, and required environment variables.
