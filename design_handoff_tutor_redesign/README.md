# Handoff: AI Python Tutor — UI Redesign

## What this is

This bundle is a **design reference** for redesigning the AI Python Tutor Flutter app. The HTML files inside `design_reference/` are mockups built in React/HTML to communicate look, behavior, and interaction — they are **not** code to port literally.

**Your task:** recreate these designs in the existing Flutter codebase, using the patterns already in place (Riverpod, `multi_split_view`, `flutter_chat_ui`, `flutter_code_editor`, `flutter_highlight`, Material widgets). Lift the visual tokens (colors, type, spacing, copy) faithfully; rewrite the structure idiomatically in Flutter.

**Fidelity:** high. Colors, spacing, copy, and interactions are intentional. Match them.

## How to use this with Claude Code

1. Open the Flutter project in Claude Code.
2. Drop this `design_handoff_tutor_redesign/` folder into the repo root (or any convenient place).
3. Prompt:
   > Read `design_handoff_tutor_redesign/README.md` end-to-end. Start with the theme + design tokens (Phase 1), then the app shell (Phase 2), then one mode at a time (Phase 3+). Do not run the HTML; treat it as a visual reference only.

The design files are also viewable directly: open `design_reference/Tutor.html` in any browser to see the live prototype with mode switching and the Tweaks panel.

---

## Design philosophy (read first)

The current UI has good bones (split view, chat + editor, sidebar) but suffers from:
- Heavy magenta chrome that competes with content
- A flat student/teacher hierarchy
- A static editor-always-visible layout that doesn't match what the student is actually doing
- Output panel that's just a black box
- Composer pattern that sends on Enter (kills multi-line questions)

The redesign reframes the app around four ideas:

1. **Warm "study lamp" palette.** Deep ink background, single leaf-green accent. Feels like night-coding-with-a-friend, not a notification.
2. **Adaptive workspace.** One shell, four modes — **Uitleg** (read & understand), **Oefenen** (write code), **Quiz** (test knowledge), **Vrij coderen** (playground). The left panel morphs per mode; the chat panel slides in/out.
3. **Subtle gamification.** Streak chip, XP bar, ambient progress line at the top edge of the window, and a level-up moment when concepts are unlocked. Designed for teens — present but not condescending.
4. **Chat-first.** The tutor has presence (avatar, online indicator), message types (uitleg / denkvraag / voorbeeld / goed), and a composer that respects multi-line input.

---

## Design tokens

All colors are OKLCH for perceptual consistency. Convert to ARGB for Flutter via `Color.fromRGBO` after running the OKLCH values through a converter, or use the `oklch` package if available.

### Colors — base

| Token | OKLCH | Approx hex | Use |
|---|---|---|---|
| `--ink-0` | `oklch(0.16 0.012 60)` | `#211d18` | Deepest background (canvas, code editor, output) |
| `--ink-1` | `oklch(0.19 0.014 60)` | `#28241e` | Surface (cards, sidebar, headers) |
| `--ink-2` | `oklch(0.23 0.014 60)` | `#332e26` | Raised (button bg, hover targets) |
| `--ink-3` | `oklch(0.28 0.014 60)` | `#3f3a31` | Border, hover, divider strong |
| `--ink-4` | `oklch(0.36 0.014 60)` | `#534d42` | Subtle divider |
| `--paper` | `oklch(0.96 0.012 80)` | `#f6f1e7` | Warm off-white (rare, for inverse cards) |
| `--fg`    | `oklch(0.94 0.012 80)` | `#eee9df` | Primary text |
| `--fg-mute` | `oklch(0.72 0.012 80)` | `#b1ab9f` | Secondary text |
| `--fg-faint` | `oklch(0.52 0.012 80)` | `#7d786d` | Tertiary, captions |

### Colors — accent (default: Blad + zand / leaf + sand)

The production palette pairs a leaf-green primary with a warm-sand success tone. Errors stay in the same `oklch(0.70 0.18 25)` warm-red regardless of accent variant.

