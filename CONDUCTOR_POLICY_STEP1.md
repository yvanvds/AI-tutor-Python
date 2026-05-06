# Conductor policy (working draft)

Part 4 of the conductor redesign. Defines how the conductor uses the
curriculum data (part 1), the student model (part 2), and the LLM
contract (part 3) to decide what to do next.

**Status: in progress.** This document grows as we work through the
policy in chunks. Each section reflects the decisions settled at the
time of writing. Sections are added in the order they were resolved,
not in the eventual reading order.

This document does **not** yet cover:

- Per-question decisions during practice (which LO next, which type,
  which difficulty after the first question) — chunk 2.
- Belief update mechanics (evidence weight tables, decay curves, cap
  shrinkage) — chunk 3.
- Subgoal completion / mastery rules — chunk 4.
- Difficulty calibration updates (promotion/demotion) — chunk 5.
- Follow-up / chaining behaviour — chunk 6.
- Edge cases (empty objectives, LLM contract failure, mid-flight
  curriculum edits) — chunk 7.
- Observability — chunk 8.

The eventual document will be reorganized once all chunks are
resolved.

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
is deferred to chunk 2b. It depends on tightening the question-type
prompt definitions; without that, the mapping isn't trustworthy. The
defaults above are the cold-start commitment.

**Gentleness ordering** (used when picking among acceptable types,
once chunk 2b lands):

```
mcQuestion < completeCode < explainCode < writeCode < socraticQuestion
```

Known issue, deliberately not fixing: `socraticQuestion` is currently
an underdefined umbrella covering both light prediction prompts ("Wat
denk je dat dit afdrukt?") and open-ended reasoning. The ordering is
honest for the latter, wrong for the former. The misclassification
mostly affects the simplest early subgoals and self-corrects once the
content gets harder. Not worth splitting the question type; flagged
for awareness when chunk 2b lands.

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
numbers in chunk 4). Same rule as cold start, with mastered LOs
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

This replaces the earlier chunk 1b proposal of "auto-advance on a
fully-mastered subgoal." Auto-advance was wrong because it ignores
student intent (they tapped *this* subgoal). The saturation prompt
respects intent while being honest that the system has nothing
further to learn from this LO right now.

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
  belief just updated?" is chunk 2a. The entry algorithm above
  produces only the first question of a session/subgoal.
- **Multi-LO questions.** Whether the conductor ever picks two LOs to
  probe in one question (cheaper coverage) is deferred to chunk 2d.
- **The full type-by-kind acceptable-set table.** Cold-start defaults
  are committed; the rest is chunk 2b.
- **What happens when an LO has no acceptable types** (empty
  intersection of "kind is X" and "type is appropriate"). Edge case;
  chunk 7.
