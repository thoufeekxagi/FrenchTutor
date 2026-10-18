# Runtime explanation evaluation — October 17, 2026

Evaluated the deployed `immersion-explain` endpoint using its configured
`gemini-3.1-flash-lite-preview` model. This is a single-model smoke evaluation,
not a comparison with OpenAI or other Gemini models, and not a French-teacher
certification.

## Automated results

20 curated A1–B2 cases, serial requests, one fresh temporary authenticated
account, exactly 20 explanation calls. All 20 returned HTTP 200 and nonempty,
bounded `meaning`, `grammar`, `example`, and `exampleTranslation` strings.
The temporary account was deleted after the run. Full request cases and model
outputs are saved only to ignored `artifacts/ai-evaluation.json`.

| Observed endpoint latency | Milliseconds |
| --- | ---: |
| Minimum | 1,205 |
| Median | 1,602.5 |
| 95th percentile (nearest rank) | 1,888 |
| Maximum | 1,897 |

Timing includes network and backend processing. Server cache hit/miss was not
instrumented; these are observed request times, not guaranteed cold-generation
latencies or a production SLA. No failure/retry calls were needed.

Coverage includes greetings, negation, contractions, gender, passé composé,
imperfect, near future, reflexive verbs, idioms, informal speech, verlan,
Québécois usage, en/y pronouns, subjunctive, past conditionals, and malformed or
ambiguous captions. The committed cases are in
`tests/fixtures/explanation-cases.json`.

## Linguistic review

An AI coding agent read all 20 outputs against the supplied context. This is a
qualitative review, separate from schema validation, with no independent human
French instructor involved. The results do **not** justify “20/20 correct.”

Most core meanings and example translations were useful. In particular, the
outputs recognized *c'est ouf*, Québec *c'est plate*, *avoir le cafard*,
*poser un lapin*, and *j'en ai marre* without translating them literally, and
handled the subjunctive and past conditional examples appropriately.

Three outputs need correction before being used as authoritative grammar:

- `a1-gender`: correctly identifies *une amie* as feminine, but incorrectly
  implies its vowel initial makes it the feminine form. The feminine form adds
  an *e* to *ami*; starting with a vowel is unrelated. The selected phrase alone
  also does not identify nationality.
- `b1-caption-error`: correctly spots likely *ça va* / *je suis* corrections,
  but calls *sa* a demonstrative adjective. It is possessive. It also assigns
  “filler or acknowledgment” too confidently to damaged text without enough
  context; a probable reconstruction should be qualified.
- `b2-caption-ambiguity`: invents a “famous tongue twister” framing for a
  truncated three-word input and adds a fourth homophone, *vers*. The individual
  word meanings and generated example are useful, but the framing exceeds the
  evidence. Saying all four forms are nouns or adjectives also misses the
  preposition use of *vers*.

Other precision limits: the imperfect formation explanation should explicitly
say to remove *-ons* from the present *nous* form; the reflexive agreement rule
is simplified and has exceptions; calling *tenir à* a “pronominal construction”
can confuse learners with reflexive/pronominal verbs. Some examples demonstrate
a grammar pattern without reusing the exact selected phrase. CEFR level control
was not independently scored.

Baseline decision before the fixes documented below: suitable for optional, clearly fallible on-demand study assistance;
not sufficiently reliable to advertise as verified grammar instruction. Keep
“AI can make mistakes” visible and treat damaged captions cautiously. No fallback
model comparison was performed or claimed. That baseline prompted the corrective iteration and targeted rerun documented
below. The final decision appears at the end of this report.

## Reproduce

After building the extension, run `node scripts/evaluate-ai.mjs` from its root.
Set public Supabase URL/anon variables in `.env.local`, and
`IMMERSION_QA_SERVICE_KEY` in the shell or ignored `.env.qa.local` (legacy
`SUPABASE_SERVICE_ROLE_KEY` / `SUPABASE_SECRET_KEY` also work). Shell values take
precedence. The script makes at most 20 requests and never prints credentials.

The separate `node tests/live-ai.mjs` test also passed with real Chromium MV3:
popup password sign-in, background request, live explanation, offline local
cache, learner overlay consent/click/rendering of all four fields, and sign-out.
Its 1280×800 `artifacts/explanation-ui.png` screenshot uses an explicitly labeled
local video fixture with illustrative imported subtitles; the AI response is
real. The fixture is silent and does not demonstrate actual spoken French.

## Post-fix regression — prompt version 3

The original 20-case evidence above is preserved. Its findings led to two prompt
revisions and a more capable route for B1/B2 requests. The final deployed Edge
Function is version 4, with cache prompt version 3. A1/A2 use
`gemini-3.1-flash-lite-preview`; B1/B2 use `gemini-3-flash-preview` with minimal
thinking. The server cache includes prompt version and actual model, so earlier
responses are not reused. Client cache version is bumped separately.

The revised generic teacher instruction distinguishes possessives from
demonstratives, grammatical gender from vowel spelling, pronoun-containing
constructions from reflexive verbs, and interpretation from unsupported
reconstruction. It requests only relevant conjugation details and cautious
handling of incomplete captions. It does not supply specific answers to cases.

Five regression requests were sent serially through the deployed endpoint using
a fresh temporary authenticated account, which was deleted afterward. All five
returned HTTP 200 with valid schema. This is targeted regression evidence, not
a statistical cross-model comparison or proof of general correctness.

| Case | Final latency | Agent linguistic review |
| --- | ---: | --- |
| `a1-gender` | 1,917 ms | Correct feminine noun/article and formation by adding e; erroneous vowel-causality/nationality claims removed. |
| `a2-imperfect` | 1,639 ms | Correct fais- stem and -ait ending, impersonal weather context; no incomplete general formation rule. |
| `b1-pronoun-y` | 1,783 ms | Correct tenir à / y reference and tiens conjugation; erroneous paradigm/pronominal labeling removed. |
| `b1-caption-error` | 1,799 ms | Correctly labels sa possessive and ça demonstrative; still too confident about the intended reassuring/filler sense. |
| `b2-caption-ambiguity` | 1,425 ms | Correct three supplied homophones, categories and pronunciation; no invented famous quotation or fourth source word. |

Final observed median: **1,783 ms**, range **1,425–1,917 ms**. Full post-fix
outputs are in ignored `artifacts/ai-regression-v3.json`. Intermediate prompt-2
outputs are preserved in `artifacts/ai-regression-v2.json`. Regression inputs and
manual review checklists are committed in
`tests/fixtures/explanation-regressions.json`. Reproduce the final set with
`node scripts/evaluate-ai.mjs --regression`.

Four of five checklist reviews passed; the malformed-caption case partially
passed. The three original concrete grammar/framing errors were absent in the
final outputs. **Remaining limitation:** neither prompting nor the stronger
model reliably expresses uncertainty for all malformed subtitles. The damaged
caption's interpretation is plausible but unverified. Retain the visible AI
fallibility disclosure and do not claim corrected subtitles or authoritative
explanations. No broader quality guarantee follows from this small sample.

Final release decision: keep optional explanations enabled with the existing
visible AI-fallibility disclosure, the stronger B1/B2 route, and prompt/cache
version 3. The observed concrete grammar mistakes were corrected in targeted
regression; malformed-caption intent remains uncertain and must not be marketed
as reliably reconstructed. No additional release-blocking schema, auth, or
request-flow failures were observed.
