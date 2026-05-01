# TESTING_PLAN

This document is the prioritized TODO list for bootstrapping a Flutter test suite for `ai_tutor_python`. The first pass implements only the **reference test** (Tier 1 conductor) so the style can be reviewed before continuing.

## Ground rules

- Pure Dart unit tests where possible; widget tests only where there's real logic.
- Mock external boundaries with `mocktail`. No `mockito` codegen. Use **explicit type arguments** (`any<T>()`, `captureAny<T>()`, `any<T>(named: '...')`) and `registerFallbackValue` so no implicit-dynamic warnings appear under strict-mode analyze.
- Services are `get_it` lazy singletons; tests register **mocks under the interface type** in the locator and call `GetIt.I.reset()` in `tearDown`.
- Tests must follow the same lint rules as production code — `flutter analyze lib test` must stay green.
- Coverage scoring is the Sonar yardstick. Skew priorities toward files with **high statement count and high branch density**. A passing test on a 20-line utility is worth less than a passing test on a 200-line orchestrator.

## CI / Sonar wiring (do not modify)

- [.github/workflows/build.yml](.github/workflows/build.yml) — runs on `windows-latest` with Flutter `3.38.3`. Pipeline: `flutter pub get` → `flutter analyze lib test` → `flutter test --coverage` → `SonarSource/sonarqube-scan-action@v6`.
- [sonar-project.properties](sonar-project.properties) — already wired: `sonar.dart.lcov.reportPaths=coverage/lcov.info`, `sonar.sources=lib`, `sonar.tests=test`, `sonar.coverage.exclusions=lib/**/*.g.dart`. We do not write to a custom coverage path.
- Tests must run **headless on Windows with no native-plugin initialization**. See "Native-plugin boundaries" below.

## What I learned from the current code (vs. PROJECT_OVERVIEW.md)

The overview is partially stale. Current state of the data/auth layer (post Firebase → Azure migration):

