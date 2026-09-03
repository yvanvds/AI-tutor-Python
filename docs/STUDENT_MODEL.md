# Student model

Part 2 of the conductor redesign. Defines the per-student runtime state
that the conductor reads to decide what to do next, and updates after
every answer. Where the curriculum model is authored and stable, the
student model is updated on every answer and lives for the lifetime of
the student account.

This document does **not** cover:

- The curriculum data model — part 1.
- What the LLM emits per answer — part 3.
- The conductor's decision policy (when to promote/demote, how big each
  evidence bump is, mastery thresholds) — part 4.

## Goals this model serves

The student model is the data side of the three redesign goals:

1. **Advance when ready, no sooner no later** → per-LO belief.
2. **Calibrate difficulty across sessions and subgoals** → per-student
   difficulty calibration.
3. **Avoid redundant questions** → recent activity per LO and per
   question type.

## Three components

### 1. Per-LO belief (Beta distribution)

For every LO the student has been exposed to, store a belief about
whether they have mastered it. Modelled as a Beta distribution
parameterized by `(α, β)`:

- `α` — pseudo-count of "evidence they have it"
- `β` — pseudo-count of "evidence they don't"
- Mean belief = `α / (α + β)` — point estimate
- `α + β` — total evidence weight; confidence in the estimate

A new LO starts with the uniform prior `α = β = 1`: no evidence, equally
likely they do or don't have it.

Updates are simple addition:

- Positive evidence (answer was good for this LO): `α += w_pos`
- Negative evidence (answer was bad for this LO): `β += w_neg`

The magnitude of `w_pos` / `w_neg` depends on answer quality, question
difficulty, and how directly the question probed this LO. Those rules
are part 3 (LLM contract) and part 4 (policy), not this document.

#### Why Beta and not just a single number

A scalar `mastery: 0.0..1.0` conflates "we're 50% sure because we have
no data" with "we're 50% sure because they got it half the time." Those
are very different situations — the first wants more probing, the
second wants probing of a different kind. Beta keeps them distinct via
the magnitude of `α + β`.

#### Mastery threshold

An LO is considered mastered when both:

- belief mean ≥ threshold (e.g. 0.8)
- total evidence ≥ minimum (e.g. `α + β ≥ 4`)

Exact values are policy and live in part 4. The minimum-evidence floor
is what prevents a single easy correct answer from declaring mastery.

#### Evidence cap

Without a cap, drilling a single LO to e.g. `(α=50, β=2)` makes the
belief unresponsive — a wrong answer barely moves the mean. Cap
`α + β` (likely around 20). When new evidence arrives at the cap,
shrink existing counts proportionally toward the prior before applying
the update.

Exact cap value is policy (part 4); the model commits to *having* a cap.

#### Decay over time

Belief from months ago should not count the same as belief from this
week. The use case is real: a 2-hour-a-week course with holidays in
between guarantees students forget previously-known concepts. Decay
matters from v1.

Applied lazily: when reading a belief for a decision, scale `α` and `β`
toward the prior based on time-since-last-update:

```
d = decay_factor(now - lastUpdatedAt)   // d ∈ (0, 1], shrinks with elapsed time
α_effective = 1 + (α - 1) * d
β_effective = 1 + (β - 1) * d
```

The `1 + (...) * d` form preserves the prior, so an LO untouched for a
year drifts back toward `(1, 1)` — uniform — rather than collapsing to
zero confidence. The student didn't unlearn the LO, they got rusty.

Half-life on the order of months, not weeks. Exact curve is policy
(part 4).

When evidence arrives, the decayed values are persisted as the new
`(α, β)` and `lastUpdatedAt` is bumped to `now`.

### 2. Per-student difficulty calibration

A single `difficulty: easy | medium | hard` per student, plus enough
recent-answer history to update it.

#### Why one global value

Per-LO or per-LO-kind difficulty is over-engineering at v1. Difficulty
is about cognitive load and task complexity, not the kind of thinking.
A student who handles medium-complexity code generally handles it
across LO kinds. If we're wrong, per-kind difficulty is an easy add
later — the data shape doesn't change much.

