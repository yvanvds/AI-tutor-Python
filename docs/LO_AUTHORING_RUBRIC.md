# LO authoring rubric

Companion to `CURRICULUM_MODEL.md`, which defines the *shape* of a Learning
Objective but explicitly punts on *how to author good ones*. This document
fills that gap. It is the rubric the goal-authoring skill follows
internally and surfaces to the teacher when relevant.

Target audience for the curriculum being authored: **~16-year-old students
with first programming exposure.** The defaults below are tuned for that
context; for older or more experienced students, the heuristics shift
(less `predict`, more `reason`, more chained dialogue).

## What an LO is

An LO is **one observable thing the student can do**, statable in the form
*"You can ___."* It is the atomic unit the conductor maintains belief
over. If you can't picture a single question that probes it cleanly, it's
not an LO yet — it's two LOs, or a topic, or a subgoal.

## The observability test

Replaces the older "banned verbs" list. One question:

> Could a stranger watching a 30-second video of the student answering
> one question see whether they have this LO?

If yes, the LO is observable. If no, it's an internal state ("understand",
"know", "be familiar with", "appreciate") and needs rewriting. The fix is
always the same: ask *"understand well enough to do what?"* and use that
verb.

## Three failure modes to watch for

Authoring goes wrong in three distinct ways. The rubric checks for each.

### 1. The LO is a topic, not an action

*"You can use if statements."* That's the subgoal title, not an LO. There
is no single question that probes "using if statements" — it's a cluster
of skills (predict, write, choose-the-right-shape, indent-correctly). If
the LO statement reads like something you'd put on a syllabus, it's a
topic and needs to be broken into actions.

### 2. The LO is two LOs glued together

*"You can predict and write if/else statements."* Two failure modes
(prediction, writing) collapsed into one. Belief on this LO becomes
ambiguous — does a wrong answer mean they can't predict, or can't write?
Split.

### 3. The LO is unobservable

*"You can understand how if/else works."* Fails the observability test.
Rewrite as the action that "understanding" produces (predict, explain,
write, distinguish).

## The four `kind` values, used deliberately

`recall | apply | predict | reason`. They are not interchangeable. The
conductor's policy may treat them differently, and a subgoal where every
LO is the same kind probes only one slice of skill.

- **`recall`** — student names, identifies, or distinguishes a thing
  without doing anything with it. *"You can identify which of these is a
  valid variable name."* Cheap to assess, brittle on its own. Use as
  scaffolding for higher-kind LOs, not as the main course.
- **`apply`** — student produces something. Writes code, fills a blank,
  completes a snippet. *"You can write an `if` statement that prints a
  message when a number is positive."* The default for procedural skills.
- **`predict`** — student traces given code and says what happens. *"You
  can predict which branch runs given the values of `x` and `y`."* For
  first-exposure students this is the workhorse: tracing before writing
  is how novices build a working mental model. Subgoals with **zero**
  `predict` LOs deserve a hard look — what's the tracing skill the
  student needs here?
- **`reason`** — student explains *why*, picks between alternatives with
  justification, or reasons about edge cases. *"You can explain why `=`
  and `==` are not interchangeable."* Higher cognitive load. Worth
  including on conceptually rich subgoals; rarely fits on procedural
  ones.

### `kind` distribution as a sanity check, not a target

There is no recipe. *"1 recall + 2-3 apply + 1-2 predict + 0-1 reason"* is
roughly what a typical first-exposure procedural subgoal looks like
*after* good authoring, not a quota to hit. The check is:

- All-same-kind subgoal? → why is that, is the skill really that
  one-dimensional?
- Zero `predict` on a procedural subgoal? → flag, propose adding one.
- Zero `apply` on anything that involves writing code? → flag.
- Three or more `reason` LOs in one subgoal? → probably over-conceptual,
  likely a topic that should be split.

If the answer to any "why" is good, leave it. The rubric flags; the
author decides.

## Granularity: split, merge, or recognize as a topic

Three cases to triage:

- **Split** when a wrong-answer pattern on one LO would not predict
  failure on the other. *"Predict whether an `if` branch runs"* and
  *"predict whether the `else` branch runs"* — same skill, merge.
  *"Predict the branch given a comparison"* and *"predict the branch given
  a boolean variable"* — different failure modes for novices, split.
- **Merge** when the natural question testing one would always also test
  the other. If you can't write a question that hits LO-A without also
  hitting LO-B, they're one LO.
- **Recognize as a topic** when the proposed LO is so broad that it
  contains its own structure. *"You can use loops"* is not an LO; it's a
  subgoal (or a goal) needing 3-6 actual LOs of its own. The tell:
  someone could write a half-hour lesson plan around the LO statement.

**Target count: 3-6 LOs per subgoal.** Below 3, the subgoal is probably
too small (consider folding into a sibling). Above 6, it's probably two
subgoals. Hard ceiling 8 — the conductor's evidence-gathering thins out
beyond that.

## Statement form

One sentence, second person, present tense, observable verb.

