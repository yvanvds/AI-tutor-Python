

# Step 1: Persist difficulty and recent-answer history on Progress

## Goal

Currently the `Conductor` keeps difficulty calibration and a 5-answer rolling window in memory only, so they reset on every app launch. This task persists them on the existing `progress` Cosmos container so they survive restarts. No behavioural change yet — this is pure persistence groundwork for an upcoming warm-up/recheck feature.

## Constraints

- **No new Cosmos containers.** Add fields to the existing `progress` container only.
- **No conductor logic changes** beyond reading from / writing to the new fields. The 5-answer window mechanics, difficulty step-up/step-down rules, and progress delta math stay exactly as they are.
- **Backwards-compatible reads.** Existing `progress` docs in production lack these fields. `Progress.fromJson` must default sensibly.
- Reuse `safeCosmos`, `pollingStream`, and the existing `ProgressService.upsert` write path. Don't add a new write method.

## Files to touch

- `lib/services/progress/progress.dart` — extend the model
- `lib/services/progress/progress_service.dart` — load/save the new fields via existing upsert
- `lib/services/tutor/conductor.dart` — replace in-memory difficulty + rolling window with reads from the loaded `Progress` doc; write back through the existing upsert call
- `test/services/progress/progress_test.dart` (or equivalent) — add JSON round-trip tests including legacy docs without the new fields
- `test/services/tutor/conductor_test.dart` — adjust existing tests if they assert on in-memory state; add a test confirming difficulty + window survive a "reload" (re-instantiate conductor with the persisted progress)

## Files to NOT touch

- `lib/core/cosmos_client.dart`, `lib/core/cosmos_paths.dart`, `lib/core/cosmos_doc_id.dart` — schema lives entirely in the model
- Any `features/` UI code — this task has zero UI surface
- `TutorService`, response handlers, instruction generator — unaffected
- `AccountService`, `GoalsService` — unrelated

## Schema additions to `Progress`

Add three optional fields:

- `difficulty: QuestionDifficulty` — last calibrated difficulty for this (uid, goalId). Default `QuestionDifficulty.easy` when missing.
- `recentAnswers: List<AnswerQuality>` — rolling window, capped at 5 entries, oldest-first. Default `const []` when missing.
- `lastSessionAt: DateTime?` — ISO 8601 string in Cosmos, parsed to `DateTime`. Default `null` when missing. Update this on every `upsert` call (set to `DateTime.now().toUtc()`).

Use the existing `QuestionDifficulty` enum from `lib/core/question_difficulty.dart` and `AnswerQuality` from `lib/core/answer_quality.dart`. Serialise enums as their `.name` string. Trim `recentAnswers` to the last 5 on write.

## Conductor wiring

Currently the conductor holds something like `_currentDifficulty` and `_recentAnswers` as instance fields. Replace these reads with reads off the loaded `Progress` for the active subgoal. On every progress update:

1. Append the new `AnswerQuality` to `recentAnswers`, trim to 5.
2. Recompute difficulty with the existing rule.
3. Pass the updated `difficulty`, `recentAnswers`, and `lastSessionAt = now` into `ProgressService.upsert` alongside the existing `progress` value.

If the conductor is currently re-initialised on goal switch, make sure it reads the persisted state for the *new* goal rather than carrying over the previous goal's window.

## Definition of done

- `flutter analyze` clean.
- `flutter test` passes, including new round-trip tests with and without the legacy fields.
- Manual test: run the app, answer 3 questions on a subgoal, force-quit, relaunch, sign in. Inspect the `progress` doc in the Cosmos data explorer — the three new fields are present and populated. The conductor resumes at the same difficulty and the rolling window is intact (verifiable by adding a temporary `print` in the conductor or by stepping in the debugger).
- No changes to the user-visible chat behaviour.


# Step 2:  Adaptive warm-up flow on session resume

## Goal

When a student starts a new session on a subgoal they've already made progress on, run a short warm-up of 0–3 questions before resuming normal exercise selection. The number of warm-up questions adapts to how well the student was doing last session: students who were acing it get a token check or skip entirely; struggling students get a longer warm-up. During warm-up, correct answers do **not** advance progress (they already earned it), but wrong/partial answers **do** decrement progress and feed the existing difficulty adaptation. After the warm-up quota completes, normal selection resumes.

This builds directly on step 1 — `recentAnswers`, `difficulty`, and `lastSessionAt` are already persisted on `Progress`.

## Constraints

- **No new containers, no new fields on `Progress`.** Warm-up state is conductor-side and ephemeral.
- **No new `ChatRequestType`.** Warm-up questions reuse the existing exercise types (`socraticQuestion`, `mcQuestion`, `completeCodeQuestion`, etc.) — warm-up-ness is invisible to the prompt layer.
- **No new response types.** Feedback handlers do not need to know whether a question was a warm-up; the conductor decides what to do with the result.
- Reuse the existing `Conductor.updateProgress` and exercise-selection paths. Don't fork them.
- Student-facing framing is one short Dutch system message before the first warm-up question, e.g. *"Welkom terug! Even kort herhalen voor we verder gaan."* Add it via the existing system-message path used elsewhere in the chat (look at how goal-completion or other conductor-driven system messages are emitted today and follow that pattern).

## Files to touch