| Token | OKLCH | Approx hex | Use |
|---|---|---|---|
| `--accent` | `oklch(0.78 0.13 150)` | `#7dc89f` | Primary accent (active goal, send button, highlights, current map node) |
| `--accent-2` | `oklch(0.84 0.10 85)` | `#dccf9a` | Success / done state (run OK, completed goals, praise bubble border) |
| `--accent-3` | `oklch(0.78 0.13 230)` | `#7ab9d4` | Info / hint (tutor tips in error panel) |
| `--danger` | `oklch(0.70 0.18 25)` | `#d97565` | Errors |

The other four accent variants in the prototype (Blad, Munt, Mos, Salie) are explorations only — **ship with Blad+zand**. The reason for the split: the leaf-green carries "this is the active thing," the warm sand carries "this is finished/correct." Using the same green for both flattens the hierarchy.

### Code syntax colors (for `flutter_code_editor` / `flutter_highlight`)

The current `monokai-sublime` theme is fine but feels disconnected from the new palette. Define a custom theme:

| Token | OKLCH | Use |
|---|---|---|
| `--syntax-kw` | `oklch(0.78 0.16 320)` | Keywords (`if`, `elif`, `for`, `def`) — soft pink |
| `--syntax-str` | `oklch(0.78 0.16 150)` | Strings — leaf |
| `--syntax-num` | `oklch(0.78 0.16 65)` | Numbers — amber |
| `--syntax-com` | `oklch(0.55 0.014 80)` | Comments — italic, muted |
| `--syntax-fn` | `oklch(0.78 0.16 250)` | Function calls — blue |
| Identifiers | `var(--fg)` | |
| Operators | `var(--fg-mute)` | |

### Typography

- **UI font**: `Inter Tight` (weights 400, 500, 600, 700, 800). Add to `pubspec.yaml` as a Google Font.
- **Mono / code**: `JetBrains Mono` (weights 400, 500, 600). Already implied by current `fontFamily: 'monospace'` — replace.
- **Numbers** (XP, streak, percentages): use Inter Tight with `tnum` feature for tabular figures, OR JetBrains Mono. The prototype uses `font-feature-settings: "tnum" 1` on a `.num` class.

#### Type scale

| Use | Family | Size | Weight | Line height | Letter spacing |
|---|---|---|---|---|---|
| Hero number (level-up "Level 5") | Inter Tight | 64 | 800 | 1.0 | -2 |
| Page title (h1) | Inter Tight | 26–36 | 700 | 1.1 | -0.3 to -0.5 |
| Section title | Inter Tight | 16 | 600 | 1.3 | 0 |
| Body | Inter Tight | 14–14.5 | 400 | 1.55 | 0 |
| Body emphasis | Inter Tight | 14 | 600 | 1.55 | 0 |
| Label / pill | Inter Tight | 11 | 600 | 1.4 | 0.4, uppercase |
| Caption | Inter Tight | 11.5 | 400 | 1.4 | 0 |
| Code / mono | JetBrains Mono | 13–14 | 400 | 1.55–1.65 | 0 |
| Kbd | JetBrains Mono | 10.5 | 400 | 1.4 | 0 |

### Spacing

The prototype uses arbitrary px; standardize to a 4-pt scale:

`4, 6, 8, 10, 12, 14, 16, 18, 22, 28, 36`

Map to Flutter `EdgeInsets`. Most cards use 14–18 padding; page padding is 28–36.

### Border radius

| Use | Radius |
|---|---|
| Pills | 999 (full round) |
| Inputs, buttons (small) | 8–10 |
| Cards | 12–14 |
| Bubbles | 14 |
| Modal | 16 |
| Avatar | size / 2 |

### Shadow

Avoid shadows except:
- Active/hovered avatar: `0 4px 12px color-mix(in oklab, var(--accent) 25%, transparent)`
- Active subway map node: `0 0 0 4px color-mix(in oklab, var(--accent) 15%, transparent)` (a "ring" not a drop shadow)

### Easing & duration

| Use | Easing | Duration |
|---|---|---|
| Mode swap (left panel content) | `cubic-bezier(.2,.8,.2,1)` | 260 ms |
| Chat panel slide in/out | `cubic-bezier(.2,.8,.2,1)` | 380 ms |
| Mode switcher fade | ease | 220 ms |
| Hover (color/bg) | ease | 120 ms |
| Progress bar fill | `cubic-bezier(.2,.8,.2,1)` | 600–800 ms |
| Level-up popup | `cubic-bezier(.2,.9,.2,1.2)` | 320 ms |

