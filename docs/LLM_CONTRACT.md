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

Two distinct calls: question generation and answer grading. A third,
lighter one — a question about the theory page on screen — sends no LOs
and grades nothing (see "Content question").

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
- `recentQuestions` (`recent_questions` in the request, #184) — the last
  12 questions asked this session, oldest first, one line each:
  `type | loId | core`, where `core` is the question's prompt with its
  code on one line, cut at 160 characters (`RecentQuestions`). Omitted
  before the first question. Generation carries no conversation history
  (see "Conversation history"), so this block is what the model knows
  about what it asked before; the teacher-authored question instructions
  point at it for "do not repeat yourself". Kept by the app, dropped on
  sign-out.

Outputs: same envelope as today, the META payload matches the existing
per-question-type schema (MCQ options, code snippet, prompt text, etc.).
No structural change on this side — only the inputs gain `targetLOs`
and the question-type prompt is told to focus on those LOs.

A multiple-choice META's `correct` (the positional letter, `"A"` = the
first option) is read since #185: `MultipleChoice.correct` resolves it to
the option's *text* — the options are shuffled before the student sees
them — and the question bank stores it as the answer key. It is not sent
back: the grader's exercise history carries the question without it, as
before. A letter past the last option, or a value that is neither a letter
nor an option's text, is no key.

The conductor may request a question that probes a single LO or
multiple LOs. The LLM should weight the question to those LOs but is
not forbidden from incidentally probing others.

### Answer grading

The student has answered. The LLM judges what the answer reveals.

Inputs:

- `goal`, `subgoal`, `teachingTips` — same as generation.
- `targetLOs` — the LOs the question was meant to probe (the same list
  passed to generation; carried through so the grader knows the
  intent). Each entry also carries `subgoalId`: the subgoal the target
  LO belongs to — the current subgoal on an ordinary probe, an *older*
  subgoal of the root on a warm-up review question (conductor policy
  1.5, #102). Signals on the target go under that id.
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

**Warm-up review questions (conductor policy 1.5, #102).** Once per
session the conductor may ask one review question on an LO of an
*older* subgoal of the current root. For both generation and grading of
that question, `subgoal` and `teachingTips` describe *that* older
subgoal, not the one the student is working on, and `targetLOs` name its
LO with its `subgoalId`. Nothing else in the contract changes: the
grader emits the same shape, `goalScopeLOs` is the same root-wide list,
and the scope check (below) accepts the signal because the older subgoal
is in scope.

### Conversation history (#184)

Every call carries the system prompt and its input; what sits between
them is set per request type (`PreviousInputs`):

- **Question generation** — none (`newSession`). The call opens a new
  exercise; earlier questions reach the model through `recentQuestions`.
- **Grading, hints, follow-ups, student and content questions** — the
  current exercise's own exchange (`exercise`): the question as the
  generator returned it (its META as JSON), then every turn since — a
  hint asked for, the answer, the grade. Nothing of earlier exercises:
  what the grader needs about older subgoals is in `goalScopeLOs`.
- **Status report** — everything recorded (`includeAll`, capped at 50
  messages).

A question put in front of the student without a generation call has to
open the exercise itself, with that question as its first entry.

### Content question (#132)

The student is reading a theory page (`SessionMode.explain`, a `content`
doc in the WebView) and types a question in the chat. The question is
about the page they are looking at — which, after paging back (#115), is
not always the active subgoal's — so the page goes along with it.

Inputs (`request_type: content_question`, built by
`QuestionFormatter.contentQuestion`):

- `question` — what the student typed.
- `content_title` — the page's `Content.title`.
- `content` — the page's `Content.body` as plain text
  (`lessonHtmlToText`): headings and list items on their own lines,
  `<pre>` blocks as fenced code, tags gone, entities decoded, capped at
  12 000 characters.
- The system prompt is the `contentQuestion` instruction doc when the
  teacher has authored one, else the built-in default
  (`defaultContentQuestionInstruction`), plus `alwaysInclude`; `{goal}`,
  `{subgoal}` and `{teachingTips}` describe the subgoal whose page is on
  screen, as they describe the older subgoal of a warm-up review.

Output: the plain `answer` envelope — TEXT is the answer, META is
`{"type": "answer"}`. No `overallQuality`, no `loSignals`, no
`followUp`: a content question is not evidence, so nothing on the
conductor side moves — no `turn_history` record, no belief or XP change,
and the exercise in flight (if any) is still pending afterwards. The
debug turn is recorded like every other request, so Recent turns and a
bug report show what was sent.

Out of scope: questions about a *practice* question's code (still
`student_question` with `code`) and multi-page context — only the page on
screen is sent.

### Output language (#117)

Both calls end with a fixed output-language directive, appended by
`InstructionGenerator` after the teacher-authored instruction bodies
(`languageDirective` in `lib/services/tutor/instruction_generator.dart`).
It names the language the student picked in Options — `appLocaleProvider`,
resolved per turn — and it is deliberately the *last* thing in the system
prompt, because the teacher-authored bodies it has to override are
themselves written in Dutch.

It is scoped to student-facing prose: the TEXT section and every
student-facing string in META (`feedbackText`, question text, MCQ
options, follow-up questions, status reports). It explicitly exempts the
machine half of this contract — META's JSON keys and enum values, LO ids,
and the code and identifiers in any snippet — which are language-neutral
by construction and would break parsing and belief updates if translated.

Out of scope: the teacher-authored instruction documents themselves and
the lesson/theory HTML. Those stay in the language their author wrote
them in.

#### Client-side script guard (#147)

The directive is a request, and a small model can ignore it by accident:
#147 is a Dutch reply with one word replaced by a run of non-Latin
lookalikes, out of a nano-class model. Since the model's output is not
something the app can correct, the app refuses it instead — the same
treatment a reply truncated in transit gets (#7). `offScriptRunInReply`
(`lib/services/tutor/responses/script_guard.dart`) reads the TEXT
section of every completion, streamed and not; a run of adjacent
characters from a non-Latin script in an otherwise Latin reply comes
back as `ChatNoticeKind.replyGarbled`, the half-streamed message is
withdrawn, and `TutorService`'s one automatic re-send asks again.

Deliberately narrow, and the rule lives in that file's header: code
spans and fenced blocks are exempt (a Python string may hold any
script), a single off-script character is not a run, and a reply
genuinely written in another script is not touched — nothing a re-send
would fix. META's own student-facing strings are not scanned, because
META also carries code.

## What the grader returns

```json
{
  "overallQuality": "wrong" | "partial" | "correct",
  "feedbackText": "student-facing message, in the student's language",
  "loSignals": [
    {
      "subgoalId": "use_if_else",
      "loId": "predict_branch",
      "signal": "positive" | "negative" | "neutral",
      "strength": "strong" | "moderate" | "weak"
    }
  ],
  "transferLOs": [
    { "subgoalId": "use_print", "loId": "print_text" }
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

`transferLOs` is optional (#101); absent or empty means "nothing to
report". It lists the goal-scope LOs from *other* subgoals of the root
that the answer **correctly used in service of the task** — the
constructs the solution genuinely needed and got right, not everything
that happens to appear in it. Meaningful for answers that contain code;
prose answers rarely have anything to list.

### Field semantics

**`overallQuality`** — coarse single-question verdict. Functions as a
self-consistency check on `loSignals`: if every signal is negative,
`overallQuality` shouldn't be `correct`. The LLM sees both as a
constraint when generating. Whether/how the UI surfaces this value is a
downstream decision, not part of the contract.

**`feedbackText`** — one message for the student, in the language they
picked in Options (#117; see "Output language" below). Same role as
the existing `prompt`/`feedback` text. Granular per-LO feedback is for
the conductor's eyes only; the student gets one readable message.

**`followUp`** — optional. When present, contains a `question` (the
text the conductor will show the student verbatim, in the student's
language) and a
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

**`transferLOs`** — the transfer-credit nominations (conductor policy
section 3.7). Each entry is a `(subgoalId, loId)` that must identify a
real LO in `goalScopeLOs`, in a subgoal other than the current one. The
grader reports what the solution demonstrates; it is *not* told which
LOs the student has mastered and must not guess — the conductor keeps
only nominations on LOs the student once mastered by direct probing,
and only from a `correct` answer. A nomination is not a signal: it
carries no strength, is never negative, and does not replace the
`loSignals` entry an LO would get if the answer *revealed a gap* in it
(that stays a negative signal on the LO, as today).

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
schema, scope, and validation rules as primary grading — except that
`transferLOs` on a follow-up answer are ignored (conductor policy 3.7:
dialogue is not a solution).

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
5. **Transfer nominations.** Each `transferLOs` entry gets the same LO
   id resolution and scope check; duplicates collapse to one. Surviving
   entries never count as "a signal" for the fallback rule below, and
   the conductor applies its own gates (conductor policy 3.7) before any
   of them touches a belief.

If the response fails to parse or every signal is dropped, the
conductor falls back to a single weak signal on the question's
**intended LO** (or the first `targetLO` if there were several), filed
under the target's own subgoal (the older one on a warm-up review), sign
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
  (part 2), not per-question signals. A signal on an earlier subgoal's
  LO is handled by the conductor per its sign (conductor policy 2.4): a
  positive is ordinary evidence on that LO, treated as `medium`
  difficulty and without any ratchet (#108); a negative is not applied
  to the belief but flags the LO for a direct re-probe at the next
  session start (#167) — it is how a prerequisite gap suspected from
  later work gets checked rather than assumed.
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
- **`transferLOs` is a nomination, not evidence** (#101). The grader
  lists what a solution correctly used from earlier subgoals; the
  conductor turns that into a small positive only for LOs the student
  once mastered, and only on a `correct` answer. Keeps the "which LOs
  count" judgment in code, not in the prompt.

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
  `feedbackText` is one message; signal granularity is for the
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
