# TODO

Content items are lost when importing and overwriting goals. They still exist in azure, but are in an abandoned state. We need a way in the content editor to reassign them to a subgoal.


## Phase E — Carry-over fixes

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