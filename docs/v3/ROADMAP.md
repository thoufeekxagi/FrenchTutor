# ParleSprint v3 roadmap: what is done, what is next, what must not be forgotten

Owner decisions are in bold. This file is the single place for the plan. Update it when work is done.

## Where we are

| Area | Status |
|---|---|
| A1 master chapters | **Stage 0 and Units 1 to 14 authored.** Units 6 to 14 pass the book ledger; app lessons are exported. The PDF remains a reference and was not rebuilt in this pass. |
| App shell, onboarding, Learn, Stories, lesson player | built, tested on the phone |
| Book to app lessons | **Stage 0 and Units 1 to 14 are in the app export** (219 authored lessons, 14 stories), produced by `export_app.py` |
| Marie live inside lessons | **built, inline**: phone button, panel (Mute, End, Skip), response pill, speaker taps say the exact line in the chosen voice. Story reader does not have it yet. See `MARIE_TUTOR.md` |
| Progress and review | **built**: furthest step is real progress, Previous, review, replay, Resume. See `AGENT_RULES.md` section 9 |
| Review (spaced repetition) | **not built.** Learn has no review card until it is |
| Tests tab (mock exams) | opens the old exam screen. A real TCF mock engine is not built |
| Lesson audio | **Decision: speaker buttons ask live Marie (the chosen tutor) to say the exact line, on one warm connection, exactly like the old vocabulary lessons.** No saved clips for lesson words, so changing tutor changes every voice |
| iPad layout | **partly done**: universal build, readable column, checked on iPad portrait and landscape, Split View safe for calls. Still to do: keyboard and Pencil friendly writing areas |
| Progress sync between devices | **not built. Progress is saved on the device only** |

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

## After A1: A2, B1, B2 (same method, same checks)

| Level | Units | Grammar focus | Skills and TCF tasks | Cumulative words (target) |
|---|---|---|---|---|
| A2 | 12 | passé composé, imparfait intro, futur proche/simple, pronoms COD/COI, comparatives, *y* and *en*, reflexive verbs | writing task 1 (60 to 120 words: message, short note), speaking task 1 (guided interview), short listening and reading texts | about 1 200 |
| B1 | 12 | imparfait vs passé composé, conditionnel, subjonctif intro, relative pronouns, connectors, indirect speech basics | writing task 2 (120 to 150 words), speaking task 2 (prepared monologue, 2 min prep), longer audio | about 2 500 |
| B2 | 14 | subjonctif, concession and cause, passive, hypothesis, formal register, argument structure | writing task 3 (120 to 180 words, opinion), speaking task 3 (interaction, give a point of view), news and interview audio | about 4 500 |

Targets are planning numbers, not promises. Vocabulary source: the 1 392-word legacy lists (`assets/content/vocab_phase1..3.json`) as a candidate pool only; every word, sound guide and example is written fresh.

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