#### Cross-subgoal stickiness

This is the key behavioral change from the current conductor.
Difficulty is a property of the *student*, not the subgoal. When a
student finishes a subgoal at medium and starts the next, the
calibrated difficulty stays at medium. The first question on the new
subgoal is at medium, not back to easy.

#### Starting value

New students start at **medium**. Reasoning:

- Medium is the course's actual target. Easy is remediation.
- Strong students don't waste turns demonstrating they're not stuck at
  easy — they start where the curriculum aims and only get demoted if
  they actually struggle.
- Demotion (medium → easy) is a more informative teacher signal than a
  long plateau at easy.
- Bayesian-ish updates are asymmetric: demotion happens fast (~2 wrong
  answers); promotion is slow (~4 correct). Starting at medium
  pre-pays for promotion strong students would otherwise have to earn.
- Worst case for a weak student is one too-hard question; the system
  reacts visibly ("Laten we het wat eenvoudiger aanpakken") and drops.

#### Stored state

```
difficulty: "easy" | "medium" | "hard"
recentAnswers: [
  { quality: "wrong" | "partial" | "correct", difficulty: "...", at: string }
]   // window of ~10 most recent
```

Window size is policy. ~10 feels right: not noisy, not slow. Window
size is *not* part of the schema commitment — it's a runtime parameter.

Update rules — when to promote, when to demote, how much weight each
recent answer carries — live in part 4.

### 3. Recent activity (per-LO, per-question-type)

Small ring buffers to support "don't poke at the same LO twice in a
row" and "don't ask the same question type twice in a row":

- Per-LO: `lastQuestionType` and `lastUpdatedAt` (the latter is also
  used by decay; one field, two uses).
- Per-student: a small ring buffer of recent question types, e.g. last
  5. Used for variety enforcement at the policy level.

That's it. Recent activity is small and lives alongside whatever
component already needs it.

## Schema sketch

### `lo_beliefs` container (new)

Partition key `/uid`. High-write (every answer can update multiple LOs);
single-record reads keyed on `(uid, subgoalId, loId)`; common query is
"all beliefs for this uid + subgoal," which is a single-partition query.

```
StudentLOBelief {
  id: string              // "{uid}_{subgoalId}_{loId}"
  type: "lo_belief"
  uid: string             // partition key
  subgoalId: string
  loId: string
  alpha: number           // pseudo-count of "has it"
  beta: number            // pseudo-count of "doesn't have it"
  lastUpdatedAt: string   // ISO 8601, used for decay and recency
  lastQuestionType: string?  // last ChatRequestType that probed this LO
  lastPositiveAtCalibratedAt: string?  // ISO 8601, set when a positive
                                        // signal arrives at the student's
                                        // calibration-or-higher at the time
                                        // of the answer. Required for
                                        // mastery (see conductor policy 4.3).
                                        // Survives calibration changes —
                                        // a one-way ratchet for the
                                        // "ever demonstrated at non-easy"
                                        // signal.
  highestPositiveDifficulty: "easy" | "medium" | "hard"?
                                        // Highest difficulty at which a
                                        // positive signal was ever earned
                                        // (conductor policy 4.3, #103).
                                        // One-way per level; absent until
                                        // the first positive. Missing on
                                        // older docs: reads as "medium"
                                        // when lastPositiveAtCalibratedAt
                                        // is set, absent otherwise.
  recentNegativesAtCalibrated: number   // conductor policy 2.3 counter
  firstMasteredAt: string?              // ISO 8601, set the first time all
                                        // three mastery conditions held
                                        // after a write (conductor policy
                                        // 4.3, #101). One-way: decay and
                                        // later negatives never clear it.
                                        // Gate for transfer credit (3.7).
                                        // Missing on older docs: read as
                                        // "mastered at the last write" when
                                        // the stored α, β and ratchet meet
                                        // the mastery rule, else absent.
}
```

Reusing the existing `progress` container would mix two unrelated doc
shapes for marginal savings; a dedicated container keeps queries clean.

### Account doc (extended)

The per-student calibration is small and read on every question. Embed
on the existing `accounts/{uid}` doc rather than spinning up another
container.