In Flutter, use `Curves.easeOutCubic` (close to the prototype's bezier) for layout transitions, and `AnimatedContainer` / `AnimatedSwitcher` / `AnimatedSize` for the implementations.

---

## Existing codebase reference

The Flutter project lives at the repo root (no nested project folder). Relevant files (paths relative to `lib/`):

```
features/
  auth/
    sign_in_page.dart
    local_key_gate_screen.dart
  account/
    accounts_page.dart
    detail/
  dashboard/
    dashboard.dart           ← MAIN SHELL — replace with new mode-aware layout
    controllers.dart         ← run/stop/reset bar — refactor into RunControls widget
    editor.dart              ← code editor wrapper — keep, restyle
    output.dart              ← output panel — replace with new design
    editor_controller.dart
    debug_dialog.dart
  chat/
    chat_widget.dart         ← MAIN CHAT — restyle bubbles, add role chips, new composer
    composer_continue_widget.dart
    composer_wait_widget.dart
    composer_mcq_wait_widget.dart
    composer_shell_widget.dart
    mcq_options_widget.dart  ← MCQ rendering — keep logic, restyle (and consider promoting to full-screen Quiz mode)
  goals/
    goals_page.dart          ← teacher tool, restyle only
    editor/, child_*, root_*, dnd.dart, tree_utils.dart
  instructions/
    instructions_editor_page.dart  ← teacher tool, restyle only
    doc_*, section_header.dart, sections_list.dart, editor_pane.dart
  progress/
    student_progress_list.dart
    goal_tile.dart           ← restyle to match new MapView card
```

Services already in place (do not duplicate):
- `tutor_service.dart` (Riverpod) — owns `TutorState` (idle / working / hasFollowUp)
- `chat_service.dart` — owns the `ChatController` and message stream
- `code_service.dart` — owns the `CodeController`
- `mcqPendingProvider`, `streamStateProvider`

---

## Implementation phases

### Phase 1 — Theme & tokens

1. Add **Inter Tight** and **JetBrains Mono** to `pubspec.yaml` via `google_fonts` package.
2. Create `lib/theme/tokens.dart` with `Color` constants for every token in the table above. Convert OKLCH → sRGB once; don't compute at runtime.
3. Create `lib/theme/app_theme.dart` exporting a single `ThemeData` (dark only — there's no light mode). Set:
   - `scaffoldBackgroundColor: AppColors.ink0`
   - `colorScheme: ColorScheme.dark(primary: AppColors.accent, surface: AppColors.ink1, ...)`
   - `textTheme` using `GoogleFonts.interTightTextTheme()` mapped to the type scale.
4. Replace `monokai-sublime` in `features/dashboard/editor.dart` with a custom `Map<String, TextStyle>` matching the syntax color table. Keep `flutter_code_editor`'s `CodeTheme` API.

### Phase 2 — App shell

Replace `features/dashboard/dashboard.dart` entirely. New top-level structure:

```
Scaffold
└── Row
    ├── Sidebar (72 wide)
    └── Expanded
        └── Column
            ├── TopBar (height ~64) — ambient progress at very top edge
            ├── AnimatedSize wrapping the workspace
            └── Expanded
                └── Row
                    ├── AnimatedContainer (left panel — flex-animated)
                    │   └── AnimatedSwitcher keyed on `mode`
                    │       └── ExplainView | EditorView | QuizView | FreeView
                    └── AnimatedContainer (chat panel — width-animated 0..460)
                        └── ChatView
```

- **Sidebar** (`lib/features/shell/sidebar.dart`): vertical icon column. Logo block at top (40×40, gradient). Student items always render. Teacher items render only if `PROFILE.role == 'teacher'` (the user confirmed teacher detection is already wired). Active item gets a 3px accent rail on the left and tinted background.
- **TopBar** (`lib/features/shell/top_bar.dart`): "Hoi {name}, aan de slag met X" on left; centered ModeSwitcher (segmented control of 4 modes); StatStrip (streak chip + XP bar + level) on right. The ambient progress line is a 2px-tall absolutely-positioned bar at the top edge, fed from a `Provider<double>` that aggregates session progress.
- **ModeSwitcher**: 4 buttons, active one has `ink-3` bg. Fades out when not in session view.

### Phase 3 — Sessie modes (the heart)

Each mode is one widget under `lib/features/session/modes/`.

#### Uitleg (Explain)
- Full-bleed scrollable canvas, max-width ~680.
- "Concept" pill + "2 / 4" counter at top.
- Big h1 title with inline `mono accent` words.
- A "**Hoe Python eraan denkt**" card showing the elif ladder as a numbered table: step number circle / `als <cond>` / `→` / output value. Each row separated by dashed divider.
- A blue-tinted "Belangrijk" callout below explaining ordering.
- Footer: prev button (ghost) / "Probeer het zelf →" (accent) / "+10 XP bij voltooien" caption.

#### Oefenen (Practice)
- Left panel = current dashboard layout, refined:
  - **ObjectiveBanner** (bg: ink-1, ~12px padding): "Huidig doel" pill + goal title + sub-line "Doel … gebruiken · 5% voltooid".
  - **RunControls** (bg: ink-1, 10px padding): green accent-2 "Run ⌘↵" button when idle; danger-tinted "Stop" with border when running. Reset icon button (ghost). On the right: hint icon + send-to-tutor icon (both ghost). **No file/version pill.**
  - **CodeArea**: full-flex code editor. Line numbers in `fg-faint`, gutter width 22. Editor uses the custom syntax theme.
  - **OutputPanel** (~160–220 height, bg: ink-1):
    - Header: status dot (idle: faint / running: accent pulse / ok: accent-2 / error: danger) + "Output" label + "· {state label}". **No tabs.**
    - Body: mono 12.5pt. On error: traceback in `fg-mute`, the actual error in `danger`, and a tutor hint card at the bottom (bg tinted `accent-3`).
- Right panel = ChatView (see Phase 4).

#### Quiz
- Full-bleed, no chat panel (chat slides closed).
- "Quiz vraag 3 / 5" pill + segmented progress bar on the right (small pill segments: green=correct, dark=upcoming, accent=current).
- Big h2 prompt.
- Code block in a card.
- 2-column grid of option buttons. Each option: A/B/C/D mono badge in a rounded square, then mono label. On answer: correct turns accent-2, wrong selection turns danger.
- Re-use `mcq_options_widget.dart` logic; this is just a different presentation of the same data.

#### Vrij coderen (Free)
- Same as Practice but **no** ObjectiveBanner.
- Header strip: "speeltuin" pill + caption "Geen doel — alleen jij en Python." **No share-with-tutor link** (the existing send icon in RunControls is the only entry).
- Chat panel hidden.

### Phase 4 — Chat panel

`features/chat/chat_widget.dart` — keep `flutter_chat_ui` but heavily customize.

**Header** (~14px padding 22, bottom border `ink-2`):
- Tutor avatar (32) — gradient circle with sparkle icon
- "Tutor" name + "online · helpt je met `elif`" sub-line (online dot in accent-2, "elif" mono fg-mute)
- Restart icon button (ghost) on the right

**Bubbles**:
- **Tutor messages** carry a small *role chip* above the bubble:
  - `uitleg` (info-blue tint, lightbulb icon) — explanations
  - `voorbeeld` (default tint, code icon) — code samples
  - `denkvraag` (accent tint, question icon) — questions back to student
  - `goed` (success tint, check icon) — praise
- Tutor bubble: `ink-1` bg, `ink-2` border, 14 radius. Width max 82%.
- Student bubble: solid `accent`, `ink-0` text, 14 radius, no border.
- Praise bubbles get a green-tinted bg + border.
- System messages: small italic centered pill with dashed border, `fg-faint`.
- Time stamp below each bubble in 10.5 `fg-faint`.

**Code bubble** (when tutor sends a code sample):
- Inner card with `ink-2` header showing filename and "Probeer dit" link.
- Body: rendered with the syntax theme.

**Composer states** (these widgets already exist — restyle):
- `idle` → `Composer` with multi-line `TextField` (rows: 2, max ~140). Placeholder: "Typ je vraag of antwoord…". Send button on the right (accent when text is non-empty, default otherwise). **`Cmd/Ctrl + Enter` sends; plain `Enter` inserts newline.** Hint footer below: `⌘↵ verstuur` · `↵ nieuwe regel` · "tip: typ `?` om een hint te vragen" (right-aligned). **No lightbulb button** — the `?` shortcut is the canonical hint trigger.
- `thinking` → small pill: tutor avatar + 3 bouncing dots + "Tutor denkt na…".
- `continue` (when `TutorState.hasFollowUp`) → accent-tinted bar with "Klaar voor het volgende stuk?" + "Ga verder ↵" button.
- `mcqPending` → keep current behavior (composer disabled).

### Phase 5 — Sidebar sections (non-session)

- **Leerpad / Voortgang** (same view): full-page list of goals as cards. Active goal card uses a tinted bg + accent border; expanded view shows children as a horizontal row of small cards inside the parent. Each goal has a 32px circle (number / check / lock), title, animated progress bar, and a "Verder" CTA when active.
- **Studenten** (teacher only): table with columns Email / Naam / Streak / Huidig doel / Voortgang. Stripe-less; rows separated by `ink-2` border-top. Header row uses uppercase 11 `fg-faint`.
- **Doelen** / **Instructies** (teacher only): keep the existing `goals_page.dart` and `instructions_editor_page.dart` widget trees; only restyle (theme + spacing).

### Phase 6 — Gamification details

- **Ambient progress rim**: 2px line at the top edge of TopBar, gradient from `accent` to `accent-2`. Animated to its target % over 800 ms.
- **Streak chip** (TopBar right): pill with flame icon (accent-tinted) + tnum number + "dagen". 6×10 padding, ink-1 bg.
- **XP bar** (TopBar right): vertical stack inside a pill — top row "Level 4" + "1240 / 1500" tnum mono on the right; below, a 3px progress bar.
- **Level-up moment**: full-screen overlay (`color-mix(ink-0, 80%) + 8px blur`). Center stack: small uppercase amber caption "+20 XP · concept ontgrendeld", giant 64pt 800-weight tnum "Level 5", subtitle "Je hebt de elif-ladder onder de knie.", "Verder leren →" accent button. Pop-in animation: `cubic-bezier(.2,.9,.2,1.2)` 320 ms with scale 0.92→1 + fade.

  **Trigger logic** (the prototype only exposes this via the Tweaks panel because the prototype has no real XP source — in production it must be event-driven):
  - Add a `LevelUpController` (Riverpod `StateNotifier<LevelUpEvent?>`) at the app shell level.
  - In the tutor / progress service, after every XP award, check whether the new total crosses a level threshold (e.g. `floor(xp / 1500)` increased). If yes, push a `LevelUpEvent { newLevel, xpAwarded, conceptName }` onto the controller.
  - The shell listens; when the value is non-null it shows the overlay with `AnimatedSwitcher` + the bezier above. Tapping "Verder leren" (or anywhere outside the card) sets the controller back to null.
  - Concrete unlock points to wire up first: completing any goal whose `kind == 'concept'` in the curriculum tree, finishing a quiz with ≥80% correct, hitting a 7-day streak. The exact thresholds belong in `lib/services/progression_service.dart`.
  - **Don't** trigger on every small XP gain — the moment should feel rare (target: 1–2× per session at most). If you find yourself wanting more frequent feedback, that's what the streak chip and ambient rim are for.

---

## Copy strings (Dutch — keep verbatim)

| Where | String |
|---|---|
| TopBar greeting | `Hoi {name},` / `aan de slag met {topic}` |
| Mode tabs | `Uitleg` · `Oefenen` · `Quiz` · `Vrij coderen` |
| Sidebar (student) | `Sessie` · `Leerpad` · `Voortgang` |
| Sidebar (teacher) | `Doelen` · `Instructies` · `Studenten` |
| Sidebar header | `Docent` |
| Run button | `Run ⌘↵` |
| Output state labels | `Geen output` · `Aan het uitvoeren…` · `Klaar in 0.04s` · `1 fout` |
| Output empty hint | `Druk op **Run** om je code uit te voeren.` |
| Output error tutor card prefix | `Tutor zegt:` |
| Composer placeholder | `Typ je vraag of antwoord…` |
| Composer hint footer | `⌘↵ verstuur` / `↵ nieuwe regel` / `tip: typ ? om een hint te vragen` |
| Thinking state | `Tutor denkt na…` |
| Continue prompt | `Klaar voor het volgende stuk?` / `Ga verder ↵` |
| Free mode header | `speeltuin` · `Geen doel — alleen jij en Python.` |
| Quiz progress | `Quiz vraag {n} / {total}` |
| Tutor presence | `online · helpt je met {topic}` |
| Goal pills | `Huidig doel` |
| Streak suffix | `dagen` |
| Level-up | `+20 XP · concept ontgrendeld` / `Level {n}` / `Je hebt de {concept} onder de knie.` / `Verder leren →` |
| Map view | `Leerpad` / `Python — beginnersreis` / `Verder` (CTA on active goal) / `voltooid` |

---

## State management additions

You may need new providers (Riverpod):

```dart
final modeProvider = StateProvider<SessionMode>((_) => SessionMode.explain);
final sectionProvider = StateProvider<Section>((_) => Section.session);
// Existing providers cover the rest:
//   tutorServiceProvider, chatServiceProvider, codeServiceProvider,
//   mcqPendingProvider, streamStateProvider
```

`SessionMode` is `{ explain, practice, quiz, free }`. `Section` is the sidebar tab `{ session, map, progress, goals, instructions, students }`.

For gamification, expose:
```dart
final profileProvider = StateNotifierProvider<ProfileNotifier, Profile>((_) => ...);
// Profile has: name, level, xp, xpNext, streak, role.
final ambientProgressProvider = Provider<double>((ref) {
  // Aggregate from current goal % + recent successful runs.
});
```

---

## Things explicitly removed in the redesign

These were in the original UI; do NOT bring them back:

- The magenta title bar and any persistent magenta chrome (replaced by a flat ink TopBar)
- Centered "{Goal title}" header above the editor (replaced by ObjectiveBanner inside the left panel)
- "Welcome back, Yvan" heavy header (now a small caption above the topic line)
- Tab labels "terminal" / "variabelen" in the output panel (fake; not implemented)
- "main.py · Python 3.12" version pill in RunControls (irrelevant — only one file)
- "+ deel met tutor" link in Vrij coderen (redundant with the send-to-tutor icon)
- Lightbulb button in the chat composer (redundant with `?` shortcut)
- Subway-map strip below the TopBar (too noisy on small laptop screens)
- Student/teacher role toggle in the TopBar (auto-detected from `PROFILE.role`)

---

## Files in this bundle

```
design_handoff_tutor_redesign/
├── README.md                            ← you are here
├── design_reference/
│   ├── Tutor.html                       ← live prototype (open in any browser)
│   ├── tweaks-panel.jsx                 ← Tweaks panel host (ignore — design-time only)
│   └── src/
│       ├── icons.jsx                    ← icon set (re-implement with flutter_svg or material icons)
│       ├── data.jsx                     ← sample data (curriculum, profile, MCQ, chat)
│       ├── parts.jsx                    ← Pill, Avatar, ProgressBar, IconButton, Kbd, Card, syntax highlighter
│       ├── chat.jsx                     ← Chat column, bubbles, composer, MCQ inline
│       ├── editor.jsx                   ← Editor column, RunControls, CodeArea, OutputPanel, ObjectiveBanner
│       ├── modes.jsx                    ← ExplainMode, ModeSwitcher, StatStrip, SubwayMap (deprecated)
│       ├── shell.jsx                    ← Sidebar, TopBar, QuizMode, FreeMode, MapView, TeacherStudents
│       └── app.jsx                      ← Top-level wiring + AnimatedSwap + level-up moment
```

**The prototype `Tutor.html` is the single source of truth.** Open it in a browser (it's self-contained — no server needed), switch modes, click around. Use the Tweaks panel (toolbar in this design tool) to:
- Cycle accent variants — but ship with **Blad+zand** (the default).
- Trigger the level-up overlay manually for layout reference. In production this is event-driven, not a button — see Phase 6.

Every interaction described in this README is live in the prototype. When the README and the prototype disagree, the prototype wins.
