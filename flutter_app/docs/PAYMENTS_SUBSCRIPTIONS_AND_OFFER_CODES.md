# ParleSprint Payments, Subscriptions, and Offer Codes

Last verified: 2026-08-18

This document explains how paid access works in ParleSprint after the Apple
payment-policy cleanup. It covers normal subscriptions, Apple offer codes,
TestFlight sandbox testing, production, and the free preview tier.

## The short answer

Apple is the billing authority.

RevenueCat is the subscription SDK that reads Apple StoreKit transactions and
turns them into the `ParleSprint Pro` entitlement.

The app caches that verified RevenueCat entitlement in local SQLite so route
guards can make an immediate, synchronous decision. Supabase is still used
for authentication and learner-data synchronization, but it is no longer
consulted to decide whether premium content is unlocked.

```text
Apple StoreKit
    ↓ purchase, restore, renewal, expiration, or Apple offer-code redemption
RevenueCat SDK
    ↓ CustomerInfo / ParleSprint Pro entitlement
Local SQLite entitlement cache
    ↓ synchronous access decision
SubscriptionGateService
    ↓
Course, practice, labs, TEF/TCF, reading, listening, writing, and speaking
```

## What each system does

| System | Responsibility | Can it unlock premium content? |
| --- | --- | --- |
| Apple App Store / StoreKit | Charges the customer and validates subscriptions and Apple offer codes | Yes, by issuing a valid StoreKit transaction |
| RevenueCat | Reads StoreKit, manages the customer identity, and exposes `ParleSprint Pro` | Yes, as the app’s entitlement adapter |
| Local SQLite | Caches the latest RevenueCat customer information for fast/offline reads | Only when the cached record came from RevenueCat and is active/unexpired |
| Supabase Auth | Signs users in and identifies their learner account | No |
| Supabase learner tables | Syncs profiles, progress, stories, sessions, and other learner data | No |
| Old Supabase invite codes | Historical migration/audit material only | No; the old grant path is disabled and blocked |

On iOS, RevenueCat uses Apple StoreKit underneath. RevenueCat does not replace
Apple’s billing system; it simplifies reading and synchronizing Apple’s
subscription state. On Android, the equivalent store is Google Play Billing.

## How a normal purchase unlocks the app

1. The learner opens the ParleSprint paywall.
2. RevenueCat loads the current products configured in App Store Connect and
   RevenueCat.
3. The learner taps the purchase button.
4. Apple presents the system purchase sheet.
5. Apple completes or rejects the transaction.
6. RevenueCat receives the active `ParleSprint Pro` entitlement.
7. The app writes the product identifier, active status, expiration date, and
   verification time to the local `entitlements` table.
8. The app invalidates the access providers.
9. The shared gate unlocks every premium area.

The app does not unlock based on the text of a product identifier, a referral
code, or a Supabase profile flag.

## How restore works

The Restore Purchase button calls Apple through RevenueCat. If Apple reports
an active `ParleSprint Pro` entitlement, the app saves that entitlement to the
same local cache and unlocks premium content.

Restore is important when:

- the customer installed the app on a new device;
- the customer redeemed an Apple offer code outside the app;
- the purchase completed while the app was not open;
- the local cache was cleared during sign-out.

## How Apple offer codes work

An Apple offer code is not an app-side unlock code.

The offer is configured in App Store Connect and attached to a real
auto-renewable subscription product. Apple decides whether the customer is
eligible, applies the free or discounted period, and creates the StoreKit
transaction. RevenueCat then sees the resulting subscription entitlement in
the same way it sees a normal purchase.

The code flow is:

```text
Apple offer code
    ↓ redeemed through Apple/Sandbox Apple Account
StoreKit transaction
    ↓
RevenueCat ParleSprint Pro entitlement
    ↓
Local entitlement cache
    ↓
All premium areas unlock
```

ParleSprint does not need a custom code-entry box. Users redeem production
codes through Apple’s redemption flow or redemption URL. Sandbox codes are
redeemed through the Sandbox Apple Account controls.

Apple’s documentation for supporting offer codes is available here:

- [Supporting offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app)
- [Set up subscription offer codes](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/)

## Current ParleSprint offers

### Free, non-renewing friend offer

Example App Store Connect offer:

`FRIEND_FREE_1M_NO_RENEW`

Expected behavior:

```text
1 month free → offer ends → no charge and no automatic renewal
```

This is appropriate for friends who should receive temporary access without
being charged afterward.

### Paid friend offer

