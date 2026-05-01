# Refactor Plan — AI Tutor Python

A five-step refactor pass to bring the codebase back to a healthy state. Steps are ordered from lowest-risk / highest-clarity-payoff to highest-risk. Do them in order; each step's "Definition of done" should be green before moving on.

Each step is self-contained — instruct Claude to "execute Step N" to act on that step alone.

---

## Step 1 — Dead-code sweep

**Goal:** Delete code that is already commented-out, unused, or never wired up. No behaviour change. This is the safest step and it shrinks the surface area for every later step.

**Files to delete entirely:**
- [lib/services/timeline/timeline.dart](lib/services/timeline/timeline.dart) — every line of the file body is commented out.
- [lib/services/timeline/code_entry.dart](lib/services/timeline/code_entry.dart) — only consumer is `message_entry.dart` and the dead `timeline.dart`.
- [lib/services/timeline/message_entry.dart](lib/services/timeline/message_entry.dart) — only consumer is `code_entry.dart`.
- The whole [lib/services/timeline/](lib/services/timeline/) directory once empty.
- [pubspec.yaml.bak](pubspec.yaml.bak) — manual rollback artifact.

**Edits inside surviving files:**
- [lib/main.dart:22-26](lib/main.dart#L22-L26) — remove the commented `_connectToFirebaseEmulator` / `_awaitFreshAuth` invocation block.
- [lib/main.dart:44-59](lib/main.dart#L44-L59) — remove the unused `_connectToFirebaseEmulator` function definition.
- [lib/main.dart:122-135](lib/main.dart#L122-L135) — remove the unused `_awaitFreshAuth` function definition.
- [lib/services/chat/chat_service.dart:35](lib/services/chat/chat_service.dart#L35) — remove the empty `addSystem` stub. Verify with grep that nothing calls it.
- [lib/services/tutor/tutor_service.dart:229](lib/services/tutor/tutor_service.dart#L229) — remove the empty `dispose()` method (services live for app lifetime; an empty dispose is misleading).
- [lib/services/tutor/tutor_service.dart:478-482](lib/services/tutor/tutor_service.dart#L478-L482) — remove `_addUserMessage` (no-op body, called from one site at line 190). Remove the call site too.
- [lib/services/tutor/tutor_service.dart:449-455](lib/services/tutor/tutor_service.dart#L449-L455) — `_startNewCode` keeps only the live line (`DataService.code.setText(code)`); remove the commented timeline lines and the now-meaningless `updateEditor` parameter (audit each callsite — currently always `true`).
- [lib/services/tutor/tutor_service.dart:457-471](lib/services/tutor/tutor_service.dart#L457-L471) — `_addTutorMessage`: keep only `DataService.chat.addTutorMessage(message)`; remove the commented timeline + line-splitting + delay code and the unused `sendToChat` parameter.
- [lib/features/dashboard/controllers.dart:17-18](lib/features/dashboard/controllers.dart#L17-L18) — remove commented timeline imports.
- [lib/features/dashboard/controllers.dart:50-63](lib/features/dashboard/controllers.dart#L50-L63) — remove the commented Previous/Next button block (and the surrounding `Spacer` if it leaves an awkward layout — verify visually).
- [lib/features/dashboard/controllers.dart:8-13](lib/features/dashboard/controllers.dart#L8-L13) — remove `onPreviousPressed` / `onNextPressed` constructor params (now unused).
- [lib/features/dashboard/dashboard.dart:60-70](lib/features/dashboard/dashboard.dart#L60-L70) — remove the empty `onPreviousPressed`/`onNextPressed` closures passed to `Controllers`.

**Cross-check before declaring done:**
- `grep -rn "timeline" lib/` returns nothing case-insensitive (or only matches in instructions / docs strings, not code).
- `flutter analyze` returns no new warnings.
- App still launches; dashboard still shows Run / Stop / Hint / Submit / Exercise buttons.

**Manual test plan:**
1. Launch the app, sign in, reach the dashboard.
2. Hit Run, then Stop on a trivial Python snippet — output panel works.
3. Hit Request Exercise — a tutor message + (optionally) code in the editor appear.
4. Hit Request Hint — a hint message appears.
5. Submit a trivial answer — feedback appears.

**Definition of done:** files deleted, no commented-out code blocks remain in the touched files, `flutter analyze` clean, the five smoke-test interactions all work.

---

## Step 2 — Fix `OpenaiConnector` error contract and re-enable the stream guard

**Goal:** Stop silently swallowing OpenAI / Firestore errors. Today an exception thrown by the OpenAI SDK is *returned as the result*, then a downstream parser turns it into `ErrorResponse("Unable to parse response: ...")` — a symptom-fix on top of a swallow. Same shape on Firestore streams. Replace both with explicit error paths.

**Files to change:**
- [lib/services/tutor/openai_connector.dart](lib/services/tutor/openai_connector.dart)
- [lib/services/tutor/responses/error_summary.dart](lib/services/tutor/responses/error_summary.dart) (likely no change, just confirm `ErrorResponse` is the right vehicle)
- [lib/services/tutor/responses/ai_response_parser.dart](lib/services/tutor/responses/ai_response_parser.dart) — adjust now that the connector returns a typed error
- [lib/services/tutor/tutor_service.dart](lib/services/tutor/tutor_service.dart) — `queryTutor` and `_resendLastRequest` callers
- [lib/core/firestore_safety.dart:86-95](lib/core/firestore_safety.dart#L86-L95)

**Concrete edits:**

1. **Type the connector return.** Change `sendRequest` and `resendRequest` from `Future<dynamic>` to a sealed result type. Either:
   - introduce `sealed class ConnectorResult { ... } class ConnectorOk extends ConnectorResult { final List<...> output; } class ConnectorFailure extends ConnectorResult { final Object error; final StackTrace stack; }`, or
   - keep returning the OpenAI output type and throw `ConnectorException` on failure, letting the caller catch it.
   Pick whichever fits the existing parser surface — `ChatResponse` is already a sealed-ish hierarchy, so option 1 is more idiomatic here.

2. **Stop returning the exception object as the value.** Replace [openai_connector.dart:71-73](lib/services/tutor/openai_connector.dart#L71-L73) `catch (e) { return e; }` with the new failure branch.

3. **Guard `resendRequest`** at [openai_connector.dart:76-81](lib/services/tutor/openai_connector.dart#L76-L81). Today both `_previousInstuctions!` and `_previousInput!` are force-unwrapped — calling `resendRequest` before any successful `sendRequest` throws. Either: return a `ConnectorFailure` with a meaningful message, or guard at the callsite in `tutor_service.dart`. Prefer guarding inside the connector so the contract is uniform.

4. **Fix the typo while we're here.** Rename `_previousInstuctions` → `_previousInstructions` in [openai_connector.dart:15, 30, 78](lib/services/tutor/openai_connector.dart#L15) (3 sites, all in this one file).

5. **Update callers.** In [tutor_service.dart:163-174](lib/services/tutor/tutor_service.dart#L163-L174) and [tutor_service.dart:424-435](lib/services/tutor/tutor_service.dart#L424-L435) consume the new typed result. The current `if (result != null) _handleResponse(result)` check becomes a `switch` on the result type; on failure, route to `_addSystemMessage` and (optionally) attempt one resend, then stop. Today there is no retry limit — `_handleResponse` calls `_resendLastRequest` on `ErrorResponse`, which can re-enter `_handleResponse` on a fresh error and loop. Add a single retry counter.

6. **Re-enable the stream guard.** [firestore_safety.dart:91](lib/core/firestore_safety.dart#L91) — uncomment the `resetAuthAndCacheAndExit()` call (or, safer for dev: keep the comment but swap to logging via `debugPrint` so the failure is at least visible). Decide intentionally rather than leaving the dead branch.

**Manual test plan:**
1. Disconnect from the network → trigger Request Exercise → confirm a system message says something sensible (not a stack trace, not silence) and the UI returns to idle.
2. Set `Env.apiKey` to a bogus value temporarily → trigger Request Exercise → same expectation.
3. Restore network/key → confirm a normal request succeeds and the retry counter doesn't fire.
4. Open Firestore rules in console and deny `accounts/{uid}/progress` for a moment → confirm the stream-guarded path now surfaces an error instead of silently doing nothing.

**Definition of done:** no `dynamic` return types on connector methods; no `catch (e) { return e; }`; `resendRequest` has a single retry budget controlled in `tutor_service.dart`; stream guard either re-enabled or replaced with intentional logging; typo renamed; smoke tests pass.

---

## Step 3 — Centralize Firestore collection paths

**Goal:** Stop scattering Firestore collection names as bare string literals across services. Today the same `accounts/{uid}/X` pattern is reimplemented in three files, and there's no single place to look up the schema.

**Sites today (confirm with `grep -n "collection('" lib/`):**
- [lib/services/goal/goals_service.dart:9](lib/services/goal/goals_service.dart#L9) — `collection('goals')`
- [lib/services/progress/progress_service.dart:27](lib/services/progress/progress_service.dart#L27) — `collection('accounts').doc(uid).collection('progress')`
- [lib/services/instructions/instructions_service.dart:9](lib/services/instructions/instructions_service.dart#L9) — `collection('instructions')`
- [lib/services/account/account_service.dart:28](lib/services/account/account_service.dart#L28) — `collection('accounts')`
- [lib/services/account/account.dart:90](lib/services/account/account.dart#L90) — `collection('accounts').doc(uid)`
- [lib/services/role/role_service.dart:21](lib/services/role/role_service.dart#L21) — `collection('roles')`
- [lib/services/status_report/report_service.dart:23](lib/services/status_report/report_service.dart#L23) — `collection('accounts').doc(uid).collection('status_reports')`
- [lib/services/config/global_config_service.dart:20](lib/services/config/global_config_service.dart#L20) — `collection('config')`

**Concrete edits:**

1. Create `lib/core/firestore_paths.dart` exporting:
   ```dart
   class FsPaths {
     static final root = FirebaseFirestore.instance;
     static CollectionReference<Map<String, dynamic>> goals() => root.collection('goals');
     static CollectionReference<Map<String, dynamic>> instructions() => root.collection('instructions');
     static CollectionReference<Map<String, dynamic>> roles() => root.collection('roles');
     static CollectionReference<Map<String, dynamic>> accounts() => root.collection('accounts');
     static CollectionReference<Map<String, dynamic>> config() => root.collection('config');
     static DocumentReference<Map<String, dynamic>> account(String uid) => accounts().doc(uid);
     static CollectionReference<Map<String, dynamic>> progress(String uid) => account(uid).collection('progress');
     static CollectionReference<Map<String, dynamic>> statusReports(String uid) => account(uid).collection('status_reports');
   }
   ```
2. Replace each of the eight call-sites above with a `FsPaths.X` call. Keep the `withConverter(...)` chains where they exist — they hang off the returned reference unchanged.
3. **While editing** `account_service.dart` and `report_service.dart`, wrap their raw Firestore calls in `safeFirestore` so they share the recovery path with the rest of the codebase.
   - [account_service.dart:40, 78, 85, 92, 145, 155, 163](lib/services/account/account_service.dart) — six raw Firestore calls.
   - [report_service.dart:27, 40, 49, 54](lib/services/status_report/report_service.dart) — four raw Firestore calls.

**Cross-check:** `grep -rn "collection('" lib/` returns zero hits outside `lib/core/firestore_paths.dart`.

**Manual test plan:**
1. Launch app, sign in, confirm dashboard loads (touches `accounts`, `progress`, `goals`).
2. Open the Goals page → goals load and edit (touches `goals`).
3. Open the Instructions editor → instructions load (touches `instructions`).
4. Open the Accounts admin page if Yvan has admin role → list of accounts loads (touches `accounts`, `roles`).
5. Trigger a status report (complete a goal) → verify it writes (touches `status_reports`).

**Definition of done:** `FsPaths` is the single source of collection names; `account_service` and `report_service` use `safeFirestore`; all five manual checks pass.

---

## Step 4 — Split `TutorService._handleResponse` into a per-response handler map

**Goal:** Replace the 15-arm `if (parsed is X)` chain in [tutor_service.dart:245-421](lib/services/tutor/tutor_service.dart#L245-L421) with a typed handler-per-response-class. The current arms duplicate the same `_addTutorMessage + sound + maybe-startNewCode + maybe-progress + maybe-next-exercise` shape, which is a perfect strategy-pattern fit and exposes the inconsistencies (e.g. the `CompleteCode` branch missing `_currentExerciseType` assignment).

**Files involved:**
- [lib/services/tutor/tutor_service.dart](lib/services/tutor/tutor_service.dart) — primary
- New file: `lib/services/tutor/responses/response_handlers.dart`
- [lib/services/tutor/responses/](lib/services/tutor/responses/) — no changes to existing classes; just consumed

**Concrete approach:**

1. Define a handler interface in the new file:
   ```dart
   typedef TutorContext = ({
     void Function(String) addTutorMessage,
     void Function(String) addSystemMessage,
     void Function(String) startNewCode,
     void Function(String) setCurrentExerciseType,
     void Function(String? msg, String? code) setFollowUp, // sets _nextMessage/_nextCode and state
     Future<void> Function() requestExercise,
     Conductor conductor,
     SoundService sound,
     // ...whatever is needed
   });

   abstract class ResponseHandler<R extends ChatResponse> {
     Future<void> handle(R response, TutorContext ctx);
   }
   ```
2. Create one tiny handler per response class — `CompleteCodeHandler`, `ExplainCodeHandler`, `WriteCodeHandler`, `SocraticQuestionHandler`, `MultipleChoiceHandler`, `GuidingExcerciseHandler`, `GuidingFeedbackHandler`, `AnswerHandler`, `HintHandler`, `CodeFeedbackHandler`, `McqFeedbackHandler`, `ExplainFeedbackHandler`, `SocraticFeedbackHandler`, `StatusSummaryHandler`, `ErrorResponseHandler`. Lift the body of each existing arm into the matching handler unchanged at first.
3. In `TutorService`, replace the chain with a `Map<Type, ResponseHandler>` lookup or — more idiomatic in Dart 3 — a `switch` on `parsed` using sealed-class exhaustiveness (this requires `ChatResponse` to be marked `sealed`; check whether that's already the case in [chat_response.dart](lib/services/tutor/responses/chat_response.dart) and adapt).
4. **While doing this, fix the latent bug:** the `CompleteCode` branch at [tutor_service.dart:245-254](lib/services/tutor/tutor_service.dart#L245-L254) does not set `_currentExerciseType`, while every other exercise type branch does. As a result, `handleStudentMessage` falls into the generic `studentQuestion` path for follow-ups on a complete-code exercise. Set it inside `CompleteCodeHandler`.
5. **Fix the spelling:** rename `GuidingExcercise` → `GuidingExercise` (and `guidingExcercise` factory → `guidingExercise`) at [responses/guiding_exercise.dart:11, 17, 23, 24](lib/services/tutor/responses/guiding_exercise.dart#L11), [responses/chat_response.dart:43](lib/services/tutor/responses/chat_response.dart#L43), [tutor_service.dart:296](lib/services/tutor/tutor_service.dart#L296). Rename the file to `guiding_exercise.dart` (already named correctly — only the class is misspelled).
6. **Move `_updateReport`** ([tutor_service.dart:437-447](lib/services/tutor/tutor_service.dart#L437-L447)) into `ReportService` — it only writes to the report service and reads `selectedChildGoal`. Call from `StatusSummaryHandler`.

**Cross-check:** the new `_handleResponse` body is < 30 lines and has no business logic, just dispatch.

**Manual test plan (exercise every response branch):**
1. Start a fresh tutor session at progress < 0.2 → expect `GuidingQuestion` flow → answer once → `GuidingFeedback` flow → answer until guidingComplete → `requestExercise` fires.
2. Force progress to ~0.3 (set `currentProgress` in Firestore) → restart → expect MCQ or ExplainCode → answer → MCQ feedback / ExplainFeedback fires correctly.
3. Force progress to ~0.5 → expect CompleteCode or SocraticQuestion → answer → CodeFeedback / SocraticFeedback fires correctly. **Specifically verify** that submitting a follow-up text message on a CompleteCode exercise routes through the right path (not the generic studentQuestion).
4. Force progress to ~0.8 → expect WriteCode or SocraticQuestion → answer → CodeFeedback fires.
5. Force progress to 1.0 → complete → expect StatusSummary handler to write a status report.
6. Force a malformed AI response (temporary patch in `ai_response_parser`) → expect ErrorResponse path with retry budget from Step 2.

**Definition of done:** `_handleResponse` is dispatch-only; one handler file per response type (or one consolidated `response_handlers.dart` if Yvan prefers); `_currentExerciseType` is set for every exercise branch; `GuidingExercise` spelled correctly everywhere; `_updateReport` moved to `ReportService`; all six manual flows verified.

---

## Step 5 — Decompose `Conductor.updateProgress`

**Goal:** [conductor.dart:113-252](lib/services/tutor/conductor.dart#L113-L252) is a 140-line method doing six concerns (delta math, milestone gating, system messages, difficulty adaptation, hint reset + persistence, goal-completion). Each concern is already bookmarked in code by numbered `// --- N) ...` comment headers — extract them into named private methods of `Conductor`. No behaviour change.

**Concrete decomposition (private methods on `Conductor`):**

1. `double _computeDelta(AnswerQuality quality)` — encapsulates the `baseDelta * typeMult * diffMult` calculation and hint penalty at [conductor.dart:122-157](lib/services/tutor/conductor.dart#L122-L157). Returns the signed delta.
2. `bool _crossesMilestone(double from, double to)` — replaces the three-branch milestone check at [conductor.dart:162-171](lib/services/tutor/conductor.dart#L162-L171). Returns true if any of the {0.3, 0.7, 1.0} thresholds is newly crossed.
3. `void _adaptDifficulty(AnswerQuality justAnswered)` — pushes `_answerHistory`, computes `correct/wrong/partial` counts, applies up/down rules, emits the system message on change. From [conductor.dart:178-213](lib/services/tutor/conductor.dart#L178-L213).
4. `Future<void> _handleGoalCompletion()` — splash + sound + clear preferred + `_setTargetGoal` + reset `_currentProgress`. From [conductor.dart:220-244](lib/services/tutor/conductor.dart#L220-L244). Trigger only when `_currentProgress >= 1.0` after the upsert.
5. `bool _rollFollowUpAllowance(bool currentlyAllowed)` — wraps the random gating at [conductor.dart:247-250](lib/services/tutor/conductor.dart#L247-L250). Pulls the magic `0.35` to a named constant.

After extraction, `updateProgress` reads as roughly:
```dart
Future<bool> updateProgress(AnswerQuality quality) async {
  if (quality == AnswerQuality.correct) DataService.sound.correctAnswer();
  final start = DataService.progress.currentProgress.value;
  final delta = _computeDelta(quality);
  final next = (start + delta).clamp(0.0, 1.0);
  bool followUpAllowed = !_crossesMilestone(start, next);

  DataService.chat.addSystemMessage('Vooruitgang: ${...} -> ${...}');
  _currentProgress = next;
  _adaptDifficulty(quality);
  _hintsUsed = 0;
  await _updateProgress(next);

  if (next >= 1.0) await _handleGoalCompletion();
  return _rollFollowUpAllowance(followUpAllowed);
}
```

**Manual test plan:**
1. With a fresh student, answer 5 wrong in a row → expect difficulty to step down (or stay easy) and progress to dip slightly.
2. Answer 4 correct in a row at easy difficulty without hints → expect difficulty to step up to medium; one of those answers should be denied a follow-up if it crosses the 0.3 milestone.
3. Use a hint, then answer correct → expect a smaller delta than answering correct without a hint.
4. Drive a child goal to 1.0 → expect goal-reached splash, sound, and the next child goal to be selected.
5. Run 20 consecutive correct answers → confirm that ~35 % of them deny the follow-up (sanity, not exact).

**Definition of done:** `updateProgress` is < 25 lines and reads as a sequence of named steps; each helper has a single concern and a docstring (one short line) explaining its role; behaviour is identical to before per the manual checks.

---

## Notes for future sessions

- There are **no automated tests** in this repo. Every step's manual test plan is the safety net — run it before claiming done.
- `flutter analyze` should be clean after each step; treat new warnings as regressions.
- The original audit memo lives in Claude memory under `code_quality_audit.md` — read it before starting any step for additional context.
- After all five steps: re-run the audit to see if anything new emerged. The 8.4k LOC count should drop by a few hundred lines.
