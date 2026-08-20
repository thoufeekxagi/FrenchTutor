# Flutter iOS UI Design with Codex

## A screenshot-led workflow for redesigning an existing app without losing its functionality

This guide documents a practical way to use Codex to redesign an existing Flutter app for iOS when the product already works, but the interface needs to feel more polished, intentional, and visually coherent.

The central idea is simple:

> Give Codex enough freedom to make strong design decisions, but add approval gates so it cannot silently invent a new product direction.

This workflow is designed for apps where you already have:

- working screens and navigation;
- established business logic and data flows;
- screenshots, wireframes, Mobbin references, or competitor examples;
- a willingness to make small interaction changes when the new UI requires them;
- a need to keep the redesign collaborative and explainable.

Last reviewed: August 2026.

## The short version

Use five layers:

1. `AGENTS.md` for permanent project rules.
2. A custom Codex skill for the redesign workflow.
3. The Flutter team’s agent plugin for Flutter-specific previews and testing.
4. Apple’s Human Interface Guidelines and Design Resources for platform principles.
5. A screenshot-and-approval loop for every screen.

Do not expect a new Flutter package to give Codex better taste. App dependencies change the product; skills and project instructions change how Codex works.

## The important distinction: rules, skills, plugins, packages, and references

| Layer | What it does | Example |
| --- | --- | --- |
| `AGENTS.md` | Gives Codex persistent project instructions before work begins | “Preserve behavior; ask before guessing; use screenshots as authority” |
| Skill | Encodes a reusable workflow with stages, gates, and output requirements | `parlesprint-mobile-ui` |
| Plugin | Packages skills and optional tools/connectors into an installable experience | Flutter’s `dart-flutter` plugin |
| Flutter package | Adds runtime functionality to the app | A chart, animation, or state-management package |
| Reference | Supplies visual or platform evidence | Screenshots, wireframes, voice notes, Apple HIG |
| Prompt | Defines the request for the current task | “Redesign the progress screen; proposal first” |

For redesign work, the strongest control is usually a short `AGENTS.md` plus one focused skill. A large collection of loosely related skills can make the model’s instructions less clear.

