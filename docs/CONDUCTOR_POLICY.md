# Conductor policy

Part 4 of the conductor redesign. Defines how the conductor uses the
curriculum data (part 1), the student model (part 2), and the LLM
contract (part 3) to decide what to do next.

The conductor's responsibilities, in one sentence: pick the next
question (which LO, which type, which difficulty), grade and
integrate the answer, and decide when the student has shown enough
understanding to advance.

**Section map:**

1. Subgoal entry — what happens when the student lands on a subgoal
2. Per-question decisions during practice — picking the next question
3. Belief update mechanics — the (α, β) arithmetic
4. Subgoal mastery rules — when is the subgoal done
5. Difficulty calibration updates — promotion and demotion
6. Follow-up and chaining behaviour — non-graded depth turns
7. Edge cases — defensive defaults
8. Observability — what's captured, who sees it

Numeric constants throughout are tunable; they belong in one named
constants module, adjustable without code archaeology. Authoring
experience will calibrate them; this document commits to coherent
starting values, not final ones.

---

## Section 1: Subgoal entry

When the student lands on a subgoal — whether through cold start,
resume, or manual selection — the conductor uses one unified path to
decide the first question. Phase distinctions ("guiding", "warm-up",
"practice") are gone; everything is just "practice with the right
inputs."

### 1.1 Cold start (fresh subgoal)

Student opens a subgoal where no LO beliefs exist yet. This happens
the first time a student reaches a subgoal in normal progression flow,
or any time a teacher adds a new subgoal to the curriculum.

**LO selection.** First LO in the subgoal's `objectives` list, by
`order`. The teacher's authoring order is treated as pedagogical
information: the LO marked first is the one the teacher wants
introduced first. The policy does not second-guess this.

