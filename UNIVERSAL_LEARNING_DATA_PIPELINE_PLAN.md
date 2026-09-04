# Universal Learning Data Pipeline and Personalized Course Plan

Status: planning document only. No implementation is included here.

This document defines the replacement for the legacy Course path. It is intentionally separate from orchestration work. The product does not need a complicated orchestration layer to teach French well. It needs one reliable learning history, one recent learner snapshot, and one lesson builder that uses the teaching engines already used by Practice.

The product promise is:

> Every Course session and every Practice session becomes learner data. That data is used to select, generate, and improve the next integrated lessons.

This includes onboarding, Course lessons, standalone reading/listening/writing/vocabulary/grammar/speaking/pronunciation practice, Gemini Live conversations, TCF/TEF practice, and extra practice after a Course lesson.

The Course gives structure. Practice gives evidence. Both have equal weight.

## 1. Product model

The Course and Practice are two doors into the same learning system.

The Course is a visible roadmap:

- Unit 1, Unit 2, and later units;
- twenty lessons per visible block;
- clear sequence and progression;
- clear skill labels;
- a predictable path.

Practice is the learner's flexible route:

- speaking or Gemini Live;
- reading or listening;
- writing;
- vocabulary reviews;
- grammar or pronunciation;
- exam tasks;
- extra work after a Course lesson.

Neither route is more important. A Course-only learner still produces learning evidence. A Practice-heavy learner still advances the Course path. The next Course lessons reflect whichever route contains the most recent and most useful evidence.

The lesson content is fresh without being disconnected:

- new situations and prompts prevent boredom;
- repeated words, phrases, grammar, pronunciation targets, and mistakes create learning;
- the same target reappears across different skills and contexts;
- completing an activity is not the same thing as mastering the target.

## 2. Core learning loop

    Onboarding profile
            +
    Course sessions
            +
    Standalone Practice
            +
    Extra Practice
            +
    Exam Practice
            +
    Gemini Live transcripts
            +
    Structured results from every skill
            |
            v
    Universal learner records
            |
            v
    Recent Practice Snapshot
            |
            v
    Personal Course Builder
            |
            v
    Integrated lesson packs
            |
            v
    Pre-check and persistence check
            |
            v
    Course or Practice delivery
            |
            v
    Result capture and the next snapshot

The Course builder must not read isolated UI stores one at a time. It reads a normalized snapshot assembled from the complete recent history.

The application stores all useful history, but generation receives a compact, relevant view. This keeps prompts useful without sending the entire account to a model.

## 3. Design principles

### 3.1 One learner history

There is one canonical history for learning evidence. Practice does not become less valuable because it happened outside the Course.

Every activity receives a source label:

- Course;
- standalone Practice;
- extra Practice related to a Course lesson;
- exam Practice;
- onboarding assessment;
- review or remediation.

The label explains where evidence came from. It must not determine whether the evidence counts.

### 3.2 Repetition is the main engine

The default target mix for a new twenty-lesson block is:

- 60% repetition, transfer, repair, and consolidation;
- 40% new or slightly harder material.

For twenty lessons, this means twelve are primarily repetition-led and eight are primarily expansion-led. Repetition does not mean twelve identical lessons. It moves through new situations, new skills, delayed recall, and gradually reduced support.

Every lesson should contain:

- at least one previously learned target;
- at least one weak target, repeated mistake, or due review item;
- one small new challenge;
- a meaningful opportunity to use the shared language in more than one skill.

### 3.3 Fresh context, shared language

Each Course lesson is one integrated theme pack, not a collection of unrelated generators.

Example theme:

    At an apartment viewing in Montréal

Stages:

1. Review recent vocabulary.
2. Introduce three to six new words or phrases.
3. Read a related listing or conversation.
4. Listen to the same situation.
5. Write a useful message to the landlord.
6. Speak through the viewing.
7. Repeat one pronunciation target from the learner's history.

The existing engines continue doing the actual teaching. The Course builder supplies the common theme, target set, level, mistakes to repair, and success criteria.

### 3.4 Save first, generate second

If a learner's result exists only in widget state, it does not exist for personalization.

The system must save:

- the activity;
- the exact content shown;
- the learner's answer or utterance;
- the expected answer where available;
- correctness or quality;
- hints and retries;
- corrections and feedback;
- transcript evidence;
- pronunciation evidence;
- the relationship to the Course lesson when one exists.

Existing UI stores may remain for speed and resume behavior, but they must write into the universal learning record.

### 3.5 Completion is not mastery

Course completion means the learner finished an activity. It does not mean every target inside it is Comfortable.

Target state is separate:

- New;
- Practicing;
- Comfortable.

The builder uses target evidence, not only completed content keys.

### 3.6 Profile changes are allowed

The learner can change onboarding information at any time.

When the profile changes:

- completed history remains immutable;
- old results retain the profile version active at the time;
- future unstarted Course packs can be rebuilt;
- an active lesson is not silently rewritten;
- the learner sees that future lessons were refreshed;
- the next snapshot uses the current profile plus historical evidence.

### 3.7 Keep the model simple

The first version does not need a black-box learner model, Bayesian Knowledge Tracing, a competency graph, or a separate planner service.

It needs:

- reliable records;
- explicit target metadata;
- simple target states;
- recent evidence selection;
- the 60/40 rule;
- deterministic quality checks;
- observable result write-back.

## 4. Scope and non-goals

### In scope

- universal records for all learning activity;
- reliable Gemini Live transcript persistence;
- structured result persistence for every skill;
- Course and Practice linkage;
- a Recent Practice Snapshot service;
- a Personal Course Builder service;
- integrated lesson packs;
- regeneration of future Course blocks;
- profile-change handling;
- pre-generation and post-session checks;
- Course-only, Practice-heavy, skill-focused, and exam-focused learners.

### Out of scope for the first version

- replacing the existing teaching engines;
- rebuilding every screen at once;
- a complex orchestration graph;
- a fully automatic CEFR certification system;
- claiming that the application guarantees an official exam result;
- deleting existing stores;
- treating generated content as proof that the learner knows the material;
- sending the entire account history in every prompt.

## 5. Storage audit

The repository already contains valuable data. The main problem is fragmentation, inconsistent structure, and missing links between an activity and the Course lesson that produced it.

### 5.1 Onboarding and profile

Relevant files:

- [learning_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/learning_store.dart)
- [app.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/app.dart)
- [speak_onboarding_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/onboarding/speak_onboarding_screen.dart)

Already available:

- goal;
- approximate level;
- preferred session length;
- reminder time and preferred days;
- time zone;
- notification permission state;
- onboarding version;
- interests or skill preferences.

Needs to be explicit for strong personalization:

- target exam, sections, date, and target score;
- native language and prior French experience;
- daily or weekly time budget;
- occupation or study context;
- concrete use cases;
- preferred region or variety of French;
- accessibility or audio constraints;
- balanced versus deliberately weighted skill preference.

The active onboarding route must be the source of truth. A separate V3 implementation must not silently create a second profile contract.

### 5.2 Normal Course and Practice sessions

Relevant files:

- [storage_service.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/storage_service.dart)
- [session_recorder.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/services/session_recorder.dart)

Already available:

- session id and user id;
- start and end time;
- summary and topic;
- content key in some paths;
- stage;
- user and tutor messages;
- completion keys.

Main problem:

SessionRecorder does not consistently receive the Course content key or lesson-pack id. A standalone and Course session can therefore look identical after saving. A summary is useful for display but is not a universal learning result.

Required fix:

Every recorded session must have a nullable Course link:

- Course lesson pack id;
- Course content key;
- unit and sequence when applicable;
- source type;
- parent session id when this is extra Practice.

The Course link is nullable because standalone Practice is valid and must still count.

### 5.3 Gemini Live sessions

Relevant files:

- [learning_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/learning_store.dart)
- [session_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/session/session_screen.dart)
- [inline_call_controller.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/services/inline_call_controller.dart)

Already available:

- ai_sessions;
- JSON transcripts for full-screen Gemini Live sessions;
- connected and ended timestamps;
- learner utterance count;
- ended reason;
- normal session messages in some flows;
- spokenSessionTexts extraction.

Main problems:

- the AI session and normal session are separate;
- the records are not reliably linked;
- some inline Live screens do not pass transcript callbacks;
- some screens save transcript text but not structured activity results;
- spokenSessionTexts has weak recency and source context;
- transcript text is not mapped to targets, corrections, or pronunciation evidence;
- a transcript can be saved without a Course or Practice result.

Required fix:

Every Live call gets a universal practice session id at start. The existing ai_sessions row can remain for provider-specific data, but it points to the canonical session. The canonical session owns the learning event.

Transcript capture must:

- persist learner and tutor turns as they arrive where possible;
- persist the final transcript on normal end;
- persist partial transcript on interruption where possible;
- record ended reason;
- mark transcript completeness;
- never treat a missing transcript as a successful speaking result.

Audit explicitly:

- storybook reading;
- V2 grammar guided mode;
- grammar roleplay;
- speaking lesson flow;
- every future inline Live surface.

### 5.4 Daily sessions

Relevant files:

- [daily_session.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/models/daily_session.dart)
- [learning_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/learning_store.dart)

Already available:

- ordered stages;
- frozen vocabulary ids;
- grammar lesson id;
- reading passage JSON;
- writing task JSON;
- stage status;
- stage result JSON;
- started and completed state.

DailySession is useful for resuming and freezing a daily experience. It is not sufficient as universal history because standalone Practice is not always a DailySession.

Required fix:

Keep DailySession for the daily UI contract, but every stage also writes a canonical Practice Session and structured attempts.

### 5.5 Vocabulary

Relevant files:

- [learning_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/learning_store.dart)
- [srs_service.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/services/srs_service.dart)
- [vocabulary_session_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/vocabulary_session_store.dart)
- [agent_led_vocab_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/pathway/agent_led_vocab_screen.dart)

This is currently the strongest area.

Already available:

- cards;
- due dates, intervals, and repetitions;
- review grade and response type;
- session id and introduction date;
- context and sentence results;
- frozen deck and retry state.

Main problems:

- reviews are not always linked to Course content;
- card ids are not always linked to a shared lesson target;
- transcript evidence is not mapped to card use;
- “shown” is not distinguished from “recalled” or “produced”.

Required fix:

Preserve SRS. Add universal activity and target links. Keep “seen”, “recalled”, “used in context”, and “used without support” as separate evidence types.

### 5.6 Writing

Relevant files:

- [learning_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/learning_store.dart)
- [writing_task_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/lessons/writing_task_screen.dart)
- [writing_workshop_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/lessons/writing_workshop_screen.dart)

Already available:

- submission text;
- task id;
- feedback;
- submitted time;
- live tutor transcript in some flows;
- rich workshop feedback including score, strengths, corrections, improved version, and next steps.

Main problems:

- feedback formats differ by screen;
- corrections are not consistently normalized;
- submissions lack Course key, topic, level, targets, and exam section;
- the original text and final feedback are not always one canonical result.

Required fix:

Store one immutable original submission plus normalized feedback items:

- error category;
- original fragment;
- corrected fragment;
- explanation;
- severity;
- target id when known;
- whether the learner successfully revised it.

Rich JSON can remain for rendering. Normalized fields are what the Course builder reads.

### 5.7 Reading

Relevant files:

- [reading_storybook_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/lessons/reading_storybook_screen.dart)
- [story_reader_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/lessons/story_reader_screen.dart)

Already available:

- story content;
- topic;
- quiz score in some paths;
- session summary;
- generated content.

Main problems:

- individual answers are often only in memory;
- missed questions are not consistently persisted;
- difficult words and translation use are not structured;
- replay, reread, and hesitation data are inconsistent;
- one reading flow has no inline Live transcript callbacks.

Required fix:

Store each reading question attempt with question id/type, learner answer, expected answer, correctness, hint or translation use, target phrase, passage id, and level. A total score alone is not enough.

### 5.8 Listening

Relevant files:

- [listening_practice_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/lessons/listening_practice_screen.dart)
- [agent_led_listening_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/pathway/agent_led_listening_screen.dart)

Already available:

- transcripts and feedback in some Live flows;
- dictation and shadowing;
- question attempts in memory;
- summary and score;
- some stage results;
- transcript callbacks in the agent-led flow.

Main problems:

- answer-level data is not universal;
- replays and missed details are not consistently stored;
- dictation and shadowing outcomes can become only a summary;
- transcript quality and comprehension are not separated.

Required fix:

Store comprehension question, dictation segment, shadowing attempt, transcript reconstruction, and detail-identification results separately. The Course builder must know whether the learner failed to hear, understand, spell, or reproduce the sound.

### 5.9 Grammar

Relevant files:

- [grammar_v2_lesson_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/grammar/grammar_v2_lesson_screen.dart)
- [grammar_roleplay_lesson_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/grammar/grammar_roleplay_lesson_screen.dart)
- [agent_led_grammar_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/pathway/agent_led_grammar_screen.dart)
- [generated_grammar_story_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/generated_grammar_story_store.dart)

