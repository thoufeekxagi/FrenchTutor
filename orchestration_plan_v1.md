# ParleSprint Orchestration Plan v1

Status: Approved implementation plan
Owner: ParleSprint founding team
Primary app: `flutter_app/`
Backend location: evolve `server/` into the authenticated learning control plane
Related plan: `PILOT_PLAN.md`

## 0. Purpose

This document is the implementation source of truth for ParleSprint's learning orchestration system. It defines what to build, in what order, how the components interact, what not to build yet, and how a future developer or coding agent should resume work safely.

The product thesis is:

> ParleSprint maintains a living, evidence-based map of a learner's French and turns each attempt, hesitation, correction, and success into the next best practice.

The MVP is successful when this statement is demonstrably true:

> What the learner did yesterday visibly and correctly changes what ParleSprint asks them to do today.

This is not a plan for either an unconstrained AI tutor or a permanently fixed rule engine. It is a plan for a governed neuro-symbolic adaptive system: symbolic competency and policy constraints, probabilistic learner-state estimation, outcome-learning task policies, and generative AI where language intelligence creates value.

## 1. Non-negotiable product principles

1. The governed orchestration system owns authoritative learner state and policy enforcement. Specialized probabilistic models estimate mastery and retention; adaptive policies and LLMs may propose plans, classifications, feedback, and content. Only schema-valid, policy-compliant decisions are committed.
2. ParleSprint is adaptive, not merely deterministic. Learner-state estimates are probabilistic, uncertainty is explicit, and task-selection policies may learn from outcomes while remaining inside pedagogical, safety, privacy, time, and cost constraints.
3. The LLM is a semantic reasoning and teaching layer, not the sole learner model. Its outputs are evidence or proposals with provenance and confidence, not unquestioned truth.
4. Credits, entitlements, identity, hard prerequisites, privacy controls, persisted plan versions, and progress claims remain server- or application-authoritative.
5. LLM calls return bounded, schema-validated language outputs. They never write directly to learner-state tables.
6. Progress is based on evidence, not lesson completion, time spent, streaks, or a single model judgment.
7. Mastery and confidence are separate. Sparse evidence must display as `more evidence needed`, not a precise score.
8. Recognition, cued recall, guided production, unaided production, and spontaneous transfer are different evidence strengths.
9. Vocabulary and grammar are knowledge domains. Listening, reading, writing, and speaking are performance modes. Pronunciation is cross-cutting.
10. One competency may have different states by modality. Reading knowledge does not prove spontaneous speaking ability.
11. Plans are immutable snapshots once started. Replanning is explicit and recorded.
12. Every required task has a machine-readable reason code and a learner-readable explanation.
13. AI failure must not block authored lessons, local review, plan display, resumption, or honest progress recording.
14. No official NCLC, TEF, or TCF score prediction is shown in v1.
15. No claim of affiliation with IRCC, TEF, TCF, CCI Paris, France Éducation international, or Alliance Française is permitted without a real agreement.
16. No permanent AI provider key may ship in the production client.
17. Raw audio is not retained by default. Transcript and AI-processing behavior must be disclosed.
18. Do not create separate courses for each persona. Personas configure scheduling policies around one competency graph.

### 1.1 State-of-the-art architecture decision

As of July 2026, there is no mature reusable learner-digital-twin framework that should be adopted wholesale. ParleSprint will compose proven components:

- a CASE-inspired competency graph with stable identifiers and prerequisite relationships;
- a Caliper/xAPI-inspired append-only learning evidence ledger;
- contextual Bayesian Knowledge Tracing for lightweight online competency beliefs;
- a swappable memory scheduler for vocabulary, with the current SRS benchmarked against FSRS before replacement;
- authored difficulty initially, with IRT/Rasch calibration only after sufficient cross-learner item data exists;
- a constrained utility policy for cold start;
- a contextual bandit operating in shadow mode before it may influence live selection;
- an LLM proposal layer for semantic evidence extraction, coherent sequencing, explanations, feedback, and content variation;
- a deterministic reference-monitor/control layer that validates every proposed state-changing action.

Deep and transformer knowledge-tracing models such as DKT, SAKT, AKT, ReKT, and successors are research candidates only after ParleSprint has enough proprietary interaction data to compare them against the lightweight baseline using calibration, learning outcomes, cost, and interpretability—not predictive AUC alone.

Standalone LLM knowledge tracing is not authoritative in v1. Current long-term tutoring benchmarks show that LLMs can extract historical evidence well while remaining unreliable at longitudinal knowledge diagnosis and adaptive teaching action. LLM-enhanced or LLM-integrated knowledge tracing remains an experiment behind the same evidence, policy, and validation boundaries.

## 2. Initial target learner and scope

### 2.1 Primary MVP learner

A serious A2 or lower-B1 learner with a Canadian goal who:

- studies approximately 45 to 180 minutes on a typical day;
- currently combines disconnected apps, videos, tutors, or exam resources;
- needs stronger productive French, not only recognition;
- wants to understand what to practise next and why;
- may not yet be ready for exam-only preparation.

A0, A1, advanced B1, and B2 learners may participate in testing, but the MVP must not claim complete coverage for them.

### 2.2 MVP curriculum boundary

Prove the complete learning loop using a narrow, deep curriculum slice:

- two or three practical themes;
- a controlled vocabulary set;
- a small set of grammar competencies;
- associated pronunciation targets;
- authored listening and reading items;
- micro-writing tasks;
- targeted Gemini Live speaking tasks;
- correction, retry, delayed review, and cross-modal transfer.

Do not expand to broad A0-B2 content until the loop works reliably.

### 2.3 Out of scope for v1

- full timed TEF/TCF mock exams;
- official-looking NCLC score estimates;
- tutor marketplace;
- social feeds or leaderboards;
- advanced predictive machine learning;
- automatic pronunciation percentages;
- unlimited live voice;
- fully generated curriculum without human review;
- inferred learning styles or personality labels;
- inferred emotional diagnoses from voice or behavior;
- microservices;
- six independent persona pathways.

## 3. Existing architecture to preserve

The current code already contains valuable foundations. Future implementation must extend rather than casually replace them.

### 3.1 Preserve