> You can `<verb>` `<object>` `<condition or constraint>`.

Pass the observability test. Avoid hedges like *"generally"*,
*"usually"*, *"in most cases"* — they describe partial mastery, which is
the conductor's job to track, not the LO's job to encode.

## Probeability check

Before accepting an LO, the skill must be able to name **at least one
question type from `instructions-export.md`** that could test it cleanly.
The conductor picks the actual type at runtime based on policy, history,
and variety; this check is just a sanity floor that the LO is testable
*at all*.

| `kind`  | natural question types                              |
|---------|-----------------------------------------------------|
| recall  | mcQuestion                                          |
| apply   | writeCode, completeCode                             |
| predict | mcQuestion, explainCode, socraticQuestion           |
| reason  | socraticQuestion, explainCode                       |

`hint` and `socraticFeedback` are response types, not probes — they
operate on a previously asked question and don't appear here.

If no type fits, the LO is wrong-shaped — usually an "understand" in
disguise, sometimes a topic. Rewrite or split.

## Prerequisite leakage check

An LO leaks when it secretly requires knowledge from a later subgoal or
goal. Example: in a subgoal *"Predict and write basic if/else,"* the LO
*"You can predict the branch given a boolean variable as the condition"*
leaks if "boolean variables" is introduced in a later subgoal — the
student doesn't have the concept yet.

The check applies at two levels:

- **Within-goal:** an LO in subgoal N may only depend on concepts
  introduced in subgoals 1..N of this goal, **plus** anything in earlier
  goals.
