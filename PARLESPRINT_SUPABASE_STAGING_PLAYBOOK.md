# ParleSprint Supabase staging and production playbook

This is the canonical reference for safely setting up staging, testing future
migrations, and protecting ParleSprint production.

## Current priority

1. Get ParleSprint approved in the App Store.
2. Acquire the first 5–10 paying customers.
3. Observe real storage, database, egress, and content usage.
4. Create staging before making further production schema changes from user
   feedback.
5. Route all future migrations through staging and CI/CD before production.

The current production Supabase project remains production. Do not wipe it,
rename it, or connect staging credentials to the production build.

## Canonical names

- Production app: **ParleSprint**
- Staging environment: **ParleSprint Staging**
- Repository/workspace: `FrenchTutor`
- Flutter package: `french_tutor`
- Production Supabase project: the existing ParleSprint project
- Staging Supabase project: a separate Free project named **ParleSprint Staging**

Do not invent unrelated product names. `FrenchTutor` is repository/package
context, not the product brand.

## Cheapest safe architecture

Use two Free Supabase projects and a local database:

```text
Local Supabase
      ↓
Pull-request tests
      ↓
ParleSprint Staging (Free)
      ↓
Manual QA and smoke tests
      ↓
ParleSprint production (current project)
```

Supabase CLI and GitHub deployment work on all plans. Supabase Branching for
per-pull-request preview environments requires Pro, so Branching is not needed
for the first staging setup.

References:

- [Supabase pricing](https://supabase.com/pricing)
- [Supabase deployment](https://supabase.com/docs/guides/deployment)
- [Supabase environment management](https://supabase.com/docs/guides/deployment/managing-environments)
- [Supabase migrations](https://supabase.com/docs/guides/deployment/database-migrations)

## Free-plan limits

The official pricing page currently lists:

- 50,000 monthly active users
- 500 MB database size
- 1 GB file storage
- 5 GB uncached egress
- 5 GB cached egress
- Shared CPU and 500 MB RAM
- Community support
- Up to two active Free projects
- Free projects may pause after inactivity

The 50,000 MAU limit is not the expected bottleneck for 4,000 customers.
Storage, database size, bandwidth, and workload shape matter more.

### File storage and images

Approximate capacity for 1 GB:

| Compressed image size | Approximate images |
|---:|---:|
| 10 KB | 100,000 |
| 25 KB | 40,000 |
| 50 KB | 20,000 |
| 100 KB | 10,000 |
| 250 KB | 4,000 |
| 1 MB | 1,000 |

At 4,000 users:

| Image pattern | 10 KB each | 25 KB each |
|---|---:|---:|
| 1 image per user | 40 MB | 100 MB |
| 5 images per user | 200 MB | 500 MB |
| 20 images per user | 800 MB | 2 GB |

ParleSprint should prefer one reusable cover per story, course set, or
content group—not a unique image for every lesson unless usage proves the
storage budget is safe.

### Database size and lessons

The 500 MB database limit stores profiles, adaptive plans, lesson records,
generated text, progress, SRS history, indexes, and metadata.

Very rough raw capacity:

| Average lesson record | Approximate raw rows in 500 MB |
|---:|---:|
| 3 KB | 166,000 |
| 5 KB | 100,000 |
| 10 KB | 50,000 |
| 25 KB | 20,000 |
| 50 KB | 10,000 |

Actual capacity is lower because other tables and indexes also consume space.
4,000 users × 20 sessions equals 80,000 session records. At 5 KB each, that
is already approximately 400 MB before profiles, progress, and indexes.
Keep adaptive specifications compact and avoid duplicating large JSON payloads.

### RAM

The 500 MB RAM value is runtime memory for the shared server environment. It is
not storage and does not directly equal a user count. Practical capacity
depends on queries, concurrency, connections, and response size.

### Egress

Egress is data sent from Supabase to users. Images, API responses, audio, and
other downloads consume it.

At 25 KB per image:

- 200,000 image downloads use approximately 5 GB.
- 4,000 users viewing 10 images each use approximately 1 GB.
- Audio and JSON traffic use additional bandwidth.

## Four-thousand-customer assessment

4,000 paying accounts are plausible on Free from an MAU perspective. The plan
does not automatically fail at 4,000 users.

The risk is the amount of content per user:

- 20 unique images per user can exceed 1 GB.
- 80,000 large lesson records can exceed 500 MB.
- Frequent image/audio downloads can exceed 5 GB egress.

The safe content model is:

- Store compact adaptive lesson specifications.
- Generate rich lesson assets only when needed.
- Store one compressed cover per content group where possible.
- Reuse covers instead of generating one per card.
- Measure actual usage after the first 5–10 customers.

## Image-storage policy

Generated card artwork must be compressed before Storage upload:

- JPEG output
- Approximately 384×576 maximum cover dimensions
- JPEG quality around 65–75
- Target approximately 10–120 KB per cover
- Never upload provider-sized raw bytes for a small card

Verify the optimizer with tests that check dimensions, JPEG validity, output
size, and acceptable visual quality on a device.

## Staging project setup

After the first 5–10 paying customers:

1. Create a new Free Supabase project named **ParleSprint Staging**.
2. Prefer the same region as production.
3. Create separate staging API keys, database credentials, Storage buckets,
   Auth settings, and Edge Function secrets.
4. Use fake seed users and fake lesson data. Never copy customer data into
   staging.
5. Create a staging app configuration/build flavor pointing only to staging.
6. Keep staging and production credentials in separate environment variables.
7. Confirm a staging build cannot read or write production rows.

Never share these between environments:

- Supabase URL
- publishable/anon key
- service-role key
- database password
- Storage credentials
- Auth redirect configuration
- Edge Function secrets

Never put a service-role key in the Flutter app.

## First staging migration: baseline carefully

The production project has already received adaptive schema changes during
development. Before automating future migrations, reconcile local files with
production history.

1. Inspect local migration files.
2. Run `supabase migration list` against production.
3. Compare local and production migration histories.
4. Pull or generate a clean baseline if production contains changes missing
   from local files.
5. Never run `supabase db reset` against production.
6. Create staging only after the baseline is understood.
7. Apply the complete migration history to staging.
8. Confirm staging schema, RLS, grants, Storage policies, and Auth settings.

Do not resolve migration drift by guessing, deleting production rows, or
manually editing migration history.

## Migration workflow

### Local

- Create a migration file.
- Run it from an empty local database.
- Run Flutter tests and analyzer.
- Check RLS and grants.
- Test offline sync and reinstall/restore behavior.

Typical CLI commands, after checking the installed CLI help/version:

```bash
supabase start
supabase db reset
supabase migration list
```

### Staging

- Deploy the migration to ParleSprint Staging.
- Test sign-up and login.
- Test adaptive plan creation and lesson sync.
- Test reinstall/restore.
- Test Storage upload/download.
- Test subscription entitlement handling.
- Test both a new user and an existing user.

### Production

- Require manual approval.
- Confirm a recent backup/export exists.
- Apply the exact migration that passed staging.
- Monitor errors, database size, Storage size, and egress.
- Do not apply a different SQL version manually in the Dashboard.

## Migration design rules

Use expand-and-contract migrations:

1. Add new nullable columns or new tables.
2. Deploy code supporting old and new schema.
3. Backfill gradually if needed.
4. Switch reads and writes to the new structure.
5. Observe production.
6. Remove old columns only in a later migration.

Avoid combining these in one release:

- Rename and delete of the same column.
- Large table rewrites.
- Destructive cleanup.
- RLS policy changes and application behavior changes without testing.
- Breaking changes while older app versions remain installed.

Migration files are not an automatic rollback system. Prefer a tested
forward-fix and a reversible rollout.

## CI/CD plan

Eventually add:

```text
.github/workflows/
  pull-request.yml       # local reset, tests, analyzer, schema checks
  deploy-staging.yml     # deploy develop to ParleSprint Staging
  deploy-production.yml  # protected manual production deployment
```

### Pull-request checks

- Install a pinned Supabase CLI version.
- Start the local Supabase stack.
- Run `supabase db reset`.
- Run migration/schema tests.
- Run Flutter tests.
- Run `flutter analyze`.
- Fail on any migration or test failure.

### Staging deployment

- Trigger after merge to `develop` or manually.
- Link the CLI to the staging project.
- Deploy pending migrations.
- Run staging smoke tests.
- Publish a staging app build for manual review.

### Production deployment

- Trigger only after reviewed merge to `main`.
- Use a protected GitHub environment requiring approval.
- Link the CLI to production.
- Deploy only migrations already verified in staging.
- Record the migration version and result.

Production secrets belong in GitHub Secrets or another secret manager, never in
source code.

## When to upgrade

Free is acceptable for production if we accept its limitations and monitor
usage. There is no magic user-count threshold.

Consider Pro when:

- Paying users require reliable daily backups.
- Storage, database, or egress reaches approximately 60–70%.
- We need continuously running production with no inactivity-pause risk.
- We need built-in Supabase Branching.
- We need longer retention or support.

Pro is currently listed at $25/month, with the first project included and
additional projects starting around $10/month. Verify pricing before purchase:

- [Supabase pricing](https://supabase.com/pricing)
- [Supabase billing FAQ](https://supabase.com/docs/guides/platform/billing-faq)
- [Supabase compute usage](https://supabase.com/docs/guides/platform/manage-your-usage/compute)

## Launch checklist

Before App Store submission:

- Production build uses production Supabase configuration.
- Staging configuration is not bundled into production.
- No service-role key is in the app.
- Adaptive sync works for a new account.
- Adaptive sync restores after reinstall.
- Generated content payloads are compact.
- Image upload uses compressed cover bytes.
- Apple sandbox subscription entitlement behavior is tested.

After the first 5–10 paying customers:

- Create ParleSprint Staging.
- Reconcile migration history.
- Apply the complete migration set to staging.
- Add synthetic seed data.
- Add CI migration checks.
- Test the next user-feedback migration in staging before production.
- Record actual Storage, database, and egress usage.

## Final rule

Production is the customer environment. Staging is the experiment environment.
No migration, RLS change, Storage policy change, or destructive cleanup should
move directly into production without passing the staging checklist.
