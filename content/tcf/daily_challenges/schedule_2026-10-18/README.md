# Daily TCF challenge drafts: 2026-10-18 to 2026-10-24

This schedule has 7 dated packages per level (28 total) built from existing authored course questions. Every package is marked `needs_human_review`; none is approved or published. A TCF editor must review the content and record reviewer metadata before production. The validator and GitHub workflow check package shape and dates, while the Supabase Edge Function keeps answer keys private and records signed-in learner answers.

## Publishing this week (not done yet)

1. Read the 28 packages, then record your review: `python3 flutter_app/tool/daily_challenges.py approve content/tcf/daily_challenges/schedule_2026-10-18 --by "Your name"`.
2. Check the rows without sending anything: add `--dry-run` to the command below.
3. Publish: set `DAILY_CHALLENGE_PRODUCTION_URL` and `DAILY_CHALLENGE_PRODUCTION_SERVICE_ROLE_KEY`, then `python3 flutter_app/tool/daily_challenges.py publish-schedule content/tcf/daily_challenges/schedule_2026-10-18 --environment production --from-date 2026-10-18 --days 7`.
4. Make sure the `daily-challenge` Edge Function and the migration `20261016032622_daily_challenge_content_and_attempts` are deployed.