Example App Store Connect offer:

`FRIEND_PAID_1M_499`

Expected behavior when configured as Pay Up Front for one month:

```text
Discounted first month → normal three-month subscription renewal
```

Because this is an auto-renewable subscription offer, the customer must see
the renewal price and billing cadence clearly. Apple may reject a regional
offer price that is not actually cheaper than the effective standard price of
the three-month product.

## TestFlight and sandbox

TestFlight uses Apple’s sandbox payment environment. Sandbox transactions do
not charge real money, and subscription renewals are accelerated for testing.

To test a sandbox offer code:

1. Download the actual code from the Sandbox Codes batch in App Store Connect.
2. Install the TestFlight build.
3. Sign in to a Sandbox Apple Account on the device.
4. Open `Settings → Developer → Sandbox Apple Account → Manage`.
5. Choose `Initiate Transaction`.
6. Select `Offer Codes` and redeem the sandbox code.
7. Return to ParleSprint and relaunch it.
8. Use `Restore Purchase` if the entitlement is not visible immediately.

Use a fresh sandbox account, or clear its sandbox purchase history, when
testing offer eligibility again. Apple applies eligibility rules to offer
codes for auto-renewable subscriptions.

Apple’s current TestFlight guidance is available at:

- [Testing subscriptions and In-App Purchases in TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/)
- [Testing offer codes in the sandbox](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app)

## Production

Production offer codes are created after the subscription and app are in the
appropriate App Store Connect distribution state. A production custom code can
be limited by redemption count and expiration date.

For a small private group, use one-time-use codes. For a campaign, use a
custom code with a strict redemption limit. The code is attached to one
specific offer; a free-offer code and a paid-offer code are different codes.

Do not add a Supabase code field or a custom local unlock path. If ParleSprint
ever adds an in-app Redeem Offer Code button, it must present Apple’s StoreKit
redemption sheet rather than validating codes itself.

## Free tier and locked areas

The free tier is independent of Apple subscription offers:

- Vocabulary, flashcards, alphabet, review/history, and the existing limited
  Free Talk allowance remain available without a subscription.
- Premium course, reading, listening, writing, grammar, roleplay, exam,
  connectors, liaison, and speaking areas share one meaningful premium preview
  per local day.
- A verified active `ParleSprint Pro` entitlement unlocks all premium areas.
- The daily preview table is local learning-access state; it never creates a
  paid entitlement and never overrides Apple billing.

The shared implementation is in:

- `lib/services/subscription_gate_service.dart`
- `lib/services/premium_access_gate.dart`
- `lib/services/revenue_cat_service.dart`
- `lib/models/pilot_access.dart`

## Legacy Supabase access retirement

The previous Supabase subscription-invite flow is not part of the release
access decision anymore.

Retired runtime behavior:

- no client call to redeem a Supabase subscription invite;
- no Supabase profile hydration for subscription access;
- no RevenueCat webhook that writes subscription authority into Supabase;
- no reviewer-email premium bypass;
- no user-entered code that directly unlocks digital content.

Historical Supabase migration files are retained as migration history so an
existing database is not made inconsistent by deleting migration files. The
launch migrations revoke client access to the historical invite functions and
the local model retains a deny-only guard for old `invite:` entitlement rows.
Those historical rows cannot unlock the App Store build.

Supabase remains in the project for Auth and learner data. That does not make
Supabase the subscription authority.

The local entitlement row is scoped to the currently signed-in learner. The
Supabase user ID is used only as an account/cache key and RevenueCat customer
identifier; it cannot create, verify, or extend premium access. Signing out or
switching accounts clears the previous local entitlement cache before the new
RevenueCat customer information is applied.

## Release verification checklist

Before submitting a new build:

- App Store Connect has the real auto-renewable products in one subscription
  group.
- RevenueCat has those products attached to the `ParleSprint Pro` entitlement.
- The RevenueCat iOS public SDK key is present in the release build.
- A normal sandbox purchase unlocks all premium areas.
- Restore Purchase unlocks the same areas.
- A sandbox free offer code produces the expected one-month non-renewing
  entitlement.
- A sandbox paid offer code produces the expected discounted period and
  renewal behavior.
- A non-subscriber can use the free core and one daily premium preview.
- A non-subscriber cannot enter a second premium area after using that preview.
- There is no custom code-entry field or Supabase unlock button.
- The paywall shows the billed amount and billing cadence more prominently
  than trial or introductory copy.

The governing Apple policy reference is [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
