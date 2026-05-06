# TODO

The UI redesign (new shell, Sidebar + TopBar, four session modes) is in. The
remaining work is wiring the new surfaces to real data and adapting the
underlying flow (conductor, content authoring, entry points) to the new
shape. Phases A–E are post-redesign work; Phase 6 is the gamification
backlog inherited from the redesign and still valid as written.

---

## Phase A — Authored explanations ("Uitleg")

Right now `explain_view.dart` ships hard-coded sample content. We want each
subgoal to have an authored explanation block, and we want the teacher to
manage those blocks in an ordered, browsable view that mirrors the
curriculum.

### Source of truth

The **goal tree is the single source of truth for ordering.** The "Lesinhoud"
teacher view is an alternative *view* over the goal tree, focused on content
authoring rather than skill structure. A content block is referenced from
exactly one subgoal in the typical case (technically reusable, but the UI
presents it in subgoal context). This avoids maintaining two parallel
hierarchies.

A content block exists per subgoal (the natural division — and it doubles
as a sound pedagogical unit: small, focused mini-explanations).

### Data model

**New container `content`**, single-partition (`/type = "content"`),
matching the pattern of `goals` and `instructions`.

`content/{id}`:
- `id: string`
- `type: "content"`
- `title: string` — for in-app display and the teacher's overview
- `body: string` — markdown
- `updatedAt: string`

**New container `modules`**, single-partition (`/type = "module"`).
Wire
 d into the data layer now even though only one module exists in
practice (`Python basics`). Module-management UI is deferred — for v1, a
single module is auto-created and every goal points at it. The teacher
cannot yet create or reorder modules from the UI.

`modules/{id}`:
- `i
 d: string`
- `type: "module"`
- `title: string`
- `order: int`
- `updatedAt: string`

**`Goal` gets two new fields:**
- `contentId: string?` — null when no authored explanation yet (transient
  during authoring; target state is non-null for every leaf subgoal)
- `moduleId: string` — ython basics" module for eun)
 
### Markdown conventions for `body`

To match the visual language of the redesigned Uitleg canvas (code card,
info callout, headings) without building a block editor, agree on a small
set of markdown conventions:

- ` ```python ` fenced blocks render as the "Hoe Python eraan denkt" code
  card.
- `> [!info] ` (or similar) renders as the info callout pill.
- Standard markdown headings/paragraphs render as expected.

If hand-authoring these conventions becomes painful, revisit a structured
block model later — but don't pre-build it.

### Editor: "Lesinhoud" view

New teacher-only section in the sidebar: `Lesinhoud`, peer of `Doelen` and
`Instructies`. Layout: a left-side ordered tree rendered **from the goal
tree** (module → root goals → subgoals), with each subgoal row showing
either the linked content's title or "(geen lesinhoud)" plus a
create-or-edit affordance. Right pane: markdown editor for the selected
subgoal's content (use `flutter_code_editor` with markdown highlighting,
same pattern as `InstructionsEditorPage`).

This view does not allow reordering — that lives in `GoalsPage`. It's
strictly a content-authoring surface that uses the curriculum's existing
order to guide the teacher through writing explanations in sequence.

The existing `GoalsPage` subgoal editor stays as the place to create or
unlink a content block for a subgoal (small "lesinhoud" affordance with
create / select / clear actions). No standalone "list of all content docs"
surface — content is always seen in subgoal context.

### Render

`explain_view.dart` reads `goalSelectionProvider.activeChildGoal.contentId`,
loads the matching `content` doc, and renders its `body`. **Keep the
existing visual layout** — header pill, code card style, callout pill,
footer with Vorige / Probeer het zelf — and have the markdown renderer feed
into it. The visual design is good; we're swapping the content source, not
redesigning.

For the (transient) case where `contentId` is null, show a placeholder
("nog geen lesinhoud beschikbaar") so the teacher notices missing blocks
during authoring. Don't hide the Uitleg tab — keeping it visible makes the
gap obvious.

---

## Phase B — Merge Quiz into Oefenen (response-type-driven render)

The student should never have to choose between Quiz and Oefenen — the
conductor already decides whether the next exercise is an MCQ, a
write-code, a complete-code, etc. The Quiz *tab* goes away, but the Quiz
*render* stays — it's good visual work and we want it for MCQs inside the
practice surface.

### Changes

- Remove `SessionMode.quiz` from `shell_state.dart`.
- Remove the Quiz entry from the TopBar `ModeSwitcher`.
- Inside `PracticeView`, switch the rendered layout based on the type of
  the in-flight exercise:
  - MCQ → use the existing quiz layout (lifted from `quiz_view.dart`,
    wired to live data).
  - Write-code, complete-code, explain-code → existing
    editor + output + chat layout.
- `quiz_view.dart` itself becomes a render component imported by
  `PracticeView`, not a top-level mode view. Keep the file (don't delete
  the visual work) but it no longer corresponds to a `SessionMode`.

### MCQ chat behaviour: hide chat during MCQ

Today MCQ flows through the chat panel via the `mcq_options` custom message
+ `mcqPendingProvider`. When MCQ rendering moves into `PracticeView`, the
chat panel should **collapse / animate out** while an MCQ is active and
return after the student answers. Provide focus rather than asking the
student to focus.

Mechanism: `SessionView` already animates the chat panel in/out for free
vs practice modes — same animation primitive, gated additionally on
`mcqPendingProvider`. The MCQ exchange (question + chosen answer +
feedback) is not added to chat history while the chat is hidden; consider
whether to backfill a compact summary into the chat timeline once the
question is answered, or let the MCQ live entirely outside the chat
record. Lean toward the latter for simplicity unless review feedback
makes the chat history feel incomplete.

---

## Phase C — Entry-point flow

The old "request new exercise" button is gone, which is correct. The new
entry point is the **"Probeer het zelf →"** button at the bottom of Uitleg:
clicking it switches `modeProvider` to `SessionMode.practice` and triggers
the conductor to request the first exercise.

### Behaviour

- "Probeer het zelf" on Uitleg → switch to Oefenen + call
  `tutorService.requestExercise()` (or whichever public method already
  exists on `TutorService` for this).
- Entering Oefenen on a subgoal that has no in-flight exercise → auto-request
  one. This covers the resume case (student closes app mid-subgoal,
  reopens, goes straight to Oefenen).
- Entering Oefenen on a subgoal with an in-flight exercise → render the
  existing one (no new request).
- "Vrij coderen" never auto-requests; it's a sandbox.

### Default landing mode

When the student picks a subgoal in Leerpad and lands in Sessie, decide the
default mode:
- New subgoal (progress == 0): land on **Uitleg**.
- Resumed subgoal (progress > 0): land on **Oefenen**.
- Subgoal without authored content: land on **Oefenen** regardless.

---

## Phase D — Conductor: drop the guiding phase

Today the conductor's `guiding` phase fires a single guidingQuestion at the
start of every fresh subgoal and only advances once `understanding` ≥ 0.8.
With authored Uitleg replacing that role for every subgoal, the guiding
phase becomes redundant.

### Change

Remove the guiding phase from the conductor's phase-selection logic. First
exercise after "Probeer het zelf" goes straight to **practice** (or warm-up
on resume, per the existing rules).

While Phase A authoring is incomplete and some subgoals don't yet have a
`contentId`, the placeholder render in `explain_view.dart` is enough — the
student still clicks "Probeer het zelf" and lands in practice. No
fallback path through guidingQuestion is needed; the gap is a teacher
visibility issue, not a runtime fallback.

The `guidingQuestion` / `guidingAnswer` request types and their handlers
stay in the codebase for now in case we want to repurpose them later (see
follow-up below); they just stop being invoked.

### Future follow-up (not in this phase)

Optional "ik snap dit al, sla over" button on Uitleg that fast-forwards
strong students past the practice opener — would re-purpose
`guidingQuestion` as a quick check before fast-forwarding. Defer until we
see whether authored content + warm-up is enough on its own.

---

## Phase E — Carry-over fixes

### E.1 Progression on easy

A student can currently muddle through on `easy` difficulty and still
complete a subgoal. Mastery should require demonstrating understanding at
medium or hard, not just a streak of easy correct answers.

Likely change: in the conductor's mastery check, require the streak to
include at least one non-easy correct answer (or N answers above easy).
Pin down the exact rule when implementing — don't over-engineer.

### E.2 Python packages

The student environment should support `matplotlib`, `pandas`, `numpy`,
`turtle` at minimum. This is a `py_runner` / installer concern — bundle
the packages with the Python host.

### E.3 GoalSplashOverlay

The completion splash stays visible too long. Either shorten the duration
or make it dismissable on tap/click. Tap-to-dismiss is the better UX
because completion duration shouldn't depend on whether the student looked
away.

### E.4 Error handling pass

Existing TODO entry "Fix errors" — vague. Walk the app and identify
remaining unhandled error paths, especially around streaming failures,
Cosmos transient errors that don't trip `safeCosmos`, and `py_runner`
crashes. Make this a real list before working it.

### E.5 Dead code cleanup

`home_shell.dart`, `theme.dart`, `features/dashboard/dashboard.dart`,
`features/dashboard/output.dart`, `features/dashboard/controllers.dart`,
`features/dashboard/editor_controller.dart` are no longer wired into the
new shell. Delete them once Phases A–C are stable enough that we're sure
nothing in there is silently still referenced.

---

## Phase 6 — Gamification logic (UI is in, data flow is not)

The redesign's gamification surfaces — streak chip, XP bar, ambient progress
rim, and the level-up overlay — are built and theme-correct, but every one of
them currently reads from a placeholder. Real numbers need a data source. None
of these are blocking other phases; they're a coherent backlog to tackle when
we want progression to feel "alive".

### 1. XP & level (`profileProvider.level`, `xp`, `xpNext`)

Today: hardcoded `level: 1, xp: 0, xpNext: 1500` in `shell_state.dart`.

We need to decide where XP comes from. Options:

**(a) Derive from existing progress docs.** Walk `Progress.progress` over all
non-optional goals, multiply by per-goal XP (constant, e.g. 100 per subgoal),
sum. Pros: no new collection, no migration, retroactive for current students.
Cons: XP only changes when `Progress.progress` changes; hard to award XP for
"streak day" or "ran code 50 times". Caps at the curriculum's total.

**(b) New `xp_events` collection.** Append-only ledger: `{uid, ts, kind,
amount, sourceId}`. `kind` ∈ {subgoal-completed, mcq-correct, run-success,
streak-day, …}. Sum on the client to get current XP. Pros: flexible, audit
trail, easy to add new XP sources. Cons: extra writes on every nudge, needs a
read-side cache or periodic rollup once the ledger grows.

**(c) Hybrid.** Derived XP from progress (a) + a small `xp_bonus` integer on
the account doc for one-off awards (streak rewards, easter eggs). Pros:
cheap, mostly retroactive. Cons: two sources of truth.

Recommended next step: pick **(a)** as v1 with a single XP-per-subgoal
constant. The visualisation already exists — the only code change is making
`profileProvider` async and aggregating. Move to **(b)** when we want
finer-grained awards (per correct answer, etc.).

`xpNext` formula (regardless of source) wants to be defined too. The simplest
sane default: `xpNext = 1500 * level` (gentle ramp). Alternatives: flat 1500,
exponential (`1000 * 1.4^level`).

### 2. Streak (`profileProvider.streak`)

Today: hardcoded 0.

A "streak day" = the student had a session with at least one tutor turn.
Options:

**(a) Derive from `Progress.lastSessionAt`.** Walk all progress docs, dedupe
to distinct calendar days (in the student's local TZ — needs a stored TZ on
account, or fall back to UTC), count consecutive days back from today. Pros:
no new collection. Cons: imprecise (lastSessionAt overwrites every upsert, so
a "streak day" only registers if some progress changed that day — students
who only chatted but didn't make progress lose the day).

**(b) New `session_days` collection or per-account `streakDays` field.**
On every successful tutor reply, write today's date (idempotent via composite
key `{uid}_{yyyy-mm-dd}`). Compute streak = longest tail of consecutive days
ending today/yesterday. Pros: precise. Cons: 1 write per session.

**(c) Bake into account doc.** `account.streakDays: int`,
`account.streakLastDate: yyyy-mm-dd`. On every tutor reply: if
`streakLastDate == today` → no-op; if `== yesterday` → increment; else →
reset to 1. Pros: one int, zero queries. Cons: lossy (no history),
hard to audit, easy to drift on TZ boundaries.

Recommended: **(c)** for v1 — a single int field is the cheapest path to a
working streak chip. Wire the increment in `tutorService._runStream` after a
successful `completeStream`. The TZ edge cases stop mattering once we add a
"resumed your streak" recovery window (e.g. 36 h grace).

Decide on grace window before wiring: lose-on-miss (strict) vs 36 h grace
(forgiving). Teens drop streaks they care about — recommend 36 h.

### 3. Ambient progress rim (`ambientProgressProvider`)

Today: returns 0 — the line is invisible.

The README calls it "an aggregated session-progress signal". What gets
aggregated is the open question:

**(a) Current child goal's progress.** Reads
`progressService.byGoalId(goalSelection.activeChildGoal)`. Simplest. Resets
to 0 every time the conductor moves to the next subgoal — the rim acts as
"how close to finishing this subgoal". Matches the prototype's behaviour.

**(b) Active root's average progress.** Average across the root's children.
Smoother (rim climbs over a longer arc). Loses the "I just finished
something" beat (a) gives.

**(c) Recent run-success rolling window.** Last N tutor turns with a "good"
outcome / N. Decouples rim from curriculum entirely. Feels most "alive" but
fairly unmoored from progression.

Recommended: **(a)**. It's the same data the goal tile already reads, no
extra plumbing, and the satisfying "fill up over a subgoal" arc is exactly
what the rim was sketched for.

### 4. Level-up trigger (`levelUpControllerProvider.push(...)`)

Today: only the debug dialog can push events ("Show level-up overlay" button).
The overlay itself is wired and animates correctly.

The README calls out the policy explicitly: "the moment should feel rare
(target: 1–2× per session at most)". Concrete unlock points the README
suggests, ranked by how cleanly they map to existing data:

**(a) Crossing a level threshold from XP.** As soon as #1 above lands,
compare `floor(oldXp / xpNext) < floor(newXp / xpNext)` after every
XP-awarding event and push. Easy, but only as good as the XP source — it'll
fire whenever XP crosses 1500 (or whatever curve we pick).

**(b) Completing a `kind == 'concept'` goal.** Requires adding a `kind` field
to `Goal` and back-filling it on the curriculum tree. Most "narrative"
because the overlay's subtitle already reads "Je hebt de {concept} onder de
knie" — the concept name is right there in the goal title.

**(c) Quiz performance (≥80 % on a quiz session).** Needs a quiz-summary
event we don't emit yet. Defer until quiz mode is wired to live MCQ data.

**(d) Streak milestone (7 / 30 / 100 days).** Easiest once #2 lands — just
check `newStreak in {7, 30, 100}` after the increment.

Recommended sequencing: **(b)** first because it's the README's narrative
hook and only needs a `Goal.kind` field. Then **(d)** as a free win after
the streak counter ships. Skip **(a)** until XP feels meaningful.

Throttling: keep a `_lastLevelUpAt` timestamp in `LevelUpController` (or
just check `state == null`) and refuse to push more than one per N minutes
to enforce the "rare" feel — protects against a chain of subgoal completions
in one sitting all firing the moment.

### Wiring order (concrete)

When ready to start, the dependency order is:
1. Pick + implement #2 (streak) — smallest, lights up the streak chip.
2. Pick + implement #1 (XP) — lights up the XP pill.
3. Pick + implement #3 (ambient rim) — purely additive once #1 lands.
4. Pick + implement #4 (level-up trigger) — depends on whichever of #1, #2,
   or a `Goal.kind` migration we go with.

Until then, the surfaces sit at 0/0/Level 1 and the only way to see the
overlay is the debug dialog button.

---

## Suggested overall sequencing

A → C → B → D → E → Phase 6.

Rationale: A unblocks C (Probeer het zelf only makes sense once Uitleg has
real content), C unblocks B (auto-request flow needs to exist before MCQ
rendering moves), D depends on A (the skip rule needs `contentId`), E and
Phase 6 are independent and can slot in whenever.


# future ideas
- lesinhoud zou een code en preview moeten bevatten
- lesinhoud met meer mogelijkeden. Markdown moet ook html blocks ondersteunen zodat we geavanceerde visualisaties kunnen toevoegen.
- en dat zorg ervoor dat de uitleg module voor de leerlingen waarschijnlijk ook meer geavanceerd moet. Misschien met een volledige webview en md to html format?
- als ik bij goals klik op de content (bewerk) dan komen we wel in de lesinhoud page terecht, maar de juiste content wordt niet geselecteerd.

In het code output widget kunnen we maar één regel selecteren. Niet handig om uitleg te vragen over output.

- als je wisselt van oefenen naar vrij coderen, dan wordt de inhoud van de code editor overgenomen. De inhoud zou voor beiden afzonderlijk moeten zijn.

- we hebben een systeem nodig om de leerlingen in vrij coderen code te kunnen laten opslaan en terug laden. (file browser)

- vrij coderen klinkt wat knullig. Misschien beter 'playground'?