- `lib/services/tutor/conductor.dart` — warm-up state machine and decision logic
- `lib/services/tutor/tutor_service.dart` — only if `initializeSession` needs a hook to trigger the warm-up evaluation. Keep changes minimal; the conductor should own the logic.
- `test/services/tutor/conductor_test.dart` — new tests for the warm-up sizing, the no-progress-on-correct rule, the still-decrements-on-wrong rule, and the transition back to normal flow.

## Files to NOT touch

- `lib/services/progress/*` — schema is unchanged
- Response handlers, instruction generator, question formatter — warm-up is invisible to them
- Any `features/` UI — no UI surface
- `lib/core/chat_request_type.dart` — no new request types

## Logic specification

### Session boundary

A "new session" for a subgoal means: `lastSessionAt == null` OR `now - lastSessionAt > 12 hours`. Use UTC.

### Warm-up sizing

On session resume for a subgoal where `progress >= 0.5`, compute warm-up count from `recentAnswers` (the persisted rolling window):

- If `recentAnswers.length < 2` → 1 question (not enough signal to skip).
- Compute `successRatio = correctCount / recentAnswers.length`, where `correct` counts as 1.0 and `partial` counts as 0.5.
  - `successRatio >= 0.8` → 1 question.
  - `0.5 <= successRatio < 0.8` → 2 questions.
  - `successRatio < 0.5` → 3 questions.
- If `now - lastSessionAt > 14 days`, add +1 to the count (cap at 3).

If `progress < 0.5` → no warm-up. The student is still in early learning on this subgoal; the existing flow already starts at appropriate difficulty.

### Warm-up question selection

Reuse the conductor's existing question-type selection at the **persisted difficulty** for this subgoal. Don't force a specific type — variety still matters. The only override: warm-up questions run at `progress`-implied type bands as they currently do, but using the persisted `difficulty` as the calibration anchor.

### Warm-up answer handling

In `Conductor.updateProgress`, when the current question was a warm-up:

- `correct` → do **not** apply the positive progress delta. Still append to `recentAnswers` and let difficulty adaptation see it.
- `partial` or `wrong` → apply the normal negative delta as today. Append to `recentAnswers`. Difficulty adaptation runs normally.
- Always still call `ProgressService.upsert` so `lastSessionAt`, `recentAnswers`, and `difficulty` persist.
- Expose the threshold as a `const Duration` at the top of `conductor.dart` so I can easily bump it down to 1 minute during manual testing, then restore.

### Transition out of warm-up

After the configured number of warm-up questions completes, the conductor returns to normal mode for the rest of the session. If during warm-up the student answered everything wrong, the existing difficulty step-down already kicks in — no special-case needed.

If the student's `progress` decrements past a goal-completion boundary (i.e. they had 1.0 and now have less), no special handling — the existing logic already handles the active-subgoal state.

### Subgoal switching mid-session

If the student switches subgoals (or the conductor advances them) during a session, the new subgoal's warm-up is evaluated independently using its own `lastSessionAt`. Practically: a freshly-completed subgoal that just advanced the student to a new one should *not* trigger warm-up on the new subgoal — its `lastSessionAt` was just set milliseconds ago (or it has no progress yet).

### System message

Before the first warm-up question of a session, emit one short Dutch system message via the existing system-message path. Don't repeat it on every warm-up question. Keep it brief and natural; do not say "warm-up" or "recheck" literally. Examples (vary across rebuilds — don't hardcode a single string, pick from a small list of 2–3 phrasings):

- *"Welkom terug! Laten we even kijken of dit nog vlot zit."*
- *"Hé, daar ben je weer. Eerst even kort opfrissen."*
- *"Even een korte herhaling om in te komen."*

## Definition of done

- `flutter analyze` clean.
- `flutter test` passes. New tests cover:
  - Warm-up count = 0 when `progress < 0.5`.
  - Warm-up count of 1 / 2 / 3 across the three success-ratio bands with synthetic `recentAnswers`.
  - Stale-session bonus (+1) when `lastSessionAt` is >14 days ago.
  - No progress increment on correct warm-up answer; normal decrement on wrong warm-up answer.
  - `recentAnswers` and `difficulty` updated normally during warm-up.
  - Transition back to normal mode after the quota.
  - Fresh sub-goal advancement does not trigger warm-up on the just-entered subgoal.
- Manual test: run the app, answer a few questions on a subgoal until you have a populated `recentAnswers`, force-quit, wait long enough that `lastSessionAt` is >12h old (or temporarily lower the threshold for testing), relaunch and sign in. Verify a system message appears, the appropriate number of warm-up questions are asked, and progress doesn't increment on correct ones. Check the Cosmos `progress` doc shows the expected updates.
- No regression in the normal (non-warm-up) flow.



# Step 3: Collect AI concept attributions on feedback responses

## Goal

When the AI evaluates a student's answer (code feedback, MCQ feedback, socratic feedback, explain feedback), let it optionally tag *which prior concept* it suspects caused the mistake. For example: a student gets a loops exercise wrong because they actually misused a variable — the AI flags `"variables"` as the suspected concept. We collect these attributions on the `progress` doc but do **not** act on them yet. This is pure data collection so we can sanity-check the AI's tagging quality on real students before wiring any behaviour to it.

This builds on steps 1 and 2 — `Progress` already persists `difficulty`, `recentAnswers`, `lastSessionAt`.

