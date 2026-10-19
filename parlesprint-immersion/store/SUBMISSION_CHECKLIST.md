# Chrome Web Store release maintenance checklist

The owner confirmed the Chrome Web Store listing is live. This task only updates the website and repository documentation; it does not upload a package, edit the live listing, or submit a store update. Check the publisher dashboard for the currently served version before planning a release.

## Before a future store update
- [ ] Confirm the live package version, listing text, permissions, privacy answers and policy URL in the publisher dashboard.
- [ ] Compare the proposed source changes with the currently published package; keep the stable extension ID.
- [ ] Build and inspect the new runtime and store packages; the store ZIP must omit the development `key`.
- [ ] Run the current automated checks and complete manual Chrome QA in `store/QA.md`.
- [ ] Make sure the public policy URL resolves to the policy matching the package and dashboard declarations.

## Historical evidence

`VERIFICATION.md` and `AI_EVALUATION.md` record dated checks of earlier source builds. They are not proof that the live store package matches the current repository. `RELEASE_0.2.0.md` records the scope and verification limits for this handoff.

## Known risks (accepted)
- Unofficial YouTube caption and Google Translate endpoints can change; the extension then shows a clear message and the offline sample still works.
- Live captions cannot be demonstrated on captioned YouTube videos by design; reviewers use the non-YouTube link.
