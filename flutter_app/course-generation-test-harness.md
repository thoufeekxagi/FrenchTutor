# Course generation test harness

This is a development-only verification lane for the adaptive Course. It is
not a second lesson engine, database, or provider pipeline. It reuses the same
client gate, Supabase sync, `prepare-course-lesson` edge function, artifact
codec, local database, and cloud mirrors as production.

## Current target

Speaking has completed its verification pass. The debug trace and saved Course
rows showed five generated Speaking lessons (sequences 11–15), each with one
provider attempt, `ready` content, no generation error, and no hidden retry.
A sixth Speaking row was left as the next planned row. Live Speaking used one
socket per lesson, compact screen-only context, and the existing local matcher.

The next debug lane is Vocabulary. The harness default is now `vocabulary`;
old generated Speaking rows are preserved but no longer block or appear in
this lane. The authored Vocabulary lesson in Unit 2 remains the gate and must
be completed before the first generated Vocabulary row can be appended.

It preserves the authored route:

- Sequences 1–5: authored Unit 1 foundation.
- Sequences 6–10: authored Unit 2 (`vocabulary`, `speaking`, `reading`,
  `listening`, `writing`).
- Sequence 11 onward: personalized generated lessons, with the unit label
  derived from the sequence in five-session blocks.

In harness mode, completion of the selected Unit 2 activity is the gate for
sequence 11. Only one personalized row is appended at a time. The next row is
not appended until the current selected-skill row is completed. The serial
gate is filtered by the selected skill, so a stale queued/planned Speaking row
cannot block the Vocabulary lane.

The harness does not delete or rewrite a ready/completed lesson. It does not
run a background lookahead, retry a failed provider call, or create rows for
the other skills. Existing non-target personalized rows are simply hidden from
the debug roadmap so the current test lane stays unambiguous.

## Switching the lane

Debug builds activate the harness automatically (`kDebugMode` remains a hard
guard). The selected skill can be supplied when the build tool preserves Dart
defines:

```text
--dart-define=PARLESPRINT_COURSE_HARNESS_SKILL=vocabulary
```

Supported values are `speaking`, `vocabulary`, `reading`, `listening`, and
`writing`. The explicit enable define is still accepted by build scripts; use
this to disable it:

```text
--dart-define=PARLESPRINT_COURSE_HARNESS_ENABLED=false
```

The second guard is `kDebugMode`, so a profile or release build cannot enable
this path accidentally even if a define is left in a build command.

## Request behavior

The client creates the next local Course specification, syncs that one row,
and makes one `prepare-course-lesson` request. In harness mode that request
contains a skill filter, so the server can only claim the selected skill. The
normal production request body is unchanged.

Gemini Live and the existing local speaking correction remain outside this
generation gate. Opening a Speaking lesson keeps the existing single Live
connection and local matcher. The harness only controls when the next saved
lesson is created and which skill it uses.

## Manual verification sequence

Use a fresh development profile if the current account already has generated
rows from an older rotation. This avoids confusing an old queued row with the
new test; no existing production data should be deleted.

1. Confirm Unit 1 and Unit 2 are present and ready.
2. Complete Unit 2 Vocabulary (`Learn common words`).
3. Confirm exactly one Unit 3+ Vocabulary row appears and one generation
   request is logged.
4. Complete it and confirm exactly one next Vocabulary row appears.
5. Repeat three or four times, checking that the sequence increases by one,
   the generated skill remains Vocabulary, and no other personalized skill is
   generated.
6. Reload the app between runs. The same row must remain available from local
   storage after hydration; reopening must not create a duplicate request.
7. If a provider call fails, confirm the row remains failed and the harness
   does not silently retry it. A later explicit action may be used to inspect
   or retry it deliberately.

The local NDJSON cost ledger records the harness trigger, request, edge
response, provider result, and Live events without sending another model
request. Use it to compare one Course generation call with the subsequent Live
session cost.

## Production hand-off

After Speaking, Vocabulary is the next lane. Then repeat the same sequence for
Reading, Listening, and Writing. Once all five lanes pass, disable the harness
activation. The production adaptive rotation and the existing local/cloud
storage contracts remain unchanged.
