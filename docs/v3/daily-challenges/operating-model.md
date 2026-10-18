# Daily TCF challenge: design and delivery plan

## What the four reference apps show

I reviewed the local screenshot sets under `references/extracted/` and the
earlier redesign direction in the completed “Sim fix” conversation. The four
apps are using related but different habits:

| App | Evidence in this repo | Useful pattern for ParleSprint |
|---|---|---|
| Babbel | May 2024 screenshots 106 and 111: the Home screen places the current lesson beside “Time to review” and “Daily vocab”. | Keep the path and review together. Show why a short review is due, not just an isolated game. |
| Memrise | Jan 2022 screenshots 126 and 140: “TO DO TODAY”, a daily goal, words reviewed, new words, learning time, and “READY FOR REVIEW”. | Make the day’s plan and actual learning evidence easy to scan. Do not turn minutes or words into a score. |
| Speak | Apr 2026 screenshots 230 to 237: challenges are a separate Challenge area with active, upcoming, and completed monthly lesson goals; course practice and roleplay are other routes. | Give longer events their own space. Keep the daily action smaller and useful on Home. |
| Vocabulary | May 2026 screenshots 86 and 102: Practice has three distinct short modes, Sprint, Rush, and Perfection. | Make the task type clear before starting. For TCF, label the skill and format instead of adding speed, lives, or perfection pressure. |

The earlier challenge-first wireframe is at [wireframes.html](wireframes.html).
The approved app home now follows the supplied visual reference: greeting,
level and exam date, weekly activity, an illustrated course continuation,
four practice tiles, and a wide TCF path card. The course remains the single
primary action; Daily challenge is one of the secondary tiles. The clinic sample
is still illustrative and requires human TCF review before production.

## Additional learning-app research

