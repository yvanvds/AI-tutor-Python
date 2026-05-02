Decisions (with reasoning)
1. Turn boundaries
A turn = one OpenaiConnector.sendRequest/sendRequestStream call. The cleanest place to mark begin/end is TutorService.queryTutor, not the connector itself:

The connector is too low-level — it doesn't know about _currentExerciseType, selectedChildGoal, or setFollowUp which are the things that matter for "stuck in conversation mode" debugging.
queryTutor already wraps both the streaming and non-streaming paths in a single try/finally.
A user action that triggers a chain (feedback → requestExercise → next exercise) calls queryTutor twice. Each invocation gets its own turn because requestExercise releases state to idle and re-enters queryTutor (tutor_service.dart:355-377). Sequential, no nesting — confirmed by the if (state.value != TutorState.idle) return; guard at tutor_service.dart:88.
Begin: top of the try block (after build-input). End: in finally.

2. Hook stitching
Active-turn pointer on the recorder (TurnRecord? _current). All other hooks (connector raw output, conductor events, state changes) append to _current if it's non-null, no-op otherwise.

Justification: turns are strictly sequential per the state guard. Threading a turn ID through every callsite would require touching Conductor constructor, OpenaiConnector constructor, every _streamingContext callback, and the dispatchResponse signature — exactly the kind of refactor the constraints forbid. The active-turn pointer lets every hook be a one-liner.