Already available:

- lesson progress;
- score;
- attempted and correct counts;
- agent-led transcript;
- drill results in some flows;
- generated grammar story content and score.

Main problems:

- per-question answer and correction data is inconsistent;
- hints and retries are not universal;
- Course linkage is missing in some paths;
- completion can exist without detailed evidence.

Required fix:

Every grammar item saves the target, learner answer, expected answer, correctness, correction, hint count, retry count, explanation shown, and later free-production evidence where available.

### 5.10 Pronunciation

Relevant files:

- [lesson_agent_service.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/services/lesson_agent_service.dart)
- [liaison_lesson_screen.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/labs/liaison_lesson_screen.dart)

Already available for liaison:

- audio analysis;
- learner transcript;
- audio clarity;
- word match;
- liaison match;
- confidence;
- feedback;
- lesson score.

Main problems:

- pronunciation is not a unified history;
- most evidence is narrow or temporary;
- rhythm, vowels, nasal vowels, the French r, final consonants, and connected speech are not consistent target types;
- transcript text without audio assessment is not pronunciation evidence.

Required fix:

Use one pronunciation result shape for every pronunciation activity. Audio retention can be optional, but the structured assessment must persist.

### 5.11 Mistakes and corrections

Relevant files:

- [learning_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/learning_store.dart)
- [progress_service.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/services/progress_service.dart)

Already available:

- mistake tags;
- descriptions;
- counts;
- resolved state;
- learner profile summaries;
- writing corrections in some JSON payloads.

Main problem:

Mistake tags are global summaries. They are not reliably tied to the exact attempt, source session, date, target, or correction.

Required fix:

Attach canonical corrections to Practice Attempts. Keep mistake_tags as an aggregate cache for display and quick summaries.

### 5.12 Generated content

Relevant stores include:

- [generated_story_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/generated_story_store.dart)
- [generated_grammar_story_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/generated_grammar_story_store.dart)
- [generated_writing_task_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/generated_writing_task_store.dart)
- [generated_vocabulary_set_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/generated_vocabulary_set_store.dart)
- [generated_roleplay_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/generated_roleplay_store.dart)
- [speaking_lesson_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/speaking_lesson_store.dart)
- [writing_lesson_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/writing_lesson_store.dart)
- [grammar_course_lesson_store.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/database/grammar_course_lesson_store.dart)

Generated content is already saved for caching, resume, offline use, and rendering. The crucial distinction is:

- generated content = what the app offered;
- practice result = what the learner did with it.

The Course builder must not infer mastery from generated content alone.

### 5.13 Existing review context

Relevant files:

- [review_material_service.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/services/review_material_service.dart)
- [fingerprint_engine.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/screens/path/fingerprint_engine.dart)

ReviewMaterialService is close to the desired concept, but it currently relies heavily on summaries and AI notes. It needs selected transcript excerpts and structured results.

FingerprintEngine reads useful sources, but generated lesson content must not count as learner evidence. The pipeline must distinguish “shown”, “attempted”, “correct”, and “produced independently”.

## 6. Canonical data contract

These are conceptual contracts for planning. They can be implemented over existing SQLite tables and stores rather than replacing everything in one migration.

### 6.1 Universal Practice Session

Every Course or Practice experience creates one canonical session.

| Field | Meaning |
|---|---|
| session id | Stable id for the learning event |
| user id | Learner owner |
| source type | Course, standalone, extra, exam, onboarding, review |
| mode | Reading, listening, writing, vocabulary, grammar, speaking, pronunciation, mixed |
| Course lesson-pack id | Nullable link to the integrated lesson |
| Course content key | Nullable compatibility link |
| parent session id | Optional link for extra Practice |
| topic and scenario | Shared situation or practice context |
| goal | User goal at time of practice |
| level at time | CEFR or exam level used |
| profile version | Onboarding snapshot used |
| start and end | Timing |
| completion status | Started, partial, completed, abandoned, failed-to-save |
| duration | Actual learner time |
| content ids | Exact passage, audio, task, deck, lesson, or roleplay shown |
| transcript references | Links to transcript records |
| result references | Links to attempts and skill results |
| summary | Human-readable summary |
| created and updated | Sync and recovery |

The record exists even when the Course link is null.

### 6.2 Universal Practice Attempt

Every answer, utterance, review, or meaningful production becomes an attempt when the activity supports that level of detail.

| Field | Meaning |
|---|---|
| attempt id | Stable result id |
| session id | Parent universal session |
| stage | Reading, listening, writing, speaking, vocabulary, grammar, pronunciation |
| attempt type | Question, dictation, shadowing, free response, card review, drill, roleplay turn |
| target id | Word, phrase, grammar point, pronunciation feature, or skill |
| source content id | Exact item that produced it |
| learner response | Text, selected answer, or transcript reference |
| expected response | Expected answer or rubric reference |
| result | Correct, incorrect, partial, unclear, skipped, unsupported |
| score | Numeric score when meaningful |
| hints and retries | Support used |
| correction | Structured correction |
| feedback | Feedback shown |
| level | Item level at that time |
| timestamp | When it occurred |

Not every speaking turn needs a scored attempt. Every learner turn should remain transcript evidence when capture is enabled.

### 6.3 Transcript record

Provider transcript storage and the canonical learning event must be distinguishable.

Required metadata:

- transcript id;
- canonical session id;
- provider session id;
- speaker role;
- text;
- timestamp or turn order;
- partial or final state;
- language;
- confidence when provided;
- transcript completeness;
- optional target references;
- privacy and retention status.

Full transcripts are stored according to policy. Generation uses selected excerpts.

### 6.4 Pronunciation result

Required fields:

- pronunciation target;
- optional retained audio reference;
- learner transcript;
- audio clarity;
- word match;
- feature match;
- confidence;
- feedback;
- retry count;
- session and attempt links;
- level and context.

Supported feature types should include liaison, rhythm, vowels, nasal vowels, the French r, final consonants, connected speech, and intonation.

### 6.5 Course Lesson Pack

A Course lesson pack is the content delivered to the learner, not only a roadmap title.

