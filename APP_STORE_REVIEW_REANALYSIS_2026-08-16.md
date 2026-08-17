# ParleSprint App Review Re-analysis — 2026-08-16

## Executive verdict

The two payment issues from the supplied App Review messages are addressed in the current Flutter source:

- The launch/referral/invite-code redemption path is disabled in the client, blocked at the entitlement layer, and blocked for client roles in Supabase.
- The active paywall now presents the localized total billed amount as the dominant pricing element. Subscription duration, auto-renewal cadence, cancel-anytime language, restore purchase, Terms, Privacy, and any configured introductory trial are visible in the purchase flow.
- The seven-day free trial is still supported. It is shown as subordinate copy such as “Includes 7 days free, then $X is billed,” while `$X` remains the prominent billed amount.
- The AI-consent screen now discloses audio/text practice plus selected photos/PDFs sent to Google for AI processing.

My calibrated estimate is:

- **Before the external checklist is verified:** approximately **60–70%** approval on the next submission. The remaining uncertainty is mostly App Store Connect/RevenueCat configuration, not the code fix.
- **After the external checklist is verified on an iPad sandbox build:** approximately **85–92%** approval for the issues shown here.

No honest estimate can guarantee approval or a review turnaround. Responding to the existing message is appropriate only if the new build, metadata, backend migration, and review notes are all ready; the response itself does not bypass a new binary review.

## What Apple requires

Apple’s current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) state that digital features and content must be unlocked with In-App Purchase and specifically disallow license keys, QR codes, and similar mechanisms. The same guidelines require clear subscription information before purchase. Apple’s [In-App Purchase HIG](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase) says the total billing price should be displayed for every purchase and that trial details should explain the post-trial charge.

The older rejection also explicitly requires the following in the app: subscription title, duration, price, functional Privacy Policy link, and functional Terms of Use/EULA link. The metadata must contain the Privacy Policy URL and either a Terms of Use link in the description or a custom EULA in App Store Connect.

## Code audit and completed fixes

### Guideline 3.1.1 — invite/referral/code unlock

Completed:

1. The user-facing referral controls had already been removed from Settings.
2. The old subscription-code UI and service are removed from the active code path.
3. The active speaking paywall no longer mentions code access; its unavailable-state copy only explains that subscriptions are temporarily unavailable.
4. `PilotEntitlement.grantsAccess` and `isPaidActive` reject historical `invite:*` product IDs, so an old cached or synced code grant cannot unlock the current build.
5. Subscription hydration rejects `invite:*` profile records.
6. `20260816142730_disable_launch_code_redemption.sql` revokes client-role execution and table access for the historical referral/invite objects.
7. `20260816160000_block_legacy_invite_entitlements.sql` clears active legacy invite grants from `profiles` without deleting the historical tables or redemption records.
8. A regression test verifies that an active legacy invite entitlement grants neither feature access nor paid-tier minutes.

The historical migrations remain in the repository intentionally for audit/history and possible future redesign. They must be deployed with the disabling migrations before review. Do not re-enable those RPCs for the App Store client. If discounted/free access is needed later, use Apple’s [In-App Purchase offer-code system](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases/) rather than a custom entitlement code.

### Guideline 3.1.2(c) — subscription information

The active `SpeakPaywallScreen` now shows:

- product title: Premium / Premium · Best value;
- localized StoreKit/RevenueCat total: `package.storeProduct.priceString`;
- billing cadence: annually, every three months, monthly, weekly, or the product’s general period;
- auto-renewal wording;
- dynamic introductory-offer copy from the store product, including the configured number of free days/weeks/months and the amount billed afterward;
- a CTA containing the billed total, e.g. `Subscribe for $X`;
- `Restore purchase`;
- Terms and Privacy links;
- cancel-anytime language.

The CTA no longer leads with “Try free”; the free trial remains visible in the plan row but is visually subordinate to the total billed amount. This directly addresses the August 13 rejection while preserving the seven-day offer.

### AI and new functionality disclosure

The redesigned app includes Live Vision Scan. The consent screen now says that audio, text, answers, photos, and PDFs selected for scanning are sent to Google for AI processing. This is required because Apple’s privacy review expects the app to disclose what data leaves the device, who receives it, and obtain permission before sending it. The app also has a Privacy Policy link, account deletion, sign-out, support access, and in-session “Report a problem” affordances.

Before submission, verify that the published Privacy Policy itself names every live processor and data type actually used by this build, especially Google Gemini/Gemini Live, Supabase, RevenueCat, analytics, and any OpenRouter path that is enabled in the release build. The app currently routes production text generation through Gemini unless the code is deliberately changed to use OpenRouter.

## Section-by-section approval risk

