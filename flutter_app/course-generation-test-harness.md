# Course generation test harness

This is a development-only verification lane for the adaptive Course. It is
not a second lesson engine, database, or provider pipeline.

## Current target

The harness is opt-in in debug builds and targets `speaking` when enabled.
It preserves the authored route:

- Sequences 1–5: authored Unit 1 foundation.
- Sequences 6–10: authored Unit 2 (`vocabulary`, `speaking`, `reading`,
  `listening`, `writing`).
- Sequence 11 onward: personalized generated lessons, with the unit label
  derived from the sequence in five-session blocks.

In harness mode, completion of the selected Unit 2 activity is the gate for
sequence 11. Only one personalized row is appended at a time. The next row is
not appended until the current selected-skill row is completed.

The harness does not delete or rewrite a ready/completed lesson. It does not
run a background lookahead, retry a failed provider call, or create rows for
the other skills. Existing non-target personalized rows are simply hidden from
the debug roadmap so the current test lane stays unambiguous.

## Switching the lane

The same harness is reusable for the next skill. Enable it and pass a Dart
define when starting a debug build:

```text
--dart-define=PARLESPRINT_COURSE_HARNESS_ENABLED=true
--dart-define=PARLESPRINT_COURSE_HARNESS_SKILL=vocabulary
```

Supported values are `speaking`, `vocabulary`, `reading`, `listening`, and
`writing`. Disable the harness completely with:

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
2. Complete Unit 2 Speaking.
3. Confirm exactly one Unit 3 Speaking row appears and one generation request
   is logged.
4. Complete it and confirm exactly one next Speaking row appears.
5. Repeat three or four times, checking that the sequence increases by one,
   the generated skill remains Speaking, and no other personalized skill is
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

After Speaking is verified, switch the define to the next skill and repeat the
same sequence. Once all five lanes pass, disable the harness define. The
production adaptive rotation and the existing local/cloud storage contracts
remain unchanged.