Rejected: random selection (throws away ordering), highest-weight
first (often selects a synthesis LO that's a bad opener).

**Question type.** Picked from a default mapping by LO `kind`, choosing
the gentlest type in the kind's set. The cold-start defaults:

| LO kind | Cold-start question type |
| --- | --- |
| `recall` | `mcQuestion` |
| `apply` | `completeCode` |
| `predict` | `mcQuestion` |
| `reason` | `explainCode` |

The full mapping of *acceptable* (not just default) types per LO kind
is deferred to section 2.2. It depends on tightening the question-type
prompt definitions; without that, the mapping isn't trustworthy. The
defaults above are the cold-start commitment.

**Gentleness ordering** (used when picking among acceptable types,
once section 2.2 lands):

```
mcQuestion < completeCode < explainCode < writeCode < socraticQuestion
```

Known issue, deliberately not fixing: `socraticQuestion` is currently
an underdefined umbrella covering both light prediction prompts ("Wat
denk je dat dit afdrukt?") and open-ended reasoning. The ordering is
honest for the latter, wrong for the former. The misclassification
mostly affects the simplest early subgoals and self-corrects once the
content gets harder. Not worth splitting the question type; flagged
for awareness when section 2.2 lands.

**Difficulty.** Read directly from the student's calibration. New
students start at `medium` (per part 2). No cold-start adjustment,
no notch-drop for "ramping into a new subgoal."

The argument for a notch-drop ("ease into new content") was rejected:
it punishes the cross-subgoal stickiness that the calibration was
designed to provide. A student calibrated at `hard` who chokes on the
first question of a new subgoal will see calibration drop within ~2
questions; the system reacts fast. Permanently dropping a notch at
every subgoal boundary would force strong students to re-climb every
time, costing dozens of turns over a curriculum.

**No marker progress.** Subgoal progress starts at 0 and only moves on
real evidence. The current `_guidingDoneMarker = 0.05` artifact
disappears.

### 1.2 Resume (existing beliefs)

Student returns to a subgoal where LO beliefs already exist. Decay has
applied lazily on read; the conductor sees the decayed `(α, β)` per
LO.

**No warm-up phase.** The current "1–3 warm-up questions with credit
suppressed" logic is dropped entirely. Decay does the re-verification
work: LOs the student has forgotten show up as low-belief LOs and get
probed first, naturally. The "gentle re-entry" purpose is handled by
curriculum-ordered LO selection (below), not by easier questions.

This is communicated to the student as a feature: practice during
holidays or your progress fades. Programming requires frequent
practice; the system reflects that honestly.

**LO selection.** First *unmastered* LO in curriculum order. "Mastered"
means belief mean ≥ threshold AND evidence count ≥ minimum (exact
numbers in section 4). Same rule as cold start, with mastered LOs
skipped.

**Last-question-type reset.** The variety rule "don't ask the same
type as last time" is not applied on the first question of a session.
The previously-stored `lastQuestionType` may be from weeks ago and
shouldn't constrain a fresh session.

**No automatic session greeting from the conductor.** The conductor's
job is to ask good questions; greetings, if wanted, belong in the
chat/UI layer, not in conductor logic.

**Decay can demote.** A previously-mastered LO whose decayed belief
falls below threshold is treated as unmastered and re-probed.
Subgoal progress chip can drop from "done" back to "in progress."
Confirmed as desired behaviour: it's an honest signal of decay and
encourages regular practice.

### 1.3 Mastered subgoal on entry

The case: student lands on a subgoal where, after decay, every LO is
still above the mastery threshold.

**There is no separate "review mode."** Belief updates always run
normally — positive *and* negative signals apply, regardless of
current mastery state. The earlier idea of "drop positive signals on
mastered LOs" was rejected because it creates a motivational
dead-end: a student who sees their leerpad chip slightly decayed and
wants to top it up would be unable to do so without further decay
first. That's a perverse incentive.

**LO selection extends to mastered LOs.** The rule becomes:

1. First unmastered LO in curriculum order, if any.
2. Otherwise, the mastered LO with the **lowest belief mean** — i.e.
   the LO most due for refresh.

This lets a student top up a partially-decayed subgoal: they practice
the LOs that have slipped, positive signals arrive, beliefs climb
back, the chip refills. Working as intended.

Rejected: lowest-evidence-count fallback. Targets where the *system's*
confidence is shakiest rather than where the *student's* belief has
slipped. The student-intent reading is the right one for the
top-up use case.

**Saturation case.** If every LO has `α + β` close to the cap (rule of
thumb: `α + β < cap - 2` is "practiceable"; if no LO meets this, the
subgoal is "saturated"), the conductor declines to ask a question and
surfaces a "verder?" prompt. The student can override the suggestion;
the prompt is a soft nudge, not a wall.

This replaces an earlier "auto-advance on a fully-mastered subgoal"
rule. Auto-advance was wrong because it ignores student intent (they
tapped *this* subgoal). The saturation prompt respects intent while
being honest that the system has nothing further to learn from this
LO right now.

**Conductor-driven entry to a saturated subgoal doesn't happen by
construction.** The conductor's "next subgoal" selection skips
mastered subgoals. If a saturated subgoal is reached via conductor
flow due to data inconsistency, advance defensively to the next
unmastered subgoal.

### 1.4 The unified entry algorithm

Putting it all together, every subgoal entry runs the same logic:

```
entry(subgoal, student):
    beliefs = read lo_beliefs for (student, subgoal), apply decay
    unmastered = LOs with mean < threshold OR evidence < minimum
    if unmastered is non-empty:
        target_lo = first unmastered LO in curriculum order
    else:
        practiceable = LOs with (α + β) < cap - 2
        if practiceable is empty:
            surface "verder?" prompt; do not generate a question
            return
        target_lo = mastered LO with lowest mean
    type = gentlest acceptable type for target_lo.kind
    difficulty = student.calibration.difficulty
    last_question_type = null   // session reset
    return Question(targetLOs=[target_lo], type=type, difficulty=difficulty)
```

Cold start, resume, and manual revisit all hit this same path. The
only differences between them are which inputs are non-empty (no
beliefs vs. some beliefs vs. all-mastered beliefs). The algorithm
falls through correctly in each case.

### 1.5 What this section deliberately does not address

- **Picking the next question after the first.** "Which LO next, given
  belief just updated?" is section 2.1. The entry algorithm above
  produces only the first question of a session/subgoal.
- **Multi-LO questions.** Whether the conductor ever picks two LOs to
  probe in one question (cheaper coverage) is deferred to section 2.4.
- **The full type-by-kind acceptable-set table.** Cold-start defaults
  are committed; the rest is section 2.2.
- **What happens when an LO has no acceptable types** (empty
  intersection of "kind is X" and "type is appropriate"). Edge case;
  section 7.

---

## Section 2: Per-question decisions during practice

After the first question, every subsequent question runs through the
same four-step decision: which LO, which type, which difficulty,
single- or multi-LO. The section 1 entry algorithm picked the first
question; this section picks every question after that.

### 2.1 Which LO to probe next

**Lowest belief mean among unmastered LOs**, with `weight` as
tiebreaker (higher weight wins on near-equal means), and a recency
guard.

**Recency guard, `K = 1`.** Don't probe the LO that was probed in the
immediately previous question, unless no other unmastered candidate
exists. This avoids hammering the same LO repeatedly on consecutive
turns — bad pedagogy and bad evidence policy. Two wrongs in a row on
the same LO doesn't tell us more than one wrong; move on, come back
later.

`K = 1` over `K = 2`: variety is real but secondary to picking the
right LO. On small subgoals (3 LOs), `K = 2` would force a rigid
A → B → C → A cycle; `K = 1` lets the policy pick freely as long as it
doesn't repeat.

**`weight` as tiebreaker only.** The primary signal is belief; weight
breaks ties. A high-weight, slightly-stronger LO does not beat a
low-weight, much-weaker LO. Authoring experience may push us to a
stronger weighting later (e.g. `weight × (1 − mean)` as the sort key);
not now.

**Mastered LOs are skipped during practice.** They re-enter the
candidate pool only via decay (section 1.2) or the saturation revisit
case (section 1.3). No within-session refresh of mastered LOs — that
conflicts with goal 3 ("don't poke at things they've shown they
handle"). Cross-session decay handles forgetting; mastered LOs that
later work keeps using are refreshed without being probed, by transfer
credit (3.7).

**Saturated LOs are filtered out of the unmastered pool.** An LO at
`α + β ≥ cap − saturationSlack` is non-practiceable (section 3.4):
the cap-then-shrink rule makes mean movement too slow for re-probing
to flip mastery in any reasonable number of turns. The saturated-stuck
rule (section 4.4) normally marks these LOs stuck so the subgoal can
advance; the selection-side filter is the matching guarantee that
during the same turn the conductor doesn't preferentially target a
dead-zone LO over a practiceable one with similar mean.

**Fallback: all unmastered LOs saturated.** Rare, but possible when
every remaining LO sits in the purgatory zone (saturated, mean in
`[stuckSaturatedMeanCeiling, masteryMeanThreshold)`). In that case
the conductor picks the **highest** mean (closest to mastery) so the
slow climb has the best chance of flipping one LO and unblocking the
subgoal. `chosenReason` is logged as `all unmastered saturated:
highest-mean fallback` for debug visibility.

**Convergence with curriculum order.** Early in a subgoal, "first
unmastered in order" (section 1) and "lowest mean unmastered" pick
different LOs because beliefs are sparse. After a few turns, every LO
has been touched and "lowest mean" effectively becomes "the one
they're stuck on" — same target the order rule would converge on.
The two rules agree in the limit; they differ in the early turns,
and "lowest mean" is the better fit there because it uses the data
the order rule throws away.

### 2.2 Which question type

Two parts: what types are *acceptable* for each LO kind, and how the
policy picks among them.

**Acceptable types per LO kind.**

| LO kind | Acceptable question types |
| --- | --- |
| `recall` | `mcQuestion`, `socraticQuestion` (short-answer style) |
| `apply` | `completeCode`, `writeCode` |
| `predict` | `mcQuestion`, `explainCode`, `socraticQuestion` (predict style) |
| `reason` | `explainCode`, `socraticQuestion` (open-ended) |

Notes:

- `recall` excludes code-production types. Producing code isn't the
  right way to test "you know this fact."
- `apply` excludes `mcQuestion` and `explainCode`. To test "you can
  write a loop," they have to write one.
- `predict` and `reason` overlap on `explainCode` because both
  involve reading code. The LLM has to interpret the LO statement to
  pick the right framing — predict ("what will this output?") vs
  reason ("why does this work?").
- `socraticQuestion` appears in three of four kinds because the type
  is currently underdefined. Once the prompt is rewritten to a
  specific job, this table will narrow.

This table is a draft. Real revision happens when we rewrite the
question-type instruction prompts.

**Selection rule.**

```
1. Take the acceptable types for the target LO's kind.
2. Exclude the type used in the immediately previous question on this LO,
   if other types remain.
3. If LO belief is weak (mean < 0.5), pick the gentlest remaining type
   (gentleness order from section 1.1).
4. Otherwise pick the type least-recently-used for this LO.
```

The `mean < 0.5` threshold is the prior midpoint: the student has
shown net-negative evidence on this LO. That's the right moment to be
gentle.

**Cross-LO type variety** is a soft preference: when 2.2 has multiple
candidates remaining, prefer one that wasn't used in the last 2
questions overall. Cross-LO variety yields to per-LO rotation if they
conflict.

### 2.3 Which difficulty

**Default: read from the student's calibration.** Same as cold start.

**Override: drop one notch on this LO.** Two strong-negative signals
on this LO at the calibrated difficulty, with no positive signal in
between, triggers a one-notch drop *for this LO only*. The student's
overall calibration doesn't change; just this LO gets gentler probing
until it recovers.

Concretely, the conductor maintains a per-LO counter
`recentNegativesAtCalibrated`. The counter:

- Increments by 1 on a `(negative, strong)` signal whose answer was
  asked at the student's calibration *at the time of the answer*.
- Resets to 0 on any positive signal on this LO, at any difficulty
  and any strength.
- Is unchanged on `(negative, moderate)`, `(negative, weak)`,
  negatives at non-calibrated difficulties, neutrals, and signals
  on other LOs.

The notch-drop fires when, at plan time, both:

- `recentNegativesAtCalibrated >= 2` *and*
- The LO has never had a positive at calibrated-or-higher
  (`lastPositiveAtCalibratedAt is null`).

The second condition means: once a student has demonstrated this LO
at calibration, the system trusts that demonstration and stops
gating subsequent probes back to easy. Recovery from the gate is via
the counter reset on the next positive (any difficulty), not via the
ratchet.

Why strong-only counts as a strike: moderate and weak negatives are
the LLM grader's own way of saying "the answer was informative but
not clean" — a one-letter typo, partially-right reasoning, ambiguous
phrasing. Counting those would make the gate trip on noise. The
strong qualifier is what makes "two strikes" meaningful as evidence
that the difficulty is wrong for this student × this LO, rather than
just two unlucky questions.

Why two strikes and not one: one-strike fires on slip answers (typo,
momentary lapse). Two confirmed strong-negatives at calibration,
without an intervening positive, is the signal we need.

**No upward override.** If belief on a target LO is high but not yet
mastered (e.g. mean 0.78, just below threshold), the policy does *not*
bump a notch above calibration. Two reasons:

1. Mastery declarations should be unambiguous. Bumping a notch to push
   over the threshold feels like a shortcut — passed on a question
   harder than the student normally handles.
2. The E.1 fix (section 4.3) requires evidence at the calibrated
   difficulty for mastery. Bumping a notch defeats that.

Calibration changes are slow and Bayesian (section 5). The right way to
push a strong student onto harder questions is to promote their
calibration, not to override it per-question.

### 2.4 Single-LO vs multi-LO targeting

**Default: single-LO targeting.** Every question targets exactly one
LO. The question generator focuses; the grader scores cleanly against
the target.

**Incidental multi-LO signals are accepted.** Per the part-3 LLM
contract, the grader may emit signals for non-target LOs based on
what the answer revealed. Those are consumed as ordinary evidence.
A `writeCode` question targeting `for_loop_structure` may reveal the
student handles `indentation_defines_block`; that signal lands in the
indentation LO's belief.

**Deliberate multi-LO targeting is structurally allowed but not yet
triggered by any rule.** The `targetLOs` field is a list; nothing
prevents the policy from passing two LOs. We just don't have a
heuristic to invoke it. The conceptual case is two LOs that are hard
to probe separately ("use range()" and "iterate a fixed count" might
be one skill in practice). We'll know when that pattern shows up; for
now, single-target keeps evidence clean.

### 2.5 The per-question algorithm

After belief has been updated from the previous answer:

```
nextQuestion(subgoal, student, lastQuestionLOId, lastQuestionType):
    beliefs = read lo_beliefs for (student, subgoal), apply decay
    candidates = unmastered LOs, excluding lastQuestionLOId
    if candidates is empty:
        candidates = unmastered LOs    # relax recency guard
    if candidates is empty:
        # all LOs mastered — fall through to section 1.3 behavior
        return entry(subgoal, student)
    target_lo = candidates sorted by (mean ascending, weight descending)[0]
    type = pickType(target_lo, beliefs[target_lo])
    difficulty = student.calibration.difficulty
    if shouldDropNotch(target_lo, beliefs[target_lo]):
        difficulty = oneStepDown(difficulty)
    return Question(targetLOs=[target_lo], type=type, difficulty=difficulty)

pickType(lo, belief):
    acceptable = acceptableTypes(lo.kind)    # from table
    candidates = acceptable \ {previous type used on this LO}
    if candidates is empty:
        candidates = acceptable
    if belief.mean < 0.5:
        return gentlest(candidates)
    return leastRecentlyUsed(candidates, lo)

shouldDropNotch(lo, belief):
    return previous answer on lo was strong-negative
       and prior answer at calibrated difficulty on lo was also negative
```

The pseudocode glosses several details (how "previous answer on lo"
is tracked, how recency-of-types-on-this-LO is stored). Those are
storage concerns: the per-LO recent activity in the student model
(part 2 §3) carries the data we need.

### 2.6 What this section deliberately does not address

- **How belief updates compute** (`(α, β)` arithmetic, weight
  conversions). Section 3.
- **When the subgoal is mastered** (the threshold and minimum-evidence
  rule). Section 4.
- **When the student's calibration promotes/demotes.** Section 5.
- **What happens after a wrong answer:** does the conductor immediately
  ask a follow-up, or move on? Section 6.
- **What `gentlest()` resolves to within an acceptable set.** The
  section 1.1 ordering applies, but the table in section 2.2 needs
  refinement when the question-type instruction prompts are
  rewritten.

---

## Section 3: Belief update mechanics

After the LLM grades an answer (per part 3), the conductor consumes
each `(loId, signal, strength)` tuple and updates the corresponding
`(α, β)` in the student's belief for that LO. This section specifies
the arithmetic.

### 3.1 Evidence weight table

The base weight per `(signal, strength)`:

| signal | strong | moderate | weak |
| --- | --- | --- | --- |
| `positive` | `α += 2.0` | `α += 1.0` | `α += 0.5` |
| `negative` | `β += 2.0` | `β += 1.0` | `β += 0.5` |
| `neutral` | (no update) | (no update) | (no update) |

**Symmetric in positive/negative.** Asymmetry would distort
calibration. The "wrong is more diagnostic than right" intuition is
real but belongs in the LLM contract — the grader emits `moderate` or
`weak` (not `strong`) on questions where lucky-guess corrects are
plausible (e.g. binary MCQ). The conductor's weights stay symmetric.

**`neutral` is a no-op.** A neutral signal means "the answer touched
the LO but gave no clear evidence." Adding `(α + 0.5, β + 0.5)` would
inflate the evidence count without informing belief — wrong. The
LLM still emits `neutral` for grading honesty (per part 3); the
conductor declines to apply it.

### 3.2 Difficulty modulation

Multiply the base weight by a difficulty factor:

| Question difficulty | Multiplier |
| --- | --- |
| `easy` | 0.6 |
| `medium` | 1.0 |
| `hard` | 1.4 |

Applies to both positive and negative signals, with the same factor:
a `correct` at hard is more diagnostic of mastery than a `correct`
at easy, and a `wrong` at hard is weighted just as heavily as that
`correct` — the multiplier says how *hard* a piece of evidence is,
not which way it points (see "Symmetric in positive/negative" above).
A consequence for the grade formula (PUNTENFORMULE §2.5): the
multiplier scales how fast evidence accrues but not where the mean
settles, so difficulty is invisible in `(α, β)`; the per-LO
`highestPositiveDifficulty` ratchet (4.3) is what carries it.

**E.1 interaction.** Lower easy-weight is one of two mechanisms that
fix the "good student grinds easy answers to mastery" problem. The
multiplier alone caps how fast easy-only mastery can accrue: it takes
more easy-correct answers to reach the same evidence count as one
medium-correct. The second mechanism — requiring evidence at the
calibrated difficulty for mastery — lives in section 4.

**Provenance modulation (#100, PUNTENFORMULE §2.7).** A second
multiplier on the same base weight says *where* the answer was
produced:

| Provenance | Multiplier |
| --- | --- |
| `home` | 1.0 |
| `supervised` | `s` = 1.25 (`PolicyConstants.supervisedWeightFactor`) |

`supervised` means the student was in an active, alert-free Anchor
classroom session at grading time, as answered per student, per turn,
by the `SupervisionSource` the host consults before building the
`GradedAnswer`. There is no manual toggle. The factor is symmetric in
positive and negative (like difficulty: it changes how *hard* the
evidence is, not which way it points), applies to follow-up signals
as well, and never drops below 1 — home evidence keeps full weight and
is confirmed or contradicted by later supervised work on the same LO.
Until Anchor is wired up every turn resolves to `home`, so the
multiplier is inert and no backfill is needed. The value is provisional
until the period-1 shadow run (PUNTENFORMULE §4).

### 3.3 Decay

**Exponential decay, half-life 60 days.** Applied lazily on read.

```
elapsed_days = (now - lastUpdatedAt) in days
d = 0.5 ^ (elapsed_days / 60)
α_effective = 1 + (α - 1) × d
β_effective = 1 + (β - 1) × d
```

The `1 + (...) × d` form preserves the prior, so an LO untouched for
years drifts toward `(1, 1)` (uniform), not zero.

**Felt-right at the inflection points** for a 2-hour-a-week course
with holidays:

- 1 week between sessions: `d ≈ 0.92` — barely visible.
- 2 weeks (Christmas / Easter break): `d ≈ 0.85` — small drop.
- 10 weeks (summer): `d ≈ 0.31` — substantial. A `(10, 2)` LO becomes
  `(3.79, 1.31)`; mean drops from 0.83 to 0.74. Just below threshold.
- 6 months: `d ≈ 0.10` — near-uniform; student starts mostly fresh.

**On read.** The conductor reads `lo_beliefs[id]`, computes elapsed,
applies decay, uses decayed values for decisions. **On write after
update**, the persisted values are post-decay-then-post-update — so
the next read doesn't double-decay. `lastUpdatedAt` is bumped to
`now` on every write.

No background job. Decay is part of the read path.

### 3.4 Evidence cap

**`α + β ≤ 20`.** When new evidence would push past the cap, shrink
existing evidence-above-prior proportionally to make room, then add
new evidence at full weight.

```
applyEvidence(α, β, w_α, w_β):
    if α + β + w_α + w_β > CAP:
        excess_capacity = CAP - 2 - w_α - w_β   // 2 = prior contribution
        existing_excess = α + β - 2
        scale = excess_capacity / existing_excess
        α = 1 + (α - 1) × scale
        β = 1 + (β - 1) × scale
    return (α + w_α, β + w_β)
```

Result: `α + β = CAP` after the update, mean approximately preserved
through the shrink, new evidence direction faithfully applied.

**Property: at cap, new evidence still moves belief.** A capped
`(18, 2)` (mean 0.9) receiving strong-negative `(0, 2)`:

1. Shrink existing-above-prior by `(20 - 2 - 2) / (20 - 2) = 16/18`:
   `(α=1 + 17×8̄/9, β=1 + 1×8̄/9) ≈ (16.1, 1.89)`.
2. Add new: `(16.1, 3.89)`. Mean 0.81. Evidence 20.

One strong-negative drops mean from 0.9 to 0.81 — still mastered, but
close. Two would demote. Right responsiveness.

**Cap value of 20** is the sweet spot found by sanity check. Smaller
(10) makes belief jumpy; larger (50) makes it rigid and hard to
recover from after decay or isolated bad answers.

### 3.5 Edge cases in the update step

- **Multiple signals on the same LO from one question.** Forbidden by
  the part-3 LLM contract (one signal per `(subgoalId, loId)` per
  question). Conductor doesn't need defensive logic.
- **Signal on a deleted LO** (teacher removed it between question
  generation and grading). Drop the signal, log. Already covered by
  part-3 validation.
- **Signal on an LO with no existing belief doc** (incidental signal
  on an LO the student has never been probed on before). Create the
  belief doc with prior `(α=1, β=1)`, `lastUpdatedAt = now`, then
  apply the update normally. Same code path; only the create-or-load
  step is special.

### 3.6 Worked example

Sanity check, medium student, "use if/else" subgoal, three LOs.

State after first 4 questions:

| LO | α | β | mean | evidence |
| --- | --- | --- | --- | --- |
| `predict_branch` | 4 | 1 | 0.80 | 5 |
| `write_if_only` | 3 | 2 | 0.60 | 5 |
| `write_if_else` | 1 | 1 | 0.50 | 2 |

`predict_branch` formally meets mastery (mean ≥ 0.8, evidence ≥ 4).

**Q5: target `write_if_else`** (lowest mean unmastered), type
`completeCode`, difficulty medium.

Answer correct. LLM emits strong-positive on `write_if_else`,
weak-positive on `predict_branch` (incidental).

- `write_if_else`: `α += 2.0 × 1.0 = 2.0` → `(3, 1)`, mean 0.75.
- `predict_branch`: `α += 0.5 × 1.0 = 0.5` → `(4.5, 1)`, mean 0.82.

**Q6: target `write_if_only`** (now lowest at 0.60), type `writeCode`
(least-recently-used), difficulty medium.

Answer wrong. Strong-negative.

- `write_if_only`: `β += 2.0 × 1.0 = 2.0` → `(3, 4)`, mean 0.43.

**Q7: target `write_if_else`** (`write_if_only` excluded by recency
guard; `write_if_else` is unmastered).

**Q8: target `write_if_only` again.** Wrong again. Strong-negative.

- `write_if_only`: `β += 2.0` → `(3, 6)`, mean 0.33.

Now two negatives at calibrated medium on this LO.

**Q9: target `write_if_only`** (recency guard relaxed; still lowest).
Notch-drop fires per section 2.3 → difficulty `easy`. Type rotates to
`completeCode`.

Answer correct. Strong-positive at easy: `α += 2.0 × 0.6 = 1.2`.

- `write_if_only`: `(4.2, 6)`, mean 0.41.

Override releases (positive received). Next probe of `write_if_only`
goes back to medium.

The progression feels right: notch-drop fires after two strikes, easy
answers count for less than medium, mastery doesn't lock in too fast
or too slow.

### 3.7 Transfer credit (#101, PUNTENFORMULE §2.8)

Older LOs live on inside newer work: December's while-loop exercise
still uses September's `print()` and variables. When a *working*
solution to a later exercise correctly uses an LO the student mastered
earlier, that LO's belief gets a small positive update. This counters
the 60-day decay without re-quizzing old material, and it rewards
transfer — using a skill in a new context is a stronger demonstration
than answering a targeted question about it.

**The grader nominates, the conductor gates.** The grading response
carries one extra field, `transferLOs: [{subgoalId, loId}]` (LLM
contract, part 3): the goal-scope LOs from *other* subgoals that the
solution *correctly used in service of the task*. That phrasing is the
guard against padding code with gratuitous constructs to farm credit;
the small weight bounds the payoff anyway. The grader is not told which
LOs are mastered — it reports what the code demonstrates; the conductor
decides what counts. No hand-authored mapping, no Q-matrix.

A nominated LO earns credit only when **all** of these hold:

1. **The answer is `correct`.** A working solution is unambiguous
   evidence that the constructs in it still work. A `partial` or `wrong`
   answer gives *nothing* to older LOs — not negative evidence (blame
   assignment across old LOs is unsolvable, so nobody outside the target
   gets blamed) and not positive evidence either. The evidence really is
   asymmetric.
2. **The turn is a primary probe, not a follow-up (6.2), and not a
   fallback turn (7.2).** Dialogue is not a solution, and a response
   whose primary signals failed validation is not trusted for extras.
3. **The LO is outside the active subgoal.** LOs inside it already get
   ordinary incidental signals at full weight (2.4); a nomination there
   is dropped.
4. **The LO was ever mastered by direct probing.** An LO that was never
   directly probed — or probed but never mastered — cannot be brought
   to mastery sideways. Tracked by the one-way `firstMasteredAt` stamp on
   `lo_beliefs` (part 2), set the first time all three mastery
   conditions (4.1) hold after a write. Docs written before the stamp
   existed read as "mastered as of the last direct write" when their
   stored `(α, β)` meet conditions 1–2 and the calibrated-positive
   ratchet is set; the stamp is then written on the next update, dated
   to that write. Nothing is backfilled.

**Refresh-and-raise, small weight.** The credit is an ordinary
`(positive, weak)` signal treated as `medium` — the same footing as a
follow-up signal (6.2) — so it is `0.5 × s` on α, with `s` the
provenance multiplier (3.2). Applied to the *decayed* belief and
persisted with `lastUpdatedAt = now`: that bump is the "decay clock
reset", and the added α is the "raise". Chosen over merely resetting
the clock because transfer deserves reward, and kept small because
this mechanism counters decay, it does not establish mastery. Diminishing
returns come free from the Beta arithmetic: the more evidence an LO
already carries, the less each credit moves its mean.

**Nothing else on the old doc moves.** Neither ratchet — not
`lastPositiveAtCalibratedAt`, not `highestPositiveDifficulty` (4.3): the
exercise's difficulty was set for the target LO, not for the transferred
one, and a hard loop exercise must not certify `print()` at hard — nor
the notch-drop counter (2.3), nor `lastQuestionType`. The other subgoal's
cached `progress` is not recomputed: positive-only credit cannot lower
it. Credits do not enter the calibration window (section 5).

**Audit.** Every credit applied is listed on the turn record as
`transferCredits: [{subgoalId, loId, alphaDelta}]` (8.1), next to the
target's own `appliedSignals`; declined nominations are logged in the
debug recorder with the reason.

**Complement: warm-up review (#102).** LOs that naturally recur in later
work are refreshed here for free; LOs that nothing later builds on are
the review questions' business. `firstMasteredAt` is the "once mastered"
signal both mechanisms share.

### 3.8 What this section deliberately does not address

- **The mastery decision** (when does an LO count as mastered, given
  the belief shape we just defined). Section 4.
- **The student's calibration update** (when does `easy/medium/hard`
  itself change). Section 5.
- **Per-question-type weight modulation** (e.g. `mcQuestion`
  guess-rate adjustment). Handled in the LLM contract, not the
  conductor — the LLM emits weaker strength on guessable formats.

---

## Section 4: Subgoal mastery rules

When does an LO count as mastered? When does the *subgoal* count as
mastered? What if a student is genuinely stuck on one LO?

### 4.1 Per-LO mastery

An LO is mastered when **all three** conditions hold:

1. **Belief mean ≥ 0.8.** The conductor is confident the student has
   it.
2. **`α + β ≥ 4`.** That confidence is grounded in evidence beyond
   the prior, not just one signal.
3. **At least one positive signal contributing to current belief was
   at the student's calibration *at the time of the answer*, or
   higher.** This is the E.1 fix (see 4.3).

All three are tunable constants (see the front-matter note on
constants).

**Mastery is checked on every belief update.** No latching. If decay
or new negative evidence drops the belief below conditions 1 or 2,
the LO is unmastered again. (Condition 3 is satisfied by a timestamp
field; once set, it doesn't reset.)

### 4.2 Subgoal-level aggregation

A subgoal is mastered when **all non-optional LOs are either
mastered or stuck** (4.4).

Rejected: weighted-majority aggregation. The whole point of LO-level
granularity is to *not* let things slip through. A student with one
clearly-missing core LO shouldn't pass because they aced the others.

**Optional LOs.** The schema gains `optional: bool` (default `false`)
on the LO. Optional LOs are still probed for variety/coverage but
don't gate advancement. Use case: "nice to have" LOs the teacher
includes for completeness without making them blockers.

> Schema amendment: part 1 (curriculum data model) needs `optional`
> added to the LO field list. Default `false`.

**`weight` does not affect aggregation.** It influences LO selection
(section 2.1, as tiebreaker) but not mastery. Mastery is binary per LO;
aggregation is "all non-optional mastered or stuck." If a teacher
wants an LO to not gate advancement, that's `optional: true` —
cleaner than fractional weighting.

### 4.3 The E.1 fix (mastery requires calibrated-difficulty evidence)

Without this rule, the easy-grinder problem persists: a student
calibrated at `easy` (or one for whom the section 2.3 notch-drop
override fires repeatedly) can accumulate enough easy-correct
positive evidence to satisfy conditions 1 and 2 alone. The 0.6
difficulty multiplier (section 3.2) makes this slower but doesn't
prevent it.

**Condition 3** (4.1) closes the gap: the student must have
demonstrated this LO at calibrated-or-higher difficulty at least
once for mastery to stick.

**Tracking.** Add field `lastPositiveAtCalibratedAt: timestamp?` to
`lo_beliefs`. Set whenever a positive signal arrives at the student's
calibration *at the time of the answer*, or higher. Mastery
condition 3 = field is non-null.

**Calibration changes don't invalidate old timestamps.** A student
who was at `medium` and got demoted to `easy` retains the meaning of
"once demonstrated at medium" — they did it, the calibration change
doesn't undo that fact. The interpretation is "did the student ever
demonstrate this LO at a non-easy level?" — a one-way ratchet for the
purposes of condition 3.

**The notch-drop override cannot bypass this.** A student whose
override (section 2.3) keeps firing on a specific LO at easy gets a
softer path through, but the override releases on positive signal.
The next probe is at calibrated difficulty. Mastery requires
demonstrating there.

**Three-level ratchet (#103, PUNTENFORMULE §2.5).** A second field,
`highestPositiveDifficulty: "easy" | "medium" | "hard" | absent`,
records the highest difficulty at which this LO ever earned a
positive signal — any strength, the difficulty *actually asked* (a
notch-dropped probe at easy counts as easy), absolute rather than
relative to the calibration in force. It only ever rises: a later
positive at a lower difficulty leaves it, and calibration shifts never
touch it. Negatives, neutrals and follow-up grading (6.2) leave it
alone, exactly like `lastPositiveAtCalibratedAt`. So does transfer
credit (3.7): a credit is not a probe of the LO at any difficulty, so
neither ratchet moves — only a direct, non-follow-up positive on the LO
itself is ratchet-worthy. The conductor does
not read it — mastery condition 3 stays on the calibration-relative
timestamp — it exists for the grade formula, where it is the only
signal that can tell medium from hard. Docs written before the field
existed read as `medium` when `lastPositiveAtCalibratedAt` is set
(the old flag's documented "ever demonstrated at non-easy" meaning)
and as absent otherwise; nothing is backfilled.

**Mastery stamp (#101).** A third field, `firstMasteredAt`, records
when the LO first met all three conditions after a belief write. One-way:
decay and later negatives unmaster the LO (4.1, no latching) but never
clear the stamp, which answers a different question — "was this ever
mastered by direct probing?" — the gate for transfer credit (3.7). Set in
the same write that first satisfies the conditions; nothing is
backfilled (3.7 says how older docs are read).

### 4.4 The stuck rule (advancing despite a missed LO)

A student is stuck on one LO. Belief plateaus around mean 0.4 with
plenty of evidence. Other LOs in the subgoal are all mastered.

Pure "never advance until everything is mastered" traps real
students who get genuinely stuck on specific things, damaging
motivation and burning the calibration system. Pure "advance after
N attempts" treats unmastered as mastered, which it isn't.

**Compound rule (classic):** an LO is *stuck* when `α + β ≥ 8` AND
mean < 0.6. A subgoal advances when all non-optional LOs are either
**mastered or stuck**.

Numbers:

- `α + β ≥ 8` is the "tried enough" threshold. Doubles the mastery
  evidence minimum (4) — meaningful effort.
- mean < 0.6 is "still not getting it." Above 0.6 is on the upswing —
  keep probing.

**Second branch (saturated):** an LO is also stuck when
`α + β ≥ cap − saturationSlack` AND mean < `stuckSaturatedMeanCeiling`
(0.75). This handles the case where an early strong-negative pushed
the LO's β up, evidence saturated at the cap before subsequent
correct answers could pull mean back above the mastery threshold, and
the cap-then-shrink rule in §3.4 now makes mean movement so slow that
further probing wastes turns. Without this branch a non-practiceable
LO with mean between the classic-stuck ceiling (0.6) and the
saturated-stuck ceiling (0.75) sits in purgatory — not mastered, not
stuck, blocks subgoal advance indefinitely.

Numbers for the saturated branch:

- `α + β ≥ cap − saturationSlack` = `α + β ≥ 18` with current
  constants. Matches the `isPracticeable` boundary in §3.4 so the
  selection-side filter (§2.1) and the stuck-side rule agree.
- mean < 0.75 leaves a one-strong-positive buffer to mastery
  (`masteryMeanThreshold` = 0.8). LOs within that buffer are not
  written off as stuck, even though the selection filter still skips
  them; the highest-mean fallback in §2.1 keeps probing them.

**Stuck is computed live, not stored.** Every mastery check evaluates
each LO as `mastered | stuck | neither`. No flag, no persistence.
Decay naturally rescues an LO from stuck status because evidence
shrinks toward the prior — on a future revisit, a previously-stuck
LO can be probed afresh.

**Student-side invisibility.** The advance feels normal to the
student. No "you didn't really master this but we're moving on"
message — that's demoralizing and counterproductive. Internally the
data is intact; teacher-side surfacing is for section 8.

**Teacher visibility (see section 8).** A subgoal advancing
with one or more stuck LOs is a real gap in the student's
knowledge — strong signal for the teacher dashboard. Stronger than
the audit-trail signal in 4.5.

### 4.5 Mastery checks and advancement flow

After every answer:

```
on_answer_processed():
    update beliefs for affected LOs    # section 3
    for each affected lo:
        recompute mastered status      # 4.1
    recompute subgoal mastered status   # 4.2 (using 4.4 stuck rule)
    if subgoal is mastered:
        advance()
```

Advancement:

- The subgoal's cached `progress` is set to 1.0 (per part 2 — the
  cache, not the source of truth).
- The conductor selects the next unmastered subgoal in curriculum
  order.
- The next question targets the new subgoal's first LO using the
  cold-start path (section 1.1) — fresh subgoal has no beliefs yet.
- The subgoal-completion event fires (existing splash/celebration UI
  hooks).

**Cascading auto-skip cap: 1.** If the next subgoal is also already
mastered (data inconsistency, prior LO sharing across subgoals via
some future mechanism, or restored beliefs from migration), the
conductor advances past it once. If a *second* consecutive subgoal
would also auto-skip, the conductor stops and presents that subgoal
to the student.

**Audit trail when the cascade halts.** The cascade-stop is a "data
looks weird, teacher might want to know" event, not "student in
trouble." Log to the student's record for teacher audit. Passive
surfacing — the student experience is fine. (Section 8 details.)

### 4.6 Worked example

Continuing from 3.6, end of Q9:

| LO | α | β | mean | evidence | mastered? | stuck? |
| --- | --- | --- | --- | --- | --- | --- |
| `predict_branch` | 4.5 | 1 | 0.82 | 5.5 | yes | no |
| `write_if_only` | 4.2 | 6 | 0.41 | 10.2 | no | **yes** |
| `write_if_else` | 3 | 1 | 0.75 | 4 | no | no |

`write_if_only` is stuck (`α + β = 10.2 ≥ 8`, mean 0.41 < 0.6).

**Q10: target `write_if_else`** (lowest-mean unmastered). Type
rotates. Difficulty `medium` (calibrated).

Answer correct. Strong-positive at medium: `α += 2.0 × 1.0 = 2.0`.

`write_if_else`: `(5, 1)`, mean 0.83, evidence 6. Condition 1 ✓,
condition 2 ✓, condition 3 ✓ (positive at calibrated medium →
`lastPositiveAtCalibratedAt` now set). **Mastered.**

Subgoal mastery check:
- `predict_branch`: mastered ✓
- `write_if_only`: stuck ✓
- `write_if_else`: just mastered ✓

All non-optional LOs are mastered or stuck → **subgoal mastered.**
Advancement triggers.

Student advances to "use elif and combine conditions logically."
`write_if_only`'s `(4.2, 6)` belief persists in the student model;
on manual revisit, decay will have softened it and re-probing
becomes meaningful. Teacher dashboard flags `write_if_only` as a
stuck LO at advancement (section 8).

### 4.7 What this section deliberately does not address

- **Difficulty calibration updates** (when does `easy → medium →
  hard` itself shift). Section 5.
- **Follow-up / chaining behaviour** (does the conductor immediately
  re-probe a wrong answer, or move on?). Section 6.
- **Empty `objectives` list** (subgoal authored without LOs). Section 7.
- **Teacher-side surfacing of stuck LOs and cascade-halt events.**
  Section 8.

---

## Section 5: Difficulty calibration updates

The student carries a `calibration: easy | medium | hard` value on the
account doc (per part 2). Sections 1–4 read this value as a given;
this section decides when and how it changes.

All numeric values in this section are tunable constants (see the
front-matter note on constants).

### 5.1 Promotion (medium → hard, easy → medium)

A student sustaining good performance at their current calibration
should see harder questions.

**Rule.** Examine the recent-answer window (last 10 answers, per
part 2). Filter to answers whose `difficulty` equals the student's
current calibration. The student promotes when:

- **at least 4** at-calibrated answers exist in the window, AND
- **at least 75%** of those are `correct` (not `partial`, not
  `wrong`).

**Why behavior at-difficulty, not belief mass.** A student can
accumulate high LO belief from low-difficulty grinding (sections 3.2,
4.3 already worry about this). Calibration must measure
"are they handling the current difficulty?" — that's a behavioral
signal, not a belief signal.

**Why partial doesn't count as correct for promotion.** A partial at
calibrated difficulty is "not yet ready." The 75% threshold (not
100%) already softens the bar; counting partials would soften it
twice.

**Cap promotion at one notch per check.** Even if a student would
warrant `easy → hard`, advance one step at a time. The numerics make
double-promotion mathematically unlikely, but explicit costs nothing.

### 5.2 Demotion (hard → medium, medium → easy)

Asymmetric to promotion: should fire faster.

**Why faster.** A miscalibrated-too-high student is in active
distress. Every wrong question at too-hard reinforces frustration
and pollutes belief data with "wrongs that mean 'too hard,' not
'don't have the LO.'" The system needs to react. A
miscalibrated-too-low student has the opposite problem (slow
advancement) but not the same urgency.

**Rule.** Filter recent-answer window to at-calibrated answers. The
student demotes when:

- **at least 3** at-calibrated answers exist in the window, AND
- **at least 60%** of those are `wrong` or `partial`.

**Why partial counts as bad here** (asymmetric to promotion). A
partial at the student's current level is evidence of struggle. For
promotion, it's "not yet ready"; for demotion, it's "currently
struggling." Both interpretations point at "current calibration
isn't solid"; the asymmetry just reflects which direction we're
moving.

**Hint usage does not influence calibration.** The current conductor
blocks promotion when the student took hints; the new conductor drops
this rule. Reasoning:

- Hints are help the student asks for. Penalizing them discourages
  help-seeking — bad pedagogy.
- A student who takes hints and gets correct still demonstrates
  something. The Beta belief update already weights the resulting
  `correct` accordingly (the LLM, seeing hint history, may rate the
  answer `moderate` rather than `strong`).
- Putting hint logic in calibration *and* in evidence weights is
  double-counting.

Hints continue to be tracked for the LLM's grading context. They
just don't enter the calibration calculation directly.

**Cap demotion at one notch per check** (same reasoning as
promotion).

### 5.3 State and timing

Tracked state on the account doc (already defined in part 2):

```
account.calibration {
  difficulty: "easy" | "medium" | "hard"
  recentAnswers: [
    { quality, difficulty, at }
  ]   // window of 10
  recentQuestionTypes: string[]   // section 2
}
```

**Window size: 10.** Big enough to absorb noise from individual
answers, small enough to react to sustained patterns. Bigger windows
delay reaction; smaller windows allow noise to flip calibration.

**Check timing.** After every answer:

1. Append `{quality, difficulty, at}` to the window (oldest evicted
   if at capacity).
2. Evaluate promotion (5.1).
3. If no promotion, evaluate demotion (5.2).
4. If calibration changed, persist the new value.

**Calibration changes take effect immediately.** The next question
generated reads the new calibration.

**Old `lastPositiveAtCalibratedAt` timestamps on LO beliefs are not
retroactively re-evaluated.** They were set against the calibration
at the time of that answer, which is the correct interpretation. A
demoted student doesn't lose their "ever demonstrated at medium"
flag on previously-mastered LOs. The same holds for
`highestPositiveDifficulty` (4.3), which does not reference the
calibration at all.

**Per-LO override (section 2.3) is independent of student-level
calibration.** The notch-drop on a struggling LO doesn't appear in
the recent-answer window as a special case — the answer's
`difficulty` field records the actual difficulty asked, which may be
below the student's calibration if the override fired. Those answers
filter out of the at-calibrated set. They influence neither
promotion nor demotion.

### 5.4 Edge cases

**New student.** Calibration starts at `medium`. Window starts empty.
The minimum-data-points rule (4 for promotion, 3 for demotion)
prevents action until enough data accumulates. Student stays at
medium for the first 3–4 questions regardless of performance.

**Calibration just changed.** The student's recent window contains
answers at the *old* calibration. The at-calibrated filter excludes
them. Immediately post-change, only new answers count toward the
next promotion/demotion check. This creates a short stabilization
period — desirable, prevents thrashing.

**Sustained inactivity.** Calibration does not decay. The reactive
demotion rule handles post-hiatus rust: a returning student gets
questions at their old calibration, struggles with decayed beliefs,
and the rule demotes them within a few turns. Adding calibration
decay on top would be redundant.

**Hypothetical fast-flux.** A student alternating correct/wrong
exactly at calibrated medium. With 60% bad for demotion and 75%
correct for promotion, neither rule fires on a 50/50 split. Window
absorbs the noise. The student stays at medium until a sustained
pattern emerges. Working as intended.

### 5.5 What this section deliberately does not address

- **Follow-up behavior on a wrong answer.** Whether the conductor
  immediately re-probes or moves on. Section 6.
- **Calibration messaging to the student** ("Laten we het wat
  eenvoudiger aanpakken"). UI concern, not policy.
- **Calibration messaging to the teacher.** Observability — section 8.

---

## Section 6: Follow-up and chaining behaviour

After a graded answer, the conductor may present a non-graded
follow-up question that deepens or extends the previous answer
before moving to the next regular probe. Follow-ups are how the
conductor takes advantage of cognitive scaffolding the student has
already built — instead of context-switching to a fresh probe, it
asks "what about Y?" while their working memory is still loaded.

### 6.1 What a follow-up is, and isn't

A **follow-up** is a non-graded conversational turn that deepens or
extends the previous answer. It is:

- **Not a new probe.** The section 2 algorithm doesn't pick a new
  target LO for the follow-up.
- **Not a re-attempt.** The follow-up doesn't ask the student to
  redo the original question.
- **Triggered by the LLM grader,** which judges (per the part-3
  contract) when an answer would benefit from extension.
- **Optional.** Most answers don't get follow-ups; only the ones
  with pedagogical value beyond the original probe.

The LLM emits the follow-up question in the same response as the
grading. The conductor presents it after the feedback message. The
student answers; the LLM produces a free-form pedagogical reply
(potentially with weak `loSignals`); then the conductor moves to the
next regular probe via section 2.

**Why follow-ups exist.** Examples that motivated the design:

- "You wrote correct Newton-Raphson — what happens if the derivative
  is zero?" Probes robustness without throwing away the cognitive
  setup.
- "You're partially right; what if the samplerate doubles?" Uses the
  student's existing reasoning as a launchpad.

Skipping these costs real pedagogical value. A regular probe after
"correct" wastes the student's loaded context; a regular probe after
"wrong" replaces a teaching moment with feedback text.

### 6.2 Belief impact of follow-up answers

Follow-up answers may produce belief evidence — but at reduced
weight.

**`loSignals` are allowed on follow-up answers**, capped at
`strength: weak`. The LLM may emit `signal: positive | negative |
neutral` on any LO touched by the follow-up answer (per the part-3
scope rules), but the conductor forces strength to `weak` before
applying.

**Why allow signals at all.** The follow-up answer is real evidence:
a student demonstrating robustness understanding *is* signal about
the relevant LO. Discarding it loses information.

**Why cap at `weak`.** The follow-up question wasn't generated to
probe a specific LO at a calibrated difficulty. Treating its answer
as a primary probe is wrong. Cap-at-weak prevents over-weighting and
keeps belief grounded in the regular-probe loop.

**Difficulty multiplier on follow-up signals.** Follow-up questions
don't carry a `difficulty` field (they're generated as dialogue, not
as calibrated probes). For weight calculation, treat as `medium`
(multiplier 1.0). Combined with the `weak` strength cap, this means
follow-up signals contribute `0.5` to belief — meaningful but
secondary to a primary probe at medium (`1.0`).

**Calibration window: follow-up answers are skipped.** They don't
have a meaningful `difficulty` to file against, and they're not
probes of the student's calibration. The section 5 promotion/demotion
rules ignore follow-up answers entirely.

**No transfer credit on follow-up answers** (3.7). A follow-up is
dialogue, not a solution; any `transferLOs` the grader emits on one are
dropped.

### 6.3 When follow-ups fire

A follow-up presents when **all** of the following hold:

1. **The LLM grader emitted a `followUp` field** in the response.
2. **The previous turn was not itself a follow-up** — unless
   `allowChains` is set on the subgoal (see 6.4).
3. **The current target LO is not stuck** (section 4.4). A stuck LO is
   one the system has decided to advance past despite low belief;
   piling on a depth-probe fights that decision.
4. **The subgoal didn't just advance.** A subgoal-mastering answer
   triggers clean advancement; the follow-up is dangled on a
   subgoal the student has already left.

If any condition fails, the follow-up is suppressed and the
conductor moves directly to the next regular probe via section 2.

### 6.4 Chains: opt-in via subgoal flag

By default, follow-ups are limited to depth 1 — original question,
one follow-up, then back to regular probes. This is the right
default for procedural and foundational content where chained
dialogue is mostly noise.

For depth-worthy content (math, physics, conceptual subgoals where
edge-case reasoning matters), one follow-up is too few. The teacher
opts in via a per-subgoal flag.

**Schema amendment to part 1:**

```
Subgoal {
  ...
  allowChains: bool   // default false
}
```

When `allowChains` is `true` for the current subgoal, the conductor
permits follow-ups up to depth 2 (original question + two follow-ups
maximum). Each follow-up still requires the LLM to emit a
`followUp` field; the flag enables chaining but doesn't force it.

**Why subgoal-level, not LO-level.** Whether a topic warrants
depth-probing is a property of the content area, not individual
LOs. A subgoal where some LOs allow chains and others don't is a
sign the LOs should be in different subgoals.

**Why `bool`, not `int` or enum.** Depth 2 is the only meaningful
"more than one" value. Beyond that, dialogue gets exhausting and
the LLM's judgment about whether to extend further becomes
unreliable. A bool keeps authoring decisions binary and clear.

**Why teacher-authored.** The system can read coarse signals (`kind:
reason` correlates with depth-worthiness; multi-paragraph answers
invite extension) but can't reliably distinguish "this is
depth-worthy content" from "this is currently being taught at a
depth level." The same LO content could be taught procedurally
early and conceptually later. That's a pedagogical decision the
teacher owns.

### 6.5 Updated post-answer flow

```
on_answer_processed(answer):
    update_beliefs(answer.loSignals)            # section 3
    update_calibration_window(answer)           # section 5
    recompute_lo_mastery(affected_los)          # section 4
    if subgoal_mastered:
        advance()
        return
    if answer.followUp and follow_up_allowed():
        return present_followup(answer.followUp)
    return pick_next_question()                 # section 2.5

on_followup_answered(followup_answer):
    if followup_answer.loSignals:
        weakened = cap_strength_to_weak(followup_answer.loSignals)
        update_beliefs(weakened)                # section 3
        recompute_lo_mastery(affected_los)
        if subgoal_mastered:
            advance()
            return
    # follow-up answers do NOT update calibration window
    if followup_answer.followUp and follow_up_allowed_in_chain():
        return present_followup(followup_answer.followUp)
    return pick_next_question()

follow_up_allowed():
    return previous_turn_was_not_followup
       and current_lo not in stuck_los
       and not subgoal_just_advanced

follow_up_allowed_in_chain():
    return current_subgoal.allowChains
       and chain_depth < 2
       and current_lo not in stuck_los
       and not subgoal_just_advanced
```

The two `follow_up_allowed` variants encode the depth-1-default vs.
depth-2-with-flag rule.

### 6.6 The follow-up field on the grader response

Part 3 carries a `followUp` field on the grader response:

```json
{
  "overallQuality": "...",
  "feedbackText": "...",
  "loSignals": [...],
  "followUp": {
    "question": "Wat als de afgeleide nul wordt?",
    "rationale": "test understanding of edge case"
  }
}
```

`followUp` is optional / nullable. Present when the grader judges
the previous answer would benefit from extension; absent otherwise.
The `rationale` field is for debugging and teacher visibility, not
shown to the student.

When present, the conductor shows the question text to the student
verbatim — provided the conditions in 6.3 (or 6.4 for chained
follow-ups) are met.

### 6.7 What this section deliberately does not address

- **Re-attempt UX after a wrong answer.** Whether the student gets
  a "probeer nog eens" affordance is a UI concern, not conductor
  policy. The conductor moves to feedback + (optional follow-up) +
  next probe, regardless of how the UI surfaces that.
- **The "ik snap dit al, sla over" fast-forward affordance** from
  TODO Phase D. That's a different mechanic (a check before normal
  practice begins, not a follow-up after an answer). Deferred to a
  future design pass — likely unnecessary if section 5 calibration is
  responsive enough that strong students don't waste many turns.
- **Free-form student questions** (`studentQuestion` request type
  today). Non-graded chat the student initiates, doesn't touch
  belief or calibration. Out of scope for this section; existing
  handling is fine.

---

## Section 7: Edge cases

Defensive rules for states that shouldn't happen but will. The goal
isn't elegant behavior for every weird case — it's guaranteeing the
conductor doesn't crash, doesn't silently corrupt belief, and
surfaces enough that the teacher (or the developer reading logs) can
debug.

Most rules in this section are conservative on purpose. The cost of
"didn't advance the student" is a teacher-visible nudge; the cost of
"silently advanced past unlearned content" is invisible damage.

### 7.1 Empty `objectives` list

A subgoal exists with `objectives: []` — teacher mid-authoring, or a
curriculum import without LOs.

**The conductor blocks the subgoal.** It surfaces a system message
("Dit subdoel is nog niet helemaal klaar — vraag je leerkracht om
het af te ronden, of kies een ander subdoel."), generates no
question, makes no state change.

**No auto-skip past empty subgoals.** Even if conductor-driven
advancement would land on an empty subgoal, it stops there. The
cap-at-1 cascade rule (section 4.5) applies to mastered subgoals, not
authored-empty ones. Cascading past empty subgoals would silently
bypass content the teacher *intends* to author.

**Logged for teacher dashboard** (section 8).

### 7.2 LLM contract failure (single)

The grader returns an unparseable response, or a response whose
every signal is dropped during validation (per part 3).

**Single-failure fallback** is already in part 3: weak signal on
the question's intended LO, sign matching `overallQuality`. The
conductor applies this and continues.

### 7.3 LLM contract failure (sustained)

Repeated failures suggest a contract-level break — instruction
corruption, model regression, or a network pattern. The
single-failure fallback shouldn't become the primary signal source.

**Rule.** Track grading-call outcomes per session. If 3 of the last
5 grading calls produced fallback signals (couldn't be parsed
normally), enter **degraded mode**:

- Stop applying belief updates from the LLM.
- Surface a system message: "Er is iets mis met de feedback. Probeer
  het over een paar minuten opnieuw."
- Halt the session.
- Log for debugging.

**Recovery.** The failure counter is per-session, not persisted. The
next session starts fresh. If the underlying issue is fixed, the
next session works.

3-of-5 is tunable.

### 7.4 Mid-flight curriculum edits

Teacher edits the goal tree while a student is actively working.
Multiple flavors:

**LO renamed (id changed):** prohibited at the editor level. LO ids
are immutable per part 2; the goals editor must enforce this. No
runtime handling needed if the editor honors the constraint.

**LO deleted.** Existing belief docs orphan (per part 2). The next
LO selection reads the current `objectives` list and won't see the
deleted LO. If the deleted LO was the *current target*:

- **In-flight question already shown:** let it complete normally.
  The grading call's signals on the deleted LO will fail validation
  and be dropped (per part 3). Student's effort isn't wasted; it
  just doesn't update an LO that no longer exists.
- **In-flight question not yet shown:** in practice, hard to detect
  reliably. Simplest rule: always let in-flight complete. Validation
  drops orphan signals.

**LO added.** The new LO has no belief — i.e. unmastered. A
previously-mastered subgoal can flip back to "in progress." This is
correct behavior; the teacher decided this LO matters. Student
returning to leerpad sees the chip slip from done back to
in-progress. The section 1 entry algorithm picks up the new LO via
"first unmastered in curriculum order" on next entry.

**Subgoal deleted.** If the conductor's current subgoal is deleted,
surface a message ("Je vorige onderwerp is verwijderd door je
leerkracht. Ga verder met het volgende.") and advance to the next
unmastered subgoal in curriculum order. Logged for teacher
dashboard.

**Flag toggles** (e.g. `allowChains`, `optional`): read fresh on
each evaluation. No retroactive effect on chains already in
progress; rules apply from the next evaluation onward.

### 7.5 Student abandons mid-question

Student answers and then closes the app, or connection drops
mid-grading.

**No mid-question persistence.** State changes only on full grading
turn completion. Belief updates are atomic at the post-grade write.
If grading didn't complete, no belief change.

**Resume after abandonment:** the next session starts with a fresh
question via section 2 probe selection. The abandoned answer is
silently discarded.

Cost: occasional lost answer. Acceptable for the simplicity gained.

**Persistence failures during write** retry per existing Cosmos
rules (already covered by `safeCosmos` in the codebase). Repeated
failures fall through to a generic system error message.

### 7.6 Calibration data loss / corruption

A student's `account.calibration` substructure is missing or
malformed (migration bug, Cosmos blip, manual editing).

**Treat as new student.** Reset to default (`difficulty: medium`,
empty windows). Log the event.

The student loses calibration history; the section 5 update rules
re-establish calibration in 3–4 turns of normal probing. Better
than crashing or freezing.

### 7.7 Single-LO stuck-subgoal deadlock

A subgoal contains only one LO. The student's belief on it satisfies
the section 4.4 stuck rule. By section 4.4, "all non-optional LOs
mastered or stuck" would advance the subgoal — on a stuck-only
basis, no mastery anywhere.

This is worse than the multi-LO case where stuck-advances means "the
student knows most of this." Single-LO + stuck means "the student
knows none of this."

**Stricter rule:** stuck-advances requires at least one *mastered*
LO in the subgoal. Single-LO subgoals where that LO is stuck do
**not** advance.

The student can pick another subgoal manually. The teacher
dashboard (section 8) surfaces the gap; a teacher-side override to
manually advance is a future feature.

Implication for curriculum authoring: single-LO subgoals are a
smell. Either merge with adjacent subgoals or split the LO. Not
enforced; teachers will do it.

### 7.8 Stale `recentAnswers` window after long absence

Student returns after months. The calibration window contains old
answers.

**No special handling.** The window is bounded at 10 entries. After
3–4 fresh answers, the window is mostly current. The section 5
minimum-data-points rule (3 for demotion, 4 for promotion at
calibrated difficulty) prevents action during the transition.

The student may also have learned LO content through other means
(coding outside the app, classes, self-study) — old answers aren't
necessarily stale data, just data the system doesn't trust as much
as fresh data. Self-cleaning is the right behavior.

### 7.9 Concurrent updates from multiple sessions

Pathological case: same student opens the app from two devices and
grades two answers within Cosmos's last-write-wins window.

**Last-write-wins.** No optimistic concurrency in v1. Cost: one
belief update lost in pathological cases. Minor.

The deployment is currently desktop-only (Windows); concurrent
sessions would require running the app twice on the same machine,
which is unlikely in practice.

### 7.10 What this section deliberately does not address

- **Teacher-side override to manually advance a stuck student** (7.7).
  Future feature; not part of the conductor.
- **Optimistic concurrency** (7.9). Defer until we see actual data
  issues from concurrent sessions.
- **Explicit calibration reset on long absence** (7.8). Defer until
  practice shows self-cleaning is insufficient.
- **In-flight question persistence and replay** (7.5). Defer; the
  cost of occasional lost answers is acceptable.

---

## Section 8: Observability

Two distinct audiences: **the teacher**, who needs to know how
students are doing and when to intervene, and the **developer**, who
needs to debug what the conductor decided and why.

This section commits to *what data is captured* and *what categories
of teacher signals matter*. Detailed dashboard design is a UI pass
after the conductor lands.

### 8.1 Per-turn data capture

A new container, `turn_history`, holds one append-only doc per
graded turn. Partition `/uid` (consistent with `lo_beliefs` and
`progress`); single-partition queries for "this student's recent
turns" are the hot path.

```
TurnRecord {
  id: string                       // ISO timestamp + suffix
  uid: string                      // partition key
  turnAt: string                   // ISO 8601
  subgoalId: string

  // What was asked
  targetLOIds: string[]            // typically one
  questionType: string             // ChatRequestType
  difficulty: string               // easy/medium/hard
  isFollowUp: bool                 // section 6
  chainDepth: int                  // 0, 1, or 2

  // Why these were picked (section 2 decisions)
  selectionReason: {
    candidateLOs: [{loId, mean, evidence}]   // top 3
    chosenReason: string                     // "lowest mean", "recency relaxed", "stuck-fallback"
    notchDropFired: bool
  }

  // What happened
  overallQuality: string            // wrong | partial | correct
  loSignals: [{subgoalId, loId, signal, strength}]
  hadFallback: bool                 // grader response was unparseable
  appliedSignals: [{loId, alphaDelta, betaDelta}]   // post-modulation
  provenance: string                // home | supervised (3.2, #100); absent on older docs = home
  transferCredits: [{subgoalId, loId, alphaDelta}]  // 3.7, #101; omitted when none

  // Calibration impact
  calibrationBefore: string
  calibrationAfter: string

  // Subgoal status after this turn
  subgoalProgressAfter: float
  loStatusAfter: [{loId, mean, evidence, mastered, stuck}]
  subgoalAdvanced: bool

  // Teacher acknowledgment (8.2)
  acknowledgedAt: string?          // null until teacher reviews

  // Observability events fired during this turn (8.2). Empty for an
  // ordinary graded turn; one or more entries when the conductor
  // detected a strong-signal or audit-only condition.
  signalEvents: [
    {
      kind: string,                  // see 8.2 enum
      severity: "strong" | "audit",
      details: object?               // optional, kind-specific payload
    }
  ]
}
```

**Audit-only events outside graded turns** (empty-objectives blocks,
subgoal-deleted redirects) are written to the same `turn_history`
container as a stub record: `targetLOIds: []`, `questionType: ''`,
`overallQuality: "wrong"` (sentinel), `loSignals/appliedSignals/
loStatusAfter: []`, `subgoalAdvanced: false`, with exactly one entry
in `signalEvents`. This keeps the dashboard query path uniform — a
single partition query against `turn_history` returns both graded
turns and audit events.

**Storage estimate.** ~500 bytes per turn × ~50 turns/student/week
× ~30 students ≈ 750 KB/week. Negligible for Cosmos.

**Deliberately not captured:**

- Full LLM response text (redundant with `loSignals` + `feedbackText`).
- Rendered question prompt text (regenerable from inputs).
- Student's literal answer text (privacy, bulk).
- Time-on-question or engagement signals.

If a future debug need requires full text, it can be added later.

### 8.2 Teacher-facing surfaces

#### Signal-event `kind` enum

Each `signalEvents[*].kind` is one of:

**Strong (badge-driving):**

- `stuckLoAdvance` — subgoal advanced with one or more stuck LOs
  (section 4.4). Real knowledge gaps the conductor passed despite low
  belief. `details: {subgoalId, stuckLoIds: [...]}`.
- `singleLoDeadlock` — single-LO subgoal stuck, conductor blocked
  from advancing (section 7.7). `details: {subgoalId, loId}`. Fires
  once per (session, subgoal) pair.
- `repeatedDemotions` — `repeatedDemotionsThreshold` consecutive
  demotions in this session with no intervening promotion. Threshold
  lives in the constants module (default 3). `details: {count,
  calibrationAfter}`. Fires once per session; promotion resets the
  counter.
- `sustainedLlmFailure` — `degradedThreshold` of the last
  `degradedWindow` grading calls fell back; the conductor flips
  into degraded mode (section 7.3). `details: {fallbackCount,
  window}`. Fires once per session.

**Audit-only (no badge, drawer-only):**

- `cascadeHalt` — auto-skip cascade exceeded `cascadeSkipCap`
  (section 4.5). Data-inconsistency signal. `details:
  {haltedAtSubgoalId, depth}`.
- `emptyObjectivesBlock` — student landed on a subgoal with
  `objectives: []` (section 7.1). Authoring incomplete. `details:
  {subgoalId}`. Fires once per (session, subgoal).
- `subgoalDeletedRedirect` — teacher deleted the active subgoal
  mid-session (section 7.4). `details: {subgoalId}`.

#### Strong signals — needs attention

The "needs attention" badge on the accounts page fires when a
student has any unacknowledged record whose `signalEvents` contains
at least one entry with `severity: strong`. The count shown on the
badge is the number of such records (one per turn, regardless of
how many strong events that turn carried).

Drilling into the student opens the detail drawer where each event
is listed (strong first, then audit) and can be acknowledged.

#### Audit-trail signals — informational

Audit-severity events are visible in the detail drawer but do not
contribute to the badge count.

#### Acknowledgment

**Per-student**, not per-event. The teacher's mental model is "I
dealt with this student"; the UI matches. Acknowledging clears all
of that student's currently-listed strong-signal events
(`acknowledgedAt` set to now on each).

**No time-based aging out.** Unacknowledged events stay on the list
indefinitely until the teacher explicitly acknowledges. A teacher
distracted by a different student's situation doesn't lose track of
the first.

#### Per-LO belief detail in the detail drawer

When the teacher drills into a student's subgoal, show per-LO:

- Belief mean
- Evidence count (`α + β`)
- Status: mastered, stuck, active
- Last probed timestamp

Replaces / extends the existing per-subgoal progress view with the
finer-grained data the LO model provides.

#### Existing surfaces to retain

- Per-subgoal progress list (uses cached `progress`).
- Per-subgoal AI status reports.
- 30-day progress-history line chart (uses `progress_history`).

#### Deferred to post-v1

- **Calibration timeline.** Line chart of student's calibration
  over time with promotion/demotion markers. Data is in
  `turn_history`; UI work deferred.
- **Curriculum-health surface.** Cross-student aggregations
  ("which LOs do most students get stuck on?", "which subgoals see
  the most calibration drops?"). Useful for the teacher iterating
  on the curriculum itself. Data feasible from `turn_history`; not
  v1 priority.

### 8.3 Developer-facing debug

The current `DebugSessionRecorder` + `DebugDialog` (in-memory
circular buffer of `TurnRecord` events, viewable in `kDebugMode`)
becomes the in-memory mirror of the persisted `turn_history`. Same
shape, two storage layers.

**Changes for the new conductor:**

- **`TurnRecord` shape unifies in-memory and persisted formats.** The
  schema in 8.1 is canonical for both.
- **Selection reasoning is shown explicitly.** `chosenReason`,
  `notchDropFired`, candidate LOs and stats. Crucial for
  understanding "why did the conductor pick this question?"
- **Fallback turns are highlighted** (`hadFallback: true`). Color
  marker or filter affordance.
- **Decay-effective values shown alongside persisted values.** When
  the dialog displays an LO belief, show both `α`/`β` (persisted)
  and `α_effective`/`β_effective` (after decay applied on read).
  Otherwise it's hard to understand why the conductor saw an LO as
  unmastered when the doc says `(8, 1)`.

**Replay-with-different-constants** is a future tool for tuning the
constants stacked across sections 3–5. The data is there in
`turn_history` to support it. Build the tool when constants need
actual tuning; until then, debug-dialog inspection of what *did*
happen is sufficient.

### 8.4 Data lifecycle

`turn_history` accumulates indefinitely by default. No automatic
pruning.

**Manual clean action (deferred admin feature).** A teacher-only
action to purge `turn_history` (and optionally `progress_history`)
for a configurable date range or specific students. Use case: end
of school year — archive everything older than the new course start
date.

The data model supports this (partitioned by `/uid`, bounded by
`turnAt`); the UI/action itself is post-v1. Belief docs don't
depend on `turn_history` content, so deletion is safe — the
conductor will not crash or behave incorrectly with empty turn
history. Only debug/teacher views are affected.

**Other persistence** (`lo_beliefs`, `progress`, `account.calibration`)
is treated as live student state and not cleaned by the same
action. Cleaning those is "reset student" — different feature,
different button, not part of the year-end-archive flow.

### 8.5 Privacy and isolation

- **Cross-student isolation continues at runtime** (per part 3).
  The LLM never sees data about students other than the one being
  graded. Teacher-side aggregations happen post-hoc, in the
  conductor's process.
- **No engagement metrics.** No time-on-question, mouse movements,
  keystrokes, or attention proxies in `turn_history`.
- **No literal student answer text** in `turn_history`. The LLM's
  extracted `loSignals` and `overallQuality` are what's stored.

### 8.6 What this section deliberately does not address

- **Detailed dashboard layout.** UI work, follows conductor
  implementation.
- **The replay-with-different-constants tool** for tuning. Future
  work.
- **The clean / archive action UI.** Deferred admin feature; data
  model supports it.
- **Curriculum-health cross-student aggregation surfaces.**
  Data-feasible but post-v1.