Duolingo describes ordering its daily quests from an easy first action to
harder tasks, while favoring activities that move a learner along the course
path. That supports one approachable first step and a strong link back to the
authored path, without copying its reward economy.
[Duolingo's product note](https://blog.duolingo.com/time-spent-learning-well/)

Quizlet describes retrieval practice, immediate feedback, and a progression
from supported multiple choice toward written recall. The challenge can use
that sequence when it suits the learner's level: recognize, retrieve, then
produce a short answer.
[Quizlet's learning design overview](https://quizlet.com/features/how-quizlet-works)

Khan Academy says its weekly streak is earned by bringing a skill to
proficiency, so the signal is tied to learning evidence rather than raw time.
For ParleSprint, record objective evidence and delayed retention; do not treat
minutes practiced as mastery.
[Khan Academy's streak design](https://blog.khanacademy.org/get-motivated-to-learn-with-khan-academys-new-streaks-and-levels-features/)

## Fit with the app as it exists now

- The approved Learn home now has a Bonjour greeting, level and exam-date
  controls, a seven-day activity strip, an illustrated course lesson card, a
  two-by-two practice grid, and a full-width TCF path card. Course continuation
  is the single primary action. The home has no Course/Practice segment.
- Daily challenge, Marie, review, Stories, and the TCF path are directly
  reachable from the home. Stories opens the fuller Practice destination, which
  retains the existing practice library and story controls. Daily challenge
  uses the V3 lesson renderer and does not move course-path progress.
- Streak Calendar and French Fingerprint have V3 presentations and links in
  Settings. Streaks still count completed learning sessions. The fingerprint
  still derives its word map from the learner’s real recall, speaking, and
  writing evidence.
- The app already initializes Supabase and syncs user-owned progress. It also
  has `review_plans`, `review_plan_targets`, and `review_attempts` for the
  existing review/warm-up flows. Those are useful precedent and reusable
  learning evidence; a published daily challenge needs its own content version
  and assignment identity.
- The daily challenge migration and Edge Function are under
  `flutter_app/supabase/`, beside the app’s existing Supabase functions and
  migrations.
- Keep challenge completion separate from `V3Progress`. A challenge draws
  from the path or SRS queue, but completing a short daily task must not move or
  rewind the course frontier.

## What Supabase calls the pieces

- **Postgres database:** relational data in tables. A *row* is one record in a
  table; it is not a separate Supabase product. Store challenge metadata,
  authored text, typed exercise JSON, dates, versions, and publishing state in
  table rows.
- **Supabase Storage:** files such as audio or optional illustrations. Store a
  bucket path and checksum on the challenge row; keep the content relationship
  and release metadata in Postgres.
- **Edge Function:** server endpoint for fetching today’s published package,
  recording an attempt, or checking an answer if answer keys should stay off a
  public read path.
- **Supabase Cron:** optional scheduler. It can validate or activate scheduled
  rows, invoke an Edge Function, and record job results. It is not required if
  the app can query a pre-published row by the learner’s date and level.

Suggested first schema:

```text
daily_challenge_versions
  id, content_key, revision, level_band, primary_skill, tcf_task_type,
  objective, source_lesson_ids, content_json, status, scheduled_at,
  available_from, available_until, created_at, approved_by

daily_challenge_attempts
  id, user_id, challenge_version_id, learner_local_date, status,
  current_step, started_at, completed_at, duration_seconds, result_summary

daily_challenge_step_events  (optional in v1)
  id, attempt_id, step_id, outcome, attempts_count, answered_at
```

Use an immutable challenge version for any attempt already started. Put only
published content on a public read policy; draft and scheduled content should
be visible only to staff. Put RLS on user attempts so each signed-in learner
can read or update only their own rows. Keep any service key inside a server
function, never in the shipped iOS app. Store recordings only when a stated
product need and privacy policy support that; the default should be to retain
the learning result, not raw voice audio.

## Publish without an App Store update

For daily copy, questions, choices, explanations, and audio that use the
already-built challenge screens, publish content data to Supabase. The app asks
for the signed-in learner’s challenge by level and local date. The Edge Function
returns only the active content and records an attempt; answer keys remain in a
private Postgres column. The app binary does not need to be resubmitted just
because tomorrow’s approved questions changed.

Apple’s App Review Guideline 2.5.2 prohibits downloading or executing code
that adds or changes app features. Keep the downloaded package as content data
rendered by the screens already in the reviewed app. A new interaction type,
new capability, or meaningful behavior change belongs in an App Store build and
review. Make new features and content accessible to review, and ensure the
metadata and in-app claims stay accurate. This is a boundary to design around,
not a guarantee that Apple will accept every content or policy change.

If you want an automatic daily switch, publish the next day’s approved row in
advance, then have the client request by learner-local date and level. Cron can
run a daily preflight or mark the scheduled batch live. A Cron job does not
push the new screen by itself: the app fetches it when opened/refreshed. Push
notifications are a separate opt-in delivery path.

## Staging and automation

1. Author one package per date/level under `content/tcf/daily_challenges/`.
   Include the skill, TCF objective, answer key, explanation, Canadian context,
   and source lesson IDs. The package is ordinary JSON data, not executable UI.
2. Run `python3 flutter_app/tool/daily_challenges.py validate <package>`.
   It checks fields and every supported V3 step shape. Review distractor
   quality, vocabulary suitability, and topic repetition with the TCF editor.
3. Add `reviewed_by` and `reviewed_at` only after a human has approved the
   package. Production publishing rejects packages without that review record
   and `review_status: "approved"`.
4. Publish first with `--environment staging`. This writes a `preview` row;
   the staging Edge Function serves it when
   `DAILY_CHALLENGE_INCLUDE_PREVIEW=true`. Production ignores preview rows.
5. After review, publish to production for its `available_on` date. The
   function selects the latest published revision for that level/date. Keep
   prior revisions for rollback and audit.

Example commands, run from the repository root:

```sh
python3 flutter_app/tool/daily_challenges.py validate \
  content/tcf/daily_challenges/a1_clinic_message.json
python3 flutter_app/tool/daily_challenges.py publish \
  content/tcf/daily_challenges/a1_clinic_message.json \
  --environment staging --available-on 2026-10-16
```

The publishing command reads the staging URL and service key from
`DAILY_CHALLENGE_STAGING_URL` and
`DAILY_CHALLENGE_STAGING_SERVICE_ROLE_KEY`. Production uses corresponding
`DAILY_CHALLENGE_PRODUCTION_*` variables. They are read by the local authoring
tool only; never add service-role credentials to Flutter assets, app config, or
source control. The `bundle` command is for local development previews and the
bundled clinic sample is gated to debug builds.

Once a separate staging project exists, the deployment sequence is:

```sh
cd flutter_app
supabase link --project-ref <staging-project-ref>
supabase db push --linked
supabase functions deploy daily-challenge --project-ref <staging-project-ref>
supabase secrets set DAILY_CHALLENGE_INCLUDE_PREVIEW=true \
  --project-ref <staging-project-ref>
```

Keep `verify_jwt` enabled (the default). The function also verifies the caller
and checks attempt ownership before saving any answer or progress.

**Staging is not connected yet.** The account currently shows an active
ParleSprint production project, but no separate staging project. The migration
and function have not been applied or deployed. Keep the current Supabase CLI
link pointed at production until a separate staging project/reference and its
credentials are available. Do not use the production project to preview drafts.

The 30-day calendar generated for 2026-10-19 through 2026-11-17 is under
`content/tcf/daily_challenges/schedule_2026-10-19/`. It contains one package
per day for A1, A2, B1, and B2, composed from existing authored course
questions. All 120 packages are `needs_human_review`; they are not bundled into
the app or eligible for production until a TCF editor reviews each package and
records reviewer metadata. Generate another calendar with
`python3 flutter_app/tool/plan_daily_challenges.py --start-date YYYY-MM-DD
--days 30`.

`.github/workflows/daily-tcf-challenges.yml` validates all challenge packages
on pull requests and pushes, publishes approved production packages daily, and
supports a manual staging or production dispatch. Configure separate GitHub
`staging` and `production` environments with `DAILY_CHALLENGE_<ENV>_URL` and
`DAILY_CHALLENGE_<ENV>_SERVICE_ROLE_KEY`. For a manual backend deployment, add
`SUPABASE_ACCESS_TOKEN` and `SUPABASE_PROJECT_REF` to that environment and
enable the backend deployment input. The scheduled job only publishes packages
with recorded human approval. Supabase credentials are never added to the app
or repository.

The app does not need Supabase Cron just to rotate daily content: pre-publish
rows with future `available_on` dates, and the app fetches the matching row when
opened. Cron can later run validation/expiry jobs. An app-open fetch will not
push an update to a learner who never opens the app; reminders or push are a
separate opt-in feature.

That gives you a genuinely daily release cadence without turning content
production into a daily App Store submission. Most batches can be prepared in
advance and switched on by schedule.

## TCF challenge design

Use a 3 to 6 minute micro-session with one obvious objective. A daily session
can combine one main TCF skill with one short bridge back to learning already
in the app:

- A main task in listening, reading, speaking, or writing, adapted to A1, A2,
  B1, or B2 and labelled as TCF-style practice.
- A short recall step from a completed lesson or due SRS word when it supports
  the objective.
- A useful explanation and a direct next step: review this phrase, continue
  the course, or try the related story.

Rotate the primary skill across the week so the Home card is not another
generic quiz. For speaking, use an authored prompt and the selected tutor. For
writing, label short beginner scaffolds honestly; only call it a full TCF task
when it meets that level’s actual task requirements. Avoid XP, coins, lives,
leaderboards, streak guilt, and promised exam scores.

## What to track

Track a small amount of evidence that helps learners and improves content:

- Whether the challenge was opened, resumed, or completed, and how far the
  learner got.
- Skill and task type, objective answer accuracy, first-try versus retry, and
  elapsed practice time.
- Which course lesson or SRS items were reused, so the same content is not
  over-assigned and later retention can be checked.
- A “report an issue” signal for unclear French, broken audio, or a wrong key.

Use those signals to compare completion and learning by level and skill, and
to find weak items. Do not use time or answer volume as a substitute for
mastery. Keep skill estimates separate from a daily challenge result and update
them only when enough validated evidence exists. Do not store voice recordings
by default.

## Implemented first slice

This branch contains the approved Learn home, challenge routing through the V3
lesson renderer, a debug-only clinic preview, a 30-day A1–B2 draft calendar,
the Postgres migration, the authenticated Edge Function, the GitHub workflow,
and the staging/production publishing tool. The remaining live setup is a
separate staging Supabase project, GitHub environment secrets, applying the
migration, deploying the function, and completing a signed-in staging answer
submission before production content is promoted.

## Official product and platform references

- [Duolingo on how its daily quests support learning time](https://blog.duolingo.com/time-spent-learning-well/)
- [Babbel vocabulary workout and spaced review](https://support.babbel.com/hc/en-gb/articles/205600228-Vocab-workout-Review)
- [Memrise streak and daily goal tracking](https://memrisebeta.zendesk.com/hc/en-us/articles/16898724195729-How-can-I-track-my-Streak)
- [Speak weekly leagues](https://help.speak.com/en/articles/12554257-what-are-leagues)
- [Quizlet retrieval practice, feedback, and staged question difficulty](https://quizlet.com/features/how-quizlet-works)
- [Apple App Review Guideline 2.5.2](https://developer.apple.com/app-store/review/guidelines/)
- [Supabase tables and RLS](https://supabase.com/docs/guides/database/tables) and [Supabase Cron](https://supabase.com/docs/guides/cron)
