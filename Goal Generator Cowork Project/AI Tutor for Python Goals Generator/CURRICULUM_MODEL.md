# Curriculum data model

Part 1 of the conductor redesign. Defines the structure of the curriculum
data — what a Goal, a Subgoal, and a Learning Objective are. This is the
authoring model: what teachers create and edit, what the conductor reads
to decide what to do next.

This document does **not** cover:

- The student model (per-student belief state, calibrated difficulty, etc.) — part 2.
- What the LLM emits per answer — part 3.
- The conductor's decision policy — part 4.
- *How* to author good LOs for a given subgoal. That's a follow-up exercise once the model is settled.

## Goals this model serves

The conductor redesign is trying to reach three things:

1. Advance a student through a subgoal as soon as they've shown understanding of its aspects — no sooner, no later.
2. Calibrate difficulty to the student, not just to the subgoal. Calibration sticks across sessions and across subgoals.
3. Avoid asking redundant questions: if a student clearly handles a type/aspect/difficulty combination, don't keep poking at it.

The curriculum model's job is goal (1): give the conductor a concrete, testable definition of "understood the aspects of this subgoal."

## Three layers: Goal → Subgoal → Learning Objective

Three nested entities. Each has a distinct purpose; conflating them
breaks the conductor's ability to reason cleanly.

### Why three layers, not two or four

- **Two (Goal → LO, no Subgoal):** collapses unit-of-work granularity. Hundreds of LOs per goal, no natural "I'm done with this chunk" beat. Authored Uitleg content also wants the subgoal granularity — a goal is too coarse for one explanation.
- **Four (e.g. Goal → Subgoal → Aspect → LO):** anything between Subgoal and LO does work the LOs already do. Modules are a real fourth layer but live *outside* this hierarchy in their own container.

## Goal (root)

The coarse curriculum unit. The student-facing chunk that shows up as a
card in Leerpad. Examples from the intended downstream curriculum:
"Conditional statements", "Bisection method", "Fourier transforms".

### Fields

- `id` — string
- `type` — `"goal"` (shared container with subgoals; `parentId == null` distinguishes a goal from a subgoal)
- `moduleId` — string, references `modules/{id}` (from Phase A)
- `title` — student-facing title
- `description` — prose. What mastering this goal means at a high level.
- `order` — int, manual ordering within the module (spaced by 1000, same as today)
- `optional` — bool

### Deliberately not on a Goal

- **No LOs.** LOs live on subgoals. A goal is essentially a folder with prose.
- **No `knownConcepts` field.** Currently used as scope-fencing for the LLM ("don't ask about things from later goals"). The LO model gives a more precise alternative: scope is "all LOs in subgoals up to and including the current one." One fewer field to maintain, more precise output.
- **No difficulty hints, no concept tags, no prerequisites.** Order *is* the prerequisite chain. Difficulty is per-student.

## Subgoal

The unit the conductor works on. A single coherent skill that can be
assessed as a whole. The student stays on this subgoal until belief on
all its LOs crosses a threshold.

### Fields

- `id` — string
- `type` — `"goal"` (same container as Goal)
- `parentId` — string, the goal it belongs to
- `title` — student-facing title
- `description` — prose. The informal version of "what does mastering this look like."
- `order` — int
- `optional` — bool
- `contentId` — string?, references `content/{id}` (from Phase A — the authored Uitleg)
- `teachingTips` — `string[]`. Free-form prose hints to the LLM about how to approach this subgoal. (Renamed from current `suggestions` for clarity. Stays unstructured deliberately.)
- `allowChains` — bool, default `false`. Enables follow-up chains up to depth 2 within this subgoal. Off by default — appropriate for procedural/foundational subgoals where chained dialogue is mostly noise. Set to `true` for conceptually rich subgoals (math, physics, edge-case reasoning) where deeper dialogue is pedagogically valuable. The flag *enables* chains; it doesn't force them. See conductor policy section 6.
- `objectives` — ordered list of LOs (see below)

### Deliberately not on a Subgoal

- **No `knownConcepts` field** (same reasoning as on Goal).
- **No question-type preferences.** Question types are a policy concern — the subgoal model says *what* to test, not *how*.
- **No difficulty hints.** Difficulty calibrates to the student, not the subgoal.

## Learning Objective (LO)

The atomic unit of belief. One thing the student either has or doesn't.
The conductor maintains a posterior belief per LO (defined in part 2).

### Fields

- `id` — string, slug-style, **unique within the subgoal** (`quote_distinction`, `predict_branch`). Stability matters because student belief state is keyed on it.
- `statement` — string, one sentence in second person describing what the student would have to demonstrate. ("You can predict which branch runs given the condition's truth value.")
- `kind` — enum, one of: `recall`, `apply`, `predict`, `reason` (see below).
- `weight` — number, default `1.0`. Lets the teacher mark high-stakes LOs.
- `optional` — bool, default `false`. Optional LOs are still probed for variety and coverage but don't gate subgoal advancement (see conductor policy section 4). Use case: "nice to have" LOs included for completeness without making them blockers — e.g. historical context for a numerical method when the implementation skill is what really matters.

### `kind` enum

