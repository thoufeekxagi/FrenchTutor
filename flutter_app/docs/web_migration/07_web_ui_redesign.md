# Web UI Redesign — the ElevenLabs / shadcn pass

**Status**: In progress. Onboarding and the app shell are done. Interior screens are the remaining work; the
checklist at the bottom tracks them.

## The thing that took two failed attempts to understand

Rearranging mobile widgets will never produce the reference look. Two attempts failed before this was clear:

1. Capping the whole wizard to a phone-width strip → read as "a phone screenshot pasted onto a browser
   window", and clipped content during PageView transitions on top of that.
2. Splitting into two columns → better arranged, but still not the reference: *"the phone thing just put at
   different places."*

The actual gap is **styling, not layout**:

| | Mobile app aesthetic (what we had) | Reference aesthetic (ElevenLabs / shadcn) |
|---|---|---|
| Background | Full-bleed brand gradient | Light neutral canvas (`canvas` #F8F9FA) |
| Surfaces | Translucent white on gradient | Opaque white cards, contained |
| Borders | White at partial alpha | 1px hairline (`hairline`, ink @ 9%) |
| Text | White on colour | Dark ink; muted grey for secondary |
| Colour | Gradient everywhere | Neutral; colour reserved for ONE action |
| Depth | Colour and blur | Border + a whisper of shadow |

A gradient screen with white text cannot be made to look like shadcn by moving boxes around. The web build
needs different *styling*, which is what this pass does.

## How web-only changes are kept web-only

The founder's requirement: web changes must not touch mobile, and must be obvious later.

**Pattern: one `_web` getter per screen, and every web-only visual choice reads from it.**

```dart
/// THE web-styling switch for this screen.
bool get _web =>
    MediaQuery.sizeOf(context).width >= DesignTokens.breakpointExpanded;
```

Then, at each point where the two aesthetics genuinely differ:

```dart
color: _web ? DesignTokens.canvas : null,
gradient: _web ? null : _heroGradient,
```

Why this and not a separate web copy of each screen:

- Mobile appearance is **provably** untouched: below the breakpoint every branch falls through to the code that
  was already shipping and tested on iOS.
- All the business logic, state, validation and copy stay in one place. Nothing is duplicated, so a change to
  how a step works applies to both platforms automatically.
- `grep -n "_web" <file>` lists every web-specific decision in that screen. That is the "so when we change it,
  we'll know" property.

Where a whole pane's composition differs (not just its colours), it gets its own method rather than a thicket
of ternaries — e.g. `_webWelcomeStep()` beside `_welcomeStep()`, and `_wideStep()` beside `_step()`. Same rule:
selected by `_web`, mobile untouched.

For genuinely shared web furniture, use the primitives in `lib/widgets/web/`:
`WebPage`, `WebPageHeader`, `WebSectionHeader`, `WebCard`, `WebCardGrid`, `WebChip`, `WebAppShell`.

## Rules for matching the reference

Borrow structure and density. **Never borrow their palette** — colours always come from `DesignTokens`
(active palette `ProSystemAzure`). Concretely:

- Page background `DesignTokens.canvas`; cards `DesignTokens.surface`.
- Every card: `Border.all(color: DesignTokens.hairline)`, `radiusCard` (16), `cardShadow` at most.
- Headings `Passeport.display(...)` in `ink`. Secondary text `Passeport.body(...)` in `mutedDim`. Eyebrows and
  group labels `Passeport.mono(11)` in `muted`.
- One azure action per screen: filled `primary` background, `surface` foreground, `radiusMedium` (12).
  Everything else stays neutral.
- Generous whitespace: card padding 32-40, section gaps `space6`.
- Hover states on anything clickable. A web app without hover affordances feels dead — that is what
  `WebCard`/`WebTextAction`/`WebIconButton` already handle.
- Cards in a row must share a height (`WebCardGrid` does this). Ragged card bottoms are the single most obvious
  "not designed" tell.
- Cap content width (`kWebContentMaxWidth` 1120, or ~920 for a focused card). Full-window line lengths are the
  fastest way to look unconsidered.

## Screen checklist

Done:

- [x] **App shell** — `widgets/web/web_app_shell.dart`: sidebar + top bar, hover and active states.
- [x] **Web layout primitives** — `widgets/web/web_layout.dart`.
- [x] **Onboarding welcome** — `_webWelcomeStep()`: split hero, neutral canvas, contained proof card.
- [x] **Onboarding steps** (goal / level / interests / tutor) — `_wideStep()`: contained card, question left,
      answers right, dark ink, azure action. Header, progress bar, choice tiles and buttons all have web
      variants gated on `_web`.
- [x] **Sign-in** — `_AuthFrame` in `auth_screen.dart`: centred form-width card instead of full-window fields.

Remaining — each needs a `_web` pass using the primitives above:

- [ ] `screens/home/dashboard_screen.dart` (+ `today_mission_widget.dart`) — the landing view; highest value.
- [ ] `screens/labs/labs_screen.dart` — natural fit for `WebCardGrid`.
- [ ] `screens/labs/grammar_lab_screen.dart`
- [ ] `screens/labs/writing_lab_screen.dart`
- [ ] `screens/labs/connectors_lab_screen.dart`
- [ ] `screens/labs/alphabet_lab_screen.dart`
- [ ] `screens/labs/liaison_lab_screen.dart`
- [ ] `screens/labs/listening_lab_screen.dart`
- [ ] `screens/labs/roleplay_lab_screen.dart`
- [ ] `screens/path/path_screen.dart` (+ `learning_graph_view.dart`)
- [ ] `screens/progress/progress_screen.dart` — charts need desktop widths; see the `dataviz` skill.
- [ ] `screens/lessons/story_reader_screen.dart` — reading measure must stay capped even on a wide window.
- [ ] `screens/lessons/flashcard_session_screen.dart`
- [ ] `screens/lessons/writing_task_screen.dart`
- [ ] `screens/notes/notes_review_screen.dart`
- [ ] `screens/history/all_history_screen.dart`
- [ ] `screens/settings/settings_screen.dart` — settings rows want a capped column, not full width.
- [ ] `screens/session/session_screen.dart` — the live call; deliberately last, since it is the most
      behaviour-sensitive screen and is still pending real-hardware mic verification (Phase 5).

Suggested order: dashboard → labs list → path → progress, since those are the four sidebar destinations and
therefore the first things anyone sees after signing in.

## Verifying

```
flutter run -d chrome -t lib/dev/web_preview.dart   # primitives in isolation
flutter run -d chrome                                # the real app
```

Check every screen at **1440×900 and at 1024×768** (just above the breakpoint), and once below it to confirm
mobile still renders the phone layout. `flutter analyze` and `flutter test` must stay clean.
