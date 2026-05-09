# LLM contract

Part 3 of the conductor redesign. Defines what the grader LLM emits per
answer, and what the question-generator LLM is told about the question
it's being asked to produce. Together these form the data interface
between the conductor and the LLM.

This document does **not** cover:

- The curriculum data model — part 1.
- The student model — part 2.
- The conductor's decision policy (when to ask which question type at
  which difficulty, how to weight evidence into Beta updates, mastery
  decisions) — part 4.
- The exact wording of the prompts. The contract here is the data
  shape; prompt wording is teacher-authored and lives in the
  `instructions` container.

## Goals this contract serves

The LLM is the only source of grading judgment in the system. For the
student model to be updated meaningfully:

1. **Per-LO evidence** — the LLM must tell us *which LOs the answer
   reflected on, and how*. A single quality enum per question is too
   lossy.
2. **Calibrated strength** — the LLM must tell us *how clearly* the
   evidence cuts, so the conductor can weight strong signals more than
   borderline ones.
3. **Validatable** — the contract must be machine-checkable so we can
   reject bad outputs without having to argue with prose.

Part 3 nails the data shape. Part 4 decides how the conductor consumes
it (evidence weights, when to ask follow-ups, etc.).

## What we send to the LLM

Two distinct calls: question generation and answer grading.

### Question generation

The conductor decides it wants to probe specific LO(s) at a given
difficulty using a given question type. The LLM produces the question.

Inputs:

- `goal` — current root goal (title, description).
- `subgoal` — current subgoal (title, description).
- `teachingTips` — the renamed `suggestions` field from the subgoal.
- `targetLOs` — list of LOs the conductor wants probed:
  `[{id, statement, kind}, ...]`.
- `difficulty` — `easy | medium | hard`. The student's calibrated
  difficulty.
- `questionType` — `mcQuestion | writeCode | completeCode | explainCode
  | socraticQuestion | guidingQuestion`. Picked by policy.

Outputs: same envelope as today, the META payload matches the existing
per-question-type schema (MCQ options, code snippet, prompt text, etc.).
No structural change on this side — only the inputs gain `targetLOs`
and the question-type prompt is told to focus on those LOs.

The conductor may request a question that probes a single LO or
multiple LOs. The LLM should weight the question to those LOs but is
not forbidden from incidentally probing others.

### Answer grading

The student has answered. The LLM judges what the answer reveals.

Inputs:

- `goal`, `subgoal`, `teachingTips` — same as generation.
- `targetLOs` — the LOs the question was meant to probe (the same list
  passed to generation; carried through so the grader knows the
  intent).
- `goalScopeLOs` — every LO from every subgoal in the **current root
  goal**, including earlier subgoals. `[{subgoalId, loId, statement,
  kind}, ...]`. The grader may emit signals against any of these,
  not just `targetLOs`.
- `question` — the prompt the student received plus any code/options.
- `studentAnswer` — what the student typed or selected.
- `difficulty` — what difficulty the question was set at.

Note: `goalScopeLOs` does not include LOs from earlier root goals.
Forgetting from earlier roots is handled by belief decay (part 2), not
by per-question signals. Keeps prompt token cost bounded.

## What the grader returns

```json
{
  "overallQuality": "wrong" | "partial" | "correct",
  "feedbackText": "Dutch student-facing message",
  "loSignals": [
    {
      "subgoalId": "use_if_else",
      "loId": "predict_branch",
      "signal": "positive" | "negative" | "neutral",
      "strength": "strong" | "moderate" | "weak"
    }
  ],
  "followUp": {
    "question": "Wat als de afgeleide nul wordt?",
    "rationale": "test understanding of edge case"
  }
}
```

`followUp` is optional / nullable. The grader emits it when it
judges the previous answer would benefit from a deepening or
edge-case probe — typically because the answer was correct but
shallow, or wrong in an instructive way that dialogue would
clarify. Most graded turns omit it.

### Field semantics

**`overallQuality`** — coarse single-question verdict. Functions as a
self-consistency check on `loSignals`: if every signal is negative,
`overallQuality` shouldn't be `correct`. The LLM sees both as a
constraint when generating. Whether/how the UI surfaces this value is a
downstream decision, not part of the contract.

**`feedbackText`** — one Dutch message for the student. Same role as
the existing `prompt`/`feedback` text. Granular per-LO feedback is for
the conductor's eyes only; the student gets one readable message.

**`followUp`** — optional. When present, contains a `question` (the
text the conductor will show the student verbatim, in Dutch) and a
`rationale` (for debugging and teacher visibility, not shown to the
student). The grader emits this when continuing the dialogue would
deepen understanding more than a fresh probe would. Whether the
conductor actually presents it depends on conductor-side conditions
(see conductor policy section 6.3): default depth limit is 1, raised
to 2 when the subgoal's `allowChains` flag is `true`.

**`loSignals`** — the array that updates belief. Always present,
possibly empty.

- `subgoalId`, `loId` — must identify a real LO in `goalScopeLOs`.
- `signal` — three values:
  - `positive` — the answer demonstrated the student has this LO
  - `negative` — the answer demonstrated the student lacks this LO
  - `neutral` — the answer touched on this LO but gave no clear
    evidence either way. Meant to be rare; the LLM is told to commit
    when it can.