Four values. The intent is to capture *what kind of cognitive work the LO is asking for*, not what question type probes it (that's a policy decision).

- **`recall`** — the student knows a fact, definition, or piece of syntax. *"You know that `range(n)` produces 0 to n-1."* Cheap to test, shallow.
- **`apply`** — the student can produce code or compute a result. *"You can write a loop that sums a list."* The most common kind.
- **`predict`** — the student can read code/math and say what it does. *"You can predict the output of this loop."* Tests understanding without requiring production.
- **`reason`** — the student can explain *why*, choose between approaches, or diagnose problems. *"You can explain why bisection requires a sign change between endpoints."* The deepest kind, most important for math/physics content downstream.

The same conceptual area can show up across multiple `kind`s. *"Implement Newton-Raphson"* is `apply`; *"Explain why Newton-Raphson can fail to converge"* is `reason`. These are separate LOs because they're separately testable and separately important — a student can have one without the other.

### `weight`

Numeric, default `1.0`. Used by the policy to decide:

- whether the subgoal is mastered (weighted across LOs)
- which LO to probe next (weight breaks ties)

In the v1 editor we leave `weight` out of the UI and let everything default to 1.0. The field is in the schema from day one because backfilling it later is messy and the data is small. We expose the knob in the UI when authoring experience tells us we need it.

### Deliberately not on an LO

- **No question-type binding.** An `apply` LO can be tested by `writeCode` or `completeCode`. A `predict` LO can be tested by `mcQuestion`, `explainCode`, or `socraticQuestion`. The mapping is policy.
- **No difficulty.** Same LO can be probed easy or hard depending on the student.
- **No prerequisites.** Order within the subgoal is the order. Cross-subgoal prereqs are implied by curriculum order.
- **No tags or concepts.** The LO's `id` and `statement` *are* the tag. We don't need a parallel taxonomy.
- **No belief data.** Belief is per-(student, LO), lives in the student model. The LO is pure curriculum data: authored once, edited rarely, never modified by runtime.
- **No "last asked" / "times probed" stats.** Runtime state per student lives in the student model, not on the LO.

## Schema sketch

Concrete shape of the documents (Cosmos `goals` container, single-partition `/type = "goal"`):

```
Goal {
  id: string
  type: "goal"
  moduleId: string
  title: string
  description: string
  order: int
  optional: bool
  parentId: null   // null marks a root goal
}

Subgoal {
  id: string
  type: "goal"     // same container; parentId distinguishes
  parentId: string
  title: string
  description: string
  order: int
  optional: bool
  contentId: string?
  teachingTips: string[]
  allowChains: bool   // default false
  objectives: [
    {
      id: string         // unique within the subgoal
      statement: string
      kind: "recall" | "apply" | "predict" | "reason"
      weight: number     // default 1.0
      optional: bool     // default false
    }
  ]
}
```

LOs are **embedded** in the subgoal doc, not stored in a separate
container. They're small, always loaded together with the subgoal, and
never queried independently. A separate container would add joins for
no benefit.

## Settled decisions

- **`kind` enum has four values:** `recall | apply | predict | reason`. Considered collapsing `recall` into `predict` and rejected — they probe different things and the policy may want to treat them differently.
- **`weight` exists at v1.** Default 1.0. Field present in schema, hidden in the UI for v1, exposed later if needed.
- **LO `id` is unique within the subgoal**, not globally. Belief state is naturally keyed on (student, subgoal, lo); globally-unique ids would just mean longer strings.
- **`optional: bool` on LO** (default `false`). From conductor policy section 4.2. Optional LOs are probed but don't gate advancement.
- **`allowChains: bool` on Subgoal** (default `false`). From conductor policy section 6.4. Subgoal-level rather than LO-level because depth-worthiness is a content-area property; granular per-LO would invite inconsistency within a subgoal.

## Non-goals of this model

- Not a knowledge graph. No cross-references between LOs across subgoals. If two subgoals genuinely share an LO, duplicate it. The cost of dedup machinery is way higher than the cost of duplication for any plausible curriculum size.
- Not a rubric. The LOs are the *outline* of what to assess. Per-question grading instructions can still be specific — that contract is part 3.
- Not a Bloom's taxonomy or other formal pedagogical framework. The four `kind` values are pragmatic, not theoretical.
- Not a difficulty scheme. Difficulty is per-student, computed at runtime, calibrated as we go.

## Migration / current-state notes

The current `goals` container holds Goal docs and Subgoal docs (both `type = "goal"`, distinguished by `parentId`). To get to this model:

- Goals: drop `knownConcepts` and `suggestions` (suggestions on a root goal is unused today). Add `moduleId` (Phase A also adds this).
- Subgoals: rename `suggestions` → `teachingTips`. Drop `knownConcepts` (currently always empty on subgoals). Add `contentId` (Phase A). Add `allowChains` (default `false`). Add `objectives` (this doc).
- Existing subgoals come in with `objectives: []`. Authoring LOs is the follow-up exercise. The conductor blocks empty-`objectives` subgoals (see conductor policy section 7.1) — students see a "not ready" message and can pick another subgoal.
- LOs carry `optional: bool` (default `false`) from the start.

Authoring LOs for a given subgoal — the heuristics, the granularity rule
("split when the LOs would naturally be probed by different questions,
merge when they'd always come up together"), and similar guidance — is
out of scope for this document. That's an authoring exercise once the
model is settled and used in anger.
