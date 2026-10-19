# ParleSprint v3 roadmap: what is done, what is next, what must not be forgotten

Owner decisions are in bold. This file is the single place for the plan. Update it when work is done.

## Where we are

**Photo Tutor/OCR:** disabled in V3 and deferred until V4. The active OCR
service is a no-op, and Google ML Kit is removed from V3 dependencies and iOS
Pods. The prior native adapter is preserved under `docs/v4_deferred/` for a
future V4 implementation.

| Area | Status |
|---|---|
| A1 master chapters | **Stage 0 and all 14 A1 units are authored and exported.** The PDF remains a reference and was not rebuilt in this pass. |
| App shell, onboarding, Learn, Stories, lesson player | built, tested on the phone |
| Book to app lessons | **Stage 0, A1 (14 units), A2 (12), B1 (12), and B2 (14) are exported in sequence** (733 indexed lessons including the dev sample; 46 stories). |
| Marie live inside lessons | **built, inline**: phone button, panel (Mute, End, Skip), response pill, speaker taps say the exact line in the chosen voice. Story reader does not have it yet. See `MARIE_TUTOR.md` |
| Progress and review | **built**: furthest step is real progress, Previous, review, replay, Resume. See `AGENT_RULES.md` section 9 |
| Review (spaced repetition) | **not built.** Learn has no review card until it is |
| Tests tab (mock exams) | opens the old exam screen. A real TCF mock engine is not built |
| Lesson audio | **Decision: speaker buttons ask live Marie (the chosen tutor) to say the exact line, on one warm connection, exactly like the old vocabulary lessons.** No saved clips for lesson words, so changing tutor changes every voice |
| iPad layout | **partly done**: universal build, readable column, checked on iPad portrait and landscape, Split View safe for calls. Still to do: keyboard and Pencil friendly writing areas |
| Progress sync between devices | **not built. Progress is saved on the device only** |

**App Store handoff (2026-10-19):** The owner confirmed the Xcode archive for
version 1.0.3 (327) uploaded to App Store Connect. The local screenshot package
contains seven iPhone and six iPad assets with a TCF Canada first-three
sequence; upload and App Review submission are not verified. Candidate ASO
metadata is documented in `flutter_app/app_store_screenshots/v3-submission/ASO_METADATA.md`.
See `CROSS_PRODUCT_RELEASE_2026-10-19.md` for the app, website and extension
handoff status.

## A1 course units (hand-authored master chapters)

Each unit follows the same path: words (5 groups), phrases, grammar, 2 dialogues, story, listening (5), reading (5), writing, speaking, TCF corner (4 listening, 3 reading), 10-question checkpoint. Run `python3 content/tcf/book/check_book.py` after each unit: it blocks any French word used before it was taught.

| Unit | Title | Grammar | Words and situations | Canada |
|---|---|---|---|---|
| 6 | Days, time and appointments | g15 days, dates, time, appointments | days, months (mastered), seasons, clock times (9 h 30), dates, appointments | 24-hour clock on schedules, *fin de semaine*, booking by phone |
| 7 | Eating: déjeuner, dîner, souper | g07a du/de la/des, g19 vouloir, pouvoir, je voudrais | meals, foods, drinks, restaurant, ordering politely | déjeuner/dîner/souper vs France, tips, *poutine* |
| 8 | Groceries and shopping | g08 negation ne...pas, pas de; g13 ce/cet/cette/ces | store types, quantities, clothes, household items, where is...? | *épicerie, dépanneur, magasiner*, store notices |
| 9 | Getting around | g07b au/aux, g16 aller + futur proche, g17 prepositions of place | city places, directions, transport, tickets, near and far | STM/OC Transpo/TTC, bus stops, winter detours |
| 10 | Housing and the lease | g18 il y a, c'est vs il est | rooms, furniture, rental ads, landlord and tenant, moving in | lease (*bail*), 1er juillet moving day in Québec, heating |
| 11 | Weather and clothes | g20 faire, prendre, il fait froid | weather, seasons, winter clothes, temperatures in Celsius | -25 °C, *tuque*, *bottes*, forecast vocabulary |
| 12 | Work and studies | (consolidation: g09, g10) | jobs, workplace, schedule, studies, coworkers | *gérante*, résumé = CV, first day, payslip |
| 13 | Health and services | g21 avoir mal à + contractions | body, symptoms, pharmacy, clinic, emergencies | health card, 811, 911, *sans rendez-vous* clinics |
| 14 | Free time and simple plans | g22 aimer, préférer | hobbies, inviting, accepting, refusing, weekend plans | hockey, skating, *cabane à sucre*, parks |