```
account.calibration {
  difficulty: "easy" | "medium" | "hard"
  recentAnswers: [
    { quality: string, difficulty: string, at: string }
  ]
  recentQuestionTypes: string[]   // ring buffer
}
```

Every calibration update rewrites the account doc. Updates happen at
most once per answer; the doc is small. Acceptable.

### `progress` container (kept, repurposed as cache)

Existing `progress` doc holds `progress: 0.0..1.0` per subgoal. New
model derives this from LO beliefs. Two options were considered:

- (a) Drop the field; compute on read by aggregating `lo_beliefs` per
  render. Simple, but the leerpad UI reads progress constantly.
- (b) Keep `progress` as a derived/cached value; recompute and write it
  whenever any constituent LO belief changes.

**(b)** is the choice. One extra write per answer, fast reads on the
hot path. The cached value is a function of LO beliefs and is *never*
the source of truth — beliefs are.

Other current `progress` fields (`recentAnswers`, `difficulty`,
`recentConceptAttributions`) become unused: difficulty moves to
the account doc, answer history moves to LO beliefs and the account
doc, concept attributions are subsumed by per-LO belief. Those fields
get dropped.

The `progress_history` container stays as-is. It's the time series for
teacher charts and is independent of the model redesign.

### `turn_history` container (new)

A separate, observability-focused container holds one append-only doc
per graded turn. Partition `/uid` (consistent with `lo_beliefs`).
Schema and rationale live in conductor policy section 8.1; the data
is part of the student's runtime record but is consumed by debug and
teacher-dashboard surfaces, not by the conductor's decision logic.
Belief and calibration are the source of truth for decisions;
`turn_history` is the audit trail.

### `milestones` and `grade_proposals` containers (#99)

Teacher-side only; nothing in the student flow reads or writes them, and
the conductor does not know they exist. They are the persistence behind
PUNTENFORMULE part 2.

`milestones` is single-partition (`/type = "milestone"`), a handful of
docs per year:

```
Milestone {
  id: string
  type: "milestone"
  title: string
  periodStart: string     // ISO 8601; M_start is read from progress_history as of here
  dueAt: string           // ISO 8601; the report moment
  expectedDifficulty: "easy" | "medium" | "hard"   // level the core must be shown at
  subgoalIds: string[]    // whose LOs make up the milestone
  coreLoKeys: string[]    // "{subgoalId}/{loId}" of every core LO; the rest is extension
  updatedAt: string
}
```

`grade_proposals` is partitioned `/uid`, one doc per `(uid, milestoneId)`
with id `{uid}_{milestoneId}`: the formula's outputs (`k`, `u`, `d`,
`mEnd`, `mStart`, `g`, `proposal`) with the counts behind them, the
reliability signals (`staleLoCount`, `neverProbedCount`,
`supervisedTurns`, `homeTurns`), `formulaVersion`, `computedAt`, the
AI-written `justification` (+ `justificationAt`), and the teacher's
`adjustedGrade`, `adjustmentNote` and `signedOffAt`. A doc with
`signedOffAt` is frozen — never recomputed, never rewritten.

## Settled decisions

- **Belief is Beta-distributed**, parameterized by `(α, β)`. Both the
  mean and the total evidence are first-class.
- **Mastery requires both** mean above threshold and minimum evidence.
  A third condition — at least one positive signal at calibrated
  difficulty (tracked by `lastPositiveAtCalibratedAt`) — is added
  by conductor policy section 4.3 to fix the easy-grinding problem.
- **Evidence cap exists.** Exact value: 20 (conductor policy 3.4).
- **Decay applies from v1**, lazily on read, gentle (months not weeks),
  preserving the prior. Half-life: 60 days (conductor policy 3.3).
- **Difficulty is per-student, one value**, sticks across subgoals.
- **New students start at medium**, not easy.
- **LO ids are immutable.** Teachers can add and delete LOs. Deleted
  LOs orphan their belief docs; orphaned beliefs do not contribute to
  recalculation (because no live subgoal references them) and can be
  cleaned up later.
- **Subgoal `progress` is cached**, recomputed from LO beliefs on every
  belief update.