| Area | Current assessment | Remaining risk/check |
|---|---|---|
| Payments / invite codes | **Green after migration deployment** | Confirm both disabling migrations ran in the production Supabase project. |
| Paywall pricing | **Green in source** | Test on iPad with real StoreKit product data; do not rely on placeholder/no-offering state. |
| Seven-day trial | **Green if configured in ASC** | Confirm the selected subscription has a 7-day introductory offer and that the sandbox reviewer is eligible. |
| Terms / Privacy in app | **Green in source** | Tap both links on the review device and confirm HTTPS pages load. |
| Terms / Privacy metadata | **Needs manual confirmation** | Put Privacy URL in the App Store Connect Privacy Policy field and `https://parlesprint.com/terms` in the App Description or custom EULA field. |
| IAP products | **Cannot be proven from this repo** | Products must be in the correct subscription group, have the intended 3-month/12-month durations, be available in the review storefront, and be attached to the RevenueCat current offering. |
| Restore purchases | **Present** | Test a restored sandbox purchase on a second install/account state. |
| Account access | **Present** | Keep the demo account active and include credentials in App Review Information. |
| AI privacy | **Improved** | Confirm live policy text matches the new camera/PDF functionality and all backend processors. |
| Account deletion | **Present** | Test the full server deletion path, not only local logout. |
| Support / AI reporting | **Present** | Test mailto/support on the review device; keep a reachable support email. |
| iPad layout | **Requires device QA** | Review used iPad Air 11-inch (M3). Exercise onboarding, paywall, scan, story, writing, and settings on that exact class of device. |
| Crash/completeness | **Tests passed previously** | A release archive/device smoke test is still required before upload. |

## App Store Connect actions before resubmitting

1. Run the Supabase disabling migrations in production and verify that the client roles cannot execute the old referral/invite RPCs.
2. In App Store Connect, confirm the subscription products and names match the paywall. At minimum, the intended three-month and twelve-month auto-renewing products must be configured and available to the review environment.
3. Configure the seven-day introductory offer on the intended subscription product. Confirm the offer is eligible for the review test account/sandbox state.
4. Confirm the RevenueCat entitlement is exactly `ParleSprint Pro`, the current offering has the products attached, and the iOS public SDK key is present in the release build.
5. Set the App Store Connect Privacy Policy field to `https://parlesprint.com/privacy`.
6. Add this exact metadata line to the App Description or custom EULA field: `Terms of Use (EULA): https://parlesprint.com/terms`.
7. Add the following to App Review Information Notes:

   > ParleSprint uses Apple In-App Purchase for all paid digital features. The app has no referral, invite, license-code, QR-code, or external unlock mechanism. The purchase flow displays the localized total billed amount, subscription duration, auto-renewal terms, a configured seven-day introductory offer when eligible, Restore Purchase, and functional Terms and Privacy links. The backend is live for review. Demo account: [insert current credentials].

8. Attach a short screen recording showing: Settings → Membership → paywall → selected three-month plan → prominent total billed price → subordinate “7 days free, then $X is billed” copy → Terms → Privacy → Restore Purchase.
9. Submit a release build with the exact current source. Do not respond using an older build whose paywall still contains the removed code UI.

## Suggested App Review reply

> Hello App Review,
>
> We have updated the app and metadata to address Guideline 3.1.2(c). The purchase flow now clearly displays the subscription title, duration, localized total billed amount, auto-renewal cadence, cancel-anytime language, Restore Purchase, and functional Terms of Use and Privacy Policy links. The configured seven-day introductory offer remains available and is displayed below the billed amount with the post-trial charge stated explicitly.
>
> We also removed and disabled all custom referral/invite-code unlock paths. Paid digital access in the submitted build is granted only through Apple In-App Purchase. Historical database records are retained for audit purposes, but client roles cannot execute the old code-redemption functions and legacy code entitlements cannot unlock the app.
>
> The App Store description includes the Terms of Use (EULA) link, and the Privacy Policy field is populated in App Store Connect. We have attached a recording of the updated purchase flow and included working review credentials in App Review Information.
>
> Thank you.

## Verification performed in this workspace

- Flutter analyzer completed with no errors; nine existing informational lints remain in unrelated files.
- Full Flutter test suite completed successfully before the final one-test addition: **218 tests passed**.
- The targeted infrastructure suite completed successfully afterward, including the new legacy-invite regression test (**6 tests passed**).
- The iOS release build was started and reached the Xcode build phase, but did not complete in this environment before the build process was stopped. Perform the final archive on the release machine/Xcode setup before upload.
- The live Terms and Privacy URLs were previously reachable with HTTP 200 checks; retest them from the final release device immediately before submission.

## Bottom line

Your expectation is reasonable: the supplied messages identify payment presentation and metadata as the only reported review blockers. With the code changes above **and** the App Store Connect/RevenueCat/Supabase checklist completed, this should be a strong resubmission. The largest remaining risks are configuration drift, an unavailable IAP offering in Apple’s review environment, metadata missing the EULA link, or a new redesigned feature whose privacy disclosure/policy does not match the shipped binary.
