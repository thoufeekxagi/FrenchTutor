# Cross-product release handoff — 2026-10-19

## iOS app and App Store Connect

- Xcode archive `1.0.3 (327)` was uploaded to App Store Connect, as shown in the owner's October 19 screenshot.
- Local assets include seven iPhone 6.1/6.3-inch screenshots (1206 × 2622) and six iPad 13-inch screenshots (2048 × 2732). Both sets lead with TCF Canada; Bonjour is fourth. Captions and filenames are in `flutter_app/app_store_screenshots/v3-submission/CAPTIONS.md` and `ipad/CAPTIONS.md`.
- Candidate App Store name, subtitle, keywords, promotional text and description are in `flutter_app/app_store_screenshots/v3-submission/ASO_METADATA.md`.
- App Store Connect screenshot upload state, current metadata save state, build selection and App Review submission were not verified during this repo handoff. The screenshots and metadata are repository assets/copy; they are not submitted by a Git push.

## Website

- The standalone `ParleSprintWebsite` repo contains the site refresh and an extension landing page that links to the existing Chrome Web Store listing.
- The canonical `FrenchTutor/landingpage` source is synced with the extension landing page and privacy page.
- The `/extension/privacy` route describes optional live tab transcription, translation, account-backed explanations, local storage and server-side explanation caching.
- Pushing `ParleSprintWebsite` `main` triggers the configured Netlify production build. Verify the deploy and the public route after the push.

## Chrome extension

- The owner confirms ParleSprint Immersion is live in the Chrome Web Store. The listing ID is `ijclgmkoljddlalgcnpodeemcmcipolb`.
- This task changes website copy and local repo documentation only. It does not change extension runtime code, build output, ZIP files, Web Store listing metadata or publisher settings, and it does not submit a store update.
- The live package version, current listing metadata, permission declarations and policy URL were not independently verified. Historical checks in `parlesprint-immersion/store/VERIFICATION.md` do not prove the current live package matches local source.
- Local source review found the manifest permission list differs from API/host usage in source. That discrepancy is documented in `parlesprint-immersion/store/RELEASE_0.2.0.md` for a separately scoped future review.

## Validation boundary

This handoff records what was evidenced by repository files and screenshots. Website lint/build results and Git push/deploy status should be appended after they complete. No Flutter tests, App Store submission or Chrome Web Store update is part of this handoff.