## Constraints

- **No new containers.** Attributions are stored as a bounded recent list on the existing `progress` doc.
- **No conductor behaviour change.** The conductor reads/writes attributions but does not divert, recheck, or alter selection based on them. That comes in a later step.
- **No changes to exercise generation.** Only the four *feedback* response types gain a new optional field. Exercise prompts (`socraticQuestion`, `mcQuestion`, etc.) are unchanged.
- The AI must constrain its tags to concepts from the goal tree's `knownConcepts` — but enforce this via the *instruction text*, not via response schema. Drift is acceptable for now; we want to see how bad it is.
- Reuse the existing `ChatResponse` / `ResponseHandler` dispatch pattern. Don't fork it.

## Files to touch

### Response models
- `lib/services/tutor/responses/code_feedback.dart`
- `lib/services/tutor/responses/mcq_feedback.dart`
- `lib/services/tutor/responses/socratic_feedback.dart`
- `lib/services/tutor/responses/explain_feedback.dart`

Add an optional `List<String>? suspectedConcepts` field. Parse from META key `suspected_concepts`. Treat missing/null/empty as "no attribution." Trim each tag, drop empties.

### Response handlers
- `lib/services/tutor/responses/response_handlers.dart`

In each of the four feedback handlers, after the existing `Conductor.updateProgress` call, pass the attribution list (if any) through to a new `Conductor.recordConceptAttributions(List<String>)` method. Handlers should not touch `ProgressService` directly — keep the conductor as the single owner of `Progress` mutations.

### Conductor
- `lib/services/tutor/conductor.dart`

Add `recordConceptAttributions(List<String> concepts)`:
- Validate each concept against the *known concepts in scope*: the union of (a) `knownConcepts` from the current root goal and (b) `knownConcepts` from all earlier root goals (same set the instruction generator already exposes via mastered concepts; reuse that helper rather than recomputing).
- Drop tags not in the validated set. Log a debug line for dropped tags so we can see drift in dev.
- Append accepted tags to a new `recentConceptAttributions` field on `Progress` (see schema below). Trim to last 20 entries (oldest-first).
- Persist via the existing `ProgressService.upsert` path. Don't add a new write method.

If `recordConceptAttributions` is called with an empty/null list, do nothing (no-op, no write).

### Progress model
- `lib/services/progress/progress.dart`

Add field:

- `recentConceptAttributions: List<ConceptAttribution>` — bounded list, last 20 entries, oldest-first. Default `const []` when missing from JSON.

Define `ConceptAttribution` as a small value type in the same file (or a sibling file under `lib/services/progress/`):

```dart
class ConceptAttribution {
  final String concept;
  final DateTime at;        // UTC
  final AnswerQuality quality; // from the same feedback turn
  // toJson / fromJson, equality
}
```

Storing `quality` alongside the tag matters: a `correct` answer that the AI still tagged `"variables"` is a very different signal from a `wrong` answer tagged `"variables"`. We want both.

### Progress service
- `lib/services/progress/progress_service.dart`

Extend the existing `upsert` to accept and persist `recentConceptAttributions` with the same backwards-compatible read pattern as the step-1 fields. No new method.

### Instruction docs
- The four feedback instruction docs in Cosmos (`codeFeedback`, `mcqFeedback`, `socraticFeedback`, `explainFeedback` — match the actual `ChatRequestType` names) need updates so the AI knows about the new field.

**Do not edit Cosmos data from code.** Instead, update `instructions-export.md` in the project files with the new section text, and add a short note to the PR description telling Yvan to import the updated Markdown via the teacher Instructions Editor (which already supports Markdown import). The export file should reflect the desired final state.

The new instruction additions should:
- Add `"suspected_concepts"` to the META section example as an optional array of strings.
- Add a rule: *"If the student's mistake appears to stem from a previously-learned concept rather than the current subgoal, list one or more concept tags in `suspected_concepts`. Use only tags from this list: {known concepts}. Omit the field entirely if the mistake is on the current subgoal itself or you're not confident."*
- Reuse the existing `{known concepts}` placeholder — `InstructionGenerator._replaceTags` already substitutes it.

### Tests
- `test/services/progress/progress_test.dart` — round-trip JSON for `ConceptAttribution` and the new list field; legacy doc without the field deserialises with empty list.
- `test/services/tutor/conductor_test.dart` — tests for `recordConceptAttributions`:
  - Accepts valid concepts from current + earlier root goals.
  - Drops concepts not in the validated set.
  - Trims to 20 entries (insert 25, expect last 20 oldest-first).
  - Empty/null input is a no-op (no upsert call).
  - Stores `quality` from the most recent feedback turn alongside the tag.
- `test/services/tutor/responses/response_handlers_test.dart` (or wherever feedback handlers are tested) — each of the four feedback handlers passes `suspectedConcepts` through to the conductor when present, omits the call when absent.

## Files to NOT touch

- `lib/services/tutor/instruction_generator.dart` — the `{known concepts}` placeholder already exists; we're only changing the *teacher-authored* instruction text, not the substitution code.
- `lib/services/tutor/openai_connector.dart` — no schema constraints, no API surface changes.
- Any `features/` UI — no UI surface in step 3. Teacher visibility comes in step 5.
- `lib/core/chat_request_type.dart`, `lib/core/answer_quality.dart`, `lib/core/question_difficulty.dart` — unchanged.
- Exercise response models (`socratic_question.dart`, `multiple_choice.dart`, etc.) — unchanged.