- **`lastPositiveAtCalibratedAt` is a one-way ratchet.** Calibration
  changes do not retroactively invalidate old timestamps — once
  set, the field reflects "the student demonstrated this LO at
  the calibration in force at that time," which remains a valid
  signal regardless of subsequent calibration shifts.
- **`highestPositiveDifficulty` is a three-level one-way ratchet** (#103).
  It records the highest difficulty a positive was ever earned at, in
  absolute terms, and only ever rises. The conductor never reads it; it
  is the grade formula's difficulty differentiator (PUNTENFORMULE §2.5),
  because the symmetric difficulty multiplier keeps difficulty out of
  `(α, β)`.
- **`firstMasteredAt` is a one-way mastery stamp** (#101). Mastery itself
  never latches (decay can demote), but "was this LO ever mastered by
  direct probing?" is a durable fact the model keeps, because transfer
  credit (conductor policy 3.7) may refresh only such LOs, and the
  warm-up review question (conductor policy 1.5, #102) picks from the
  same set. Beliefs in *other* subgoals than the active one can therefore
  be written by a graded turn: upward only by a transfer credit, in
  either direction by the once-per-session warm-up review, which is a
  direct probe of that LO and updates its doc like any probe (ratchets
  and counter included), and in either direction by an incidental
  `loSignal` the grader places on an earlier subgoal's LO (conductor
  policy 2.4, #108), which moves only `(α, β)` and `lastUpdatedAt` —
  never a ratchet, the counter or `lastQuestionType` — and creates the
  doc at the prior if there was none. `lastUpdatedAt` doubles as the
  staleness clock for the warm-up review: an LO not written for
  `warmUpStaleAfter` is due. None of these mechanisms recomputes the
  other subgoal's cached `progress`.

## What this model deliberately does not do

- **No skill/concept layer above LOs.** No "this student is good at
  loops in general." Could be derived later as stats; the model
  doesn't invent the taxonomy.
- **No per-(LO, question-type) belief** and **no per-(LO, difficulty)
  belief.** Single belief per LO. Question type and difficulty are
  evidence dimensions in part 3 / part 4, not new belief axes.
- **No session concept.** Sessions are a UI artifact derived from
  timestamps. The model has no `Session` entity.
- **No teacher-visible aggregates as stored fields.** "How many
  students are struggling on subgoal X" is a query over LO beliefs and
  calibrations, not a stored field.
- **No XP, level, or streak.** Those are gamification surfaces (Phase 6
  in TODO). They may derive from the student model but are not part of
  this model.
- **No re-derivation of curriculum data.** The student model references
  `subgoalId` and `loId` but never caches LO statements, weights, or
  kinds. Curriculum is read from the curriculum data on demand.

## Migration / current-state notes

The current student-state shape is `Progress` (per uid, per goalId)
plus implicit fields on the account doc. To get to this model:

- New `lo_beliefs` container, partition `/uid`. Empty for existing
  students at first; populated as students answer questions under the
  new conductor.
- New `turn_history` container, partition `/uid`. Empty at first;
  populated per graded turn. Schema in conductor policy 8.1.
- Extend `accounts/{uid}` with `calibration` substructure. Default for
  existing students: `difficulty = "medium"`, empty histories.
- `progress.{progress}` field is repurposed as a derived cache. Drop
  `recentAnswers`, `difficulty`, `recentConceptAttributions` from the
  doc shape.
- `progress_history` is unchanged.

Existing per-subgoal progress values (`Progress.progress`) for
in-flight students do *not* automatically translate to LO beliefs —
the data dimensions don't match. Cleanest path: at the moment we ship
the new conductor, treat all students as fresh on the LO model. Their
existing root/subgoal progress remains visible in the leerpad UI
(cached), but the conductor's decisions are based on freshly-built
beliefs from there forward.

Whether to backfill anything (e.g. mark previously-mastered subgoals as
"already done so don't ask again") is a migration policy question.
Default proposal: previously-`progress = 1.0` subgoals are skipped by
the conductor (treated as done, no LO probing) until the teacher
re-opens them. Defer to part 4 if needed.