- `flutter_app/lib/flow/pathway_coordinator.dart`: single-owner navigation and completion semantics.
- `flutter_app/lib/flow/stage_outcome.dart`: typed evidence returned from stages.
- `flutter_app/lib/models/daily_session.dart`: resumable daily state.
- `flutter_app/lib/data/database/app_migrations.dart`: forward-only migrations, UUIDs, append-only history.
- `flutter_app/lib/data/database/learning_store.dart`: local-first persistence boundary.
- `flutter_app/lib/services/srs_service.dart`: vocabulary review scheduling.
- `flutter_app/lib/services/gemini_live_service.dart`: low-latency voice transport and validated tool-call pattern.
- `flutter_app/lib/services/audio_streaming_service.dart`: audio capture/playback behavior.
- `flutter_app/lib/services/lesson_agent_service.dart`: language-task use cases, but production requests must move behind the backend.
- `flutter_app/lib/data/content_service.dart`: authored curriculum loading during MVP.
- `flutter_app/lib/data/database/pilot_infrastructure_store.dart`: installation, entitlement cache, outbox, and privacy-safe operational events.

### 3.2 Replace or evolve

- Replace fixed daily stage ordering with a generated `LearningPlan` containing required and optional tasks.
- Replace completion-based skill percentages with competency evidence summaries.
- Replace broad profile levels with diagnostic evidence and confidence.
- Evolve mistake counters into append-only error events.
- Evolve client-direct text AI calls into authenticated backend calls.
- Replace permanent Gemini Live client keys with backend-minted ephemeral tokens.
- Evolve local advisory credits into server-authoritative usage.
- Evolve the legacy `server/` voice tutor into the learning control plane; do not maintain two sources of truth.

## 4. Domain model

### 4.1 Competency dimensions

Use two dimensions.

Knowledge and competency types:

- `lexical`: words, expressions, collocations;
- `grammar`: forms and sentence structures;
- `phonology`: sound distinctions, rhythm, liaison, pronunciation targets;
- `function`: communicative functions such as introducing, requesting, comparing, and explaining;
- `discourse`: coherence, connectors, paragraph and spoken-response organization;
- `strategy`: comprehension, repair, planning, and later exam-task strategies.

Performance modalities:

- `listening_recognition`;
- `reading_recognition`;
- `controlled_writing`;
- `spontaneous_writing`;
- `controlled_speaking`;
- `spontaneous_speaking`;
- `pronunciation_production`.

Support levels:

- `recognition`;
- `cued_recall`;
- `hinted_production`;
- `unaided_production`;
- `spontaneous_transfer`.

### 4.2 Required Dart models

Create domain models under `flutter_app/lib/orchestration/models/`:

- `competency.dart`
- `content_descriptor.dart`
- `evidence_event.dart`
- `error_event.dart`
- `competency_state.dart`
- `learning_plan.dart`
- `plan_task.dart`
- `planning_context.dart`
- `plan_reason.dart`
- `assessment_snapshot.dart`

Models must be pure data structures. UI dependencies are prohibited.

### 4.3 Competency

Required fields:

```text
id
kind
title
description
difficultyBand
prerequisiteIds
targetLevelLabel
examRelevance
curriculumVersion
```

Example identifiers:

```text
lex_professional_intro_01
grammar_present_etre
grammar_present_travailler
phonology_french_r_basic
function_introduce_professionally
discourse_give_reason_basic
strategy_listening_numbers_dates
```

IDs are stable curriculum identifiers. Never derive them from display text.

### 4.4 ContentDescriptor

Every selectable learning item needs:

```text
id
type
title
estimatedMinutes
difficultyBand
contextTags
requiresSpeakingAloud
requiresNetwork
aiCostClass
authoredOrGenerated
curriculumVersion
```

Supported initial task types:

```text
vocab_review
vocab_introduction
grammar_explanation
grammar_drill
pronunciation_contrast
listening_comprehension
listening_dictation
reading_comprehension
micro_writing
writing_retry
controlled_speaking
live_roleplay
correction_review
transfer_check
weekly_assessment
```

### 4.5 Content-to-competency mapping

Each content item maps to one or more competencies with:

```text
contentItemId
competencyId
role: teaches | practises | assesses
modality
weight
```

No task may update the twin unless this mapping exists.

## 5. Persistence schema

Add a new forward-only migration. Do not edit existing shipped migrations.

### 5.1 `competencies`

