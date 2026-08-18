# Getting Paid Users: ParleSprint Growth and Personalization Plan

Status: research-backed implementation brief  
Last reviewed: 2026-08-17  
Scope: paid acquisition, onboarding, personalized learning, subscriptions, retention, notifications, email, ASO, and Apple review  

This is the durable reference for future product and growth work. It separates:

- **Measured facts:** benchmarks or platform rules reported by a primary or named source.
- **Case-study evidence:** results reported by a vendor or customer story, not an independent controlled benchmark.
- **Anecdotes:** public founder/operator reports that are useful for hypotheses but not proof.
- **Implementation decisions:** our chosen experiments. These must be validated against ParleSprint cohorts.

The goal is not to maximize installs. The goal is to turn a serious learner’s motivation into a visible learning outcome, then into a subscription that keeps earning its place through personalized progress.

## 1. Executive decision

The first monetization loop to build is:

```text
Acquisition promise
  -> goal and level onboarding
  -> personalized first lesson
  -> visible feedback and next-step plan
  -> transparent annual/monthly paywall
  -> chosen-time reminder
  -> personalized progress recap
  -> next lesson or review
```

The product should feel like a coach who knows:

- why the learner is studying French;
- what they can currently do;
- what level of French and English support is appropriate;
- which situations and skills matter to them;
- how much time they realistically have;
- when they want to practise;
- what they struggled with last time;
- what the next useful action is.

The first implementation should not be a large redesign. It should be a closed loop around a single learner profile and a single daily practice event. The app already has most of the learning primitives. The missing growth layer is the connection between profile data, content selection, reminder scheduling, paywall context, and measurement.

## 2. What the current code already has

The active Flutter app is `flutter_app/`. The relevant pieces are:

| Existing capability | Current location | Growth implication |
| --- | --- | --- |
| Onboarding goal, level, focus, tutor, daily minutes | `flutter_app/lib/screens/onboarding/speak_onboarding_screen.dart` | Good foundation, but reminder time is not asked and the collected data is not presented as a strong personal plan before conversion. |
| Profile persistence | `flutter_app/lib/models/profile.dart`, `flutter_app/lib/data/database/learning_store.dart` | `Profile` already stores `goal`, `level`, `sessionLength`, `interests`, and nullable `reminderTime`. |
| Profile sync | `flutter_app/lib/services/sync_service.dart` | `reminder_time` is already part of the sync shape; adding notification preferences should follow the same profile or preference-sync boundary. |
| A1, A2, B1, B2 routing | `flutter_app/lib/services/speak_roadmap_service.dart`, `flutter_app/lib/services/speak_curriculum_catalog.dart` | The course can be projected by level. Do not create a second curriculum; make selection and recommendations learner-aware. |
| Goal-specific daily order | `flutter_app/lib/services/daily_goal_service.dart` | Already changes mission order for Everyday French vs TEF Canada. This should become the first version of a goal-aware planner. |
| Personalized language mix | `flutter_app/lib/services/speak_language_profile.dart` | A1/A2 can receive more scaffolding; B1/B2 can receive more French. This is useful premium value when it is visible to the learner. |
| Progress and mastery evidence | `flutter_app/lib/orchestration/twin/`, `flutter_app/lib/orchestration/planning/`, `flutter_app/lib/orchestration/models/` | The system can select next work from evidence rather than only from a fixed sequence. |
| SRS and review state | `flutter_app/lib/services/srs_service.dart`, `flutter_app/lib/data/database/learning_store.dart` | The app can send a real “review these phrases” reminder instead of a generic notification. |
| Daily value recap | `flutter_app/lib/services/daily_summary_service.dart`, `flutter_app/lib/screens/home/daily_summary_card.dart` | This is the raw material for a daily/weekly progress email and the post-lesson value moment. |
| Saved sessions and notes | `flutter_app/lib/services/session_recorder.dart`, `flutter_app/lib/data/database/storage_service.dart` | Useful for feedback, continuity, reactivation, and paywall proof. |
| Subscription SDK and soft paywall | `flutter_app/lib/services/revenue_cat_service.dart`, `flutter_app/lib/screens/subscription/speak_paywall_screen.dart`, `flutter_app/lib/screens/subscription/paywall_screen.dart` | Purchase flow exists, but paywall context, dismissal, offer state, and full funnel instrumentation need to be added. |
| Product analytics wrapper | `flutter_app/lib/services/product_analytics.dart` | The wrapper exists. The next step is a complete funnel event taxonomy, not another analytics dependency. |
| Reminder field without delivery engine | `Profile.reminderTime` and profile migration | The field is present, but onboarding does not currently ask for it and no notification scheduler/orchestrator was found in `flutter_app/lib`. |