- `strength` — three buckets:
  - `strong` — the answer cleanly demonstrates or fails to demonstrate
    the LO
  - `moderate` — the answer is mostly informative but has noise (e.g.
    correct logic, wrong vocabulary)
  - `weak` — the answer is informative only at the margin

Three strength buckets, not two: forcing a binary choice rounds away
the "correct but ugly" / "almost right" cases that show up constantly
in real grading.

The LLM may emit at most one signal per `(subgoalId, loId)` pair per
question.

## Grading follow-up answers

When the student answers a follow-up (a question the conductor
presented because the previous grader response had a `followUp`
field, per conductor policy section 6), the LLM is invoked again
with the follow-up question and the student's answer. The grading
contract is the same shape as for primary probes — same
`overallQuality`, `feedbackText`, `loSignals`, and an optional
nested `followUp` if chains are allowed.

Two semantic differences from primary probe grading:

- **No calibrated difficulty.** Follow-up questions don't carry a
  `difficulty` field; they're dialogue, not calibrated probes. The
  conductor treats follow-up signals as `medium` for the
  difficulty-multiplier step in belief updates.
- **Conductor caps strength at `weak`** for any `loSignals` emitted
  on a follow-up answer. The LLM may emit `strong` or `moderate`,
  but the conductor downgrades to `weak` before applying. This
  reflects that follow-up answers, while real evidence, weren't
  designed as calibrated probes of a specific LO at a specific
  difficulty.

Other than these two, follow-up answer grading uses the same
schema, scope, and validation rules as primary grading.

## Validation on the conductor side

Every grader response is validated before it touches the student
model:

1. **Schema validation.** All required fields present, enums in the
   allowed set.
2. **LO id resolution.** Each `(subgoalId, loId)` must resolve to a
   live LO in the current goal's scope. Unresolved signals are
   dropped; the drop is logged.
3. **Scope check.** `subgoalId` must be the current subgoal or an
   earlier subgoal *within the current root goal*. Forward-references
   (next subgoal, future goal) are dropped and logged.
4. **Self-consistency.** If `overallQuality = correct` but every
   surviving signal is negative (or vice versa), log it. The conductor
   trusts `loSignals` over `overallQuality` for belief updates;
   `overallQuality` is for the UI/debug only.

If the response fails to parse or every signal is dropped, the
conductor falls back to a single weak signal on the question's
**intended LO** (or the first `targetLO` if there were several), sign
matching `overallQuality`:

- `correct → (positive, weak)`
- `partial → (neutral, weak)`
- `wrong → (negative, weak)`

The fallback exists so the conductor doesn't dead-end on a bad LLM
call. It deliberately under-credits/under-debits — a malformed
response shouldn't have full evidence weight.

## Cross-student isolation

Every grading call is scoped to one student. The LLM is never told the
ids of other students, never sees other students' belief data, and
never receives prompts that would let it correlate across students.
Belief updates happen against exactly one student model: the one whose
answer was just graded.

## Settled decisions

- **Three strength buckets:** `strong | moderate | weak`. Two would
  round away the common borderline cases.
- **`neutral` signals are kept** but the LLM is told they should be
  rare.
- **Scope of `loSignals` is the current root goal**, not just the
  current subgoal. Cross-goal forgetting is handled by belief decay
  (part 2), not per-question signals.
- **Categorical signals only.** No numeric scores from the LLM. The
  conductor maps `(signal, strength)` to evidence weights — keeping
  calibration in code, not prompts.
- **`overallQuality` is kept as a self-consistency check** for the
  generator, not because the UI requires it. UI usage is a downstream
  decision.
- **Cross-student isolation is absolute.** The LLM never sees data
  about students other than the one being graded.
- **`followUp` is a question text**, not a hint. When present, the
  conductor shows it to the student verbatim. Whether to present it
  is a conductor-side decision (policy section 6.3); the contract
  just provides the question.
- **Follow-up answer grading reuses the primary grading shape**
  with two semantic differences: signals are treated as
  `medium`-difficulty for weight calculation, and the conductor
  caps emitted strength at `weak`.

## What this contract deliberately does not do

- **Does not let the LLM update beliefs directly.** The LLM emits
  evidence; the conductor decides how to weight it.
- **Does not ask the LLM to calibrate difficulty.** Difficulty is
  per-student state, set by the conductor before generation.
- **Does not let the LLM second-guess question difficulty after the
  fact.** If the question turned out badly calibrated, that's evidence
  for updating *student* difficulty, not for re-tagging the question.
- **Does not emit per-LO numeric scores.** Categorical only, by design.
- **Does not promise per-aspect feedback to the student.**
  `feedbackText` is one Dutch message; signal granularity is for the
  conductor.
- **Does not handle multi-turn grading as a single call.** Each call
  is one question / one answer. Follow-up exchanges produce their own
  grading events with their own `loSignals`.
- **Does not carry `suspectedConcepts`.** The LO model replaces it: a
  shaky concept surfaces as a signal on the LO that owns it. No
  parallel free-text taxonomy.
- **Does not let the LLM control whether a follow-up is presented.**
  The grader emits a `followUp` if it judges one warranted; the
  conductor decides whether to actually present it (chunk 6.3
  conditions).