```sql
CREATE TABLE competencies (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  difficulty_band TEXT NOT NULL,
  prerequisite_ids_json TEXT NOT NULL DEFAULT '[]',
  target_level_label TEXT,
  exam_relevance_json TEXT NOT NULL DEFAULT '{}',
  curriculum_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

Authored competency definitions may remain in versioned assets for MVP, but a local table or index must support joins and eventual server synchronization.

### 5.2 `content_competencies`

```sql
CREATE TABLE content_competencies (
  id TEXT PRIMARY KEY,
  content_item_id TEXT NOT NULL,
  competency_id TEXT NOT NULL,
  role TEXT NOT NULL,
  modality TEXT NOT NULL,
  weight REAL NOT NULL,
  curriculum_version TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

Add indexes on `content_item_id` and `competency_id`.

### 5.3 `evidence_events`

Append-only source of truth:

```sql
CREATE TABLE evidence_events (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  plan_id TEXT,
  plan_task_id TEXT,
  content_item_id TEXT NOT NULL,
  competency_id TEXT NOT NULL,
  modality TEXT NOT NULL,
  support_level TEXT NOT NULL,
  correctness REAL,
  score REAL,
  response_time_ms INTEGER,
  attempt_number INTEGER NOT NULL DEFAULT 1,
  evaluator TEXT NOT NULL,
  evaluator_confidence REAL NOT NULL,
  response_json TEXT,
  error_codes_json TEXT NOT NULL DEFAULT '[]',
  occurred_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
```

Indexes:

- `(user_id, competency_id, modality, occurred_at)`
- `(plan_id, plan_task_id)`
- `(occurred_at)`

### 5.4 `error_events`

```sql
CREATE TABLE error_events (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  competency_id TEXT NOT NULL,
  source_evidence_id TEXT NOT NULL,
  error_code TEXT NOT NULL,
  observed_form TEXT,
  expected_form TEXT,
  explanation TEXT,
  severity REAL NOT NULL,
  evaluator TEXT NOT NULL,
  evaluator_confidence REAL NOT NULL,
  resolved_by_evidence_id TEXT,
  occurred_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

### 5.5 `learner_competency_states`

Derived cache, rebuildable from evidence:

```sql
CREATE TABLE learner_competency_states (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  competency_id TEXT NOT NULL,
  modality TEXT NOT NULL,
  mastery_estimate REAL NOT NULL,
  confidence REAL NOT NULL,
  retention_strength REAL NOT NULL,
  evidence_count INTEGER NOT NULL,
  transfer_status TEXT NOT NULL,
  last_observed_at TEXT,
  last_success_at TEXT,
  next_review_at TEXT,
  learner_model_type TEXT NOT NULL,
  model_version TEXT NOT NULL,
  model_state_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  UNIQUE(user_id, competency_id, modality)
);
```

### 5.6 `learning_plans`

```sql
CREATE TABLE learning_plans (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  local_date TEXT NOT NULL,
  available_minutes INTEGER NOT NULL,
  environment_json TEXT NOT NULL,
  primary_priority TEXT NOT NULL,
  explanation TEXT NOT NULL,
  planner_version TEXT NOT NULL,
  input_snapshot_json TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

### 5.7 `plan_tasks`

```sql
CREATE TABLE plan_tasks (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  plan_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  content_item_id TEXT NOT NULL,
  requirement TEXT NOT NULL,
  estimated_minutes INTEGER NOT NULL,
  reason_code TEXT NOT NULL,
  reason_detail_json TEXT NOT NULL,
  target_competency_ids_json TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at TEXT,
  completed_at TEXT,
  result_summary_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT
);
```

Requirements are `must`, `should`, or `bonus`.

### 5.8 `assessment_snapshots`

Store versioned, dated summaries. Never overwrite historical assessments.

```text
id
user_id
assessment_type
summary_json
source_evidence_ids_json
model_version
created_at
```

### 5.9 Migration and repository requirements

- Add every synchronized table to the outbox allowlist.
- History tables remain append-only.
- Derived competency states may use server-authoritative replacement.
- Add typed repository methods; UI code must not issue SQL.
- Add migration tests that open an old schema, migrate, write, read, and rebuild state.

## 6. Evidence contract

### 6.1 Every task produces evidence or explicitly produces none

A task result must return:

```text
status
attempts
competencyEvidence[]
errors[]
learnerVisibleFeedback
technicalMetadata
```

If evidence cannot be trusted, record task completion separately and emit no mastery evidence.

### 6.2 Evaluator types

Initial values:

```text
deterministic_exact
deterministic_rule
self_report
speech_to_text_signal
llm_text_rubric
llm_audio_coaching
human_teacher
```

### 6.3 Confidence caps

Initial policy:

- Exact authored multiple-choice grading may have high grading confidence but only low-to-medium mastery weight.
- Self-report cannot prove mastery.
- STT mismatch is weak pronunciation evidence.
- One LLM judgment cannot create high mastery confidence.
- Human-reviewed benchmark evidence may carry higher evaluator confidence.
- Repeated delayed unaided production has the strongest mastery impact.

Keep caps in a versioned configuration object, not scattered literals.

## 7. Twin update engine

Create `flutter_app/lib/orchestration/twin/`:

- `twin_updater.dart`
- `evidence_weight_policy.dart`
- `retention_policy.dart`
- `transfer_detector.dart`
- `competency_state_rebuilder.dart`

### 7.1 V1 probabilistic learner model

Use a lightweight contextual Bayesian Knowledge Tracing belief model for competency-by-modality state. The update calculation is deterministic and reproducible, but the resulting state represents uncertainty rather than pretending knowledge is certain.

Initial model parameters include:

```text
pKnownInitial
pLearn
pSlip
pGuess
pForget
```

Evidence context modifies observation reliability rather than bypassing the model:

- support level: recognition, cued, hinted, unaided, spontaneous transfer;
- evaluator confidence;
- item difficulty prior;
- attempt number;
- time since prior evidence;
- controlled versus spontaneous production;
- modality.

For each evidence event:

1. Validate competency, modality, score bounds, evaluator, provenance, and confidence.
2. Convert the observation into an evidence likelihood using the versioned reliability policy.
3. Update the prior belief to a posterior using the configured BKT variant.
4. Apply a bounded learning transition after a genuine learning opportunity.
5. Apply the configured forgetting/retention transition from elapsed time where the model supports it.
6. Update estimate confidence separately using independent evidence count, delay, evaluator quality, and modality diversity.
7. Update last-observed and last-success timestamps.
8. Calculate review urgency and `next_review_at`.
9. Detect unresolved errors and cross-modal transfer.
10. Persist learner-model type, model version, posterior state, and the evidence provenance used.

Do not copy pyBKT into the Flutter runtime. Implement the small online update behind a Dart `LearnerStateModel` interface for offline use, then use pyBKT in backend experiments to fit parameters and verify parity. Any future PFA, Elo, ReKT, AKT, or LLM-integrated model implements the same interface and is compared in shadow evaluation before promotion.

Vocabulary scheduling remains behind an `SrsPolicy` interface. Preserve the current SRS first; benchmark FSRS in shadow mode against observed delayed recall before replacing the live scheduler.

### 7.2 Required invariants

- Values remain in `[0, 1]`.
- One event cannot move mastery by more than a configured maximum.
- Hinted success cannot count as unaided success.
- A corrected immediate retry does not prove delayed retention.
- Speaking evidence does not automatically prove pronunciation quality.
- Reading evidence does not automatically update spontaneous speaking.
- Rebuilding from the same ordered events produces the same state.
- Unknown or invalid evidence is rejected, not silently coerced.

### 7.3 Transfer states

Initial values:

```text
not_observed
single_modality
cross_modal_supported
cross_modal_productive
spontaneous_transfer_observed
```

Transfer messages must cite real source tasks.

## 8. Governed adaptive orchestration engine

Create `flutter_app/lib/orchestration/planning/`:

- `orchestrator.dart`
- `candidate_generator.dart`
- `candidate_scorer.dart`
- `plan_constraint_solver.dart`
- `plan_explainer.dart`
- `task_selection_policy.dart`
- `constrained_utility_policy.dart`
- `llm_proposal_policy.dart`
- `shadow_bandit_policy.dart`
- `planning_policy.dart`
- `fallback_plan_factory.dart`

`TaskSelectionPolicy` is the swappable decision boundary. V1 executes `ConstrainedUtilityPolicy`. `LlmProposalPolicy` may select and sequence only from approved candidate IDs, and its output passes through the same constraint solver. `ShadowBanditPolicy` records an unexecuted alternative until promotion gates are met. No policy directly persists a plan or learner state.

### 8.1 Planning inputs

Stable profile inputs:

- goal;
- selected exam or undecided;
- exam horizon, if supplied;
- usual weekly availability;
- speaking environments;
- preferred session bounds;
- accessibility preferences.

Dynamic inputs:

- available minutes today;
- can speak aloud;
- network availability;
- learner-requested intensity;
- due reviews;
- competency states;
- unresolved errors;
- recent task history;
- recent workload;
- recent skips and pauses;
- AI allowance;
- eligible curriculum items.

### 8.2 Candidate pools

Generate candidates from:

1. overdue review;
2. recent correction retry;
3. weakest goal-relevant competency;
4. cross-modal transfer opportunity;
5. prerequisite-ready new material;
6. stronger-skill maintenance;
7. learner-selected interest;
8. exam-oriented work only when readiness gates allow it.

### 8.3 Initial score components

Each candidate receives named components:

```text
reviewUrgency
goalRisk
weaknessPriority
correctionFollowUp
transferOpportunity
prerequisiteReadiness
learnerPreference
varietyBenefit
fatiguePenalty
repetitionPenalty
contextMismatchPenalty
aiCostPenalty
```

Weights live in a versioned `PlanningPolicy`. The plan snapshot stores the planner version and score breakdown.

### 8.4 Constraints

The solver must enforce:

- total estimated time fits the selected budget within configured tolerance;
- `requiresSpeakingAloud` tasks are excluded when speaking is unavailable;
- network-only tasks are excluded offline;
- AI-cost limits are respected;
- maximum new competencies per session;
- required overdue reviews are protected;
- at least one productive task appears when context and time permit;
- excessive repetition is avoided;
- weekly listening, reading, writing, and speaking coverage is protected;
- the primary priority remains coherent across tasks.

### 8.5 Must, should, bonus

- `must`: minimum valuable session and urgent reviews/corrections.
- `should`: completes the day's connected loop.
- `bonus`: deeper practice that can be omitted without implying failure.

### 8.6 Reason codes

Initial enum:

```text
due_review
recent_mistake
weakest_skill
cross_skill_transfer
prerequisite_ready
goal_maintenance
exam_readiness
learner_choice
skill_maintenance
insufficient_evidence
```

The UI displays a concise explanation generated from controlled templates. An LLM may rewrite for tone only if the reason code and facts remain fixed.

### 8.7 Plan immutability

- Generate once and persist.
- Starting any task locks the plan.
- A context change may hide an impossible optional task but cannot silently rewrite completed history.
- Explicit `Replan today` creates a new plan version linked to the prior plan and records the reason.

### 8.8 Adaptive-policy lifecycle

The adaptive policy evolves through controlled promotion:

1. `baseline`: the constrained utility policy makes live selections.
2. `shadow`: contextual Thompson sampling observes the same context and candidate set but its choice is not executed.
3. `offline_evaluated`: logged-policy evaluation checks learning reward, calibration, subgroup behavior, and constraint violations.
4. `limited_experiment`: a capped cohort receives bandit choices with conservative exploration and immediate fallback.
5. `promoted`: the learned policy may select inside the safe candidate envelope.
6. `rolled_back`: remote configuration returns all users to the baseline without data migration.

The reward must prioritize delayed learning and transfer, not raw engagement:

```text
delayed_recall_gain
+ cross_modal_transfer_gain
+ corrected_retry_gain
+ appropriately_difficult_completion
- abandonment_penalty
- excessive_time_penalty
- repeated_easy_work_penalty
```

Every recommendation records context, candidate set, selected action, propensity/probability where applicable, policy version, and later reward. Exploration never bypasses prerequisites, time, environment, privacy, cost, entitlement, or balanced-skill constraints.

### 8.9 LLM planning boundary

The LLM may propose a coherent sequence from approved candidates and explain its pedagogical story. It receives opaque/stable candidate IDs plus bounded learner evidence, and must return structured IDs and rationale. It may not invent content IDs, prerequisites, scores, entitlements, or mastery changes. The reference monitor rejects invalid proposals and the baseline policy remains available.

## 9. Plan execution architecture

Refactor the current pathway into a plan executor rather than a hardcoded five-stage sequence.

Create:

```text
flutter_app/lib/orchestration/execution/
  plan_executor.dart
  task_registry.dart
  task_runner.dart
  task_result.dart
  execution_guard.dart
```

### 9.1 Task registry

Map task type to renderer/runner without placing screen imports inside the core planner.

Examples:

```text
vocab_review -> existing vocabulary session
language explanation -> grammar lesson
listening_comprehension -> existing listening runner
micro_writing -> existing pathway writing
live_roleplay -> existing SessionScreen with objective contract
```

### 9.2 Execution responsibilities

The executor owns:

- task start/pause/complete;
- route launching;
- exact resumption;
- typed result validation;
- evidence emission;
- plan-task status;
- transition to the next eligible task.

Screens own presentation and return typed results. Screens do not update mastery directly.

### 9.3 Backward compatibility

During migration, adapt the existing daily pathway stages into plan-task adapters. Do not rewrite every learning screen before proving the new plan model.

## 10. AI architecture

### 10.1 Production rule

All production text AI calls go through the authenticated backend. Gemini Live uses a short-lived backend-minted token and remains a direct device-to-Gemini connection for latency.

### 10.2 Backend modules

Evolve `server/` into:

```text
server/
  api/
    auth.py
    plans.py
    evidence.py
    sessions.py
    live_tokens.py
    entitlements.py
    config.py
    health.py
  domain/
    competencies.py
    mastery.py
    orchestration.py
    assessments.py
  integrations/
    gemini.py
    supabase.py
    revenuecat.py
  repositories/
  schemas/
  tests/
```

Keep a modular monolith. Do not create networked microservices.

### 10.3 Text AI endpoint use cases

- writing feedback;
- micro-writing feedback;
- bounded error extraction;
- explanation at learner level;
- generated exercise variation;
- session summary;
- learner-facing wording from fixed facts.

Use provider-supported structured outputs with explicit JSON Schema. Validate again server-side.

### 10.4 Gemini Live token flow

1. Flutter authenticates with ParleSprint.
2. Backend verifies entitlement and remaining allowance.
3. Backend creates a one-use, short-lived Gemini Live token.
4. Backend constrains allowed model/configuration where supported.
5. Flutter connects directly to Gemini Live using the ephemeral token.
6. Flutter and backend record session start/end and usage.
7. Backend reconciles usage and rejects further tokens if the allowance is exhausted.

### 10.5 Live session contract

Every learning call receives:

```text
objective
allowedCompetencies
targetVocabulary
targetStructures
learnerSupportLevel
maximumTurns
completionCondition
forbiddenClaims
availableTools
```

Marie may vary the scenario and natural language but may not change the objective or mark mastery.

### 10.6 Pronunciation rule

A transcript is not a pronunciation score.

MVP pronunciation may use:

- listen and repeat;
- recording and replay;
- authored sound contrasts;
- mouth-position guidance;
- STT mismatch as a weak signal;
- Gemini audio feedback labeled as coaching.

Do not display pronunciation percentages or official readiness claims. Pilot calibration must compare AI feedback with qualified human judgments before pronunciation materially affects mastery.

## 11. Content architecture

### 11.1 Authored spine, generated variation

Authored content owns:

- competency definitions;
- prerequisites;
- teaching explanations;
- canonical examples;
- learning objectives;
- assessment rubrics;
- official-format claims;
- core listening scripts and recordings;
- accepted answers.

AI may generate:

- contextual variation;
- extra examples;
- controlled distractors;
- personalized micro-prompts;
- roleplay turns;
- explanations based on authored truth.

### 11.2 Content validation

Add a validation command/test that verifies:

- unique stable IDs;
- valid prerequisite references;
- valid competency references;
- valid modality and role values;
- estimated time present;
- every assessing task has a rubric or deterministic answer;
- every plan-eligible item has competency mappings;
- curriculum version present;
- no unsupported immigration or exam claims.

### 11.3 MVP theme example

Theme: professional introduction

- Vocabulary: profession, experience, company, work, role.
- Grammar: present tense of `être` and `travailler`.
- Pronunciation: selected French `r` and vowel targets.
- Listening: short professional introduction.
- Reading: short profile or email.
- Writing: four-sentence introduction.
- Speaking: introduce yourself to Marie.
- Transfer: reuse a corrected structure in another mode after a delay.

## 12. Learner experience

### 12.1 Onboarding additions

Collect only actionable information:

- goal;
- exam selection or undecided;
- approximate horizon;
- current self-estimate;
- weekly availability;
- usual daily contexts;
- when speaking aloud is possible;
- perceived strongest and weakest abilities.

Then run a lightweight diagnostic. Self-report is context, not proof.

### 12.2 Home plan presentation

Show:

```text
Today's priority
Why it matters
Must do
Should do
Bonus
Estimated time
Speaking/network requirements
```

Example:

> Today's priority: past narration in speaking. Yesterday you used the correct form in writing but switched to the present while speaking.

### 12.3 Learning map

Learner-facing states:

```text
demonstrated
developing
due_for_review
needs_more_evidence
current_priority
```

Avoid fake precision in the main UI. Internal numerical values are for planning and debugging.

### 12.4 Evidence explanation

A learner may inspect:

- why a competency changed;
- which attempts contributed;
- why a task returned;
- whether the estimate is confident;
- what would strengthen the evidence.

### 12.5 Absence recovery

Do not punish missed days. On return:

- run a short retention check;
- preserve urgent reviews;
- reduce new material;
- rebuild the plan from current evidence.

## 13. Offline-first and synchronization

### 13.1 Local behavior

Offline availability must include:

- previously downloaded plan;
- authored lessons;
- vocabulary review;
- deterministic drills;
- local task completion;
- evidence queueing;
- exact resumption.

Network-dependent AI tasks show a clear queued or unavailable state.

### 13.2 Sync ownership

Client-created facts:

- task start, pause, completion;
- deterministic answers;
- offline reviews;
- learner context selection.

Server-authoritative facts:

- entitlement;
- AI usage;
- AI evaluations;
- final derived competency cache;
- remote configuration;
- curriculum version availability.

### 13.3 Conflict rules

- Append-only events deduplicate by UUID.
- Profile preferences initially use last-write-wins by `updated_at`.
- Plans remain immutable.
- Task statuses sync independently.
- Derived states rebuild from ordered evidence after reconciliation.
- Server time is authoritative for paid usage and entitlement.

## 14. Security, privacy, and compliance

Before paid access:

- remove production dependence on client-bundled Gemini/OpenRouter keys;
- authenticate every backend request;
- enable Supabase RLS for every user-owned table;
- verify RevenueCat entitlements server-side;
- meter AI usage server-side;
- rate-limit token and evaluation endpoints;
- add data export/deletion behavior;
- publish privacy policy and terms;
- disclose AI processing and third-party providers;
- default to no raw audio retention;
- minimize transcript retention;
- prevent transcripts from entering product analytics;
- support remote model/feature disablement;
- use paid AI service terms appropriate for production data.

Operational telemetry must remain categorical and privacy-safe. Do not add raw learner responses, transcripts, email addresses, or immigration information to generic analytics properties.

## 15. Implementation phases

Complete phases in order. A phase is complete only when all acceptance criteria and tests pass.

### Phase O1: Competency foundation

Build:

1. competency and modality enums/models;
2. competency asset format;
3. initial competency taxonomy for the MVP themes;
4. content-to-competency mappings;
5. validation tests;
6. migration tables and repositories.

Acceptance criteria:

- every MVP content item has valid mappings;
- prerequisite graph has no missing references or cycles;
- curriculum validation runs in tests;
- existing app still boots and current pathways work.

### Phase O2: Evidence ledger

Build:

1. evidence and error models;
2. append-only repositories;
3. typed task result contract;
4. adapters from existing vocabulary, grammar, listening, writing, and speaking results;
5. evaluator-confidence policy;
6. migration and repository tests.

Acceptance criteria:

- completing each supported task emits valid evidence;
- unsupported evidence is rejected;
- hints and attempts are preserved;
- no screen writes mastery state directly;
- evidence survives restart.

### Phase O3: Probabilistic twin updater v1

Build:

1. `LearnerStateModel` interface;
2. contextual BKT online updater in Dart;
3. versioned BKT parameter and observation-reliability policy;
4. separate estimate-confidence calculation;
5. forgetting/retention scheduling;
6. `SrsPolicy` interface preserving the current scheduler;
7. error resolution linking and transfer detection;
8. full-state rebuild command/test;
9. Python/pyBKT parity and parameter-fitting fixture outside the Flutter runtime.

Acceptance criteria:

- same ordered events and model version always rebuild the same posterior states;
- posterior uncertainty remains explicit;
- one weak AI event cannot produce mastery;
- delayed unaided success raises confidence more than immediate hinted retry;
- modality boundaries are preserved;
- all probabilities remain bounded;
- the current vocabulary scheduler remains behaviorally unchanged until a shadow comparison approves a replacement.

### Phase O4: Governed adaptive orchestrator v1

Build:

1. planning context;
2. candidate generation;
3. `TaskSelectionPolicy` interface;
4. constrained utility baseline policy;
5. LLM proposal policy limited to approved candidate IDs;
6. scoring policy and reference-monitor constraint solver;
7. reason codes;
8. Must/Should/Bonus output;
9. persisted plan and decision-trace snapshot;
10. offline fallback plan.

Acceptance criteria:

- plans fit time/context constraints;
- impossible speaking tasks are excluded;
- overdue reviews and recent errors influence plans;
- a cross-modal transfer task is selected when appropriate;
- every selected task has a valid reason and policy trace;
- same inputs and baseline policy version produce the same plan;
- invalid LLM proposals are rejected without affecting learner state or plan continuity.

### Phase O4.5: Adaptive policy shadow evaluation

Build:

1. contextual Thompson-sampling shadow policy;
2. candidate-set, context, propensity, and baseline-choice logging;
3. delayed learning and transfer reward computation;
4. offline policy evaluation;
5. subgroup, calibration, and safety reports;
6. remote rollback and policy-version controls.

Acceptance criteria:

- the shadow policy never changes a live learner plan;
- every shadow recommendation is reproducible from its recorded model/policy version and random seed;
- reward excludes raw engagement as a sufficient success signal;
- no shadow action outside the safe candidate envelope is accepted;
- promotion criteria are written before a limited live experiment begins.

### Phase O5: Plan executor and home integration

Build:

1. task registry;
2. adapters around existing screens;
3. plan execution/resume;
4. plan UI replacing fixed daily tiles;
5. explicit replan behavior;
6. progress transition compatibility.

Acceptance criteria:

- existing stage screens run through plan tasks;
- force-quit resumes exact task and content;
- completion produces evidence and updates the twin;
- skipping is explicit and does not fabricate progress;
- started plans do not silently regenerate.

### Phase O6: Connected vertical loop

Build one complete theme end-to-end:

1. vocabulary introduction/review;
2. grammar teaching and drill;
3. pronunciation coaching;
4. listening;
5. reading;
6. micro-writing;
7. targeted speaking;
8. correction extraction;
9. next-plan follow-up;
10. delayed transfer check.

Acceptance criteria:

- yesterday's error visibly changes today's plan;
- corrected material returns in another modality;
- the learner can inspect the reason;
- evidence and confidence update correctly;
- AI outage still permits the non-AI portion.

### Phase O7: Secure AI control plane

Build:

1. Supabase-authenticated FastAPI middleware;
2. server-side Gemini text gateway;
3. JSON Schema structured outputs;
4. Gemini Live ephemeral-token endpoint;
5. usage ledger and rate limits;
6. model/feature configuration;
7. error taxonomy and retries;
8. remove production need for user-entered provider keys.

Acceptance criteria:

- no long-lived provider secret is recoverable from release builds;
- malformed AI output cannot update learner state;
- token endpoint verifies user and allowance;
- usage is server-authoritative;
- provider outage degrades safely.

### Phase O8: Cloud sync and identity

Build:

1. Supabase project and migrations;
2. RLS policies;
3. Apple/Google or selected authentication;
4. local-to-cloud migration;
5. outbox processor;
6. pull/reconciliation;
7. account deletion;
8. sync integration tests.

Acceptance criteria:

- reinstall/login restores learner data;
- one user cannot read another user's records;
- duplicate event uploads are harmless;
- offline evidence syncs later;
- competency state rebuilds after reconciliation.

### Phase O9: Pilot instrumentation and calibration

Build:

1. privacy-safe event upload;
2. crash reporting;
3. pilot dashboard;
4. prompt/model version logging;
5. human review workflow for sampled feedback;
6. learner feedback capture;
7. AI-cost reporting.

Acceptance criteria:

- team can inspect failures without reading unnecessary private content;
- every AI evaluation records model/prompt/rubric versions;
- cost per active learner is measurable;
- teacher review can compare AI output and submit corrections.

### Phase O10: Paid access

Build only after pilot evidence supports it:

1. RevenueCat SDK;
2. one founding entitlement;
3. purchase and restore;
4. server webhook/verification;
5. grace and unavailable states;
6. server-authoritative feature gating;
7. support/refund process;
8. capped release controls.

Acceptance criteria:

- purchase unlocks correctly;
- restore works after reinstall;
- expired/inactive entitlement blocks paid AI without deleting learning data;
- webhook retries are idempotent;
- app remains useful when verification is temporarily unavailable.

## 16. Testing strategy

### 16.1 Unit tests

Required suites:

- competency graph validation;
- evidence validation;
- evidence weighting;
- BKT posterior update and parameter-version parity;
- mastery probability bounds;
- confidence growth;
- retention scheduling;
- transfer detection;
- current-SRS behavioral preservation;
- candidate scoring;
- plan constraints;
- baseline plan determinism;
- invalid LLM proposal rejection;
- shadow-bandit action-envelope enforcement;
- reason generation;
- usage and entitlement guards.

### 16.2 Property/invariant tests

Verify across generated event sequences:

- state values remain bounded;
- rebuild is deterministic;
- event order is respected;
- duplicate event IDs do not double count;
- hinted evidence never outranks equivalent unaided evidence;
- invalid modality cannot update a state;
- total required plan duration stays within configured bounds.

### 16.3 Integration tests

- onboarding -> diagnostic -> plan -> task -> evidence -> next plan;
- force-quit and resume;
- offline completion -> later sync;
- Gemini malformed response;
- Gemini timeout;
- Live token denial after allowance exhaustion;
- entitlement active/grace/inactive;
- account restore;
- migration from current local database.

### 16.4 Golden benchmark datasets

Maintain versioned samples for:

- writing submissions with teacher rubrics;
- common grammar errors;
- speaking transcripts with known limitations;
- pronunciation recordings for later calibration;
- plan scenarios representing each persona.

Do not tune only on happy paths.

## 17. Pilot metrics

### 17.1 North-star behavior

`Meaningful learning days`: a day where the learner completes evidence-producing tasks and at least one task is linked to prior evidence, a due review, or a current competency risk.

### 17.2 Activation

- diagnostic completion;
- first plan viewed;
- first required task completed;
- first correction retried;
- first explanation opened.

### 17.3 Orchestration value

- plan acceptance rate;
- override/replan rate;
- skip rate by reason;
- estimated versus actual duration;
- plans containing prior-evidence follow-up;
- corrections retried;
- cross-modal transfer attempts;
- learner response to `I know what to practise next`.

### 17.4 Learning evidence

- delayed unaided recall;
- improvement on corrected retries;
- successful use in a second modality;
- regression after delay;
- weakest-competency movement;
- human/AI evaluator agreement.

### 17.5 Reliability and economics

- crash-free sessions;
- plan-generation success;
- resume success;
- voice connection success;
- structured-output validation failures;
- AI latency;
- AI cost per meaningful learning day;
- voice minutes and cost per active learner;
- support requests per active learner.

## 18. Launch gates

### 18.1 MVP gate

- Every supported task emits valid evidence or explicitly emits none.
- Every evidence event maps to a valid competency and modality.
- At least one real error changes a later task.
- Baseline plan generation is deterministic for fixed inputs and policy version; stochastic policies record the seed/propensity needed for audit and evaluation.
- Every required task has an inspectable reason and policy trace.
- Interrupted learning resumes without fabricated completion.

### 18.2 Closed-pilot gate

- No critical data-loss issue remains.
- AI failure does not block core non-AI learning.
- Human review finds feedback useful and non-misleading at an acceptable rate defined before the cohort begins.
- Learners understand why tasks were selected.
- Actual time and estimated time are sufficiently aligned to make plans trustworthy.
- AI cost is measured under real usage.

### 18.3 Paid gate

- Auth, RLS, sync, restore, deletion, and entitlements work.
- Provider keys and usage limits are secure.
- Privacy and AI-processing disclosures are published.
- Support can diagnose plan reasons without unnecessary transcript access.
- Product claims match shipped capability.
- Unit economics remain acceptable under observed voice usage.

## 19. Risks and mitigations

### Cold-start uncertainty

Mitigation: diagnostic, conservative priors, rapid evidence collection, and visible confidence.

### LLM inconsistency

Mitigation: structured outputs, low variance settings, fixed rubrics, confidence caps, benchmark datasets, model versioning, and human calibration.

### Content explosion

Mitigation: narrow authored spine, reusable templates, constrained generated variation, caching, and expansion based on observed bottlenecks.

### Voice cost

Mitigation: targeted short calls, on-device speech for low-stakes drills, daily allowance, server metering, and cost-aware planning.

### Conversation drift

Mitigation: objective contracts, tool validation, short turns, allowed competencies, maximum turns, and deterministic completion conditions.

### User overload

Mitigation: Must/Should/Bonus, today's available time, environment filters, one primary priority, and absence recovery.

### Misleading progress

Mitigation: evidence provenance, separate confidence, no official score claim, no fake percentages in learner-facing summaries, and inspectable changes.

### Privacy concerns

Mitigation: data minimization, no audio retention by default, transcript controls, paid AI service configuration, RLS, deletion, and privacy-safe analytics.

### Persona overfitting

Mitigation: personas configure initial planning constraints; observed evidence replaces assumptions over time.

## 20. Future coding-agent protocol

Every coding agent working from this plan must follow this process.

### 20.1 Before implementation

1. Read this entire document.
2. Read `PILOT_PLAN.md`.
3. Inspect current git status and do not overwrite unrelated user changes.
4. Identify the first incomplete phase in the implementation ledger below.
5. Read all referenced existing files before editing.
6. Check project skills and repository rules.
7. Create/update a task list for only that phase.
8. Write failing tests for the phase's core invariant where test infrastructure permits.

### 20.2 During implementation

1. Keep one owner for orchestration state.
2. Do not let UI or LLM services write mastery state directly.
3. Use forward-only database migrations.
4. Preserve exact resumption semantics.
5. Use typed models instead of unvalidated free-form maps at boundaries.
6. Keep reason codes and model versions in persisted records.
7. Do not add unsupported product claims.
8. Do not add a new dependency before confirming existing libraries cannot solve the need.
9. Keep AI calls bounded and schema-validated.
10. Update tests alongside each change.

### 20.3 Before marking a phase complete

1. Run relevant unit tests.
2. Run `flutter analyze`.
3. Run full Flutter tests when the phase affects shared models, database, planning, or execution.
4. Run backend tests when the phase affects server code.
5. Verify migration from an existing database fixture.
6. Review privacy and security impact.
7. Review learner-facing claims.
8. Update the implementation ledger with completed items, decisions, deviations, and next action.
9. Do not mark a phase complete if any acceptance criterion is unverified.

### 20.4 If blocked

Record:

```text
Blocker
Why it blocks the acceptance criterion
Evidence gathered
Safe options considered
Decision required from founder
```

Do not silently bypass security, data integrity, pedagogy, or acceptance criteria.

## 21. Implementation ledger

This section is the resume point for future agents. Update it after every implementation session.

### Current phase

`O5: Plan executor and home integration (not started); O3/O4 persistence is now done`

### Phase status

- [x] O1 Competency foundation
- [x] O2 Evidence ledger
- [x] O3 Probabilistic twin updater v1 — online/rebuild baseline, retention/review scheduling, and transfer detection are implemented and persisted; pyBKT parity/calibration fixture outside the Flutter runtime remains open
- [x] O4 Governed adaptive orchestrator v1 — constrained utility baseline, reason-code explainer, offline fallback plan, and immutable plan snapshot persistence (with explicit replan) are implemented; LLM proposal validation against approved candidate IDs remains open
- [ ] O4.5 Adaptive policy shadow evaluation — not started
- [ ] O5 Plan executor and home integration — not started; `pathway_coordinator.dart` still owns the fixed five-stage flow, deliberately untouched so shipped navigation keeps working while the new plan model is exercised only via the Orchestration Lab
- [ ] O6 Connected vertical loop — not started
- [ ] O7 Secure AI control plane — not started (server/ is still the legacy voice-tutor monolith)
- [ ] O8 Cloud sync and identity — not started (no Supabase project/auth yet)
- [ ] O9 Pilot instrumentation and calibration — not started
- [ ] O10 Paid access — not started; explicitly deferred until pilot evidence exists, per section 2.3/10

### Decisions made

- The architecture is governed neuro-symbolic and adaptive: probabilistic learner beliefs, learnable policies, bounded generative AI, and deterministic authorization.
- Contextual BKT is the lightweight v1 competency model; current SRS remains live while FSRS is benchmarked in shadow mode.
- The constrained utility policy is the live cold-start selector; LLM proposals and contextual bandits remain validated/shadowed until promotion criteria are met.
- The initial target is serious A2/lower-B1 Canadian-goal learners.
- The MVP proves a narrow cross-skill loop before expanding curriculum breadth.
- Mastery and confidence are separate.
- Evidence is append-only and derived state is rebuildable.
- Plans are immutable after starting.
- One competency graph serves all personas.
- Gemini Live remains direct from client using ephemeral tokens in production.
- The existing FastAPI location becomes the modular learning control plane.
- Supabase is the planned auth/Postgres backend.
- RevenueCat is deferred until pilot evidence and secure infrastructure are ready.

### Open founder decisions

Resolve only when the corresponding phase requires them:

- Final names and scope of the first two or three MVP themes.
- Whether closed pilot access is free, refundable, or paid.
- Transcript retention default and retention period.
- Initial daily live-voice allowance for the pilot.
- Initial supported authentication methods by platform.
- Whether a qualified French teacher is available for weekly calibration.

### Last completed work

Phase O2, and O3/O4 through persistence, now provide:

- immutable typed evidence, error, evaluator-provenance, and task-result contracts;
- forward-only migration v5 adding `learner_competency_states`, `learning_plans` (immutable, replan-linked), `plan_tasks`, and append-only `assessment_snapshots`, on top of v4's evidence/error tables;
- transactional evidence persistence with duplicate rejection and atomic rollback;
- a versioned evaluator-confidence cap policy;
- vocabulary, grammar, listening, writing, and speaking result adapters that preserve attempts and withhold untrusted mastery claims;
- pathway-coordinator evidence emission without changing existing task completion thresholds;
- contextual competency-by-modality BKT beliefs, explicit confidence, forgetting, and deterministic rebuilds;
- evidence-to-observation validation against the authoritative competency mappings;
- `RetentionPolicy` (deterministic `next_review_at`/review urgency from mastery × confidence) and `TransferDetector` (the five `TransferStatus` states, citing the real evidence ids that justify each one);
- `CompetencyStateRebuilder`, tying BKT rebuild + retention + transfer into the persistable `CompetencyState` cache, and `CompetencyStateStore` for its rebuildable persistence;
- a deterministic constrained utility planner with time, voice, network, prerequisite, weakness, uncertainty, review, error, transfer, and goal signals;
- `PlanExplainer` (fixed reason-code templates per section 8.6) and `FallbackPlanFactory` (deterministic offline default when the baseline planner has nothing eligible);
- `PlanStore`: immutable plan snapshot persistence, task-progress transitions, and explicit `replan` that atomically retires the prior plan and links the new one — enforced via `PlanImmutableException` once a plan is replaced;
- `OrchestrationService`, the single facade wiring rebuild → context projection → planning → explanation → persistence, exposed only through the debug Orchestration Lab (which now also surfaces persisted per-competency evidence counts as a repetition/mastery view) — deliberately **not** wired into `pathway_coordinator.dart`'s live navigation yet;
- focused contract, repository, adapter, learner-model, retention, transfer, rebuilder, plan-store, explainer, fallback-factory, planner, graph, and lab tests (92 passing).

### Exact next action

O5, the plan executor:

1. build `execution/task_registry.dart` mapping task type → existing screen, without importing screens into the core planner;
2. build `execution/plan_executor.dart`/`task_runner.dart` to replace `pathway_coordinator.dart`'s fixed five-stage sequence with `OrchestrationService.ensureTodayPlan` + `PlanStore` task transitions, preserving exact-resumption semantics;
3. add a plan-based home UI (Must/Should/Bonus, today's priority, why-it-matters) alongside the existing fixed tiles until parity is proven, then cut over;
4. only after O5 is proven: validate bounded LLM plan proposals against approved candidate IDs (O4's `llm_proposal_policy.dart`) and begin O4.5 shadow evaluation.

O7-O10 (server auth, Supabase, RevenueCat) remain intentionally not started — they require external infrastructure/accounts and are gated behind pilot evidence per sections 2.3 and 10.

## 22. Definition of v1 success

Orchestration v1 is complete when a pilot learner can:

1. complete onboarding and a lightweight diagnostic;
2. receive a time- and context-appropriate daily plan;
3. understand why each required task was selected;
4. complete connected vocabulary, grammar, listening, reading, writing, pronunciation, and speaking work across the weekly plan;
5. receive bounded, useful feedback;
6. see a real mistake return in a later task;
7. demonstrate corrected knowledge in another modality;
8. inspect the evidence behind their learning map;
9. resume after interruption or offline use;
10. use the system without receiving unsupported exam or immigration promises.

The system is not successful merely because it generates personalized text. It is successful when its plans are explainable, its evidence is trustworthy, its state is reproducible, and learners experience less uncertainty about what to do next.

## 23. Research basis for the governed adaptive architecture

Primary references guiding v1:

- LongTutor, ACL 2026: LLMs perform well at historical evidence acquisition but struggle with long-term knowledge-state diagnosis and adaptive teaching action — https://aclanthology.org/2026.acl-long.1371/
- FoundationalASSIST, 2026 preprint: frontier models barely exceeded a trivial knowledge-tracing baseline and were weak at item discrimination — https://arxiv.org/html/2602.00070v1
- Twenty-five years of Bayesian Knowledge Tracing, 2024 systematic review: BKT remains an interpretable, extensible learner-model family — https://link.springer.com/article/10.1007/s11257-023-09389-4
- pyBKT: accessible BKT implementations and real-time roster support — https://github.com/CAHLR/pyBKT
- pyKT: reproducible benchmarking across deep knowledge-tracing models and warning against inflated comparisons — https://github.com/pykt-team/pykt-toolkit
- Context-Aware Attentive Knowledge Tracing: attention, forgetting, and Rasch-inspired item difficulty for a later data-rich benchmark — https://doi.org/10.1145/3394486.3403282
- Free Spaced Repetition Scheduler: lightweight difficulty/stability/retrievability memory modeling with Dart implementations available — https://github.com/open-spaced-repetition/free-spaced-repetition-scheduler
- 1EdTech CASE: machine-readable competency identifiers, relationships, alignments, and rubrics — https://www.1edtech.org/standards/case
- 1EdTech Caliper Analytics: consistent learning-activity event vocabulary — https://www.1edtech.org/standards/caliper
- Anthropic, Building Effective Agents: use predictable workflows for well-defined consequential processes and add agentic flexibility only where it earns its cost — https://www.anthropic.com/engineering/building-effective-agents

Research promotion rule: no model or policy is adopted because it is newer, larger, or labeled state of the art. It must outperform the current baseline on ParleSprint data using predeclared metrics for delayed learning, transfer, calibration, subgroup behavior, latency, cost, explainability, and safety.
