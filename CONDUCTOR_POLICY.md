## 1. Subgoal entry

**1a. Cold start** — student opens a fresh subgoal (no LO beliefs yet). What's the first question? Which LO does it probe, what type, what difficulty? This is where the calibrated `medium` starting difficulty meets the curriculum's first LO.

**1b. Resume** — student returns to a subgoal with existing beliefs. Decay applies on read. After decay, are any LOs still "mastered"? Are any genuinely weak? Does the conductor probe the weakest first, or warm up gently?

**1c. Returning to a fully-mastered subgoal** — covered in part 2's migration notes for old data, but also a live case once the new system runs (teacher reopens a subgoal, or the curriculum changes and adds an LO to a previously-mastered subgoal). What does the conductor do?

## 2. Per-question decisions

**2a. Which LO to probe next.** Coverage logic. Weakest belief? Lowest evidence count? Random among unmastered? Weighted by LO `weight`?

**2b. Which question type to use.** The "type as a tool" idea you flagged earlier. Which LO `kind` maps to which question types as good defaults? When does the policy override the default (e.g. variety, recovery from a wrong answer, etc.)?

**2c. What difficulty.** Mostly read from student calibration, but: should the conductor *ever* override? E.g. probe at one notch easier when belief is weak negative, to avoid burying the student?

**2d. Multi-LO questions.** Should the conductor sometimes ask a question that probes multiple LOs at once (cheaper coverage)? Or always single-LO for cleanest evidence?

## 3. Belief update mechanics

**3a. Evidence weight table.** The mapping from `(signal, strength)` to `(α += w_pos, β += w_neg)`. Concrete numbers.

**3b. Difficulty adjustment to evidence weight.** Should a `correct` answer at `easy` count less than at `medium`? Almost certainly yes — but how much less? And what about a `wrong` answer at `hard`?

**3c. Decay curve.** Half-life decision. The student model commits to "months not weeks" but the actual function needs picking.

**3d. Evidence cap behavior.** When `α + β` hits the cap, how do we shrink? (Proportional toward prior — already in part 2, but worth nailing the exact rule.)

## 4. Subgoal completion

**4a. Mastery check.** Mean threshold + minimum evidence per LO, weighted by LO `weight` for the aggregate. Concrete numbers.

**4b. Optional LOs.** The schema has a `weight` field. Does `weight = 0` mean "skip"? Or is there a separate `optional: bool`? (I don't think we have that on LOs; need to decide.)

**4c. Partial mastery / advancing anyway.** Edge case: student has 4 LOs mastered and 1 genuinely stuck. Does the policy ever advance with a known gap? (Probably yes after enough attempts; this is the "don't trap the student forever" rule.)

**4d. The E.1 problem (mastery on easy only).** The "good student" who never sees medium because they grind out easy correct answers. Does the policy refuse to declare mastery if no medium-or-harder evidence exists? This is where E.1 actually gets fixed.

## 5. Difficulty calibration update

**5a. Promotion rule.** When does `easy → medium` or `medium → hard` happen? How many recent answers at what quality?

**5b. Demotion rule.** Same in reverse. Should be more reactive than promotion (drop fast, climb slow).

**5c. Hint usage as input.** Today, hints block promotion. Keep that? Drop it? Modify it?

## 6. Follow-up / chaining

**6a. When does a wrong answer trigger a follow-up vs. moving on?** The current `_allowFollowUp` rule says "no follow-up after wrong, no follow-up after mastery streak." What's the new rule given per-LO belief?

**6b. Repurposing `guidingQuestion`.** Phase D drops it as the subgoal opener. Does the policy ever use it for recovery (student got two wrongs in a row on the same LO)? This is where your TODO note about "use them when there are signs that a student struggles" comes in.

**6c. The "ik snap dit al" skip path.** Future follow-up in TODO. Does the policy spec address it, or do we leave it for later?

## 7. Edge cases

**7a. Empty `objectives` list.** A subgoal with no LOs (existing data, or teacher mid-authoring). Fallback to current quality-only behavior? Skip the subgoal? Block the student?

**7b. LLM contract failure.** Part 3 specifies a fallback (weak signal on intended LO). The policy needs to handle the case where this happens repeatedly — at what point does the conductor stop trying?

**7c. Teacher edits LOs mid-flight.** Student has belief on LOs that the teacher just renamed/deleted. (Already settled in part 2: orphaned beliefs sit unused. But the policy needs to not crash on missing LOs.)

**7d. Student abandons mid-question.** Persisted state assumptions. Probably already handled but worth confirming.

## 8. Observability

**8a. What does the policy log/expose for the teacher dashboard?** Current `recentConceptAttributions` goes away; what replaces it? Per-LO belief is much richer data — what does the teacher see?

**8b. Debug surfacing.** `recordDebugEvent` calls in the current conductor. New events list?

---

## Where I'm least confident this list is complete

Three areas where I expect we'll find missing chunks once we start:

- **The interaction between difficulty calibration and belief updates.** I've separated them into 3a/3b and 5a/5b, but they couple in subtle ways. There may be a "consistency" decision I'm not seeing yet — e.g. what does it mean for a student to be calibrated at `hard` but have weak beliefs across the subgoal's LOs? Genuinely don't know if that's a thing the policy needs to handle or if it just falls out.
- **Question-type-to-LO-kind mapping.** I've got it as 2b but I suspect this is its own chunk that'll spawn sub-questions about which combos are even sensible. (`recall` LO probed by `writeCode`? Probably wrong, but is it forbidden?)
- **The "rare cases" cluster around fully-mastered subgoals on resume.** 1b and 1c overlap and I haven't fully thought through the matrix.

---

## My suggestion

Take this list as the working outline. Start with **chunk 1a (cold start)** — it's the most concrete, forces us to commit to the easy-to-think-about case, and will surface dependencies on later chunks (you can't pick a first question without committing to "which LO" and "which type" — 2a and 2b). When those dependencies surface, we'll know whether they're full chunks or just sub-decisions.

I'd commit to the list but treat it as living. If we get to chunk 6 and realize we missed something, we add it.

Want to start on 1a?