- **Cross-goal:** the goal as a whole may only depend on earlier goals
  in the module (per the curriculum's order-is-prerequisite rule).

When leakage is found, the rubric does not silently rewrite. It flags:
*"LO X depends on Y, which doesn't exist yet. Either author Y first, or
assert it's covered out-of-band."* Hard refusal would get in the way the
first time you legitimately want to leave a gap (e.g. a math concept the
student already has from class); the soft flag preserves teacher
authority while making the gap visible.

## Cross-subgoal duplication: surface, don't dedupe

`CURRICULUM_MODEL.md` is explicit: if two subgoals genuinely share an LO,
**duplicate it**. The dedup machinery would cost more than the duplication.
The rubric respects this — it does **not** try to merge LOs across
subgoals.

But duplication is sometimes accidental, so the skill surfaces it as
informational:

> "LO `predict_branch` in this subgoal is similar to `predict_branch_runs`
> in subgoal 'Conditional statements basics'. Duplicate intentionally, or
> rephrase one?"

This is a flag, not a block. Confirm and move on.

## Weights and `optional`

Default `weight: 1.0`, `optional: false`. The skill should not ask about
these per LO — that's tedious. After the LO list is drafted, ask one
question per subgoal: *"Are any of these LOs the high-stakes core ones,
or any merely nice-to-have?"* and bump weights / set `optional: true` only
on flagged exceptions. For a first-exposure curriculum, expect almost all
LOs to be `weight: 1.0, optional: false`.

## `allowChains` (subgoal-level, not LO-level)

Default `false`. Set `true` when the subgoal contains at least one
`reason` LO **and** the misconceptions are subtle enough that "ask, get
partial answer, ask one follow-up" is genuinely valuable.

For first-exposure procedural subgoals (variables, basic if/else, basic
loops): leave `false`. For conceptual subgoals (truthiness, scope,
mutability, when-to-use-which-loop): consider `true`.

The skill asks explicitly when there's a `reason` LO present; defaults to
`false` without asking otherwise.

## `teachingTips` — the pedagogical voice

Per `CURRICULUM_MODEL.md`, `teachingTips` is unstructured prose hints to
the LLM at runtime. It is where the **misconceptions** live. Without
good teachingTips, the runtime tutor will ask bland surface-level
questions and miss the things that actually trip first-exposure students
up.

The skill elicits teachingTips with focused prompts, not a generic "any
tips?":

- "What are the 1-3 misconceptions a 16-year-old first-exposure student
  typically has on this subgoal?"
- "Is there an analogy or framing that helps?"
- "Anything to *avoid* — e.g. don't lean on math notation, don't use
  English keywords as variable names in examples?"

Aim for **2-4 teachingTips per subgoal**. Each tip should be one
sentence, concrete, actionable for the LLM. Subgoals with zero
teachingTips are flagged; one is acceptable but borderline.

## Self-critique pass

After eliciting all LOs across all subgoals — and before emitting JSON —
the skill runs the checklist below and produces a structured report. Each
flagged item names the LO or subgoal, identifies the issue, and proposes
a fix. The teacher reviews, confirms or amends, and the skill emits.

The report has one entry per concern, in this shape:

```
subgoal: <id> | lo: <id (if applicable)>
  issue: <one-sentence description>
  proposed fix: <concrete rewrite or action>
```

The skill never refuses to emit. It surfaces every concern, asks for
explicit confirmation when concerns exist, and writes the JSON once the
teacher has acknowledged or fixed them. Teacher authority is final;
the rubric advises, the teacher decides.

### Checklist

| # | Check                                                         |
|---|---------------------------------------------------------------|
| 1 | LO statement fails the observability test                     |
| 2 | LO statement reads like a topic (failure mode 1)              |
| 3 | LO statement is two LOs glued together (failure mode 2)       |
| 4 | No question type fits the LO's `kind` / shape                 |
| 5 | Subgoal has < 3 LOs                                           |
| 6 | Subgoal has > 6 LOs                                           |
| 7 | Subgoal has > 8 LOs (extra-loud warn — conductor evidence thins) |
| 8 | Subgoal has all-same-`kind` LOs                               |
| 9 | Procedural subgoal has zero `predict` LOs                     |
|10 | Subgoal involving code-writing has zero `apply` LOs           |
|11 | LO leaks prerequisites from a later subgoal/goal              |
|12 | Subgoal has zero `teachingTips`                               |
|13 | LO statement is similar to one in another subgoal             |
|14 | Subgoal has only one `teachingTips` entry                     |
|15 | Three or more `reason` LOs in one subgoal                     |

Items 1–4 are hard authoring mistakes; the skill flags them prominently
and proposes rewrites, but if the teacher confirms the LO as-is, the
skill emits. Items 5–11 are pedagogical concerns. Items 12–15 are
informational.

## Worked examples

### Good: subgoal *"Predict and write basic if/else"*

```json
{
  "objectives": [
    {
      "id": "predict_branch_from_comparison",
      "statement": "You can predict which branch runs given a numeric comparison like x > 0.",
      "kind": "predict",
      "weight": 1.0,
      "optional": false
    },
    {
      "id": "predict_branch_from_boolean",
      "statement": "You can predict which branch runs given a boolean variable as the condition.",
      "kind": "predict",
      "weight": 1.0,
      "optional": false
    },
    {
      "id": "write_if_only",
      "statement": "You can write an if statement that runs a single block when a condition holds.",
      "kind": "apply",
      "weight": 1.0,
      "optional": false
    },
    {
      "id": "write_if_else",
      "statement": "You can write an if/else that picks between two blocks based on a condition.",
      "kind": "apply",
      "weight": 1.0,
      "optional": false
    },
    {
      "id": "explain_indent_role",
      "statement": "You can explain why indentation determines what's inside the if block.",
      "kind": "reason",
      "weight": 1.0,
      "optional": false
    }
  ],
  "teachingTips": [
    "Novices often think the condition needs to print or assign — probe whether they treat it as a question.",
    "Watch for confusion between = and ==; lean on this if a student writes if x = 5.",
    "Prefer concrete numeric comparisons over abstract bool variables for first probes."
  ],
  "allowChains": true
}
```

Five LOs. Mix of predict (2), apply (2), reason (1). No `recall` because
nothing memorizable here isn't already covered upstream. `allowChains:
true` because of the `reason` LO and the conceptual subtlety around
indentation. Three teachingTips, each pointing at a real misconception.

### Bad: same subgoal, common authoring mistakes

```json
{
  "objectives": [
    {
      "id": "understand_if_else",
      "statement": "You can understand how if/else works.",
      "kind": "reason",
      "weight": 1.0,
      "optional": false
    },
    {
      "id": "use_conditionals",
      "statement": "You can use conditional statements.",
      "kind": "apply",
      "weight": 1.0,
      "optional": false
    },
    {
      "id": "predict_and_write_if",
      "statement": "You can predict the branch and write the matching if/else.",
      "kind": "apply",
      "weight": 1.0,
      "optional": false
    }
  ],
  "teachingTips": [],
  "allowChains": false
}
```

What's wrong, against the checklist:

- `understand_if_else` (1, block): fails observability — "understand" is
  internal state. The 30-second-video test fails.
- `use_conditionals` (2, block): topic, not an LO. *"Use conditional
  statements"* is the subgoal title; nothing here describes a single
  observable action.
- `predict_and_write_if` (3, block): two LOs glued together. Predict and
  write are separate failure modes — splitting them is what lets the
  conductor distinguish a tracing problem from a writing problem.
- (5, warn): only 3 LOs, and after fixing the blocks one of them
  disappears entirely — the subgoal is under-specified.
- (11, warn): zero teachingTips. The runtime tutor has nothing to lean
  on for misconceptions.
- `allowChains: false` is wrong here given the conceptual content, but
  this is a judgement call surfaced separately by the `allowChains`
  prompt rather than the checklist.

The fix is the good version above.

## Out of scope for this rubric

- **How the conductor picks question types and difficulty at runtime.**
  That's policy, in `CONDUCTOR_POLICY.md`.
- **How belief evolves on each LO.** That's `STUDENT_MODEL.md`.
- **What the LLM emits per answer.** That's `LLM_CONTRACT.md`.
- **Module-level structure and goal ordering.** That's the goal-tree
  authoring flow, separate from per-subgoal LO authoring.
