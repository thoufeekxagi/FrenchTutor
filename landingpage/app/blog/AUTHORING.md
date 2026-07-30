# Writing a new ParleSprint blog post

This is the reference for adding a new post so it matches the site's structure, design, and brand
voice automatically. Follow it exactly — don't invent a new content shape per post.

## Where posts live

Every post is one object in the `posts` array in [`data.ts`](./data.ts). There is no separate file
per post and no CMS — add an object, run the build, ship it.

```ts
{
  slug: "kebab-case-unique-slug",
  title: "The exact H1 shown on the page",
  description: "1-2 sentence summary. Used as the meta description, OG description, and card excerpt.",
  category: "One of the existing categories below, or a new one if it's a genuinely new topic",
  date: "YYYY-MM-DD",
  readingTime: "X min read", // estimate: ~200 words per minute
  keywords: ["primary target phrase", "secondary phrase"], // from keyword research, used in <meta keywords>
  coverImage: "/blog/your-image.jpg", // optional, not yet used on cards but reserved for future use
  content: [ /* ContentBlock[], see below */ ],
}
```

Existing categories (reuse these unless the topic genuinely doesn't fit): `TEF & TCF Canada`,
`Immigration French`, `Professional French`, `Learning French`.

## The content block types

`content` is an array of blocks rendered in order by `BlogProse.tsx`. Available types:

| Type | Shape | Use for |
|---|---|---|
| `p` | `{ type: "p", text }` | Body paragraphs |
| `h2` | `{ type: "h2", text }` | Major section headings |
| `h3` | `{ type: "h3", text }` | Sub-section headings within an h2 |
| `ul` | `{ type: "ul", items: string[] }` | Bullet lists |
| `ol` | `{ type: "ol", items: string[] }` | Numbered lists |
| `quote` | `{ type: "quote", text, attribution? }` | Pull quotes, forum quotes, testimonials |
| `callout` | `{ type: "callout", text }` | The soft product-mention box — one per post, where ParleSprint/Marie is introduced as the answer |
| `image` | `{ type: "image", src, alt, caption? }` | A single image, full-width, 16:9 crop |
| `carousel` | `{ type: "carousel", images: [{ src, alt, caption? }] }` | Multiple images the reader can swipe/click through |
| `video` | `{ type: "video", src, caption?, poster? }` | A video. YouTube URLs (`youtube.com/watch?v=...` or `youtu.be/...`) auto-embed; any other `src` renders as a native `<video>` tag |

Put images in `public/blog/` and reference them as root-relative paths (`/blog/my-image.jpg`), not
external URLs — `next/image` isn't configured to optimize arbitrary remote hosts, and pointing at
someone else's server is fragile anyway.

A typical post shape: 1-2 intro paragraphs, then 3-5 `h2` sections (each usually opening with a
paragraph and sometimes a list), ending in one `callout` that introduces ParleSprint/Marie as the
answer to the problem just described, then a closing paragraph. Real images/video are optional —
don't force one in if there's nothing genuinely illustrative to show.

## Brand voice rules — these are not optional

- **Never use the word "AI" in visible copy.** Say "personal tutor," "digital tutor," or just
  "Marie." The target audience is actively turned off by AI branding. (It's fine in `<meta>`
  keywords/descriptions if genuinely useful for search, just not in anything a reader sees.)
- **No em dashes anywhere.** Rewrite with a period, comma, or colon instead. Em dashes are one of
  the most common "this was written by AI" tells and the user has explicitly asked for them to be
  removed everywhere on this site.
- **No fake statistics or invented percentages.** If you don't have a real number, don't make one
  up — write "many learners find..." instead of "73% of users report...".
- **No fluency-timeline overclaiming.** Never promise "fluent in 3 months" or a specific CEFR level
  by a specific date. This audience has read the news coverage debunking exactly those claims from
  competitors, and it destroys trust fast. Say "faster than a generic class" or "measurable
  progress," not a guaranteed outcome.
- **Be honest about affiliation.** Any post touching TEF, TCF, IRCC, or SLE should make clear
  ParleSprint is not affiliated with and doesn't guarantee outcomes on those programs, the same way
  the FAQ section already does.
- **One typeface, no serif.** This is handled automatically by the site's global CSS (everything
  uses the Apple system font stack) — don't add any font overrides in a post.

## Adding the post

1. Add the object to the `posts` array in `data.ts`.
2. If you added images, place them in `public/blog/`.
3. From `landingpage/`, run `npm run build` locally and confirm it compiles with no errors and the
   new route shows up under `Route (app)` in the build output.
4. The homepage "From the blog" section always shows the 2 most recent posts automatically (sorted
   by `date`), and the sitemap picks up the new URL automatically too — no manual step needed for
   either.
5. Add the new slug to `BLOG_SLUGS` in `scripts/indexnow-submit.mjs` so it gets pinged to Bing/
   Yandex on the next deploy — this one is not automatic, unlike the sitemap.
6. Sync the change to the deployed repo (`ParleSprintWebsite`) the same way prior posts were synced,
   commit, and push — Netlify auto-deploys on push to `main`, and the IndexNow ping fires
   automatically as part of that build.
