# ParleSprint Marketing

This folder is the whole 90-day organic growth plan: pre-written posts for Reddit, Twitter/X, LinkedIn, and Instagram, plus a small local website to track what to post and when.

## How to use this, day to day

1. The tracker runs on its own, permanently, at `http://localhost:58432/site/index.html`. It's a systemd user service (`parlesprint-marketing.service`) with lingering enabled, so it starts at boot and needs nothing from you, no terminal, no manual server command. There's also a desktop launcher called "ParleSprint Marketing Tracker" in your applications menu that opens it directly.
2. Click the **Today** tab. It shows only what's scheduled for the current date across all four platforms.
3. Copy the text with the "Copy post text" button, paste it into the actual platform, post it, then check the "Posted" box. That's it. The whole daily task should take under 20 minutes.
4. Use **Upcoming** to look ahead, or **Full calendar** to browse everything, search, or filter by platform.

Your "posted" checkmarks are saved in your browser's local storage, so they persist between visits on the same machine and browser.

## Managing the background service

You shouldn't need to touch this, but if the tracker ever stops loading:

- Check it's running: `systemctl --user status parlesprint-marketing.service`
- Restart it: `systemctl --user restart parlesprint-marketing.service`
- The service definition lives at `~/.config/systemd/user/parlesprint-marketing.service`, and it serves this whole `marketing/` folder on port 58432.

## Folder layout

- `reddit/reddit_calendar.json` — 26 posts (Mon/Thu, 2/week), rotating across r/ImmigrationCanada, r/ExpressEntry, r/French, r/learnfrench. Value-first, no link in the post body ever, link only goes in the first comment once the app is live.
- `twitter/twitter_calendar.json` — 90 daily build-in-public tweets documenting the actual app journey.
- `linkedin/linkedin_calendar.json` — 26 posts (Tue/Fri, 2/week), slightly more professional founder-journey and product-reasoning content.
- `instagram/instagram_calendar.json` — 39 posts (Mon/Wed/Fri), bite-sized French/exam tips and personality content, roughly 1 in 5 mentioning the app directly.
- `site/index.html` — the tracker itself, a single static page, no build step, no dependencies.

Each platform folder also has its own short README with the specific rules for that channel.

## The one rule that matters most

Every post has to be useful on its own, even to someone who never talks to you again. The app itself is never pitched in a post body, not once in 90 days. It shows up naturally in a first comment or as a transparent update, and only after the account has already given real value repeatedly. If a draft post doesn't teach or help a stranger, it doesn't go up.

## Timeline built into the calendars

- Days 1 to about 21 (2026-07-20 to 2026-08-09): pure authority-building, no product mentioned anywhere.
- Days ~22 to 56 (through about 2026-09-10): app goes live, soft hook posts start appearing (still mostly value), beta learnings get shared.
- Days ~57 to 90 (through 2026-10-17): a small paid "founding member" tier gets mentioned transparently, free tier explicitly stays free.