The narrow risk: a hook fires while no turn is open (e.g. Conductor.recordConceptAttributions called outside a turn — actually it isn't, but defensively). That's fine — the recorder swallows it.

3. TurnRecord shape

turnId            (incrementing int, scoped to the session)
sessionId         (uuid, stable for the session)
startedAt         (UTC ISO)
endedAt           (UTC ISO)
latencyMs         (computed)
requestType       (ChatRequestType.name — e.g. "submitCode")
currentExerciseTypeAtStart   (the _currentExerciseType string at turn begin)
tutorStateAtStart            (TutorState.name)
selectedRootGoalId / selectedChildGoalId
preferredRootGoalId / preferredChildGoalId   (both — they can differ from selected*)
streamable        (bool)
previousInputsMode  (PreviousInputs.name)
userInput         (raw JSON string from QuestionFormatter)
instructionsDocId (the matched doc id, e.g. "submitCode" or "alwaysInclude")
instructions      (the full assembled string, verbatim)
rawOutput         (the verbatim model output — pre-parse)
parsedType        (ChatResponse.type after parse)
parsedResponse    (parsed.toJson())
events: List<TurnEvent>   # see below, time-ordered
error             (string, if endTurn was called with an error)
TurnEvent = {atMs, name, data} where name is one of:

tutor.state_change {from, to}
tutor.exercise_type_set {from, to}
tutor.follow_up_set {hasMessage, hasCode}
tutor.request_exercise.entered / tutor.request_exercise.next {type, difficulty}
tutor.maybe_retry {retriesLeft}
dispatch.unhandled {type}
stream.failed {message}
conductor.subgoal_set {goalId, persistedProgress, warmupRemaining}
conductor.next_question {type, difficulty, diagnosingNext, guidingDone}
conductor.guiding_progress {delta, total, completed}
conductor.update_progress {quality, isWarmup, suppressPositive, streakBefore, streakAfter, typesInStreak, difficultyBefore, difficultyAfter, displayFrom, displayTo, mastered, allowFollowUp}
conductor.record_concepts {input, accepted, dropped}
conductor.hint_provided
conductor.mastered_and_advanced {goalId, quality, isWarmup}
These together let me see "stuck in conversation mode" cases: dispatch.unhandled, a tutor.exercise_type_set value that doesn't match what handleStudentMessage checks against, a missing requestExercise after feedback, or setFollowUp lingering past expected.

Note on the "35% dice roll": the prompt mentions a "follow-up suppressed by 35% dice roll" — I don't see that mechanic in the current Conductor. _allowFollowUp (conductor.dart:332-340) suppresses on wrong answers and on streak-at-threshold, no randomness. Flagging this — either it was removed, never landed, or you're thinking of a different branch. I'll record allowFollowUp deterministically from the conductor return value; if you re-add a dice roll later, plumb the roll outcome into the update_progress event then.

4. Session metadata (top-level export keys)

schema: 1
sessionId, sessionStartedAt, exportedAt
appVersion        (from kAppVersion)
modelName         (from globalConfig.cachedConfig?.model — captured at session start)
uid               (full, not anonymized)
email             (full)
turns: [...]
On uid/email anonymization: keep full. Per the task ("Full fidelity. This is a debug tool — don't redact"), and per the existing security stance ("students tampering is OK", auth_service.dart:18-21). Exports stay on the teacher's machine.

5. Buffer reset semantics
Reset on TutorService.initializeSession(force: true). That call is already the canonical "new student session" boundary — fired by AccountService on first non-null account doc per uid (PROJECT_OVERVIEW.md#L317). It naturally clears the buffer when a different user signs in.

Not on sign-out: a teacher signing out and another student signing in would already get covered by the next initializeSession(force: true). Not on app restart: there's no buffer to reset.

6. Export UI placement
AppBar action, an IconButton left of the sign-out button. Icons.bug_report_outlined, tooltip "Debug-sessie exporteren". Visible to both roles (no isTeacher gate) per the task constraint.

Not the overflow menu — the existing AppBar only has one action so an overflow menu would be extra ceremony. Not the settings page — there isn't one.

7. Failure modes
Every public recorder method wrapped in try { ... } catch (e, st) { debugPrint('DebugRecorder: $e'); }. Internally:

parsed.toJson() throws → store {error: e.toString()} instead of the parsed map.
jsonEncode of the export throws → return {schema: 1, error: ...} so the file picker still gets something.
Recorder constructed before locator init → static getters are lazy, so it'll just construct at first access.
Recorder accessed during sign-out (currentUser becomes null) → the recorder reads from DataService snapshots at event time; null is captured as null. No crash.
The recorder never propagates exceptions to the tutor.

8. Test surface
Worth testing:

Ring buffer overflow at the kBufferCapacity constant (insert N+5, expect last N).
Turn stitching: beginTurn → recordRequestPayload → recordEvent ×3 → recordParsedResponse → endTurn produces one record with events in insertion order.
Schema stability: exportJson() always has schema: 1 and the documented top-level keys.
Failure tolerance: a ChatResponse whose toJson() throws does not throw out of recordParsedResponse.
resetSession() clears the buffer and mints a new sessionId.
Not worth testing:

The file_picker save dialog (UI, brittle).
kAppVersion and globalConfig.model reads — they're trivial DataService getters.
End-to-end "tutor turn produces correct turn record" — would require mocking the entire request pipeline; the per-component tests above cover the meaningful behaviour.
Step-by-step plan
Step 1 — Recorder skeleton + models
Files: new lib/services/debug/debug_session_recorder.dart

Define TurnRecord, TurnEvent, DebugSessionRecorder with the API listed in section 3. Top-of-file const int kBufferCapacity = 200. All public methods wrapped in try/catch. Buffer is a List<TurnRecord> with removeAt(0) on overflow (n=200, fine). Implements exportJson() returning the documented top-level structure.

Manual verify: flutter analyze clean. Nothing else wired yet.

Step 2 — Register in DataService
Files: lib/services/data_service.dart

Add _locator.registerLazySingleton(() => DebugSessionRecorder()) and static DebugSessionRecorder get debug => _locator<DebugSessionRecorder>().

Manual verify: existing tests still pass; DataService.debug accessible.

Step 3 — Hook OpenaiConnector for raw output + stream failures
Files: lib/services/tutor/openai_connector.dart

In sendRequest after _extractText, call DataService.debug.recordRawOutput(text). In sendRequestStream, after the await-for loop call recordRawOutput(raw.toString()); in the catch and on stream failure, call recordStreamFailure(message).

Manual verify: after a turn, the recorder snapshot has rawOutput populated with verbatim model text including <TEXT>/<META> envelope.

Step 4 — Hook dispatchResponse for parsed + unhandled
Files: lib/services/tutor/responses/response_handlers.dart

In dispatchResponse, before iterating, call DataService.debug.recordParsedResponse(parsed). If no entry matches, call recordEvent('dispatch.unhandled', {'type': parsed.type}) before returning false.

Manual verify: turn record's parsedType and parsedResponse are populated; an unknown type produces a dispatch.unhandled event.

Step 5 — Hook Conductor for progression events
Files: lib/services/tutor/conductor.dart

Add recordEvent(...) calls (no logic changes) at:

_resetSubgoalState end → conductor.subgoal_set
getNextQuestion return → conductor.next_question
guidingIsComplete → conductor.guiding_progress
updateProgress (capture before/after snapshots in locals already computed) → conductor.update_progress
recordConceptAttributions → conductor.record_concepts with input/accepted/dropped
hintProvided → conductor.hint_provided
_markMasteredAndAdvance → conductor.mastered_and_advanced
Manual verify: answer one feedback turn; the recorded conductor.update_progress event has the quality, before/after streak, before/after difficulty, mastered flag, and allowFollowUp result.

Step 6 — Hook TutorService for turn boundaries, state changes, and reset
Files: lib/services/tutor/tutor_service.dart

Constructor: state.addListener(() => DataService.debug.recordEvent('tutor.state_change', {...})) with the previous value tracked in a small closure.
initializeSession(force: true): call DataService.debug.resetSession(uid, email, model).
queryTutor: after _buildRequestInput returns non-null, call beginTurn(...) with requestType, currentExerciseTypeAtStart, tutorStateAtStart, selected/preferred goals, streamable, previousInputsMode. After generateInstructions: recordRequestPayload(userInput: request.input, instructions: instructions, instructionsDocId: type.name). In finally: endTurn().
_streamingContext / _nonStreamingContext: wrap setExerciseType and setFollowUp callbacks to also call recordEvent.
requestExercise: bookend with tutor.request_exercise.entered and tutor.request_exercise.next events.
_maybeRetry / _maybeRetryStream: log tutor.maybe_retry.
Manual verify: run a few real turns; export; confirm each turn has a tutor.exercise_type_set event whose to matches the next _currentExerciseType and that state_change events bracket the turn (idle → working → idle or working → hasFollowUp → ...).

Step 7 — Export action in HomeShell
Files: lib/home_shell.dart

Add an IconButton(icon: Icon(Icons.bug_report_outlined), tooltip: 'Debug-sessie exporteren', onPressed: _exportDebugSession) to the AppBar actions list, before the sign-out button. The handler calls DataService.debug.exportJson(), encodes with JsonEncoder.withIndent('  '), opens FilePicker.platform.saveFile(dialogTitle: ..., fileName: 'ai-tutor-debug-<timestamp>.json'), and on a non-null path writes the bytes via dart:io's File(path).writeAsString(json). Show a SnackBar on success/failure.

Manual verify: button visible for both roles; tapping opens save dialog; resulting file is valid JSON with "schema": 1 and a turns array containing the turns I just ran.

Step 8 — Unit tests
Files: new test/services/debug/debug_session_recorder_test.dart

Tests listed in section 8. Uses mocktail only minimally — most of the recorder is pure data so direct construction works. The "ChatResponse whose toJson throws" test uses a small fake.

Manual verify: flutter test passes (existing + new). flutter analyze clean.

Definition of done (whole feature)
flutter analyze clean
flutter test passes (existing + new)
Manual: run app, do ~5 tutor turns including a wrong answer + a follow-up, export, open the JSON. Confirm: schema=1, all turns present, each has instructions (full string), rawOutput (envelope-wrapped), parsedResponse, conductor events, state-change trail. Confirm _currentExerciseType value visible at start of every turn.
Manual: a unit test (rather than 200 real turns) covers the buffer cap.

