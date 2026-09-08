# Guided Writing implementation

## Scope

This is the first course-writing slice. Guided writing is a local word-order
exercise backed by one quiet Gemini Live connection for optional help. Complete
and Roleplay modes remain available, but they do not open a Live socket until a
user explicitly uses their Live control.

## Runtime flow

1. The course row is authored by the existing `prepare-course-lesson` Edge
   Function through `ai-text` using `openai/gpt-5.6-luna`.
2. The writing validator requires five guided steps for A1/A2/B1/B2, with a
   reconstructable French word/chunk bank and one meaning per selectable item.
   Guided targets are short, punctuation-free sentences; commas, periods, and
   question marks are not selectable chips.
3. The writing screen shuffles each step's words locally. Token chips are
   content-sized and wrap long or multi-word chunks instead of assuming equal
   widths. The decoder also cleans older rows that included punctuation chips.
4. Checking is local and deterministic: the selected token order is normalized
   and compared with the target. No Gemini token is spent to grade an answer.
5. A guided screen opens one silent Live socket. It receives only the current
   step (level, target, meaning, bank, and selected order). Advancing suppresses
   the old reply and replaces that context with the new step.
6. The centered speaker button sends an explicit command to say the exact
   current French target once. Marie does not explain, translate, solve, grade,
   or introduce the next sentence automatically.
7. Translation is off by default and appears only when the translation control
   is enabled. The hint remains local/short.

## Live cost guardrails

Guided writing uses the compact Live prompt and context compression thresholds
of 1,000 trigger tokens / 500 target tokens. The dynamic current-step context is
bounded to 700 characters. These are session-context controls, not a promise
that every provider response is exactly 500 tokens; the prompt also tells the
model to stay silent until an explicit request.

## Generation recovery

`prepare-course-lesson` makes at most two authoring calls. If the first JSON is
rejected, the second call receives the exact validator error and rejected JSON
so the model can repair its own artifact. Guided writing is normalized at the
server boundary before validation: punctuation is removed from targets and
word-bank items, and punctuation-only items are dropped. Writing authoring is
capped at 2,200 output tokens. This is bounded recovery, not an unbounded
retry loop.

## Development harness

The harness default is now `writing`:

```bash
flutter run -d <device> \
  --dart-define=PARLESPRINT_COURSE_HARNESS_SKILL=writing
```

After a Unit 2 writing completion (sequence greater than 5), the existing
course completion hook asks for the next queued writing row. Other skills are
not advanced by this harness. Change the define to `vocabulary`, `speaking`,
`reading`, or `listening` when testing the next slice.

## Verification

- `flutter analyze` passes for the modified writing, Live, prompt, and harness
  files.
- The Edge Function is deployed as version 34 on the ParleSprint project with
  JWT verification enabled.
- An unauthenticated POST is rejected with HTTP 401, confirming the deployed
  function is active and protected.
- The iPhone debug build was installed and launched on device `kodekarbon`
  (`00008101-00124C4601EB001E`) with the writing harness define.