| Field | Meaning |
|---|---|
| lesson-pack id | Stable generated lesson id |
| Course content key | Existing routing compatibility |
| unit and sequence | Roadmap position |
| title and theme | Learner-facing context |
| scenario | Shared real-life situation |
| profile version | Profile used |
| source practice ids | Evidence that influenced it |
| level | CEFR or exam level |
| primary/supporting skills | Clear labels |
| review targets | Old words, phrases, grammar, pronunciation, errors |
| new targets | New or harder material |
| exam relevance | Section and task type |
| success criteria | Observable outcomes |
| estimated minutes | Workload |
| stage content | Reading, listening, writing, speaking, vocabulary, grammar, pronunciation |
| generation metadata | Model, prompt version, time, fallback |
| validation status | Passed, repair, rejected |
| status | Planned, available, started, completed, superseded |

The pack stores source ids so the product can explain why it was generated.

### 6.6 Course Lesson Result

Course completion writes a result, not only a content key.

Required:

- lesson-pack id;
- universal session id;
- stage results;
- target attempts;
- transcript references;
- writing submissions;
- reading and listening answers;
- vocabulary grades;
- grammar outcomes;
- pronunciation outcomes;
- completion state;
- learner time;
- next action;
- unresolved targets.

## 7. Universal collection pipeline

This is the dedicated data and teaching pipeline. It is not an orchestration framework.

### Step 0: Read the current learner profile

At session start, read the current profile and attach its version to the new session.

The profile controls goal, level, exam, time budget, preferred skill balance, interests, real-life contexts, and regional preferences. It is context, not performance evidence.

### Step 1: Start one universal session

Before showing content, create the canonical session.

The caller supplies:

- source type;
- mode;
- optional Course lesson-pack id;
- optional Course content key;
- optional parent session id;
- topic or scenario;
- content ids;
- level;
- profile version.

All recorders and Live controllers receive this id.

### Step 2: Freeze delivered content

Save the exact passage, audio reference, writing task, vocabulary deck, grammar items, roleplay context, pronunciation prompt, or exam task shown to the learner.

Historical results must point to the original version even if generated content later changes.

### Step 3: Save live transcript evidence

For Gemini Live:

- create or link the provider AI session;
- save learner and tutor turns continuously where possible;
- save the final transcript on normal end;
- save a partial transcript on interruption where possible;
- record ended reason and completeness;
- associate the transcript with the canonical session.

Transcript capture cannot depend on an optional screen callback being present by accident.

### Step 4: Save structured results

Every skill writes through the universal session:

- reading: answer attempts and difficult-word interactions;
- listening: comprehension, dictation, and shadowing attempts;
- writing: original submission and normalized feedback;
- vocabulary: card reviews and context or sentence results;
- grammar: item answers and corrections;
- speaking: transcript turns, rubric results, and target use;
- pronunciation: structured audio assessment;
- exam Practice: section, task, timing, answer, and rubric result.

### Step 5: Finalize honestly

On normal completion:

- set end time;
- set completion status;
- save summary and stage totals;
- save all known attempts;
- record missing results as unknown;
- link content and transcript records.

On abandonment or failure:

- save partial status;
- preserve captured evidence;
- record the reason;
- never convert partial work into success.

### Step 6: Normalize evidence

Extract:

- targets seen;
- targets recalled;
- targets produced;
- targets produced without support;
- incorrect targets;
- repeated mistakes;
- new corrections;
- pronunciation features;
- topics and contexts;
- practiced skills;
- exam sections;
- level and difficulty reaction.

This can begin with deterministic extraction plus structured model output from existing feedback. It does not need a complex learner model.

### Step 7: Update aggregate views

Update target state, SRS due date and interval, mistake counts, skill activity balance, recent topics, exam summary, and Course display progress.

Aggregates are derived views. Canonical attempts remain the source of truth.

### Step 8: Build or refresh the snapshot

Rebuild before the first block, after enough new evidence, after a profile change, when the block is nearly consumed, or when the learner requests a refresh.

## 8. Recent Practice Snapshot

The snapshot is compact, explainable, and source-balanced.

### 8.1 Include

Current profile:

- goal;
- level;
- exam target;
- time budget;
- preferred skills;
- interests;
- current profile version.

Recent activity:

- latest 10 to 20 meaningful sessions;
- structured results from the latest 14 days by default;
- all due and recently failed vocabulary cards;
- unresolved writing and grammar corrections;
- recent pronunciation weaknesses;
- recent listening and reading misses;
- recent Course lessons and results;
- recent standalone Practice results;
- recent exam tasks;
- recent Gemini Live learner transcript excerpts;
- recently used topics and phrases.

Learning state:

- target state;
- evidence count;
- last seen time;
- last independent success;
- last failure;
- hint or retry dependence;
- skill coverage;
- source coverage;
- current level;
- next review time.

Generation constraints:

- lesson length;
- level range;
- required skill labels;
- 60/40 target mix;
- exam requirements;
- topics to avoid repeating immediately;
- content already planned in the current block.

### 8.2 Exclude from the prompt

Do not send:

- the entire account transcript;
- every generated lesson ever created;
- stale summaries with no current relevance;
- raw audio unless a pronunciation evaluator needs it;
- private profile fields unrelated to teaching;
- content that was shown but never attempted.

The account can retain complete history according to policy. The snapshot selects useful evidence.

### 8.3 Evidence priority

Select in this order:

1. recent failed or uncertain attempts;
2. due or failed SRS items;
3. repeated corrections across sessions;
4. recent learner-produced transcript phrases;
5. pronunciation feedback;
6. listening and reading misses;
7. recent Course results;
8. introduced targets not yet independently used;
9. goal and exam requirements;
10. new curriculum material at the learner's level.

Course results are not automatically more important than Practice results. Recency, weakness, due status, and relevance decide.

### 8.4 Transcript selection

Store the full transcript according to retention rules. For generation, select:

- learner lines containing target phrases;
- recent lines with corrections;
- repeated hesitation or repair patterns;
- lines connected to the goal or current topic;
- one or two successful examples for contrast;
- pronunciation-related turns when structured assessment exists.

Every excerpt is labeled learner-produced or tutor-provided, corrected or uncorrected, successful or uncertain, source session, date, skill, and target references.

This prevents the model from mistaking a tutor sentence for learner knowledge.

## 9. Target states and evidence rules

Use three simple states for vocabulary, useful phrases, grammar, and pronunciation.

### New

The learner has not meaningfully practiced the target, or has only seen it in generated content.

Evidence that does not move a target out of New:

- the target appeared in a story;
- the tutor said it;
- the target was listed in a vocabulary deck;
- the learner opened a translation without attempting it.

### Practicing

The learner has attempted the target but is inconsistent, needed help, or used it in only one activity.

Examples:

- recalled it with a hint;
- answered correctly once but failed later;
- recognized it while reading but could not produce it;
- used the phrase with grammar errors;
- had unclear pronunciation;
- corrected writing once but did not revise independently.

### Comfortable

A target moves to Comfortable only after meaningful repeated evidence:

- at least three successful uses or recalls;
- across at least two activities or modalities;
- at least one unaided production;
- no unresolved severe correction on the target;
- preferably one delayed or later-session success.

If a learner has only seen a target in the Course, it is not Comfortable.

### Difficulty reaction

| Result | Next response |
|---|---|
| Poor or unclear, below roughly 50% | Repeat the same target with simpler language, stronger scaffolding, and a shorter task |
| Mixed, roughly 50% to 80% | Keep the target, change the situation or skill, and reduce support slightly |
| Strong, above roughly 80% without hints | Add a small extension, maintain spaced review, and introduce a related target |

These are starting thresholds, not scientific claims. The result also considers task difficulty, hints, time pressure, and whether the learner produced language or only recognized it.

## 10. Personal Course Builder

The Personal Course Builder has four responsibilities:

1. select targets;
2. select the curriculum position;
3. create a coherent shared theme;
4. produce and validate integrated packs.

It does not run the learner's entire account and does not decide every UI action.

### 10.1 Inputs

The builder receives:

- current profile;
- current Course unit and sequence;
- completed Course lesson results;
- Recent Practice Snapshot;
- target metadata;
- exam blueprint and required sections where relevant;
- lesson length;
- current block themes and targets;
- supported generators and fallback templates.

### 10.2 Target selection

For each lesson, select:

- two to four old targets for repetition;
- one weak target or repeated mistake;
- one to two new or extension targets;
- one grammar or pronunciation focus when supported;
- one primary skill;
- one or two supporting skills.

Short beginner sessions may use fewer targets. Quality and successful use matter more than a fixed word count.

Repetition priority:

1. failed targets;
2. due targets;
3. repeated corrections;
4. targets used with heavy support;
5. recent targets that have not transferred across skills;
6. recently learned targets needing delayed review.

New-material priority:

1. the next curriculum concept;
2. the learner's goal and real-life context;
3. exam relevance;
4. a natural extension of a repeated target;
5. a level-appropriate phrase needed to complete the theme.

### 10.3 The twenty-lesson block

Every visible block has twenty roadmap items and a plan for the full block.

| Lessons | Main purpose | Typical target mix |
|---|---|---|
| 1–4 | Re-entry and repair | Recent weak targets plus small extensions |
| 5–8 | Transfer | Same targets in different skill combinations |
| 9–12 | Delayed retrieval | Earlier targets with less support |
| 13–16 | Expansion | New material connected to stable targets |
| 17–19 | Integration | Mixed-skill and real-world use |
| 20 | Demonstration and checkpoint | Independent, exam-style, or goal-specific task |

This is a suggested rhythm, not a rigid script. If the snapshot shows serious weakness, more of the block can be repetition-led. The block must still visibly progress.

Create twenty full lesson briefs and enough saved content to make each lesson stable. If generation cost or network reliability requires batching, generate and validate groups of five, but never expose an unvalidated lesson as ready.

### 10.4 Integrated theme pack

Each lesson has one shared semantic anchor:

- real-life situation;
- location or relationship;
- learner objective;
- target vocabulary and phrases;
- grammar focus;
- pronunciation focus;
- difficulty;
- exam task type where relevant.

Every stage uses the anchor:

1. warm-up and review;
2. vocabulary in context;
3. reading;
4. listening;
5. writing;
6. speaking;
7. pronunciation;
8. quick retrieval check.

A short session may omit a stage, but the pack still knows how the stage connects. The learner should not receive unrelated reading, writing, and speaking topics without an intentional transition.

### 10.5 Personalization requirements

Each generated lesson must answer:

- What recent learner evidence caused this lesson to exist?
- Which old targets are being repeated?
- Which mistake is being repaired?
- What is genuinely new?
- Why is the level appropriate?
- How does the lesson fit the goal or exam?
- Which skills are primary and supporting?
- What counts as success?
- What gets saved when the learner finishes?

The saved pack includes source practice ids and target ids so personalization can be inspected later.

## 11. Course and Practice balance

Equal weight does not mean equal frequency. It means no source is discarded.

### Course-only learner

Course sessions create evidence through:

- stage results;
- writing;
- vocabulary;
- transcripts;
- pronunciation;
- reading and listening answers.

The next block uses those results. A completed Course lesson with no detailed results is a storage defect, not assumed mastery.

### Practice-heavy learner

Standalone Practice writes to the same records. The next Course block can:

- reuse failed targets;
- recognize strong speaking activity;
- add reading if the learner has avoided it;
- turn a Live conversation into a writing or listening lesson;
- adapt difficulty from repeated performance.

### Single-skill learner

A learner who mostly practices reading or listening receives personalization from that evidence. The Course can respect the preference while keeping balanced progression:

- emphasize the preferred skill in supporting stages;
- use a strong skill as a bridge into weaker skills;
- introduce small related tasks in neglected modes;
- never infer speaking mastery from reading recognition.

### Extra Practice after Course

Extra Practice can link to a Course lesson or target set. If it has no link, it still counts as standalone evidence. The builder reads both direct Course evidence and related Practice evidence.

### Exam-focused learner

Exam Practice is both learning evidence and a goal constraint. It influences:

- target vocabulary;
- grammar and register;
- timed listening and reading;
- writing task types;
- speaking prompts;
- block checkpoints.

Official exam requirements and scoring rules should be versioned metadata and verified separately from generated lessons.

## 12. Course regeneration rules

### First block

After onboarding:

1. save the current profile version;
2. create an initial snapshot;
3. identify known level and unknowns;
4. generate twenty integrated lesson briefs;
5. validate every brief;
6. generate lesson content in batches if needed;
7. validate content;
8. save the block and source evidence;
9. expose the roadmap.

If onboarding evidence is limited, the first block can be more diagnostic, but it must still teach useful French. It must not become twenty tests.

### During a block

Do not regenerate a lesson the learner has started unless there is a critical defect.

Refresh unstarted lessons when:

- the learner completes enough new Practice evidence;
- the learner repeatedly struggles;
- the profile changes;
- the exam or goal changes;
- a generated pack fails validation;
- the current block reaches its refresh threshold.

Recommended refresh trigger:

- after every five meaningful sessions; or
- when fewer than five validated lessons remain.

The trigger is a product setting, not an architectural dependency.

### Next block

When the next block is needed:

1. close the previous block's result aggregation;
2. build a new snapshot;
3. carry forward unresolved targets;
4. carry forward due spaced-review targets;
5. advance curriculum position only where evidence supports it;
6. apply the 60/40 mix;
7. generate and validate the new twenty lessons.

A learner who practiced heavily outside the Course should see that work reflected even if they completed few Course lessons.

## 13. Pre-generation checks

Before generating a block or lesson pack, produce an internal pre-check result.

### Data-source check

Confirm:

- current profile loaded;
- profile version attached;
- Course history loaded;
- standalone Practice history loaded;
- Gemini Live transcripts included when available;
- exam results included when relevant;
- SRS due and failed items included;
- writing, reading, listening, grammar, speaking, and pronunciation results included;
- missing data is labeled rather than silently assumed.

### Evidence check

Confirm that the snapshot distinguishes:

- content shown;
- content attempted;
- content correct;
- content produced;
- content produced independently;
- content corrected;
- content due for review.

### Repetition check

Confirm:

- approximately 60% repetition or transfer;
- approximately 40% new or extension;
- difficult targets are not forgotten;
- new targets are not above the allowed level jump;
- no target repeats in the same prompt pattern too many times.

### Level check

Confirm:

- every target has level metadata;
- every activity has level metadata;
- level is consistent with the learner's current band;
- a strong result justifies only a small step up;
- a weak result causes support or repetition;
- exam material is labeled separately from CEFR difficulty.

### Integration check

Confirm:

- every stage has the same theme and target set;
- reading and listening refer to the same situation;
- writing asks for relevant language;
- speaking gives a realistic reason to use it;
- pronunciation targets a phrase from the lesson;
- grammar supports the intended production;
- the lesson has a concrete success criterion.

### Quality and safety check

Confirm:

- no unsupported claim about the learner;
- no tutor sentence is labeled learner knowledge;
- output is appropriate for the level;
- answer keys are valid;
- audio and transcript references exist;
- no duplicate lesson is accidentally generated;
- content is culturally and contextually appropriate;
- private data unrelated to teaching is excluded.

### Persistence check

Before marking a lesson ready:

- save the lesson pack;
- save all stage content references;
- save target ids;
- save source practice ids;
- save profile version;
- save validation status;
- verify the pack can reopen after reload or offline restoration.

### Example pre-check output

    Sources: 4 Course sessions, 7 standalone Practice sessions,
    3 Gemini Live transcripts, 12 vocabulary reviews, 2 writing
    submissions, 1 listening result, 1 pronunciation result.

    Repetition: 12 of 20 lessons.
    New or extension: 8 of 20 lessons.
    Main repairs: gender agreement, past-tense auxiliary choice,
    final consonant clarity.
    Reused contexts: work, housing, daily scheduling.
    New context: an apartment viewing.
    Level: A2 content with controlled B1 extension.
    Status: ready for generation.

This report is useful for developer QA and future learner-facing explanations.

## 14. Post-session result checks

After every lesson or Practice session, run a result check.

### Required checks

Confirm:

- canonical session id exists;
- source type exists;
- Course link is present when applicable;
- content shown is stored;
- learner answer or transcript is stored;
- result and score are stored when measurable;
- hints and retries are stored when available;
- corrections are stored;
- pronunciation result is stored when used;
- stage completion is stored;
- partial or failed state is represented honestly;
- target state updates occurred;
- SRS updates occurred where relevant;
- the next snapshot can find the new evidence.

### Missing-data behavior

If a required result is missing:

- mark the stage partial or unknown;
- do not claim success;
- keep the session available for recovery;
- log the missing field and source screen;
- retry persistence where safe;
- allow the learner to continue without corrupting mastery state.

### Result summary for the next lesson

The next builder must see:

- what the learner successfully did;
- what they struggled with;
- what support was needed;
- what they produced independently;
- what should be repeated;
- what can be made harder;
- what remains unknown because data was not captured.

## 15. Storage implementation strategy

The safest path is an additive canonical layer.

### Keep existing stores

Keep current stores for:

- UI resume state;
- SRS scheduling;
- generated-content caching;
- DailySession;
- current Course display;
- synchronization compatibility.

Do not throw away working vocabulary or generated-content persistence.

### Add universal records

Add a small canonical layer for:

- universal practice sessions;
- practice attempts;
- transcript links and completeness;
- skill results;
- target evidence;
- lesson-pack source links;
- Course lesson results.

Existing screens can write both their local/domain-specific store and the canonical universal record. The migration can consolidate duplicate fields later, after behavior is proven.

### Link, do not duplicate blindly

The same Gemini Live transcript may currently exist in ai_sessions and normal messages. The universal layer should reference the provider transcript and avoid creating two independent histories.

When duplicate records are unavoidable:

- store canonical session id;
- store provider record ids;
- mark the relationship;
- deduplicate while building the snapshot.

### Sync and recovery

Every canonical record needs:

- local id;
- updated time;
- deletion or tombstone behavior consistent with existing sync;
- retry state;
- stable serialization;
- migration coverage;
- hydration coverage.

An activity that exists only on the device and disappears after reload cannot personalize the next Course block reliably.

## 16. Level and curriculum metadata

Current repository support includes:

- A1, A2, B1, and B2 policies in [vocabulary_level_policy.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/services/vocabulary_level_policy.dart);
- explicit A1/A2/B1/B2 guidance in [live_prompts.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/prompts/live_prompts.dart);
- grammar levels and validation in [grammar_curriculum_catalog.dart](/Users/thoufeekx/Desktop/Millionaire/FrenchTutor/flutter_app/lib/data/grammar_curriculum_catalog.dart).

Every target and content item used by the pipeline should have:

- target id and type;
- CEFR level;
- skill or modality;
- topic and context;
- grammar relation;
- pronunciation relation;
- exam relevance;
- prerequisite targets;
- difficulty;
- source content id;
- introduction status;
- version.

Historical records preserve the level used at the time. A future catalog update must not rewrite an old result.

The profile level is the starting band. Recent evidence can support a controlled extension within or just above the band. One good answer must not cause an uncontrolled jump.

## 17. AI generation contract

All AI-generated lessons and targeted Practice use the same snapshot contract.

Generation input:

- learner profile;
- current Course position;
- target list with states;
- recent evidence;
- selected transcript excerpts;
- repeated mistakes;
- recent successful examples;
- exam constraints;
- requested skill balance;
- 60/40 block position;
- lesson theme;
- content already used in the block;
- output schema;
- validation rules.

Generation output:

- lesson theme and scenario;
- primary and supporting skills;
- review targets;
- new targets;
- level;
- stage content;
- answer keys or rubrics;
- pronunciation target;
- success criteria;
- source evidence references;
- warnings or uncertainty;
- generation version.

Reject or repair output when:

- stages use unrelated topics;
- targets are missing or above the allowed level;
- answer keys are ambiguous;
- the lesson contains only new material;
- repetition has no meaningful transfer task;
- source evidence is not attached;
- required content cannot be saved.

## 18. How existing teaching engines fit

The engines remain responsible for teaching quality in their own modality:

- reading creates and evaluates reading content;
- listening creates audio, questions, dictation, and shadowing;
- writing creates tasks and feedback;
- vocabulary manages cards and SRS;
- grammar creates explanation and practice;
- speaking runs roleplay or conversation;
- pronunciation evaluates sound production.

The Universal Learning Data Pipeline is responsible for:

- starting and linking sessions;
- collecting results;
- normalizing evidence;
- building the snapshot;
- selecting shared lesson targets;
- supplying the common theme;
- saving the Lesson Pack;
- validating the result;
- feeding the next generation.

This division avoids rebuilding the parts that already know how to teach.

## 19. Course UI contract

Keep the roadmap simple and visible:

- twenty lesson cards per block;
- unit and sequence labels;
- level label;
- primary skill label;
- supporting skill labels;
- theme or real-life outcome;
- status: upcoming, ready, in progress, complete;
- optional “built from your recent Practice” explanation;
- clear checkpoint at the end of the block.

The UI does not need to show every internal score. It should show enough to make personalization believable:

- what the learner is practicing;
- why the topic is relevant;
- which skills are included;
- what was carried forward;
- what comes next.

After standalone Practice, the Course can show a message such as:

    Your recent conversation practice will be used in your next Course lessons.

Show this only when the canonical record and snapshot contain that evidence.

## 20. Rollout plan

### Phase 0: Storage audit and fixtures

Document every current screen that creates a session, transcript, writing submission, reading result, listening result, vocabulary review, grammar result, pronunciation result, or Course completion.

Create fixtures for:

- Course-only;
- Practice-heavy;
- reading-heavy;
- listening-heavy;
- writing-heavy;
- exam-focused;
- Live-conversation-heavy.

Acceptance:

- every data path is identified;
- each fixture has representative stored data;
- missing fields are visible.

### Phase 1: Canonical session and attempt records

Add the universal session and attempt contracts. Update SessionRecorder and Live start/end flows to receive canonical ids and Course links.

Acceptance:

- every new Course session writes one universal session;
- every standalone Practice session writes one universal session;
- extra Practice can link to a parent Course session;
- provider-specific records link to the universal session.

### Phase 2: Transcript reliability

Unify full-screen and inline Gemini Live persistence. Audit every callback path. Add partial transcript and completeness handling.

Acceptance:

- every Live screen is findable by universal session id;
- learner and tutor turns are distinguishable;
- interrupted calls retain partial evidence when available;
- duplicate transcript records can be deduplicated.

### Phase 3: Structured skill results

Write item-level results for reading, listening, writing, vocabulary, grammar, speaking, pronunciation, and exam Practice.

Acceptance:

- each mode has a structured result contract;
- scores are not the only evidence;
- corrections and retries are available;
- missing data is marked unknown.

### Phase 4: Recent Practice Snapshot

Extend ReviewMaterialService or replace its internals with the universal snapshot reader. Keep its responsibility simple: return a compact, source-balanced learner snapshot.

Acceptance:

- Course and standalone Practice have equal access;
- transcript excerpts and structured results are included;
- generated content is not counted as learner evidence;
- every snapshot item is explainable by source ids.

### Phase 5: Integrated Personal Course Builder

Replace the legacy Course source with lesson-pack generation driven by the snapshot and curriculum position.

Acceptance:

- twenty visible lessons are generated per block;
- twelve are repetition-led and eight expansion-led by default;
- every lesson has a shared theme;
- every stage uses the selected targets;
- source practice ids are stored;
- each pack passes pre-checks before exposure.

### Phase 6: Course and Practice write-back

Make Course and standalone Practice screens write Course-relevant evidence through the canonical layer.

Acceptance:

- Course-only users get a different next block after meaningful results;
- Practice-heavy users get a different next block after meaningful results;
- extra Practice influences relevant future lessons;
- onboarding changes refresh only future unstarted content.

### Phase 7: Quality and exam readiness

Build regression tests, synthetic learner comparisons, persistence-failure tests, and exam blueprint checks.

Acceptance:

- lessons remain coherent over multiple blocks;
- repetition is measurable;
- level changes are controlled;
- exam requirements are versioned and inspectable;
- missing storage paths never silently create false mastery.

## 21. Test matrix

### Scenario A: Course-only learner

Input:

- completes Course lessons;
- makes repeated grammar and pronunciation mistakes;
- does not use standalone Practice.

Expected:

- the next block repeats those mistakes in new contexts;
- Course results are enough to personalize;
- the next block is not a generic copy of the previous one.

### Scenario B: Practice-heavy learner

Input:

- completes several Gemini Live conversations;
- does vocabulary and writing Practice;
- completes few Course lessons.

Expected:

- Live transcript excerpts, corrections, vocabulary results, and writing feedback appear in the snapshot;
- the next Course block reflects those sessions;
- Course progress and Practice history remain separate in the UI but connected in learning data.

### Scenario C: Reading specialist

Input:

- completes many reading stories;
- has strong reading comprehension;
- has little speaking evidence.

Expected:

- reading strengths are recognized;
- Course uses reading topics to bridge into speaking and writing;
- the system does not infer speaking mastery.

### Scenario D: Listening and Live specialist

Input:

- frequent Live conversations and listening;
- repeated difficulty with fast speech and connected pronunciation.

Expected:

- future lessons include a slower-to-natural listening progression;
- transcript corrections and pronunciation evidence are repeated;
- speaking, reading, and writing use the same phrases.

### Scenario E: Extra Practice after Course

Input:

- completes a housing Course lesson;
- later performs a housing roleplay and writes a landlord message.

Expected:

- both activities influence future housing and communication targets;
- extra Practice is not ignored because it happened outside the Course.

### Scenario F: Exam learner

Input:

- target exam and date are in the profile;
- exam reading and speaking results are available.

Expected:

- future blocks include relevant exam sections;
- weak sections receive more repetition;
- everyday French remains connected to exam tasks.

### Scenario G: Interrupted Live session

Input:

- Live call ends due to network failure after several learner turns.

Expected:

- partial transcript and ended reason are saved;
- the session is partial, not complete;
- usable transcript evidence can influence a future snapshot;
- missing pronunciation or score fields remain unknown.

### Scenario H: Onboarding change

Input:

- learner changes goal, level estimate, or exam target.

Expected:

- completed history remains unchanged;
- future unstarted packs are rebuilt with the new profile version;
- the current in-progress pack remains stable;
- the snapshot combines the new profile with historical evidence.

### Scenario I: Two-learner comparison

Input:

- two learners have the same starting level;
- one struggles with past tense;
- one struggles with listening speed.

Expected:

- their next blocks have different repeated targets, themes, and supporting activities;
- both still follow the same visible Course structure.

## 22. Observability and developer checks

For every generated block, log or persist enough metadata to answer:

- which profile version was used;
- which sessions were included;
- which transcript excerpts were selected;
- which targets were classified as weak;
- how many lessons were repetition-led;
- how many were expansion-led;
- which generator created each stage;
- which validation checks passed;
- whether output was repaired or used a fallback;
- which results were saved after delivery.

Useful internal counters:

- universal sessions created by source;
- sessions with missing Course links;
- Live sessions with incomplete transcripts;
- attempts saved by skill;
- result records missing expected fields;
- generated packs rejected by validation;
- packs whose next block changed after Practice;
- targets incorrectly marked Comfortable.

The pipeline should be debuggable from one lesson-pack id back to:

    lesson pack
      -> source practice ids
        -> universal sessions
          -> attempts and transcripts
            -> target evidence and corrections

## 23. Definition of done

The replacement Course system is ready when all of the following are true:

- every new Course session is saved as a universal session;
- every new standalone Practice session is saved the same way;
- Course links are present when applicable and nullable otherwise;
- Gemini Live transcripts are saved and linked;
- partial Live sessions are represented honestly;
- reading, listening, writing, vocabulary, grammar, speaking, pronunciation, and exam results are structured;
- the snapshot contains recent Course and Practice evidence;
- full history is retained while prompts remain compact;
- the builder uses current onboarding data;
- profile changes refresh future unstarted content;
- every twenty-lesson block visibly progresses;
- the default block mix is 60% repetition and 40% new or extension;
- every lesson is one connected theme pack;
- every lesson has skill labels and success criteria;
- target states are New, Practicing, or Comfortable;
- completion does not automatically mean mastery;
- each generated pack records why it was selected;
- pre-checks run before exposure;
- post-session checks confirm what was saved;
- Course-only and Practice-heavy learners receive different next blocks when evidence differs;
- the existing teaching engines remain reusable;
- no orchestration dependency is required.

## 24. Recommended first implementation decisions

1. Add the canonical universal session and attempt layer before changing the Course generator.
2. Make SessionRecorder and all Live flows accept the universal session id and optional Course lesson-pack id.
3. Fix transcript persistence gaps before using Live data for personalization.
4. Normalize per-item results for vocabulary, reading, listening, writing, grammar, and speaking first. Add pronunciation and exam-specific fields in the same contract.
5. Extend ReviewMaterialService into the Recent Practice Snapshot reader instead of creating a disconnected context system.
6. Replace the legacy Course generator with a Personal Course Builder that creates integrated theme packs.
7. Generate twenty lessons per block, but refresh only future unstarted lessons when new evidence arrives.
8. Use 60% repetition and 40% new or extension as the default. The pre-check can increase repetition when the learner is struggling.
9. Store source practice ids and target ids on every lesson pack.
10. Build the test fixtures before declaring the pipeline personalized.

The simple product story is therefore true and technically defensible:

> The learner's onboarding profile starts the path. Every Course and Practice session then adds saved evidence. The app selects useful recent evidence, repeats what is weak, introduces a controlled amount of new French, and generates the next connected lessons.

## 25. Repository implementation plan

The implementation should be delivered as a vertical slice rather than a
large rewrite.

### Step 1: Build the universal snapshot reader

Create one service that reads the existing local sources:

- current profile;
- recent completed Course and Practice sessions;
- normal session messages;
- Gemini Live transcripts;
- writing submissions and feedback;
- vocabulary reviews and due cards;
- lesson progress;
- mistake tags;
- exam Practice summaries;
- recent topics and stages.

The service returns both structured fields and a bounded prompt context. It
must preserve source ids and timestamps so the Course builder can explain why
a lesson was selected.

### Step 2: Make the adaptive Course generator consume the snapshot

The adaptive Course generator keeps its visible roadmap structure, units, and
twenty-session blocks, but receives the snapshot as an input.

For every new block it selects:

- weak or failed targets;
- due vocabulary;
- recent learner-produced phrases;
- recent writing corrections;
- pronunciation or listening weaknesses;
- exam requirements;
- a controlled amount of new curriculum material.

The Course path must not prefer Course history over standalone Practice.

### Step 3: Persist shared targets on each Course session

Each adaptive Course session needs durable target phrases and evidence links.
The current title and context are not enough for the downstream speaking,
writing, vocabulary, and roleplay screens.

Unstarted sessions may be refreshed. Started or completed sessions keep their
historical specification.

### Step 4: Add validation and targeted repair boundaries

The generation pipeline should use:

1. deterministic schema and persistence checks;
2. lightweight qualitative checks for level, theme coherence, repetition, and
   answer quality;
3. a targeted repair request containing only the failed JSON path, relevant
   lesson context, and the validator findings;
4. a final full-pack check.

Repair only the failed stage or field. Do not redo the entire lesson unless
the shared lesson specification itself is invalid. Limit repair attempts and
fall back safely when a repair remains invalid.

### Step 5: Wire result write-back

Course and Practice must both write results through the existing session and
content keys. The next snapshot should find:

- Course completion;
- the actual Practice session;
- learner/tutor transcript turns;
- writing and exam results;
- SRS grades;
- corrections and pronunciation feedback.

This step can be additive first. Existing domain stores remain responsible for
their current UI behavior while the universal layer becomes the Course input.

### Step 6: Verify two different learners

Before pushing, test at least:

- a Course-only learner with grammar mistakes;
- a Practice-heavy learner with Live transcripts and writing feedback.

The Course roadmap structure should be the same, but their future contexts,
targets, supporting skills, and repetition choices must differ.

### Delivery boundary

The first code delivery should make the Course path genuinely data-driven
without pretending that every rich content engine is already fully normalized.
The universal snapshot and Course linkage come first. Rich lesson-pack
generation and multi-model repair can then be added behind the same contract
without changing the Course UI again.