## Definition of done

- `flutter analyze` clean.
- `flutter test` passes including new tests.
- Manual test: answer a few feedback-eliciting questions across different goal types. Inspect the `progress` doc in Cosmos data explorer and confirm `recentConceptAttributions` populates with `{concept, at, quality}` entries. Confirm tags outside `knownConcepts` scope are dropped (visible in debug log).
- The updated `instructions-export.md` reflects the new META field and rule for all four feedback docs. PR description notes that Yvan must import the updated Markdown into the running app's Instructions Editor for the change to take effect in production.
- No behavioural change in chat flow: same exercises, same feedback, same progress dynamics.



# Step 4: Add progress_history container and write a sample on every progress change

## Goal

Currently `Progress` only stores the *current* value per (uid, goalId). To support graphs in the teacher detail panel (step 5), we need a time series. This task adds a new `progress_history` Cosmos container, writes one sample to it on every progress change, and exposes a watch/read API for later UI use. No UI surface in this step — it's groundwork for step 5.

This builds on steps 1–3. Step 5 will consume `progress_history` for graphs.

## New Cosmos container

**You will need to create this container in the Cosmos data explorer before deploying:**

- Database: `python-tutor`
- Container: `progress_history`
- Partition key: `/uid`
- Indexing: defaults are fine

The partition key matches `progress`, `accounts`, and `status_reports` — same per-user partitioning model.

## Schema

Each document is one snapshot:

- `id` — composite, see below
- `uid` — partition key, the student's Entra Object ID
- `goalID` — the subgoal id (same convention as `Progress.goalID`; root-goal progress is *not* sampled directly — see "What to sample" below)
- `progress` — the value at the moment of the sample, 0.0–1.0
- `difficulty` — the persisted difficulty at that moment (string, enum `.name`)
- `quality` — the `AnswerQuality` of the answer that triggered this sample (string, enum `.name`). Optional — not every progress change comes from a feedback turn (e.g. teacher resets, future admin tools), so allow null/missing.
- `isWarmUp` — bool. Distinguishes warm-up answers from normal ones, since warm-up correct answers don't change progress but you may still want to record the attempt. See "What to sample" for the decision.
- `at` — ISO 8601 UTC timestamp

`id` should be unique per sample. Choose a scheme that's monotonically sortable and collision-free for rapid writes — a timestamp-prefixed scheme works (e.g. ISO timestamp + short random/uuid suffix). Add a helper to `cosmos_doc_id.dart` rather than constructing ids ad-hoc in the service.

Add the container handle to `cosmos_paths.dart` alongside the existing per-user containers.

## What to sample

Sample on *every* progress change for a subgoal. Specifically:

- Every successful `ProgressService.upsert` that actually changes the `progress` value.
- Skip writes where `progress` is unchanged (idempotent upserts shouldn't generate history noise — but recheck `recentAnswers` / `difficulty` / `lastSessionAt` updates without a progress delta should not produce a history sample either).
- For warm-up correct answers: progress doesn't change, so by the rule above, no sample. That's fine — `recentAnswers` already captures the attempt and step 5's graphs are about progress trajectory, not attempt counts.
- For warm-up wrong/partial: progress *does* decrement, so a sample is written. Set `isWarmUp = true` so step 5 can style it differently if useful.

**Do not sample root-goal progress.** Root progress is a derived average of children and changes whenever any child changes — sampling it would double-write and complicate later aggregation. Step 5 can recompute root trajectories from child samples.

## Files to touch

- `lib/core/cosmos_paths.dart` — new container handle
- `lib/core/cosmos_doc_id.dart` — helper for the new id scheme
- `lib/services/progress/progress_service.dart` — write a history sample inside the existing `upsert` path when `progress` actually changes; expose read/watch methods (see API below)
- A new file under `lib/services/progress/` for the history sample model — name it as Claude Code sees fit (e.g. `progress_sample.dart`)
- `test/services/progress/progress_service_test.dart` — see test list below
- New test file for the sample model's JSON round-trip if Claude Code adds one

## Files to NOT touch

- `lib/services/progress/progress.dart` — `Progress` itself is unchanged
- `lib/services/tutor/conductor.dart` — the conductor already calls `upsert`; history writing is a `ProgressService` internal concern
- Response handlers, instruction generator, tutor service — unaffected
- Any `features/` UI — UI in step 5

## API to expose on `ProgressService`

The history is read-mostly and only by future UI. Expose:

- A one-shot read for a given `(uid, goalID)` returning samples ordered by time, with optional `since: DateTime?` and `limit: int?` parameters.
- A one-shot read for an entire student (`uid` only), returning samples across all goals — needed for the teacher detail panel's overview graph. Order by time. Same optional filters.
- A `watch` variant (or two) following the existing `safeCosmosStream(pollingStream(...))` pattern, mirroring whatever cadence is used elsewhere. The 5s poll is fine.

Don't expose a delete method. Don't expose batch insert. The only writer is the upsert path.

## Write-side error handling

The history write must not break the main progress write. If the history insert fails (network blip, throttled, anything), the user-visible progress update should still succeed. Wrap the history write so that:

- Progress upsert success + history write success → normal.
- Progress upsert success + history write failure → log the error, continue. Don't surface a `CrashRecoveryScreen`. Use `safeCosmos` semantics where appropriate but don't let an auth error on the history container nuke a working progress update — though in practice if one fails on auth, both will, and the existing recovery flow will catch the next call.

Don't add retry logic beyond what `cosmos_client.dart` already does internally.

## Growth and bounds

A student answers maybe 50–200 questions a week, across maybe 20 subgoals, so we're looking at low-thousands of docs per student per term. Cosmos handles this without fuss. **Do not** add pruning, TTL, or rollups in this step — premature. If it ever becomes an issue the natural fix is a TTL on the container or a periodic compaction job, both out of scope here.

## Tests

- Round-trip JSON for the sample model, including legacy/missing optional fields (e.g. `quality` absent).
- `ProgressService.upsert` writes a history sample when `progress` changes, with the expected fields populated from the upsert call.
- `upsert` does **not** write a history sample when `progress` is unchanged but other fields (`difficulty`, `recentAnswers`, `lastSessionAt`, attributions) change.
- History write failure does not propagate as an error from `upsert` (mock the client to throw on history container only, assert progress upsert still succeeded and the error was logged).
- Read methods return samples ordered by `at` ascending and respect `since` / `limit`.
- Warm-up wrong answer produces a history sample with `isWarmUp = true`; warm-up correct answer produces no sample (because progress is unchanged).
- The "warm-up wrong" case requires the conductor to pass warm-up state through to `upsert`. That's a small `upsert` signature extension — Claude Code can decide whether to add a parameter, a method overload, or carry it on a small request object. Update `conductor.dart` accordingly to pass the flag.

## Definition of done

- New `progress_history` container exists in Cosmos (manual step, document in PR description).
- `flutter analyze` clean.
- `flutter test` passes including new tests.
- Manual test: answer several questions on a subgoal, including at least one wrong answer during a warm-up. Inspect `progress_history` in the Cosmos data explorer — samples appear in time order with the expected fields, warm-up sample is marked, no samples for unchanged-progress upserts, no samples for root-goal id.
- No behavioural or UI change visible to the student.

# Step 5: Teacher progress visibility: inline indicators and detail drawer

## Goal

Give the teacher at-a-glance per-student progress on the existing accounts page, and a detailed peek panel showing per-subgoal progress, recent answer quality, hint usage proxy via attribution noise, status reports from the AI, and a progress-over-time graph per root goal. This is the first time `progress`, `progress_history`, and `status_reports` get surfaced to teachers.

This builds on steps 1–4. All required data is already persisted.

## Constraints

- **No new Cosmos containers.** Reads only.
- **No changes to student-facing flows.** The conductor, tutor service, response handlers, and student UI are untouched.
- Reuse existing patterns: `safeCosmos` / `safeCosmosStream` / `pollingStream`, `MultiValueListenableBuilder`, `get_it` lazy singletons via `DataService`, `ValueNotifier` reactivity.
- Add **one** new dependency: `fl_chart` (latest stable). No other new packages.
- Reuse the existing student progress widgets where they fit. Specifically `features/progress/goal_tile.dart` and `features/progress/student_progress_list.dart` should become parameterisable by `uid` rather than always reading the signed-in user's progress. If that's invasive, factor a shared inner widget rather than copy-pasting.
- All UI text in Dutch, matching the existing tone.

## Reads needed and how to get them

**For the inline accounts table columns:**
- All progress docs across all students. The teacher's session has master-key Cosmos access (per the existing security stance), so a cross-partition `SELECT * FROM c` on `progress` is fine. Add a `getAllProgress()` (and `watchAllProgress()`) method to `ProgressService`.
- Goals are already loaded via `GoalsService` and don't need rework.
- Account list is already fetched by the accounts page.

**For the detail drawer:**
- One student's progress across all goals — already covered by the cross-partition read filtered client-side, or add a `getProgressForUser(uid)` if a per-uid query is cleaner.
- One student's full `progress_history` — already exposed in step 4 (whole-student read).
- One student's status reports — add `getStatusReportsForUser(uid)` and `watchStatusReportsForUser(uid)` to `ReportService` mirroring the per-user pattern.

Polling cadence: the existing 5s tick is fine for the inline table. The drawer can reuse the same cadence; don't introduce a faster poll.

## Files to touch

### Services
- `lib/services/progress/progress_service.dart` — add `getAllProgress()` / `watchAllProgress()` and `getProgressForUser(uid)` / `watchProgressForUser(uid)` if not already covered. Reuse `safeCosmosStream(pollingStream(...))`.
- `lib/services/status_report/report_service.dart` (or whatever the file is named) — add `getStatusReportsForUser(uid)` / `watchStatusReportsForUser(uid)`.

### Existing student UI made reusable
- `lib/features/progress/student_progress_list.dart` and `lib/features/progress/goal_tile.dart` — accept an optional `uid` parameter (or factor a shared inner widget). When `uid` is null, behave as today (signed-in student). When provided, show that student's progress in read-only mode (no goal selection side-effects).

### Accounts page
- `lib/features/account/accounts_page.dart` — add new columns (see "Inline columns" below). Add row tap behaviour to open the detail drawer.

### New files for the detail drawer
- A new directory under `lib/features/account/detail/` for the drawer and its sub-widgets. Suggested split (Claude Code can adjust):
  - drawer host widget that orchestrates loading and layout
  - per-root-goal progress chart widget (uses `fl_chart`)
  - recent-answers strip widget (the 5 dots)
  - status report list widget
  - struggling/concept-attribution summary widget

### Tests
- `test/services/progress/progress_service_test.dart` — new `getAllProgress` / `getProgressForUser` tests.
- `test/services/status_report/report_service_test.dart` — equivalent.
- Widget tests for: the inline columns rendering correctly given mocked services; the drawer opening on row tap; the struggling signal computation. Keep widget tests focused on logic, not pixel layout.

### pubspec.yaml
- Add `fl_chart` under dependencies.

## Files to NOT touch

- `lib/services/tutor/*`, response handlers, instruction generator, conductor — none of this changes.
- `lib/features/progress/*` student-facing call sites should keep working unchanged. The parameterisation is additive.
- Anything under `lib/features/goals/`, `lib/features/instructions/`, `lib/features/dashboard/`, `lib/features/chat/` — out of scope.
- `lib/core/cosmos_*` — no schema changes, no new doc id schemes.

## Inline columns on accounts page

For each student row, add (alongside existing columns):

- **Huidig doel** (current goal) — short title of the root goal whose latest activity is most recent, derived from progress docs' `updatedAt`. If the student has no progress yet, show an em-dash.
- **Voortgang** (overall progress) — a thin progress bar showing average progress across all non-optional root goals. Numeric percentage next to the bar.
- **Status** — a coloured dot signalling one of:
  - struggling (red): recent-answer-quality average over the most-recently-active subgoal indicates ≥0.5 weighted-wrong (definition: weight wrong=1.0, partial=0.5, correct=0.0, mean over `recentAnswers`, requires ≥3 entries)
  - active (green): has progress in the last 7 days and not struggling
  - idle (grey): no activity in the last 7 days, or insufficient data
  - Tooltip on hover spelling out the meaning.

Sort and search continue to work over existing columns; no need to make the new columns sortable in this step (can add later).

The struggling computation is a small pure function — put it somewhere reusable (e.g. alongside `Progress` or in a small helper file), not buried in the widget, since the drawer uses it too.

## Detail drawer

Opens on row tap, slides from the right, takes ~40–50% of the viewport width on a wide window. Closeable via the usual drawer affordances.

Contents, top to bottom:

1. **Header** — student's name, email, current root goal in a compact strip.
2. **Status summary** — struggling/active/idle with a one-sentence Dutch explanation. If struggling, also show the suspected concepts derived from `recentConceptAttributions` on the most-recently-active subgoal: count attributions per concept tag, show top 1–2 with counts, framed as e.g. *"Lijkt te haperen op: variabelen (3×), printen (1×)"*. If no attributions, omit this line.
3. **Goal tree with per-subgoal detail** — the reused `student_progress_list` in read-only mode, but expanded to show per-subgoal:
   - progress bar (already there)
   - persisted difficulty as a small label (e.g. *gemakkelijk / gemiddeld / moeilijk*)
   - the recent-answers strip: up to 5 dots from `recentAnswers`, oldest left, colour by quality (red/yellow/green or similar)
   The strip is the new bit; keep it compact.
4. **Status reports** — collapsible section per subgoal that has a `status_reports` doc, showing the AI-written `statusReport` text and `updatedAt`. Most recent first. Plain text rendering is fine; no markdown processing required.
5. **Progress over time** — one `fl_chart` `LineChart` per root goal, showing each child subgoal as a line plus the root's derived average as a thicker line. X axis: time (last 30 days, with sensible labels). Y axis: 0.0–1.0 progress. Source: `progress_history` for the student, grouped by `goalID`, with root averages computed client-side from child samples.
   - If a goal has no history yet, show a dashed empty-state ("Nog geen geschiedenis") instead of an empty chart.
   - Warm-up samples (`isWarmUp=true`) render the same as normal samples in this step. Distinguishing them visually is a possible later refinement.
   - Don't try to show all root goals at once if there are many; render charts lazily as the user scrolls, or limit to roots that have any history.

Loading states: the drawer should show a spinner while initial data loads, then progressively reveal sections as their respective streams emit. Don't block the whole drawer on the slowest read.

Errors: any read failure shows an inline message in that section, not a full crash recovery.

## Performance notes

A class of 30 students × maybe 5–10 active subgoals = 150–300 progress docs, 30 accounts, low-thousands of history docs. Loading all of this every 5s is acceptable on a desktop app on a school LAN, but:

- The accounts table should stream progress *once* via `watchAllProgress` and derive each row's columns client-side. Don't issue per-student queries from each row.
- The drawer's history read is per-student and only active while the drawer is open. Make sure subscriptions are cancelled on drawer close.

## Definition of done

- `flutter analyze` clean.
- `flutter test` passes, including new service tests and the targeted widget tests above.
- Manual test:
  - Sign in as a teacher. Accounts page shows the three new columns populated for students with progress, sensible empty states for students without.
  - Tap a student. Drawer opens with header, status summary, goal tree, status reports, and at least one chart for a root goal that has history.
  - Generate some struggling data on a test student (a few wrong answers in a row) and confirm the red dot and *"Lijkt te haperen op…"* line appear.
  - Close the drawer, open another student — drawer updates cleanly, no stale data flash.
- No regression in student-facing UI: dashboard, chat, student progress list still work identically.
- No regression in non-teacher roles: a signed-in student sees no accounts page (gated by `RoleService.isTeacher` as today).

---

Two things to flag before you hand this off:

The struggling threshold (`≥0.5` weighted-wrong over `≥3` answers) is my guess. You'll want to tune it after seeing real data — a class with mostly easy material early on will have a lot of greens, so a strict threshold is fine. If everyone's red, loosen it.

The drawer is the biggest single UI surface in the project so far. If Claude Code's first attempt is shaky, splitting this into 5a (inline columns only) and 5b (drawer) is a reasonable fallback — the inline columns are independently useful even without the drawer.

---

# Step 6: Concept-health-driven diversions in the Conductor

## ⚠️ Before running this prompt — verification gate

This task only makes sense if the AI's `suspected_concepts` tagging from step 3 is producing usable signal. **Do not run this against Claude Code until you've verified the data.**

Verification checklist (do this in the Cosmos data explorer, takes ~20 minutes):

1. Pick 3–5 students (or seed accounts you've roleplayed) who have answered ≥20 feedback-eliciting questions across at least 2 different root goals.
2. Pull their `progress` docs and inspect `recentConceptAttributions`.
3. Sanity checks:
   - **Frequency:** is the AI using the field at all? If <10% of wrong/partial answers have any tags, the instruction wording in step 3 is too cautious — tune it before running step 6.
   - **Plausibility:** spot-check 10 attributions. Does the tagged concept make sense given the subgoal and likely mistake? E.g. a wrong loop answer tagged `"variables"` when the loop body misuses a variable = good. A wrong loop answer tagged `"print()"` for no obvious reason = noise.
   - **Correct-answer noise:** are correct answers rarely tagged? Some tagging on correct answers is fine (the AI flagging "they got it but seemed shaky on X"). Heavy tagging on correct answers means the AI is over-eager — tune wording.
   - **Drift:** check the debug logs from step 3's `recordConceptAttributions` for dropped tags. Frequent drops mean the AI is hallucinating concepts not in the goal tree's `knownConcepts` — tune wording before proceeding.

If any of these fail, fix the instruction wording in `instructions-export.md` (the four feedback docs from step 3), import the updated Markdown, collect another week of data, re-verify. *Do not run step 6 against bad data.*

If all four checks pass: proceed.

---

## Goal

When the conductor detects that a student's recent struggles on the current subgoal are repeatedly attributed to a specific *prior* concept, divert: temporarily switch to the root goal that originally taught that concept, ask one focused question there, then return to the original subgoal. The diversion's outcome feeds into the diverted goal's progress like any normal answer, so a successful diversion bumps the underlying concept's progress and a failed one decrements it.

This is the first time `recentConceptAttributions` drives behaviour rather than just being collected.

## Constraints

- **No new containers, no schema changes.** All required data is on existing `progress` docs.
- **No new `ChatRequestType`.** Diversion questions reuse existing exercise types — divertedness is invisible to the prompt layer, same pattern as warm-ups in step 2.
- **At most one diversion per session.** A student who's struggling on multiple concepts shouldn't get pinballed across the goal tree. One diversion, then back to the original subgoal regardless of outcome.
- **Diversion is a Conductor decision, not a TutorService one.** Keep TutorService thin.
- All Dutch student-facing framing follows step 2's pattern (short system message, varied phrasing, no jargon like "diversion" or "recheck").

## Trigger conditions

Divert when *all* of the following hold at the moment of selecting the next question:

- The current subgoal has `progress >= 0.3` (so the student isn't a complete beginner on it — for a brand-new subgoal, struggles are expected and not diagnostic).
- `recentAnswers` on the current subgoal contains ≥3 entries with weighted-wrong average ≥0.5 (same definition as the struggling signal in step 5: wrong=1.0, partial=0.5, correct=0.0).
- `recentConceptAttributions` on the current subgoal contains ≥3 entries from the *same concept tag* within the last 10 attributions, where each contributing entry has `quality` of `wrong` or `partial` (correct-answer attributions don't count toward the trigger).
- A diversion has not already fired this session.
- The attributed concept maps to a known earlier root goal (see "Mapping concepts to goals" below). If a concept can't be mapped, don't divert — log a debug line and continue normally.

If multiple concepts cross the threshold simultaneously, pick the most-recently-attributed one. Ties broken by frequency.

## Mapping concepts to goals

Each `Goal` has a `knownConcepts: List<String>` field. The diversion target is the *earliest* root goal (lowest `order`) whose `knownConcepts` contains the attributed concept tag. The instruction generator already exposes a "mastered concepts" helper that walks earlier root goals — reuse or adapt that traversal logic rather than duplicating it.

If the attributed concept appears on the *current* root goal's `knownConcepts` (i.e. it's not actually a prior concept), do not divert — that's a same-goal struggle, handled by existing difficulty adaptation.

## Diversion mechanics

1. Conductor decides to divert *before* generating the next question.
2. Save the current root+subgoal selection so it can be restored.
3. Switch the active goal to the target root goal. Pick its first non-optional subgoal (or, if all children are complete, the root goal itself if that's a meaningful selection in the existing model — Claude Code will know what fits).
4. Emit a short Dutch system message before the diverted question, varied across 2–3 phrasings. Examples:
   - *"Even iets korts over variabelen — daar lijkt nog iets onduidelijk."*
   - *"Snelle zijstap: laten we variabelen even nakijken."*
   - *"Voor we verder gaan, even kort terug naar variabelen."*
   The concept tag is interpolated into the message. Keep it natural.
5. Generate one question of an exercise type appropriate for the diverted subgoal's progress band (reuse existing selection logic) at the persisted `difficulty` of the diverted subgoal — *not* the original subgoal's difficulty.
6. The student answers. Feedback handler fires normally.
7. `Conductor.updateProgress` runs against the **diverted** subgoal — so a correct diversion answer bumps that subgoal's progress, a wrong one decrements it. `recentAnswers` and `difficulty` on the diverted subgoal update normally. `recentConceptAttributions` on the diverted subgoal also update normally if the AI tags this answer (recursion is fine — diversion-of-diversion is prevented by the once-per-session rule).
8. After the feedback turn completes, restore the original root+subgoal selection.
9. Mark this session as having diverted. No further diversions until the session ends.
10. Continue with normal selection on the original subgoal.

## Session boundary

Reuse the same session boundary as step 2: `now - lastSessionAt > 12 hours` starts a new session. The "diverted this session" flag is in-memory on the conductor, reset on session start.

## Edge cases

- **Goal completion during diversion.** If the diversion answer pushes the diverted subgoal's progress to 1.0, fire the existing goal-reached splash + sound as normal. Then still restore the original selection — the splash celebrates the concept mastery, but we're not making the student suddenly switch their *primary* learning track.
- **Original subgoal completed by something else mid-diversion.** Shouldn't be possible (only one question runs at a time), but if state is somehow inconsistent on restore, fall back to the conductor's normal "advance to next incomplete subgoal" path.
- **Student types a free-text question during diversion.** Treat it normally — the `studentQuestion` flow doesn't care about diversion state. Don't restore-and-divert based on a question; only on a feedback turn.

## Files to touch

- `lib/services/tutor/conductor.dart` — diversion decision logic, state, restoration. The bulk of this task lives here.
- `lib/services/tutor/tutor_service.dart` — only if the conductor needs a hook to inject the system message and trigger the goal switch. Keep changes minimal.
- `test/services/tutor/conductor_test.dart` — comprehensive new tests, see below.

## Files to NOT touch

- Response models, response handlers, instruction generator, question formatter — diversion is invisible to all of them.
- `Progress` model, `ProgressService` — schema and write path unchanged.
- Any `features/` UI — no UI surface in this step. The teacher detail panel from step 5 will naturally start showing diversion-driven progress changes in the existing graphs and recent-answers strips, with no extra work.
- `instructions-export.md` — the prompt instructions don't change. The AI doesn't know about diversions.

## Tests

- Trigger fires when all conditions are met.
- Trigger does not fire when current subgoal `progress < 0.3`.
- Trigger does not fire when weighted-wrong average is below threshold.
- Trigger does not fire with <3 same-concept attributions in last 10.
- Trigger does not fire when the same-concept attributions are all from `correct`-quality answers.
- Trigger does not fire when the attributed concept maps to the current root goal (not a prior concept).
- Trigger does not fire when the concept doesn't map to any earlier root goal.
- Tie-breaking: most-recent wins, then frequency.
- Only one diversion per session, even if conditions re-trigger after the diversion.
- Diversion correctly switches active goal, emits one system message, asks one question, then restores.
- Correct answer during diversion bumps diverted subgoal's progress, not original's. Original's progress and `recentAnswers` are untouched.
- Wrong answer during diversion decrements diverted subgoal's progress, not original's.
- Goal completion during diversion still fires splash; restoration still happens after.
- Session boundary resets the diversion flag.
- Free-text `studentQuestion` during diversion does not trigger restore.

## Definition of done

- The verification gate at the top of this prompt has been satisfied. Don't skip this.
- `flutter analyze` clean.
- `flutter test` passes including new tests.
- Manual test:
  - Find or seed a student with ≥3 same-concept wrong/partial attributions on a current subgoal mapping to an earlier root goal.
  - Start a session (force `lastSessionAt` if needed). Confirm: warm-up runs first if step 2's conditions hold, then the next question is the diversion. System message references the concept. Question is from the earlier root goal's subgoal at that subgoal's persisted difficulty.
  - Answer the diversion correctly. Confirm: diverted subgoal's progress increments, original subgoal's progress is unchanged, next question returns to the original subgoal.
  - Continue the session. Confirm: no second diversion fires even if attributions accumulate.
  - End the session (force `lastSessionAt > 12h`), restart. Confirm: diversion flag is reset and a new diversion can fire if conditions hold again.
- No regression in student-facing flow when diversion conditions are not met.
- No regression in teacher UI from step 5 — diversion-driven progress changes show up in the existing graphs and strips automatically.

---

A note for future-you reading this in four months: if the verification gate fails (the AI's tagging is bad), the right move is *not* to weaken the trigger conditions to compensate. Bad tags driving diversions creates a worse experience than no diversions. Tune step 3's instruction wording, collect more data, retry the gate.