**Units 6 to 14 are authored and exported.** Their master chapters are in `content/tcf/book/chapters/06_unit06.py` through `14_unit14.py`; the final content pass reported 0 book-ledger warnings and 0 app-validation errors.

**Planned stories now assigned to their units:** *Au dépanneur* (Unit 8), *Mon premier jour* (Unit 12), and *Un rendez-vous à la clinique* (Unit 13). They are authored with their units and included in the app export.

**A1 mini mocks** remain separate work: the syllabus calls for timed, one-play sets of 12/12 questions after Unit 5, 15/15 after Unit 10, and 20/20 after Unit 14. No mini-mock content is currently in the app export, and the mock engine is not built.

**Book front and back matter still to add:** A1 grammar summary (all conjugations on two pages), numbers and dates reference, Canadian French mini-dictionary, study calendar (14 to 18 weeks), a printable progress sheet.

## A2–B2 course path

| Level | Units | Grammar focus | Skills and TCF tasks | Cumulative words (target) |
|---|---|---|---|---|
| A2 | 12 | see `content/tcf/syllabus/grammar_a2.json` and `content/tcf/syllabus/a2.json` | all four skills; writing Task 1 (60–120 words); oral Task 1 interview practice | 570 new word entries; 173 app lessons |
| B1 | 12 | plus-que-parfait, future clauses, hypothetical conditions, relative pronouns, subjunctive, connectors, reported speech, indirect questions, passive/on, gerund and past-participle agreement | all four skills; writing Task 2 (120–150 words); oral Task 2 information-seeking dialogue (2 min prep + 3 min 30); short, clearly labelled oral Task 3 practice | 360 new focus terms (30 per unit); 157 app lessons |
| B2 | 14 | see `content/tcf/syllabus/grammar_b2.json`; argument, reporting, relative clauses, narrative time, subjunctive, hypotheses, cohesion, question strategy, synthesis and editing | all four skills; writing Tasks 1–3 and oral Tasks 1–3; original listening/reading; independent transfer | 420 new focus terms (30 per unit); 183 app lessons |

Targets are planning numbers, not promises. Vocabulary source: the 1 392-word legacy lists (`assets/content/vocab_phase1..3.json`) as a candidate pool only; every word, sound guide and example is written fresh.

**A1 delivery status:** All 14 A1 units are authored and included in the app path. The book ledger and general app validator pass in this content audit.

**A2 delivery status:** All 12 units are authored and exported (173 lessons, 12 stories, 1,820 steps and 516 generated checks). The 570 new-word target is a planning count, not an official CEFR vocabulary requirement. A focused refinement pass cleaned up examples and past-tense progression. `check_book.py`, scoped export, `validate.py`, `tool/check.sh --quick` and 266 Flutter tests pass. The complete 152-page reviewer copy is `docs/v3/book/ParleSprint_A2_Reviewer_Draft.pdf`; human French/TCF and audio review and physical iPad/iPhone testing remain open. See `docs/v3/A2_REVIEW_AND_DEVICE_QA.md` for the handoff and test steps.

**B1 delivery status:** All 12 units are authored in `content/tcf/book/b1_source.py` with numbered chapter adapters, 30 focus terms and 8 reusable chunks per unit, a four-skill readiness baseline, 12 sequenced grammar targets, and TCF practice. The scoped app export contains 157 B1 lessons and is ordered after A2 and before B2. `validate_b1.py` checks the source, all five six-term vocabulary sets, lesson exports, model word ranges, and answer keys.

**B2 content status:** All 14 units are authored in `content/tcf/book/b2_source.py` and export 183 lessons, including 30 focus terms in five six-term sets per unit, 8 reusable chunks per unit and 14 sequenced grammar targets. The B2 syllabus sets 420 new focus terms as a planning target. `validate_b2.py` checks the vocabulary sets, writing ranges, lesson files and answer keys. The app path is ordered after B1 but does not enforce CEFR prerequisites. A fluent French and audio review remains outstanding across levels.

**Stories tab additions:** Ten original B1 and ten original B2 reading stories are attached to Units 1–10 and exported into the Stories tab. Each has seven French sentences with English lines, tap-to-define word coverage, a three-question comprehension quiz and an adult-life theme connected to its unit. Source: `content/tcf/book/story_extensions.py`. The app index contains 46 stories total. This pass did not add separate listening materials; fluent-speaker review of the French, translations and glosses remains open.

**Cross-level content audit (2026-10-13):** The authored path contains 14 A1, 12 A2, 12 B1 and 14 B2 units (52 total). The planned focused word entries sum to 1,980 across the four syllabi; this is not a count of every word learners need to know or a CEFR/TCF guarantee. `check_book.py` passes with 0 errors and 0 ledger warnings; `validate.py` reports 0 errors and one expected warning for the hidden `dev-sample`; `validate_b1.py` and `validate_b2.py` pass. The app index contains 732 non-dev lessons plus the dev sample and 46 stories. The later A2 QA pass ran 266 Flutter tests and built the A2 reviewer PDF; no physical device install/test or human French/audio review has been completed.