OpenAI describes skills as reusable packages of instructions, references, scripts, and optional assets. Skills can be invoked explicitly or selected when their descriptions match the task. [OpenAI: Build skills](https://learn.chatgpt.com/docs/build-skills)

## The custom skill created for this workflow

The custom skill is named:

```text
parlesprint-mobile-ui
```

On this machine it lives at:

```text
~/.codex/skills/parlesprint-mobile-ui/
```

Its purpose is not to impose one visual style. Its purpose is to control the redesign process so the user and Codex stay aligned.

The skill requires Codex to:

- classify incoming screenshots, wireframes, and voice notes;
- distinguish what to preserve, borrow, and avoid;
- ask clarification questions when references conflict or are incomplete;
- produce a screen contract and a wireframe before editing code;
- wait for explicit approval;
- implement one screen or one visual delta at a time;
- preserve data flow, navigation, and core behavior by default;
- stop if implementation reveals an unapproved behavior decision;
- run Flutter checks and compare screenshots after implementation;
- report visual changes separately from behavior changes.

The skill was validated with Codex’s skill validator and forward-tested against a realistic redesign request. It correctly stopped at the proposal stage instead of writing code immediately.

## The approval-gated workflow

### Phase 1: intake

Send the references first. They can include:

- screenshots of apps you like;
- screenshots of the current app;
- wireframes;
- recordings;
- voice notes;
- written product decisions;
- notes about what must not change.

Codex should organize them by screen, state, viewport, and purpose. It should extract decisions from voice notes, but mark uncertain statements as open questions.

At this stage, Codex should not edit UI code.

### Phase 2: clarification

Codex should ask only questions that materially affect the design. Good questions are concrete:

- “Should this tab remain directly accessible, or can it move into More?”
- “Is this screenshot a visual reference only, or should its navigation pattern also be borrowed?”
- “Should the current copy remain exactly the same?”
- “Does this new button replace the current action, or only change its appearance?”

Avoid vague questions such as “What vibe do you want?” unless Codex provides concrete visual choices.

### Phase 3: proposal and wireframe

Before implementation, Codex should show:

- the screen’s purpose;
- the primary and secondary actions;
- unchanged behavior;
- any small proposed behavior changes;
- the visual direction;
- the layout regions;
- the components to reuse or create;
- open questions;
- a simple labeled wireframe;
- acceptance criteria.

The wireframe is a communication tool, not a claim that the final UI is already designed.

The response must end with:

```text
Waiting for your approval before I edit code.
```

### Phase 4: implementation

After approval, Codex should:

1. inspect the relevant Flutter screen and existing theme/components;
2. preserve data, routing, persistence, and core learning behavior;
3. reuse existing tokens and widgets where appropriate;
4. add only the smallest necessary behavior change;
5. change one screen or visual delta;
6. avoid unrelated refactoring;
7. avoid adding dependencies unless explicitly approved.

### Phase 5: visual verification

After each implementation pass, Codex should:

- run the narrowest relevant Flutter checks;
- render the affected screen at the target phone size;
- check tablet behavior when relevant;
- capture a screenshot;
- compare the screenshot with the approved wireframe and reference;
- list remaining visual differences;
- stop and wait for the next note.

OpenAI’s current UI workflow guidance also recommends a tight loop of one focused visual change, one verification step, and then the next change. [Make granular UI changes](https://learn.chatgpt.com/codex/use-cases/make-granular-ui-changes)

## Recommended `AGENTS.md` rules

Create a short `AGENTS.md` at the project root. Codex reads these files before doing work and combines global and project-specific instructions in a defined order. [Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)

Use rules like these:

```md
# ParleSprint UI Rules

This is an existing Flutter app whose primary design target is iOS.

## Evidence priority

1. User-approved decisions
2. User-provided screenshots, wireframes, recordings, and voice notes
3. Existing app behavior, content, navigation, and design tokens
4. Apple Human Interface Guidelines
5. Codex judgment

When evidence conflicts, explain the conflict and ask before choosing.

## Redesign rules

- Preserve existing functionality, navigation, data, and business logic by default.
- Ask before changing behavior.
- Do not edit code before showing a proposal and wireframe.
- Make one screen-level change at a time.
- Reuse existing components and design tokens.
- Do not add packages without approval.
- Do not invent copy, assets, navigation, or screens.
- Do not add generic cards, gradients, pills, or decorative elements without evidence.
- Verify visual changes with screenshots.
- Support safe areas, Dynamic Type, Dark Mode, VoiceOver, touch targets, and Reduce Motion.

For redesign tasks, use $parlesprint-mobile-ui.
```

Keep this file concise. Put the detailed workflow in the skill instead of turning `AGENTS.md` into a massive prompt.

## Creating or updating the skill

Codex can create a reusable skill with:

```text
$skill-creator
```

A useful creation prompt is:

```text
Create a reusable skill named parlesprint-mobile-ui.

It is for redesigning an existing Flutter app for iOS using screenshots,
wireframes, Mobbin references, recordings, and voice notes.

The skill must preserve existing functionality by default. It must ask
clarifying questions when references are ambiguous, create a labeled wireframe
and implementation proposal before editing code, wait for explicit approval,
implement one screen at a time, and verify each change with Flutter checks and
screenshots.

It must never invent missing product decisions, navigation, copy, assets, or
behavior. It must distinguish visual changes from behavior changes and stop
when an unapproved behavior decision appears.
```

The skill format is a directory containing a required `SKILL.md` and optional `references/`, `scripts/`, and `assets/` directories. [OpenAI: Build skills](https://learn.chatgpt.com/docs/build-skills)

## Installing Flutter-specific support

The Flutter team maintains an agent plugin with Flutter-oriented skills for:

- widget previews;
- widget tests;
- integration tests;
- responsive layouts;
- layout debugging;
- Flutter architecture workflows.

For Codex CLI, the repository documents:

```bash
codex plugin marketplace add flutter/agent-plugins
codex plugin add dart-flutter@dart-flutter
```

The Flutter repository also documents a universal skills installation route:

```bash
npx skills@1.5.17 add flutter/agent-plugins --skill '*' --agent universal --yes
```

Use one installation route appropriate for your Codex surface. Restart Codex if a newly installed skill does not appear.

These Flutter skills improve implementation and verification. They do not replace the ParleSprint design skill, because a tooling plugin should not decide your product’s visual identity. [Flutter Agent Plugins](https://github.com/flutter/agent-plugins)

## Why not install a large UI package collection?

Flutter packages are useful when the app genuinely needs a capability such as charts, animation, navigation, or a specific control. They do not solve communication problems between the designer and Codex.

Adding packages too early can:

- introduce visual defaults that conflict with the reference direction;
- add unnecessary dependency and maintenance cost;
- make it harder to tell whether a design decision came from the product or the package;
- encourage Codex to assemble widgets instead of understanding the intended composition.

Start with Flutter’s existing primitives, the current design system, platform conventions, and approved references. Add a package only when the design requires a capability that cannot be implemented reliably with the current stack.

## Apple iOS design references

Use Apple’s documentation to answer platform questions, not to erase the product’s identity.

### Human Interface Guidelines

The HIG emphasizes hierarchy, harmony, and consistency across platforms. Its iOS guidance also covers accessibility, layout, typography, color, materials, navigation, and system components.

- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)
- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)
- [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Components](https://developer.apple.com/design/human-interface-guidelines/components/)

### Apple Design Resources

Apple provides official UI kits for Figma and Sketch, platform templates, fonts, and SF Symbols.

- [Apple Design Resources](https://developer.apple.com/design/resources/)
- [SF Symbols](https://developer.apple.com/sf-symbols/)

Useful iOS checks include:

- one clear primary action;
- safe-area-aware layout;
- reachable controls and appropriate touch targets;
- Dynamic Type support;
- Light Mode and Dark Mode;
- meaningful VoiceOver labels and order;
- reduced-motion behavior;
- familiar navigation and feedback patterns;
- iPhone and iPad layout checks when applicable.

Apple’s current iOS guidance specifically recommends limiting onscreen controls, adapting to Dark Mode and Dynamic Type, and placing important interactions where they are comfortable to reach. [Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)

## Reference packet format

For each screenshot or reference, provide as much of this information as possible:

```text
Screen: Home
Viewport: iPhone portrait
State: Returning user with progress
Purpose: Visual direction for hierarchy and spacing
Preserve: Current progress data and primary learning action
Borrow: Header rhythm, whitespace, progress emphasis
Avoid: Exact branding and copy from the reference
Confidence: High / Medium / Low
```

For a group of screenshots, label which ones are:

- visual references;
- interaction references;
- content references;
- layout references;
- examples to avoid.

This prevents Codex from treating every visible detail as a requirement.

## Prompt templates

### Start a redesign

```text
$parlesprint-mobile-ui

I want to redesign the [screen name] in my existing Flutter iOS app.

Attached references:
- [reference 1]: visual direction
- [reference 2]: navigation inspiration
- [current screenshot]: what exists today

Preserve:
- [functionality]
- [data]
- [navigation]

Possible behavior change:
- [describe it, or say none yet]

First inspect the references, ask the minimum clarifying questions, and show
a labeled wireframe and proposal. Do not edit code yet.
```

### Approve a proposal

```text
Approved for implementation.

Implement only the approved [screen/section].
Keep all other screens and behavior unchanged.
If implementation requires a new behavior decision, stop and ask me.
```

### Request one iteration

```text
Make only this visual change:
[specific change]

Use the approved proposal and current reference screenshot.
Do not change navigation, data, copy, or unrelated screens.
Capture a screenshot after the change and report the remaining differences.
```

### Give voice feedback

```text
My voice note means:
- Decision: [what I definitely want]
- Preference: [what I probably want]
- Unclear: [what needs confirmation]

Ask me about the unclear item before editing.
```

## What this workflow prevents

It is designed to prevent common AI redesign failures:

- jumping from a vague brief directly into code;
- replacing the whole information architecture;
- inventing a generic “premium” style;
- copying every detail from a reference screenshot;
- changing behavior without permission;
- adding packages to compensate for unclear design direction;
- claiming a screen matches without visual evidence;
- polishing unrelated screens before the current screen is approved.

## Suggested tutorial or social post structure

### Hook

“I stopped asking Codex to redesign my Flutter app in one giant prompt.”

### Problem

The app already worked, but broad redesign prompts caused AI-generated screens to drift, invent details, and change behavior accidentally.

### Setup

Show the five layers:

1. `AGENTS.md`
2. custom redesign skill
3. Flutter agent plugin
4. Apple HIG references
5. screenshot approval loop

### Demo

1. Attach the current screen and reference screenshots.
2. Give Codex a voice note.
3. Show Codex asking clarifying questions.
4. Show the wireframe proposal.
5. Say “approved.”
6. Show the focused Flutter change.
7. Compare before and after screenshots.

### Closing lesson

“The skill does not choose the brand for you. It makes Codex slow down at the right moments, use your references as evidence, and earn permission before it changes the product.”

### Suggested title

```text
How I Made Codex Redesign My Flutter iOS App Without Losing Control
```

### Suggested tags

```text
#Codex #Flutter #iOSDevelopment #UIUX #AppDesign #AIEngineering #MobileDevelopment #HumanInterfaceGuidelines
```

## Source links

- [OpenAI: Build skills](https://learn.chatgpt.com/docs/build-skills)
- [OpenAI: Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [OpenAI: Make granular UI changes](https://learn.chatgpt.com/codex/use-cases/make-granular-ui-changes)
- [Flutter Agent Plugins](https://github.com/flutter/agent-plugins)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [Apple: Designing for iOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-ios)
- [Apple Design Resources](https://developer.apple.com/design/resources/)
