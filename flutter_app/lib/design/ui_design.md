# ParleSprint — Million-Dollar Apple Design System

Comprehensive visual heuristics, design tokens, component architecture, and Stitch / Gemini 3.7 Flash prompt specifications.

---

## 1. Core Visual Heuristics (Apple Design Award Standard)

1. **Continuous Squircle Geometry**:
   - Use `20px` to `24px` continuous curvature (`CornerCurve.continuous` in Flutter).
   - Avoid generic sharp-radiused boxes.
2. **Zero Raw Emojis in Core UI**:
   - NEVER use raw platform emojis (`🍁`, `✈️`, `🌱`) for functional icons.
   - Use **tinted squircle vector badges** (44x44pt container, 14pt radius, `#EFF6FF` container with `#0062CC` SF Symbol / Cupertino icon).
3. **Restrained 3-Color Hierarchy**:
   - **Primary Action**: French Azure (`#0062CC` / `#007BFF`)
   - **Prominent Ink**: Obsidian Slate (`#0F172A`)
   - **Muted Metadata**: Slate (`#64748B`)
   - **Base Canvas**: Warm Alabaster (`#FAF9F6` or pure `#FFFFFF`)
4. **8pt Spacing Rhythm & Touch Targets**:
   - All padding/gaps use multiples of 8 (`8, 16, 24, 32`).
   - Minimum tap target: **54px** for CTAs, **68px+** for selection cards.
5. **Zero-Scroll Above-the-Fold Law**:
   - Setup screens must fit 100% above the fold across all device sizes (iPhone SE to 16 Pro Max).
   - Single punchy headline (≤ 6 words), 1-line subtitle, no paragraph walls.

---

## 2. Design Tokens

### Color Tokens
```dart
const kColorPrimary = Color(0xFF0062CC);       // Active actions, progress, checkmarks
const kColorPrimaryBg = Color(0xFFEFF6FF);     // Active card surface tint
const kColorPrimaryBorder = Color(0xFFDBEAFE); // Active badge outline
const kColorInk = Color(0xFF0F172A);           // Primary headlines & titles
const kColorMuted = Color(0xFF64748B);         // Subtitles, step counters
const kColorBorder = Color(0xFFE2E8F0);        // Inactive hairline strokes (1px)
const kColorCanvas = Color(0xFFFAF9F6);        // Atelier background
```

### Typography Scale
* **Display / Headline**: `GoogleFonts.plusJakartaSans(weight: w800, letterSpacing: -0.5)`
* **Body / Subtitle**: `GoogleFonts.inter(weight: w500, height: 1.4)`
* **Micro Labels**: `GoogleFonts.inter(weight: w700, fontSize: 11, letterSpacing: 1.2)`

---

## 3. Core Component Contracts

### A. Step Navigation Header (`TopStepBar`)
* Back chevron (`CupertinoIcons.chevron_back`, 22px).
* Centered `STEP X OF Y` tracked uppercase label (11px).
* 3px full-width progress indicator with fractionally sized `#0062CC` active fill.

### B. Luxury Selection Card (`LuxuryCard`)
* Height: `68px–76px`, Padding: `16px horizontal, 14px vertical`.
* Border radius: `20px continuous`.
* Leading: `44x44px` tinted squircle badge (`14px radius`) with vector icon.
* Title (`Plus Jakarta Sans` 15.5px w700) + Subtitle (`Inter` 12px w500).
* Trailing: 22px circular selection indicator (solid blue with white checkmark when active).

### C. Segmented Switcher (`PillSegmented`)
* Height: `44px`, container `#F1F5F9`, border `#E2E8F0`.
* Active item: White elevated pill with `0px 2px 6px rgba(0,0,0,0.05)` shadow.

### D. Primary Action CTA (`PrimaryPillButton`)
* Height: `54px`, full-width pill (`radius: 100px`).
* Background: `#0062CC`, Text: White bold 16px.

---

## 4. Stitch & Gemini Prompt Engineering Formula

To generate pixel-perfect screens in Stitch using Gemini Flash:

```text
Create a luxury Apple-Standard [SCREEN NAME] screen for ParleSprint (iPhone 16 Pro, 390px mobile layout).

Design Specifications:
- High-end Apple Design Award aesthetics. Continuous 20px rounded squircle corners, 1px hairline borders.
- NO RAW EMOJIS. Use 44px tinted squircle container badges with sleek Apple SF Symbols / vector icons.
- Zero cognitive load, everything fits comfortably above the fold.

Layout & Elements:
1. Top Navigation: iOS back button, clean step indicator 'STEP [X] OF [Y]' with [Z]% blue progress bar (#0062CC).
2. Header:
   - Punchy single headline: '[HEADLINE]' (Bold 26px, Plus Jakarta Sans, deep ink #0F172A).
   - Short 1-line subtitle: '[SUBTITLE]' (14px slate #64748B).
3. Selection Cards / Content:
   - [Card 1 (Active)]: [Vector Badge Name], '[Title]' • subtitle '[Subtitle]' (Royal blue border #0062CC, tint #EFF6FF, checkmark).
   - [Card 2]: [Vector Badge Name], '[Title]' • subtitle '[Subtitle]' (Clean white card, 1px border #E2E8F0).
4. Bottom Action:
   - Full-width 54px solid blue CTA button (#0062CC, rounded-full, crisp white text): '[CTA TEXT]'.
```

---

## 5. Master Screen Pipeline

| # | Screen ID | Stage | Key Components |
|---|-----------|-------|----------------|
| 1 | `welcome` | Onboarding | Speech bubbles mark, quote card, trust badge, Get Started |
| 2 | `goal` | Onboarding | Step 1/3, 3 squircle goal cards (Immigration, Travel, Beginner) |
| 3 | `level` | Onboarding | Step 2/3, 4 CEFR level cards (A1-B2) + 3-pill daily time selector |
| 4 | `tutor` | Onboarding | Step 3/3, Marie vs Thomas voice persona cards + audio waveform |
| 5 | `preparing` | Dynamic | Real-time checklist builder animation |
| 6 | `trial_call`| Aha Moment | Live 3-min interactive voice conversation with Marie |
| 7 | `today` | Core App | Daily session card with duration, target CEFR competency, and streak |
