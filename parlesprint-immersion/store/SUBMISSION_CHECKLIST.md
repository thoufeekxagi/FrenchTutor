# Submission checklist (v0.2.0)

Upload: `release/parlesprint-immersion-0.2.0-chrome-STORE.zip` (built with `npm run zip:store`; the manifest has no `key`, as the Web Store requires).

## Done and verified
- [x] 117 unit tests, 16 backend tests, 28 browser tests pass; production build contains no test-only code or secrets.
- [x] Minimal permissions: storage, activeTab, scripting, tabCapture, offscreen. Hosts: youtube.com, translate.googleapis.com, the Supabase project. No broad host access, no microphone, no remote code, no identity.
- [x] Backend accepts any Chrome extension origin (the store assigns the ID after upload), rejects websites, and enforces free daily limits per install, IP and globally.
- [x] Privacy policy deployed at the Supabase URL and matches this build (v0.4). Previous deployed text archived in `store/archive/`.
- [x] Four real 1280x800 screenshots in `store/screenshots/` taken from this build on a real YouTube video. Old-UI screenshots moved to `store/archive-old-ui/`.
- [x] Reviewer instructions with a guaranteed offline sample, a captioned YouTube video and a non-YouTube French audio page for live captions.

## You still do in the dashboard
- [ ] Upload the zip, choose Education, paste the listing text and single purpose from `LISTING.md`.
- [ ] Privacy tab: paste the permission justifications; fill the data form from `PRIVACY_DISCLOSURES.md` (website content, no user accounts, not sold); privacy URL and support email.
- [ ] Add the four screenshots and the 440x280 promo tile.
- [ ] Optional: use a custom domain page for the policy instead of the Supabase URL.
- [ ] Submit. Review can take days. If asked for test accounts: none exist.

## Known risks (accepted)
- Unofficial YouTube caption and Google Translate endpoints can change; the extension then shows a clear message and the offline sample still works.
- Live captions cannot be demonstrated on captioned YouTube videos by design; reviewers use the non-YouTube link.
