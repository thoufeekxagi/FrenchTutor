# ParleSprint Immersion 0.2.0 source and live listing note

Date: 2026-10-19

The owner confirms ParleSprint Immersion is live in the Chrome Web Store. The listing ID used by the website is `ijclgmkoljddlalgcnpodeemcmcipolb`: <https://chromewebstore.google.com/detail/parlesprint-immersion/ijclgmkoljddlalgcnpodeemcmcipolb>.

The repository contains version 0.2.0 source. The live listing's exact package version, description, permissions, privacy answers and policy URL were not independently verified in this task. `store/LISTING.md` and `store/PRIVACY_DISCLOSURES.md` are reference worksheets, not exports of the dashboard.

## Scope of this handoff

- The website's extension page links to the existing Chrome Web Store listing and its new `/extension/privacy` policy page.
- Repository docs now describe the listing as owner-confirmed live and distinguish the published package from checked-in source.
- No extension runtime code, build output, ZIP, Chrome Web Store metadata or publisher dashboard setting was changed or submitted.
- The standalone site's privacy page is the current source for the website URL. The old Supabase privacy function source was aligned with that text locally, but it was not deployed. If the live store listing still links to the Supabase endpoint, verify and deploy the policy function separately.

## Future source review

The checked-in `wxt.config.ts` declares `storage`, `activeTab`, `scripting`, `tabCapture`, and `offscreen`, with hosts for Supabase, Google Translate, and YouTube. The source contains optional Chrome Identity sign-in and a Gemini Live connection without corresponding `identity` and Gemini host entries in that manifest. Reconcile this before producing a future store package; this note does not claim that the published package has the same configuration.

Historical automated and manual checks are in `store/VERIFICATION.md`, `store/AI_EVALUATION.md` and `store/QA.md`. They apply only to the dated source/build recorded there, not automatically to the package currently served by Chrome Web Store.