### Important current-state conclusion

The app is not missing “personalization” as a slogan. It is missing a reliable **personalization contract**:

```text
learner profile
  + current evidence
  + next recommended action
  + chosen schedule
  + subscription state
  -> one content decision
  -> one reminder decision
  -> one paywall message
```

That contract should be implemented before adding many more questions or many more campaigns.

## 3. What makes people pay: evidence

### 3.1 Immediate value beats feature inventory

The strongest relevant case study found was ASL Bloom, a sign-language learning app with a similar outcome-oriented learning problem. Its published story says the original feature-led onboarding created a paywall drop-off. The redesign connected onboarding to the learner’s desired real-world outcome, added trust and social proof, set an achievable daily target, and reframed the paywall as a bridge to that outcome. The vendor-reported results were a 15% increase in trial conversion, 12% higher ARPU, 28% more users completing their first real-world communication goal, and 18% higher 30-day retention. This is a vendor case study, not an independent benchmark, but it is directly relevant to ParleSprint’s positioning.

Source: [RevenueCat / ASL Bloom case study](https://www.revenuecat.com/blog/growth/asl-bloom-applica-case-study)

Implementation meaning:

- Ask for the learner’s outcome, not only their preferred feature.
- Show the learner what their first useful French result will be.
- Make the first lesson produce that result.
- Put the subscription behind a specific continuation promise: more guided practice, saved progress, deeper feedback, and the next step in their route.

### 3.2 Personalized schedules and progress messaging are established lifecycle patterns

Busuu’s published Braze case study describes a personalized Study Plan using the target language, desired proficiency, available study times, selected schedule, and estimated completion dates. It sends reminders at the time the learner selected and adjusts messaging using progress and proficiency. The case study reports a 70% increase in direct opens for personalized push compared with other push, a 93% increase in open rate for weekly progress emails compared with other engagement emails, and a 126% increase in click-through rate for reactivation emails. These are vendor/customer-reported results, not a universal language-app benchmark.

Sources: [Braze / Busuu client story](https://www.braze.com/customers/busuu-client-story)

Implementation meaning:

- Ask when the learner wants to study.
- Send at their chosen local time, not at a global broadcast time.
- Skip the reminder if they already completed the planned action.
- Use the learner’s actual goal, level, recent activity, and progress in the message.
- Make weekly email a progress report, not a generic newsletter.

### 3.3 Subscription benchmarks: conversion and retention are different problems

RevenueCat’s 2026 report is based on more than 115,000 apps, more than $16 billion in revenue, and more than one billion transactions. It is an aggregated benchmark, not a forecast for ParleSprint.

The report says:

- Hard-paywall apps have higher early conversion than freemium in its dataset: 10.7% vs 2.1% download-to-paid by Day 35. The report also says year-one retention is nearly identical between the two models. This means a hard paywall can improve early monetization, but it does not automatically solve long-term value.
- 55% of cancellations for 3-day trials happen on Day 0. The first session is therefore a high-risk and high-value moment.
- Trials of 17+ days converted 42.5% trial-to-paid versus 25.5% for trials of four days or less in the report. Apps are nevertheless shortening trials, and nearly half use four days or less.
- AI apps generated 41% more revenue per payer but churned 30% faster in the report’s AI vs non-AI comparison.
- Education apps had a median D30 download-to-trial rate of about 6.5% in the category data. This is a broad Education bucket, not a professional French-learning benchmark.
- Broad Education pricing medians in the report were approximately $9.99 monthly and $44.99 yearly. These are reference points, not proof of our optimal price.

Sources: [RevenueCat State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps-2026-utilities), [RevenueCat 2026 trend summary](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026)

### 3.4 What the data does not prove

There is no credible universal fact that:

- a 3-day trial is always best;
- a 7-day trial is always too long;
- a 40% discount after closing a paywall always converts well;
- an annual plan always produces the best retention;
- a daily push notification always improves retention;
- showing a paywall after exactly three lessons is optimal;
- a specific churn rate is “best” for this app.

Those are testable product hypotheses. The correct answer for ParleSprint must come from randomized experiments and cohort analysis because the result depends on traffic source, learner goal, perceived outcome, price, trial configuration, onboarding quality, and whether the first lesson creates a real win.

## 4. Product positioning for serious learners

ParleSprint should not position itself as “another Duolingo.” The paid audience is better described as:

> Adults who need a structured route from their current French level to a concrete real-world outcome, with practice that adapts to their time, goals, and mistakes.

The primary product promise should be outcome-based:

- Everyday French: “Handle the next real conversation with more confidence.”
- TEF / TCF Canada: “Build a focused route toward your exam level.”
- Travel: “Practise the situations you will actually face.”
- Professional French: “Prepare for the conversations, messages, and meetings your work requires.”

The app can still teach A1 through B2, but level is the calibration layer, not the headline benefit. The headline benefit is what the learner can do next.

## 5. Onboarding specification

### 5.1 Questions to ask

Keep the minimum required questions short and useful:

1. **Outcome:** Why are you learning French?
   - Everyday conversations
   - TEF / TCF Canada
   - Travel
   - Work or professional communication
   - Another specific situation
2. **Current level:** A1, A2, B1, B2, or “I’m not sure.”
3. **Time per session:** 5, 10, 15, or 20 minutes.
4. **Preferred study days:** every day, weekdays, weekends, or selected days.
5. **Preferred reminder time:** local time picker, with a skip option.
6. **Priority skills:** speaking, roleplay, listening, vocabulary, grammar, reading, writing, review.
7. **Tutor preference:** keep the existing tutor preview because voice fit is a meaningful personalization choice.

Do not ask for data that does not change a content, schedule, or paywall decision. Every question must map to one of:

```text
profile field -> planner input
profile field -> notification input
profile field -> paywall copy/input
profile field -> analytics segment
```

### 5.2 What onboarding must show before the first lesson

After the questions, show a concise personal plan:

```text
Your ParleSprint route

Goal: Everyday conversations
Starting point: A2
Practice rhythm: 10 minutes, weekdays, 7:30 PM
First milestone: Handle a short café or introduction conversation
This week: vocabulary -> listening -> speaking -> review
Tutor: Marie
```

The learner should be able to edit the plan. The plan is not a decorative summary; it is the contract that later powers content, reminders, and progress email.

### 5.3 First-session sequence

The first session should be a complete, short learning loop:

1. One useful situation tied to the chosen goal.
2. Small vocabulary set appropriate to level.
3. One listening or pronunciation moment.
4. One guided speaking attempt.
5. One short correction with an explanation appropriate to level.
6. One “you can now…” result.
7. A visible next lesson and review plan.

The first session should not be a generic feature tour. It should create evidence that ParleSprint understands the learner and can help them do something useful.

### 5.4 Level-specific content rules

Use the existing A1/A2/B1/B2 catalog and planner, with these rules:

| Level | Content contract | Feedback contract |
| --- | --- | --- |
| A1 | Concrete daily situations, short sentences, high English scaffolding, pronunciation foundations when needed | One correction at a time, plain English explanation, immediate repeat attempt |
| A2 | Familiar situations with simple past/future and more independent production | Correct the most useful pattern, then reuse it in a second example |
| B1 | Connected conversation, practical narration, more French-led instruction | Focus on transfer, natural phrasing, and one high-value correction |
| B2 | French-led and immersion-leaning, richer discussion, professional or abstract situations | Focus on nuance, precision, register, and spontaneous transfer |

The current `SpeakLanguageProfile` already expresses the scaffolding direction. The next step is to make the planner and generated content consume the same profile rather than letting each screen infer difficulty separately.

## 6. Personalized pathway rules

### 6.1 Recommendation priority

The next lesson should be selected by this priority order:

1. Due SRS review that is important to the learner’s current goal.
2. A skill the learner selected as a priority and has not practised recently.
3. A competency with weak evidence or repeated mistakes.
4. The next item in the learner’s level route.
5. A low-friction fallback lesson if data is missing.

This preserves structure while making the route feel personal.

### 6.2 Goal-to-content mapping

| Goal | First route emphasis | Premium proof moment |
| --- | --- | --- |
| Everyday | speaking, roleplay, listening, vocabulary | successfully complete a realistic short conversation |
| TEF / TCF Canada | vocabulary, grammar, listening, writing, then speaking | produce an exam-calibrated answer and receive feedback |
| Travel | roleplay, listening, vocabulary, speaking | handle a practical travel scene |
| Work | roleplay, writing, listening, speaking | complete a workplace message or meeting exchange |

The goal should influence lesson order, scenario selection, feedback framing, paywall copy, notification copy, and weekly recap.

### 6.3 Content-personalization inputs

The planner should be able to consume:

- goal;
- CEFR level;
- session length;
- preferred days and time;
- priority skills;
- tutor/persona;
- recent completed content keys;
- recent sessions and summaries;
- SRS due items and hard words;
- mistake tags;
- writing scores;
- speaking duration and utterance count;
- current competency states;
- subscription/trial status.

Do not generate a new lesson merely because personalization exists. Generate or select a lesson when the learner’s current evidence indicates a meaningful next step.

## 7. Paywall and subscription specification

### 7.1 Paywall timing to test

Run at least two controlled variants:

- **Variant A, post-aha:** after the first complete personalized lesson and feedback recap.
- **Variant B, early plan:** after the personalized plan preview, before the first full lesson, while preserving a meaningful free first action.

Do not infer the winner from trial starts alone. The primary metric is Day-35 download-to-paid, with 30-day activation and refund/cancellation guardrails.

The existing paywall can be reframed as:

```text
You completed: [specific outcome]

Your next step is: [next lesson/review]

Premium keeps your route moving with:
- personalized lessons at [level]
- feedback based on your recent speaking/writing
- saved progress and review
- practice at your chosen time

[Annual plan] [Monthly plan]
Start your [trial length]-day trial
```

### 7.2 Pricing presentation

The broad Education median in RevenueCat’s 2026 category data is approximately $9.99 monthly and $44.99 yearly. A proposed $8.99 monthly / $72 yearly structure would be near the monthly median but materially above that broad annual median. The higher annual price may still be justified if the app credibly delivers professional-level outcomes, but the benchmark alone does not justify it.

Always show:

- total annual price;
- billing frequency;
- monthly equivalent only as a secondary comparison;
- trial duration and exact conversion date;
- cancellation and restore information;
- Terms of Use and Privacy links;
- the selected plan clearly.

Do not use a fake crossed-out price, hidden renewal terms, or a discount that is not actually available.

### 7.3 Trial decision

Test 3-day and 7-day introductory trials against the same onboarding and paywall. RevenueCat’s data says short trials convert less well in aggregate than 17+ day trials, but 3-day trials are common and can work when the first session is strong. It also says 55% of 3-day trial cancellations happen on Day 0, so a 3-day trial requires an excellent first session and immediate follow-up.

Required experiment metrics:

- trial start rate;
- trial Day-0 activation;
- first lesson completion;
- first meaningful outcome completion;
- trial-to-paid;
- Day-7 and Day-30 retention;
- refund rate;
- cancellation reason;
- revenue per install;
- realized value after the first billing cycle.

Choose the trial by revenue and retained learning value, not by trial-to-paid percentage alone.

### 7.4 Closing the paywall and discounts

There is no reliable public benchmark proving that a 40% discount after closing a paywall is universally effective. The correct first implementation is:

1. Record paywall shown, plan viewed, close, trial start, purchase, and restore.
2. Run a control with no discount.
3. Run an offer variant only if the offer is a real Apple-supported product/offer state and its renewal terms are explicit.
4. Compare net revenue, retained subscribers, refunds, and support issues.

On Apple, use official offer-code, promotional-offer, or win-back mechanisms for eligible users. Do not invent a hidden pricing state in the UI that does not correspond to the App Store product/offer configuration. See Apple’s [subscription offer-code documentation](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/), [promotional offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions), and [win-back offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-win-back-offers/).

The best initial use of discounts is likely targeted recovery:

- a learner who reached the paywall, understood the value, and dismissed;
- a previously paid learner who lapsed;
- a learner who cancelled a trial but returned to a high-value feature.

Do not train every new user to close the paywall in expectation of a cheaper price.

## 8. Notification and email lifecycle

### 8.1 Permission principle

Ask for notification permission after explaining the benefit and after the learner chooses a study time. Apple’s notification guidance recommends requesting authorization in context; the system prompt only appears the first time. The in-app explanation should say exactly what the learner will receive and how often.

Source: [Apple asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking_permission_to_use_notifications)

### 8.2 Daily reminder rules

The notification engine must:

- use the learner’s local timezone;
- send at the learner’s selected time and selected days;
- deep-link directly to the next action;
- skip if the learner already completed the planned action;
- avoid more than one learning reminder per day unless the learner explicitly requests more;
- stop or reduce reminders after unsubscribe, account deletion, or notification denial;
- avoid shame, streak threats, or fake urgency;
- rotate copy using actual goal, level, due review, and recent progress.

Push notifications should be event-aware, not just timer-aware.

### 8.3 Evidence-aligned first-week sequence

OneSignal’s current mobile lifecycle guidance recommends a Day 1 value-led message, a Day 1 email, one useful nudge per day, behavior-based exits, a first-week recap, and direct deep links. This is an implementation pattern, not a measured ParleSprint result.

| Timing | Channel | Trigger and message job |
| --- | --- | --- |
| After first session + 4 hours | Email | Thank the learner, recap the first win, confirm the chosen study time, explain what messages they will receive. |
| Next app open | In-app message | Ask for notification permission and confirm the plan. Do not show this after permission is already granted. |
| Day 1 at chosen time | Push | Deep-link to the next useful action, not the home screen. |
| Day 2 | Push | One quick win, such as a 60-second review, only if no meaningful practice occurred. |
| Day 3 | In-app or push | Explain one underused feature, such as saved feedback, roleplay, or review. |
| Days 4–6 | Push | Goal-specific use case or due-review reminder. Suppress after practice. |
| Day 7 | Email | Personal first-week recap: minutes, sessions, skills, words, hard items, and next milestone. |
| Trial start | In-app/email | Explain what is included and show the next outcome. Do not wait until expiry to communicate value. |
| Trial end minus 1 day or the equivalent pre-expiry point | Email/push | Recap actual value received and explain the next billing state clearly. |
| Inactive 3 days | Push | Resume the unfinished route with one low-friction action. |
| Inactive 7 days | Email | Show what was learned, what is due, and a one-click return path. |
| Lapsed subscriber | Email/push | Win-back based on the last goal and last successful feature; use official offers only when configured and eligible. |

For a 3-day trial, the schedule must be compressed:

- Day 0: first lesson, immediate recap, paywall, and permission context;
- Day 1: personalized reminder and visible next lesson;
- Day 2: value recap plus clear trial-ending information;
- pre-expiry: exact renewal explanation and a direct return to the plan.

### 8.4 Notification copy examples

These are templates, not fixed copy:

- Everyday: “Your next French step is ready: practise the café conversation you started yesterday.”
- TEF/TCF: “Your 10-minute TEF route is ready: review the connectors you missed, then try one timed response.”
- Travel: “One useful travel scene today: ask for directions, then hear the natural reply.”
- A1: “A small French step is ready: say three new phrases with [tutor].”
- B2: “Your next challenge is ready: make this idea sound more natural in French.”
- Review: “Two phrases are due for review. Bring them back before they fade.”
- Return after inactivity: “Your route is still here. Resume with the next 3-minute practice.”

Avoid:

- “Your streak is dying”;
- “You are falling behind”;
- generic “Come back!”;
- sending a reminder after the learner already completed the lesson;
- repeatedly selling before delivering the promised learning value.

### 8.5 Email data contract

The weekly progress email should be generated from persisted facts:

- sessions completed;
- practice minutes;
- skills touched;
- words reviewed;
- hard words due next;
- writing score or improvement where available;
- speaking time and utterances;
- current level and goal;
- next recommended lesson;
- subscription/trial state.

The email must not claim progress the learner did not make. If there is no activity, use a truthful “resume your route” message rather than a fabricated recap.

Reminder research is not uniformly positive. A peer-reviewed study in *npj Science of Learning* describes smartphone-based reminders as potentially double-edged: reminders can support repetition, but poorly designed reminders can interfere with habit formation. Notification quality and suppression logic matter more than notification volume.

Source: [npj Science of Learning reminder study](https://www.nature.com/articles/s41539-024-00253-7)

## 9. Required data model

The existing `Profile` should be extended deliberately rather than adding unrelated fields over time.

### Learner profile

```text
goal
level
session_length
interests / priority_skills
preferred_days
reminder_time_local
timezone
tutor_id
notification_permission_state
email_marketing_consent
onboarding_version
plan_version
```

### Learning state

```text
current_recommendation_id
recommendation_reason
next_milestone
last_aha_event_at
last_meaningful_session_at
last_summary_at
due_review_count
top_mistake_tags
```

### Monetization state

```text
paywall_variant
paywall_first_seen_at
paywall_last_dismissed_at
trial_started_at
trial_end_at
subscription_product_id
subscription_status
offer_id_if_any
offer_eligibility_source
```

### Campaign state

```text
acquisition_source
campaign_id
custom_product_page_id
last_notification_sent_at
last_notification_reason
last_notification_opened_at
notification_suppressed_until
```

Do not put all of this into one opaque JSON blob. Profile, learning state, subscription state, and campaign delivery state have different ownership and sync rules. Start with the smallest fields needed for the first loop, but define names that can survive future experiments.

## 10. Analytics event taxonomy

Every event must include common properties where known:

```text
app_version
onboarding_version
paywall_variant
trial_variant
goal
level
session_length
has_reminder_time
notification_permission
acquisition_source
```

### Onboarding events

```text
onboarding_started
onboarding_question_answered
onboarding_plan_viewed
onboarding_plan_edited
onboarding_completed
notification_time_selected
notification_permission_prompted
notification_permission_granted
notification_permission_denied
```

### Learning events

```text
first_lesson_started
first_lesson_completed
aha_outcome_completed
lesson_feedback_viewed
recommendation_shown
recommendation_started
recommendation_completed
review_due_shown
review_completed
daily_summary_viewed
```

### Monetization events

```text
paywall_shown
paywall_plan_selected
paywall_closed
trial_started
trial_cancelled
purchase_started
subscription_purchased
purchase_failed
purchase_restored
offer_shown
offer_redeemed
subscription_expiring_soon
subscription_cancelled
subscription_renewed
subscription_lapsed
```

### Messaging events

```text
push_scheduled
push_suppressed
push_sent
push_opened
email_sent
email_opened
email_clicked
deep_link_opened
```

The funnel should be cohortable by goal, level, reminder selection, trial variant, paywall variant, and acquisition source. If the event does not support a product decision, do not add it yet.

## 11. Experiment plan

Run one major experiment at a time until there is enough traffic for interaction analysis.

### Experiment 1: first-value timing

- A: personalized lesson, then paywall;
- B: personalized plan, then paywall, then free first action;
- primary: Day-35 download-to-paid;
- guards: first lesson completion, Day-7 retention, refund rate.

### Experiment 2: trial length

- A: 3 days;
- B: 7 days;
- primary: revenue per install at Day 35 and Day 90;
- guards: first-session completion, cancellation day, renewal, support complaints.

### Experiment 3: annual framing

- A: annual-first with total annual price and monthly equivalent;
- B: monthly-first with annual option;
- primary: annual mix and Day-35 paid conversion;
- guards: refund, early cancellation, first renewal.

### Experiment 4: post-dismiss offer

- A: no offer;
- B: Apple-configured targeted offer;
- primary: net retained revenue at 30/90 days;
- guards: discount cannibalization and repeated-dismiss behavior.

### Experiment 5: reminder timing

- A: learner-selected time;
- B: a default time window;
- primary: second-session completion and Day-7 retention;
- guards: notification disablement and unsubscribe rate.

### Minimum decision rule

Do not declare a winner from:

- paywall click-through alone;
- trial starts alone;
- one viral post;
- a one-week revenue spike;
- a tiny cohort;
- an improvement that increases purchases but worsens first renewal or refunds.

## 12. Retention and churn interpretation

Churn is not one number. Track:

- trial cancellation;
- first paid-cycle cancellation;
- monthly renewal;
- annual renewal;
- involuntary billing failure;
- voluntary cancellation reason;
- refund;
- reactivation;
- active usage before renewal.

RevenueCat defines retention differently from sequential renewal and warns that these metrics should not be conflated. Its 2026 report shows that short-term conversion, year-one retention, and renewal behavior answer different questions.

For a goal-oriented language app, the product should reduce churn by increasing delivered value before the next billing decision:

1. show the learner what they can now do;
2. keep the next step obvious;
3. make practice fit their actual schedule;
4. make mistakes and improvement visible;
5. bring due material back at the right time;
6. recover gracefully after missed days;
7. communicate billing and cancellation clearly.

The target is not “high churn.” The target is a high share of subscribers who keep receiving and using value. A subscriber who cancels because they completed a short goal is not equivalent to a subscriber who cancels because the app never became relevant.

## 13. ASO and distribution

### 13.1 Store positioning

Use outcome and audience language, not only “AI French tutor.” Candidate search themes should be validated with actual keyword data:

- French speaking practice;
- French conversation practice;
- French for work;
- French pronunciation;
- TEF Canada preparation;
- TCF Canada preparation;
- French A1 / A2 / B1 / B2;
- French roleplay;
- French writing feedback;
- French listening practice.

Do not use competitor names as keywords or imply affiliation.

### 13.2 Custom product pages

Apple supports custom product pages with unique screenshots, promotional text, keywords, shareable URLs, and deep links on supported OS versions. Use separate pages for separate high-intent audiences, for example:

1. TEF / TCF Canada;
2. professional French;
3. French speaking and roleplay;
4. A1 to B2 structured pathway;
5. travel and everyday conversations.

Each page must match the acquisition promise, onboarding goal, first lesson, and paywall message. Do not send a TEF user to a generic “learn French” page.

Sources: [Apple custom product pages](https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions), [Apple App Analytics](https://developer.apple.com/app-store-connect/analytics/)

### 13.3 Distribution channels

Prioritize channels that can demonstrate the outcome:

- short videos showing a real roleplay before/after;
- TEF/TCF study communities and newcomer/professional communities;
- search content answering specific French problems;
- creator partnerships with French teachers and exam coaches;
- referral moments after a learner completes a real-world goal;
- landing pages that preserve the acquisition goal into app onboarding.

Public Instagram indexing did not provide reliable audited subscription benchmarks. Public LinkedIn, Reddit, and Indie Hackers posts are useful for ideas but should remain anecdotal evidence. Use them to generate experiments, not to set product policy.

## 14. Apple review and subscription constraints

Apple’s App Review Guidelines require auto-renewable subscriptions to provide ongoing value and the subscription period to last at least seven days. The app must present clear subscription information and must not use misleading pricing or bait-and-switch behavior.

Important operational rules:

- A three-day introductory trial is different from a three-day subscription period. The subscription itself must satisfy Apple’s rules.
- The first auto-renewable subscription product is submitted with a new app version; additional subscriptions can be submitted without a new version after the first is approved, subject to App Store Connect state and review.
- If a build is rejected, reply in App Store Connect with the changes and submit a new build when code/binary changes are required. Do not treat a review reply as a substitute for resubmission when subscription metadata or behavior changed.
- Keep trial language, renewal date, pricing, terms, and restore behavior visible and truthful.

Sources: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Apple auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/), [Apple offer codes](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/)

## 15. Implementation sequence

### Phase 1: profile and measurement foundation

1. Add preferred study days, timezone, notification permission state, onboarding version, and priority skills to the learner profile.
2. Add a real reminder-time question after session length.
3. Show the editable personal plan before the first lesson.
4. Add the event taxonomy above to existing `ProductAnalytics` calls.
5. Add paywall shown/closed/selected/started events before changing copy.

### Phase 2: personalized first-value loop

1. Create a single `LearnerPlan`/recommendation contract consumed by dashboard, pathway, lesson launch, summary, and notifications.
2. Select the first lesson by goal + level + priority skill.
3. Ensure the first lesson ends with a specific outcome and feedback.
4. Show the next action and the first daily/weekly milestone.
5. Show the paywall only in an explicitly measured context.

### Phase 3: notifications

1. Add a platform notification service with permission request and local scheduling.
2. Schedule one reminder at the learner’s chosen local time.
3. Cancel or suppress it after meaningful practice.
4. Deep-link to the recommended lesson/review.
5. Add first-week, inactive, and trial lifecycle states.
6. Add email only after the in-app facts are reliable enough to populate a truthful recap.

### Phase 4: subscription experiments

1. Configure 3-day and 7-day trial variants in a controlled way.
2. Add annual/monthly framing variants.
3. Add Apple-supported targeted offer state only after the control funnel is measurable.
4. Compare revenue per install, paid conversion, renewal, refund, and retained usage.

### Phase 5: distribution and ASO

1. Create custom product pages by audience/goal.
2. Match page promise to onboarding goal and first lesson.
3. Use App Analytics to compare page-to-install and install-to-paid by source.
4. Produce outcome demonstrations and community-specific landing pages.

## 16. First coding slice for the next task

The first implementation task should be narrow and testable:

```text
Add preferred study days, a reminder-time picker, timezone, and onboarding-version
to Profile; show the editable personal plan; persist/sync it; emit onboarding and
notification-permission events; do not yet send recurring notifications.
```

Why this is first:

- It turns an existing nullable field into an actual user choice.
- It creates the data contract required by content, push, and email.
- It improves perceived personalization before asking for payment.
- It is reversible and easy to test.
- It avoids building a notification engine on top of missing preferences.

After that slice is verified, the next task should wire the first recommendation to the profile and current evidence. Only then should we implement scheduling and paywall experiments.

## 17. Sources and evidence ledger

### Measured or platform sources

- [RevenueCat State of Subscription Apps 2026](https://www.revenuecat.com/state-of-subscription-apps-2026-utilities)
- [RevenueCat 2026 trend summary](https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple asking permission to use notifications](https://developer.apple.com/documentation/usernotifications/asking_permission_to_use_notifications)
- [Apple custom product pages](https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions)
- [Apple subscription offer codes](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-subscription-offer-codes/)
- [Apple promotional offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-promotional-offers-for-auto-renewable-subscriptions)
- [Apple win-back offers](https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-win-back-offers/)
- [OneSignal mobile-first lifecycle journeys](https://documentation.onesignal.com/docs/en/mobile-first-journeys)
- [npj Science of Learning study-reminder research](https://www.nature.com/articles/s41539-024-00253-7)

### Named case studies

- [RevenueCat / ASL Bloom onboarding and paywall case study](https://www.revenuecat.com/blog/growth/asl-bloom-applica-case-study)
- [Braze / Busuu personalized study-plan case study](https://www.braze.com/customers/busuu-client-story)

### Public anecdotes, not benchmarks

- [Indie Hackers onboarding/paywall redesign report](https://www.indiehackers.com/post/i-redesigned-the-onboarding-and-paywall-in-my-app-and-in-a-single-week-i-earned-more-than-in-the-previous-six-months-combined-9bdd175e03)
- [Reddit trial-conversion report](https://www.reddit.com/r/GetStartups/comments/1upp2cm/fixed_my_trial_conversion_21_44_and_just_passed/)
- [Reddit post-cancel discount anecdote](https://www.reddit.com/r/iOSProgramming/comments/1jmunv/personal-experience-on-increasing-revenue/)

Public posts are included because they can reveal current operator hypotheses and language patterns. They must never be treated as causal evidence without a controlled ParleSprint experiment.

