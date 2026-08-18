# ParleSprint project context

Use this file as the canonical naming reference for every future task.

## Product names

- Production app: **ParleSprint**
- Staging app/environment: **ParleSprint Staging**
- Repository/workspace: `FrenchTutor`
- Flutter package name: `french_tutor`
- Supabase production project: the existing ParleSprint production project
- Supabase staging project: a separate project named **ParleSprint Staging**

Never call this product Pulsepin, PulsePin, FrenchTutor, or any other invented
brand name in user-facing explanations. `FrenchTutor` is only the repository
and package context.

## Product description

ParleSprint is a personalized French-learning app for serious learners,
including TEF/TCF candidates, professionals, people relocating, and learners
who want practical French. Its course content is dynamically generated from
the learner's onboarding profile, current CEFR level, goals, interests, and
progress.

## Engineering direction

- Personalized adaptive course content is the authoritative learner course
  path.
- Existing practice structures remain: vocabulary, grammar, reading,
  listening, writing, speaking, and roleplay.
- Supabase production data must not be changed casually from a laptop.
- Database changes belong in migration files and should be tested locally and
  in **ParleSprint Staging** before production deployment.
- Never invent replacement product, environment, or company names when the
  canonical name is already available here.