- **Cosmos DB** replaces Firestore. New surface in [lib/core/](lib/core/): [cosmos_client.dart](lib/core/cosmos_client.dart), [cosmos_paths.dart](lib/core/cosmos_paths.dart), [cosmos_safety.dart](lib/core/cosmos_safety.dart), [cosmos_doc_id.dart](lib/core/cosmos_doc_id.dart). The old `firestore_*` files are gone. There is **no native Azure SDK** — `cosmos_client.dart` is hand-rolled HTTP over `package:http`.
- **Entra ID** replaces Firebase Auth. New service [lib/services/auth/auth_service.dart](lib/services/auth/auth_service.dart) — hand-rolled OAuth 2.0 + PKCE flow against `login.microsoftonline.com`, tokens persisted in `SharedPreferences`. `currentUser` is a `ValueNotifier<AccountIdentity?>` exposing `oid` (the partition key for `accounts`/`progress`/`status_reports`).
- **`AccountService`** no longer hosts a `_SwitchMap` extension — it's gone after the migration. The service now listens to `AuthService.currentUser` and (on first sign-in for an oid) calls `_ensureProfile`. Watch-via-polling everywhere instead of Firestore snapshot streams.
- **`ProgressService`** writes composite-id docs `${uid}_${goalId}` to Cosmos with partition key `uid`.
- **`GoalsService`** uses Cosmos `executeBatch` for `applyOrder`/`deleteSubtree`/`restoreSubtree`. Manual ordering is still spaced by 1000 ([goals_service.dart:163](lib/services/goal/goals_service.dart#L163)).
- **`Conductor`** is unchanged in spirit — it uses `DataService.goals/progress/chat/sound/splash`, no constructor injection. Tests mock through the locator.

The plan below is adjusted for these realities: there is no Firestore mock to write; we mock the **service** boundary (`GoalsService`, `ProgressService`, etc.).

## Native-plugin boundaries (and what's blocked)

| Native plugin | Used in | Wrapper status | Test impact |
|---|---|---|---|
| `audioplayers` | [sound_service.dart](lib/services/sound/sound_service.dart) (only) | `SoundService` IS the wrapper. Plugin is not injected; it is hard-imported by the wrapper. | ✅ Tier 1/2/3 tests mock `SoundService` at the locator. No new interface needed. |
| `shared_preferences` | [auth_service.dart](lib/services/auth/auth_service.dart), [local_api_key_storage.dart](lib/services/config/local_api_key_storage.dart) | No wrapper — plugin is called directly inside the service. | ✅ Tier 1/2 tests mock `AuthService` at the locator. Direct unit tests of these two services are deferred (would need either `SharedPreferences.setMockInitialValues` plumbing or a new interface). |
| `dart_openai` | [openai_connector.dart](lib/services/tutor/openai_connector.dart) (only) | `OpenaiConnector` IS the wrapper. Pure HTTP under the hood, but uses `Env.apiKey` from generated `env.g.dart` at construction. | ✅ Tier 2 tests mock `OpenaiConnector`. Direct tests of the connector itself are out of scope. |
| `py_engine_desktop` | [output.dart](lib/features/dashboard/output.dart) (only) | **No wrapper.** The widget directly calls `PyEngineDesktop.init / pipInstall / startScript / stopScript`. | 🚫 **Blocks Tier 3.2** ([output.dart](lib/features/dashboard/output.dart) widget test). To unblock, the engine calls would need to move behind an interface registered in `get_it`. **Stopping here for your call** — that's an architectural change, not a test-only one. |
| `url_launcher` | [auth_service.dart](lib/services/auth/auth_service.dart) (sign-in flow) | No wrapper. | Tier 4 anyway — `AuthService` interactive flow is out of scope this pass. |
| Cosmos via `CosmosPaths.*()` (not a native plugin, but blocking) | All services in `lib/services/{account,goal,progress,instructions,...}` | `CosmosContainer` is a class, but services reach for it via the **static** `CosmosPaths.goals()` → `CosmosClient.instance` → singleton. Not injectable. | 🚫 **Blocks Tier 2.3/2.4/2.5** as currently scoped. To unblock, the container handle would need to be injected into each service (constructor or `get_it`-registered factory) so tests can hand a `MockCosmosContainer`. **Stopping here for your call.** |

**Bottom line:** the planned Tier 1 tests (and Tier 2.1/2.2) need **no architectural changes** — they all mock at the existing service boundary. Tier 2.3/2.4/2.5 and Tier 3.2 are real blockers; flagged above.

---

## Prioritized TODO list (re-ranked by Sonar leverage)

For each item: **file under test** · **what's verified** · **what gets mocked** · **why this matters** (regression risk).

### Tier 1A — high-leverage, no architectural changes needed

These dominate the Sonar coverage score: large statement counts, deep branching, and the most blast radius if they break. Order = priority.

#### 1A.1 [services/tutor/conductor.dart](lib/services/tutor/conductor.dart) ⭐ **REFERENCE TEST (DONE)**
- **Verify:**
  - `getNextQuestion()` returns the right candidate pool per progress band: `<0.2` → guiding only; `<0.4` → mc/explain; `<0.7` → completeCode/socratic; `≥0.7` → writeCode/socratic. Back-to-back-repeat avoidance.
  - `_computeDelta` (via observable side effect on `progress.upsert`): sign + magnitude per `AnswerQuality × QuestionType × Difficulty × hintsUsed`.
  - 5-answer adaptation window: 4/5 correct with `hintsUsed ≤ 1` bumps difficulty up; ≥3 wrong (or ≥4 not-correct) bumps it down. System message emitted on change.
  - Parent recompute: child upsert + root upsert with average of children.
  - Goal completion: crossing `1.0` triggers `splash.showGoalReached` + `sound.playGoalReached` + advance to next incomplete subgoal.
  - Guiding flow: `guidingIsComplete` accumulates understanding, caps progress display at 0.2, fires `sound.guidingComplete()` and resets at ≥0.8.
- **Mocks:** `GoalsService`, `ProgressService`, `ChatService`, `SoundService`, `SplashService`. Real `ValueNotifier`s plumbed in via the mocks' getters.
- **Why this matters:** Brain of the app, ~350 LOC, very high branch density. Silent regressions mis-rate students for whole sessions.
- **Status:** [test/services/tutor/conductor_test.dart](test/services/tutor/conductor_test.dart), 10 tests passing.

#### 1A.2 [services/tutor/responses/response_handlers.dart](lib/services/tutor/responses/response_handlers.dart) — `dispatchResponse` + 14 handlers ⬆ **promoted from Tier 2**
- **Verify:** Every `ChatResponse` subtype routes to its handler (14 branches). Unknown subtype → `dispatchResponse` returns `false`. Each handler does the right thing on its `TutorContext` callbacks (e.g. `CodeFeedbackHandler` calls `conductor.updateProgress` then either `setFollowUp` or `requestExercise` depending on `suggestion` + `suggestionAllowed`; `HintHandler` calls `conductor.hintProvided`; `ErrorResponseHandler` calls `maybeRetry`).
- **Mocks:** stub the eight `TutorContext` callbacks; mock `Conductor` and `SoundService` via the locator. `ReportService` for `StatusSummaryHandler`.
- **Why:** ~280 LOC, 14-way strategy table. A missed branch silently swallows a response type. Sonar leverage is comparable to the conductor.
- **Status:** [test/services/tutor/responses/response_handlers_test.dart](test/services/tutor/responses/response_handlers_test.dart), 24 tests passing.

#### 1A.3 [services/tutor/responses/chat_response.dart](lib/services/tutor/responses/chat_response.dart) factory + the 14 typed responses
- **Verify:** `ChatResponseFactory.fromMap` returns the right subtype for every `type` value. Unknown type → `ErrorResponse(type:'error', message:'Unknown type: …')`. Missing `type` → `FormatException`. Each subtype's `fromMap`/`toJson` round-trips faithfully — focus on the awkward ones: `MultipleChoice.options` (list-of-`{option:...}`), `StatusSummary.stats.{hints_used,common_issues,last_exercise_type}`, `CodeFeedback._stringToQuality` defaulting to `wrong` on bad/missing input, `GuidingFeedback.understanding` accepting both `int` and `double`.
- **Mocks:** none — fixture maps.
- **Why:** AI responses come from a non-deterministic source. Schema drift here corrupts progress without crashing. Combined LOC of all response models is ~600.
- **Status:** [test/services/tutor/responses/chat_response_test.dart](test/services/tutor/responses/chat_response_test.dart), 50 tests passing.

#### 1A.4 [services/tutor/responses/ai_response_parser.dart](lib/services/tutor/responses/ai_response_parser.dart)
- **Verify:** `parse(...)` extracts the first `output_text` chunk; strips ```` ```json ```` fences; falls back to `ErrorResponse` for empty / non-JSON / array-without-object / non-message items. `extractAllTextStrings` on the `{text: {value: ...}}` provider variant.
- **Mocks:** none — fixture maps/strings.
- **Why:** Every tutor turn round-trips through this. Silent fallback to `ErrorResponse` would blank the UI without any logged error.
- **Status:** [test/services/tutor/responses/ai_response_parser_test.dart](test/services/tutor/responses/ai_response_parser_test.dart), 23 tests passing.

### Tier 1B — medium-leverage, no blockers

#### 1B.1 [services/tutor/instruction_generator.dart](lib/services/tutor/instruction_generator.dart)
- **Verify:** `_replaceTags` substitutes `{goal}`, `{subgoal}`, `{suggestions}`, `{known concepts}` case-insensitively and tolerates whitespace inside braces (`{ Goal }`). Per-type instructions come first, `alwaysInclude` appended last. Mastered-concepts loop stops at the first goal whose `order >= target.order` (so the target's own concepts are NOT mastered). Empty when no goal selected.
- **Mocks:** `GoalsService`, `InstructionsService`.
- **Why:** A subtle off-by-one in the order check leaks the target goal's own concepts as "already mastered" and breaks every prompt.

#### 1B.2 [services/tutor/question_formatter.dart](lib/services/tutor/question_formatter.dart)
- **Verify:** Each formatter (~13 thin functions) emits the expected JSON shape for its `ChatRequestType` (`request_type`, optional `difficulty` enum-name, optional payload fields). `studentQuestion` with `code = null` produces `"code": ""`.
- **Mocks:** none.
- **Why:** Prompt-format drift silently changes what the model sees. Cheap, broad coverage.

### Tier 1C — low-leverage, batch last

These are small files; high coverage % but low absolute statement contribution to Sonar.

#### 1C.1 [features/goals/tree_utils.dart](lib/features/goals/tree_utils.dart)
- **Verify:** `buildParentMap`, `isAncestor`, `wouldCreateCycle`. Self-parent → cycle. Moving to root → safe. Move to descendant → cycle.
- **Mocks:** none. No Flutter deps.
- **Why:** DnD reparent uses this to gate drops. A goal becoming its own ancestor is unrecoverable in the UI.

#### 1C.2 [core/debounce.dart](lib/core/debounce.dart)
- **Verify:** Two `run()` calls inside `delay` only fire the second action; `dispose()` cancels a pending action. Use `fake_async`.
- **Mocks:** none.
- **Why:** Used wherever search/typing triggers Cosmos reads. A regression to "fire immediately" multiplies read costs.

### Tier 2 — service orchestration (mostly unblocked)

#### 2.1 [services/tutor/tutor_service.dart](lib/services/tutor/tutor_service.dart)
- **Verify:** `state` transitions `idle → working → idle/hasFollowUp` per request kind. `handleStudentMessage` routes by `_currentExerciseType` to the right `ChatRequestType`. `_processResult` retry path on `ConnectorFailure` — exactly one retry, then gives up. `requestExercise` short-circuits on `noResult`. `moveToFollowUp` flushes `_nextMessage`/`_nextCode` and returns to `idle`.
- **Mocks:** `OpenaiConnector`, `Conductor`, `ChatService`, `CodeService`. (`InstructionGenerator` is `new`'d inline; we let it run with mocked `GoalsService`/`InstructionsService` returning empty.)
- **Why:** Stuck-in-`working` would freeze the chat composer. ~280 LOC, branchy switch.

#### 2.2 [services/progress/progress_service.dart](lib/services/progress/progress_service.dart) 🚫 **BLOCKED**
- **Blocker:** `CosmosPaths.progress()` is static; `CosmosContainer` is not injected. To run this test we'd refactor `ProgressService` to accept a container (constructor param or a `get_it` factory). Architectural — paused for your call.
- **Verify (when unblocked):** `getAll`/`getByGoalId`/`upsert`/`delete` build the right Cosmos doc-id and partition-key, throw `StateError` when no signed-in user. `currentProgress` notifier emits.

#### 2.3 [services/goal/goals_service.dart](lib/services/goal/goals_service.dart) 🚫 **BLOCKED** (same Cosmos-injection blocker)
- **Verify (when unblocked):** `applyOrder` produces 1000-spaced `order` values and one batch op per id; `reparent` patches `parentId` + bumps `order` to end-of-list; `backupSubtree` → `deleteSubtree` → `restoreSubtree` round-trip preserves ids and fields; `_nextOrder` returns 1000 when empty and `current+1000` otherwise.

#### 2.4 [services/account/account_service.dart](lib/services/account/account_service.dart) 🚫 **BLOCKED** (same Cosmos-injection blocker)
- **Verify (when unblocked):** Listening to `AuthService.currentUser`: null → `currentAccount = null`; new identity → `_ensureProfile` upserts a doc only if absent; identity change with the same `oid` does NOT re-init the tutor session (the `_lastInitedUid` dedupe). `upsertAccount` preserves existing `mayUseGlobalKey`/`targetGoal`/`createdAt`. `setTargetGoal` throws when signed out.

### Tier 3 — widgets with real logic

#### 3.1 [features/chat/chat_widget.dart](lib/features/chat/chat_widget.dart)
- **Verify:** The composer swap driven by `TutorService.state` (idle → default; working → `composer_wait_widget`; hasFollowUp → `composer_continue_widget`).
- **Mocks:** `TutorService` (real `ValueNotifier<TutorState>` for state), `ChatService` with a real `InMemoryChatController`.
- **Why:** A frozen "Continue" button is one of the easiest regressions to ship and the hardest to notice in dev.

#### 3.2 [features/dashboard/output.dart](lib/features/dashboard/output.dart) 🚫 **BLOCKED**
- **Blocker:** the widget calls `PyEngineDesktop.init/pipInstall/startScript/stopScript` directly. To run a widget test headless on `windows-latest` CI, the engine surface must move behind an interface (e.g. a `PythonRunner` service registered in `get_it`, with a `FakePythonRunner` for tests). Architectural — paused for your call.

### Tier 4 — explicitly out of scope this pass

- **`OpenaiConnector` HTTP integration** ([services/tutor/openai_connector.dart](lib/services/tutor/openai_connector.dart)) — too much surface for unit tests without real HTTP fixtures; mocked at the boundary in 2.1.
- **The Cosmos client itself** ([core/cosmos_client.dart](lib/core/cosmos_client.dart)) — needs an integration test against a real Cosmos emulator.
- **`AuthService` end-to-end** — covers a localhost HTTP server + a real browser launch; an integration test, not a unit test. (We could later unit-test `_decodeJwtPayload`, `_identityFromIdToken`, and `_TokenSet.fromStoredJson` — defer.)
- **Layout-only widgets:** [features/dashboard/dashboard.dart](lib/features/dashboard/dashboard.dart), root/child panes without DnD, [theme.dart](lib/theme.dart), [home_shell.dart](lib/home_shell.dart) (the update-flow specifically), [main.dart](lib/main.dart), [boot_gate.dart](lib/boot_gate.dart), [crash_recovery_screen.dart](lib/crash_recovery_screen.dart).
- **Generated code:** [services/tutor/env.g.dart](lib/services/tutor/env.g.dart), `services/config/azure_config.g.dart`. (Already excluded by `lib/**/*.g.dart`.)
- **Trivial DTOs:** [features/goals/dnd.dart](lib/features/goals/dnd.dart) (single-field data carrier), [features/goals/drag_feedback.dart](lib/features/goals/drag_feedback.dart) (visual).
- **Audio side effects:** `SoundService` is mocked everywhere; we don't try to verify audio playback.

---

## `sonar.coverage.exclusions` — suggested additions

Do not edit `sonar-project.properties` here — list for your review and apply manually. The current value is `lib/**/*.g.dart`; suggested additions (path patterns relative to the repo root):

```
lib/**/*.g.dart,
lib/main.dart,
lib/boot_gate.dart,
lib/home_shell.dart,
lib/crash_recovery_screen.dart,
lib/theme.dart,
lib/create_text_theme.dart,
lib/version.dart,
lib/firebase_options.dart,
lib/widgets/**,
lib/features/dashboard/dashboard.dart,
lib/features/dashboard/editor.dart,
lib/features/dashboard/editor_controller.dart,
lib/features/dashboard/controllers.dart,
lib/features/auth/sign_in_page.dart,
lib/features/auth/local_key_gate_screen.dart,
lib/features/account/accounts_page.dart,
lib/features/instructions/**,
lib/features/progress/**,
lib/features/goals/goals_page.dart,
lib/features/goals/root_pane.dart,
lib/features/goals/root_row.dart,
lib/features/goals/child_pane.dart,
lib/features/goals/child_row.dart,
lib/features/goals/drag_feedback.dart,
lib/features/goals/editor/**,
lib/services/output/**,
lib/services/code/**,
lib/services/sound/**,
lib/services/splash/**,
lib/services/chat/**,
lib/core/cosmos_safety.dart
```

Rationale by group:
- **App entry / shell:** `main.dart`, `boot_gate.dart`, `home_shell.dart`, `crash_recovery_screen.dart` — boot wiring + Material scaffolding, not unit-testable.
- **Theming / version:** `theme.dart`, `create_text_theme.dart`, `version.dart`, `firebase_options.dart` (still present from pre-migration; safe to delete in a separate PR).
- **Pure layout widgets:** all of `widgets/`, the dashboard layout shell + editor wrappers, the auth and account pages, the instructions/progress feature pages, the goals page + row widgets (the *logic* in `tree_utils.dart` and `dnd.dart` stays in scope — only the visual rows and panes are excluded).
- **Thin service shells around plugins:** `services/output/`, `services/code/`, `services/sound/`, `services/splash/`, `services/chat/` — these are wrapper-only files that exist so the rest of the app can mock at the locator. Their internals are dominated by plugin calls and `ValueNotifier` plumbing.
- **`core/cosmos_safety.dart`** — the polling-stream + navigator-key plumbing is hard to unit-test usefully; the contract is documented at the call sites.

`features/goals/dnd.dart` (single-field data carrier) is too small to bother excluding; coverage will be 0% but the LOC contribution is negligible.

---

## Approach for `get_it` in tests

```dart
// In test/helpers/locator.dart — register under the *interface* type so the
// service code's `_locator<GoalsService>()` resolves to the mock.
void registerMock<T extends Object>(T mock) {
  final locator = GetIt.instance;
  if (locator.isRegistered<T>()) locator.unregister<T>();
  locator.registerSingleton<T>(mock);
}

// In each test file:
setUpAll(() {
  registerFallbackValue(_FakeProgress());      // for any<Progress>() / captureAny<Progress>()
});

setUp(() {
  registerMock<GoalsService>(MockGoalsService());
  registerMock<ProgressService>(MockProgressService());
  // ...
  when(() => mockProgress.upsert(any<Progress>())).thenAnswer((_) async {});
  // explicit type arguments everywhere — no implicit-dynamic warnings.
});

tearDown(() async {
  await GetIt.instance.reset();
});
```

Each mock exposes real `ValueNotifier`s through stubbed getters (so the conductor's `notifier.value = x` writes work as in production).

## Definition of done for this pass

- [x] `TESTING_PLAN.md` (this file).
- [x] `test/` skeleton compiles ([test/helpers/](test/helpers/) for shared mocks; subfolders for the rest seeded with `.gitkeep`).
- [x] `pubspec.yaml` adds `mocktail: ^1.0.4` to `dev_dependencies`.
- [x] Reference test for the conductor (1A.1) — [test/services/tutor/conductor_test.dart](test/services/tutor/conductor_test.dart) — passes via `flutter test` (10/10 tests green); uses explicit `any<T>()` / `captureAny<T>()` everywhere.
- [x] `flutter test --coverage` produces `coverage/lcov.info` at the default path.
- [x] `flutter analyze lib test` is clean (`No issues found!`).
- [x] Tier 1A.2–1A.4 implemented (97 tests added, 107 total green; `flutter analyze lib test` clean).
- [ ] Tier 1B / Tier 1C tests **not yet implemented**.
- [ ] Tier 2.2 / 2.3 / 2.4 and Tier 3.2 require an architectural decision (Cosmos-injection and `py_engine_desktop` wrapper) — **paused pending your call**.