| A2 unit | Focus | Main new grammar |
|---|---|---|
| 1 | Explain a weekly routine and clarify details | clause connectors and sequencing |
| 2 | Recount what happened this week | passé composé with *avoir* and regular participles |
| 3 | Describe an earlier routine and a first experience | common irregular past participles |
| 4 | Tell a clear past story | imparfait for background and habits |
| 5 | Explain an event against its background | passé composé / imparfait contrast |
| 6 | Compare homes and make future plans | futur simple basics; comparatives and superlatives |
| 7 | Handle a health or service appointment | *qui, que, où* to connect details |
| 8 | Ask and follow up at work or school | direct object pronouns (*le, la, les*) |
| 9 | Navigate a trip and adapt to a change | indirect object pronouns; *y* for places |
| 10 | Shop and talk about food quantities | *en* with quantities |
| 11 | Resolve a service problem politely | imperative; polite conditional requests |
| 12 | Integrate A2 across a changing week | cumulative retrieval and four-skill transfer |

Pacing is a planning estimate, not a weekly lock: at 14–16 focused hours per
unit, 52 units take roughly 728–832 hours. That is about 12–14 months at two
hours a day or 6–7 months at four hours a day, with progress gated by delayed
recall and new-context performance rather than lesson completion alone.

**TCF Canada facts to keep correct** (verify on the France Éducation international site before release): Listening 39 questions in 35 minutes, one play; Reading 39 in 60; Writing 3 tasks in 60; Speaking 3 tasks in 12 minutes. Questions run from easiest to hardest. A wrong and a blank answer both score zero. NCLC 7 is the common immigration target. Never promise a score.

## Book to app

The book is the master. The app lessons and stories are produced from it so the two cannot disagree.

1. Words groups become word lessons with quick checks.
2. Phrases, grammar, dialogues become explain and phrase lessons.
3. Listening and reading questions become listen and choose steps with the same answers and explanations.
4. Stories become story files (with a meaning for every word).
5. Checkpoints become a lesson per unit.
6. `python3 content/tcf/tools/validate.py`, `flutter test`, then `tool/e2e_all.sh` on the phone.

## App work that must not be forgotten

- **iPad** (the owner studies on an iPad, with a notes app beside it): support Split View and Slide Over (no full-screen-only flag), a readable column width on wide screens, landscape, keyboard and Pencil friendly text areas for writing. Test on an iPad simulator and device before release.
- **Review**: spaced repetition over words learned in lessons, words missed in questions, words saved in stories. Today the Learn tab shows no review card because the old review is not wired to the new content.
- **Writing and speaking feedback**: Marie checks a short text or a spoken answer with one concise correction, one better version, one reason. No invented scores.
- **Marie "check my pronunciation" switch** in lessons (live, optional, billed).
- **TCF mock engine**: real timers, one-play audio, 39-question sets per level, estimate labelled as an estimate.
- **Lesson audio is live tutor speech** (see the table above). Revisit a pre-made clip catalog only if live cost becomes a problem, and then per tutor voice.
- **Progress sync**: today progress lives on the device. Reinstalling erases it. Add account sync before real users.
- **Free vs paid**: decide the free lessons and gate the rest. Paywall redesign (Vocabulary.com trial timeline pattern).
- **A fluent French speaker must review** the book and the baked audio before it is sold (`content/tcf/REVIEW_NEEDED.md`). Pronunciation guides are approximations.
- **App Store**: update screenshots, subtitle, What's New and App Review notes to match the TCF-only app. No claim of affiliation with France Éducation international or IRCC. Keep Restore Purchases, Terms, Privacy, account deletion, AI consent.
- **Account link on the welcome screen** ("I already have an account") for reinstalls.
- **Remove the legacy generation code** (OpenRouter and AI lesson builders) once nothing reaches it. It costs money if anything triggers it.
- **Dark mode** and **large text** checks on every new screen.
- **Accessibility**: labels and 44 point targets are linted. Add a VoiceOver pass.

## Rules that keep quality

1. Every French word used in a dialogue, story or exam item was taught earlier (the book checker enforces it).
2. Every answer key is re-solved blind from the text before the unit is committed.
3. Canada vs France differences are marked, and only where verified.
4. Original text only. Public sources set targets and patterns, never wording.
5. The app never invents scores, progress or recommendations.
6. Device tests never touch real progress (keys are namespaced in test builds).
