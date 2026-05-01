# PROJECT_OVERVIEW

## 1. High-level summary

`ai_tutor_python` is a Flutter desktop application that acts as a personalised Python tutor for students. A single window combines an embedded Python code editor + runner, a chat panel that talks to an LLM-backed tutor, and a teacher-authoring side (goals, AI instructions, accounts). The tutor adapts the type of exercise (guiding question, multiple choice, explain code, complete code, write code, Socratic) to the student's progress on a tree of teacher-defined "goals", stores per-student progress and status reports in Firestore, and lets teachers edit the prompts that shape the tutor's behaviour. Built and used by a Python teacher (Yvan) for his own classroom; UI is in Dutch.

## 2. Tech stack

- **Flutter SDK constraint:** Dart `^3.9.2` (see [pubspec.yaml](pubspec.yaml)). No explicit Flutter version pin.
- **Target platforms:** Windows desktop only. `firebase_options.dart` only configures Windows; all other platforms throw `UnsupportedError`. `distribute_options.yaml` packages a Windows `.exe` installer; an in-app updater fetches a manifest from `ai-tutor-python.web.app/version.json` and re-runs the installer ([core/update_info.dart](lib/core/update_info.dart)).

### Key packages (from [pubspec.yaml](pubspec.yaml))

**State / DI**
- `get_it` — service locator; all singletons registered in [services/data_service.dart](lib/services/data_service.dart).
- `provider` — used only inside `flutter_chat_ui`'s custom-composer contract (`ComposerHeightNotifier`); not project-wide.

**Firebase**
- `firebase_core`, `firebase_auth`, `cloud_firestore` — auth + Firestore document store.

**AI / LLM**
- `dart_openai` — pinned to a fork at `https://github.com/yvanvds/openai.git`.
- `envied` (+ `envied_generator`) — obfuscates the build-time API key from `.env` into [services/tutor/env.g.dart](lib/services/tutor/env.g.dart).

**Code execution**
- `py_engine_desktop` — embedded Python interpreter for desktop. Used in [features/dashboard/output.dart](lib/features/dashboard/output.dart) to `init()`, `pipInstall(...)`, and `startScript(path)` against a temp file.

**Editor / UI**
- `flutter_code_editor`, `flutter_highlight`, `highlight` — the Python editor and its theming.
- `flutter_chat_ui`, `flutter_chat_core`, `flyer_chat_text_message`, `flyer_chat_system_message`, `flyer_chat_text_stream_message` — the chat panel.
- `multi_split_view` — resizable panels in the Dashboard.
- `lottie`, `loading_animation_widget`, `audioplayers` — confetti splash, spinner, sound effects.
- `google_fonts`.

**Misc**
- `path`, `path_provider`, `shared_preferences`, `pub_semver`, `http`, `crypto`, `uuid`, `collection`.

### Python execution approach

Embedded Python via `py_engine_desktop` (a Flutter desktop plugin). On first mount of [features/dashboard/output.dart](lib/features/dashboard/output.dart) the engine is initialised and `numpy`, `pandas`, `requests`, `matplotlib`, `scikit-learn` are pip-installed unconditionally. Run-code writes the editor buffer to `<tempDir>/student_script.py` and starts a `PythonScript`, streaming `stdout`/`stderr` lines into the output panel. There is no sandboxing — student code runs in-process with full filesystem/network access.

### AI provider

OpenAI's Responses API, called via `dart_openai` (forked) in [services/tutor/openai_connector.dart](lib/services/tutor/openai_connector.dart). The model name comes from the Firestore `config/global` document (field `Model`), defaulting to `gpt-4o`. The API key is the build-time obfuscated `Env.apiKey`; per-user override via locally-stored OpenAI key in `SharedPreferences` (see [features/auth/local_key_gate_screen.dart](lib/features/auth/local_key_gate_screen.dart)) — note: that local key is *saved* but is not actually wired into `OpenaiConnector`, which always uses `Env.apiKey`. Worth confirming whether this is intentional.

History is managed client-side (the connector passes `store: false`) with two parallel logs: `_allHistory` (across sessions) and `_sessionHistory` (current question chain). Each `sendRequest` chooses one of `includeAll | includeSession | newSession`.

## 3. Project structure

```
lib/
├── main.dart                    # App entry, Firebase init, auth gate, theme
├── boot_gate.dart               # Shift-on-startup → safe-mode reset dialog
├── home_shell.dart              # NavigationRail shell, app bar, update check
├── crash_recovery_screen.dart   # Shown on FlutterError or permission-denied
├── firebase_options.dart        # Generated; Windows-only config
├── theme.dart                   # Material 3 light/dark color schemes
├── create_text_theme.dart       # Google Fonts text-theme helper
├── version.dart                 # const String kAppVersion
│
├── core/
│   ├── chat_request_type.dart   # enum of every request kind sent to the AI
│   ├── chat_response_type.dart  # (parallel enum; declared but lightly used)
│   ├── question_difficulty.dart # easy | medium | hard
│   ├── answer_quality.dart      # wrong | partial | correct
│   ├── firestore_paths.dart     # Single source of truth for collection refs
│   ├── firestore_safety.dart    # safeFirestore wrapper, cache-reset, NavigatorKey
│   ├── update_info.dart         # In-app installer-update helpers
│   └── debounce.dart            # Generic debounce util
│
├── services/                    # All registered as get_it lazy singletons
│   ├── data_service.dart        # The locator + typed getters
│   ├── account/                 # Account model + AccountService (Firestore)
│   ├── chat/chat_service.dart   # Wraps flutter_chat InMemoryChatController
│   ├── code/code_service.dart   # Wraps flutter_code_editor CodeController
│   ├── config/                  # GlobalConfigService + LocalApiKeyStorage
│   ├── goal/                    # Goal model, GoalsService (CRUD + reparent + subtree backup)
│   ├── instructions/            # Instruction (sections map) + InstructionsService
│   ├── output/                  # OutputService + OutputController (binds to widget)
│   ├── progress/                # Progress model + ProgressService (per-user subcollection)
│   ├── role/role_service.dart   # Watches roles/{uid}, exposes ValueNotifier<bool> isTeacher
│   ├── sound/sound_service.dart # Plays goal_reached/note/question/chime mp3s
│   ├── splash/splash_service.dart # Goal-reached overlay state
│   ├── status_report/           # StatusReport model + ReportService
│   └── tutor/
│       ├── tutor_service.dart           # queryTutor() request builder + orchestrator
│       ├── conductor.dart               # Picks next question type, updates progress, adapts difficulty
│       ├── openai_connector.dart        # OpenAI Responses-API client + history
│       ├── instruction_generator.dart   # Assembles system prompt from Firestore instructions + goal context
│       ├── question_formatter.dart      # JSON-encodes user-turn payloads
│       ├── env.dart / env.g.dart        # Envied-obfuscated OPEN_AI_API_KEY
│       └── responses/                   # Typed AI-response models + dispatch
│           ├── chat_response.dart       # Sealed-ish interface + factory by "type"
│           ├── ai_response_parser.dart  # Pulls JSON map from Responses API output
│           ├── response_handlers.dart   # Per-type ResponseHandler + dispatchResponse()
│           ├── answer.dart, hint.dart, code_feedback.dart, mcq_feedback.dart,
│           │ explain_feedback.dart, socratic_feedback.dart, guiding_feedback.dart,
│           │ status_summary.dart, error_summary.dart   # Feedback/system payloads
│           └── socratic_question.dart, multiple_choice.dart, explain_code.dart,
│             complete_code.dart, write_code.dart, guiding_exercise.dart  # Exercise payloads
│
├── features/
│   ├── auth/
│   │   ├── sign_in_page.dart           # Sign in / register (email+password)
│   │   └── local_key_gate_screen.dart  # Asks for OpenAI key if mayUseGlobalKey == false
│   ├── dashboard/                      # Default page: editor + run buttons + output + chat
│   │   ├── dashboard.dart              # MultiSplitView layout
│   │   ├── editor.dart                 # CodeField bound to CodeService.controller
│   │   ├── controllers.dart            # Run/Stop/Hint/Submit/Request-exercise toolbar
│   │   ├── output.dart                 # py_engine_desktop runner + log view
│   │   └── editor_controller.dart      # Entirely commented-out, dead file
│   ├── chat/
│   │   ├── chat_widget.dart            # flutter_chat_ui Chat host, swaps composer by TutorState
│   │   ├── composer_continue_widget.dart  # "Continue" button when tutor has follow-up
│   │   └── composer_wait_widget.dart       # Spinner composer while tutor is "working"
│   ├── goals/                          # Teacher: goal-tree CRUD + reparent + DnD
│   │   ├── goals_page.dart             # Three-pane: roots / children / editor
│   │   ├── root_pane.dart, root_row.dart, child_pane.dart, child_row.dart
│   │   ├── editor/{edit_goal_panel,goal_form,parent_field}.dart
│   │   ├── dnd.dart, drag_feedback.dart, tree_utils.dart
│   ├── instructions/                   # Teacher: doc/section editor over instructions/{id}.sections{}
│   │   ├── instructions_editor_page.dart
│   │   ├── doc_list.dart, doc_header.dart, sections_list.dart,
│   │   │ section_header.dart, editor_pane.dart
│   ├── progress/                       # Student: see all goals + progress bars
│   │   ├── student_progress_list.dart
│   │   └── goal_tile.dart
│   └── account/accounts_page.dart      # Teacher: paginated table, toggle mayUseGlobalKey, delete profile
│
└── widgets/                            # Reusable building blocks
    ├── multi_value_listenable_builder.dart  # Combine N ValueListenables in one builder
    ├── goal_crumb_in_app_bar.dart           # Title-bar crumb for current goal/subgoal
    ├── goal_splash_overlay.dart             # Full-screen splash on goal completion
    ├── add_input.dart, chips_editor.dart, inline_title.dart, undo_snackbar.dart

docs/                                  # Markdown specs (data, UX, security, roadmap, etc.)
public/version.json                    # Update manifest hosted at ai-tutor-python.web.app
firestore.rules                        # Auth + role-based rules
firestore.indexes.json                 # Composite indexes for goals(parentId, order)
firebase.json                          # Hosting + emulator config
distribute_options.yaml                # flutter_distributor windows-exe job
windows/                               # Windows runner + packaging/Inno Setup config
```

## 4. Data model

All Firestore paths funnel through [core/firestore_paths.dart](lib/core/firestore_paths.dart) (`FsPaths`).

### Top-level collections

**`accounts/{uid}`** — student or teacher profile, mirrored by [services/account/account.dart](lib/services/account/account.dart).
- `uid: string` (matches doc id and Auth uid)
- `email: string`
- `firstName: string`
- `lastName: string`
- `targetGoal: string` (a goal id; appears written but not read in current flow)
- `mayUseGlobalKey: bool` — gate for using the bundled API key vs requiring a per-user local key
- `createdAt: Timestamp`, `updatedAt: Timestamp`

  **Subcollections:**
  - `accounts/{uid}/progress/{goalId}` — per-goal progress, model in [services/progress/progress.dart](lib/services/progress/progress.dart). Doc id is the goal id.
    - `progress: double` (0.0–1.0)
    - `updatedAt: Timestamp` (server timestamp)
  - `accounts/{uid}/status_reports/{goalId}` — short tutor-written notes per goal, model in [services/status_report/status_report.dart](lib/services/status_report/status_report.dart).
    - `statusReport: string`
    - `updatedAt: Timestamp`

**`goals/{goalId}`** — flat collection forming a tree via `parentId`. Model: [services/goal/goal.dart](lib/services/goal/goal.dart).
- `title: string`
- `description: string?`
- `parentId: string?` — null for roots
- `order: int` — manual ordering, spaced by 1000 in [goals_service.dart:127](lib/services/goal/goals_service.dart#L127)
- `optional: bool`
- `suggestions: string[]` — interpolated into AI instructions as `{suggestions}`
- `knownConcepts: string[]` — earlier-root concepts treated as "mastered" when prompting

**`instructions/{docId}`** — teacher-edited prompt fragments. Model: [services/instructions/instruction.dart](lib/services/instructions/instruction.dart).
- `sections: map<string, string>` — flexible bag of named text sections
- `updatedAt: Timestamp`

The `docId` matches a `ChatRequestType` enum name (e.g. `socraticQuestion`, `mcQuestion`, `submitCode`, …) plus a special `alwaysInclude` doc whose sections are appended to every system prompt.

**`roles/{uid}`** — read by [role_service.dart](lib/services/role/role_service.dart). Single field `role: string`; `'teacher'` enables teacher-only nav destinations.

**`config/global`** — single doc, model [services/config/global_config.dart](lib/services/config/global_config.dart).
- `Model: string` (OpenAI model id, e.g. `gpt-4o`)
- `ApiKey: string` (defined on the model but not used by `OpenaiConnector` — confirm whether this is dead).

### Local persistence

- `SharedPreferences` key `local_api_key`: a per-device OpenAI key set via the `LocalKeyGateScreen` ([services/config/local_api_key_storage.dart](lib/services/config/local_api_key_storage.dart)).

### Local DTOs that mirror Firestore

`Account`, `Goal`, `Progress`, `StatusReport`, `Instruction`, `GlobalConfig` — each provides `fromDoc/fromMap` and `toMap` (or equivalent) and is the only thing the rest of the app sees. `safeFirestore` ([core/firestore_safety.dart](lib/core/firestore_safety.dart)) wraps all reads/writes to push `permission-denied` to a `CrashRecoveryScreen`.

## 5. Core features & their entry points

### Python code panel (editor + execution)
- Editor: [features/dashboard/editor.dart](lib/features/dashboard/editor.dart) renders `CodeField` bound to the singleton `CodeService.controller` ([services/code/code_service.dart](lib/services/code/code_service.dart)). `CodeService.setText(...)` is how the tutor pushes new starter code.
- Toolbar (Run/Stop/Hint/Submit/Request-exercise): [features/dashboard/controllers.dart](lib/features/dashboard/controllers.dart).
- Runner: [features/dashboard/output.dart](lib/features/dashboard/output.dart) — initialises `py_engine_desktop`, pip-installs a fixed set of packages on first mount, writes code to `student_script.py`, and tails `stdout`/`stderr`. The runner registers `_runCode`/`_forceStop` callbacks on `OutputService.controller.bind(...)` so other widgets call `DataService.output.run(code)` without knowing about the widget tree.

### AI chat panel
- [features/chat/chat_widget.dart](lib/features/chat/chat_widget.dart) hosts `flutter_chat_ui`'s `Chat`, bound to `ChatService.controller`. Composer swaps based on `TutorService.state` (`idle | working | hasFollowUp`) between the default composer, [composer_wait_widget.dart](lib/features/chat/composer_wait_widget.dart) (spinner), and [composer_continue_widget.dart](lib/features/chat/composer_continue_widget.dart) (Continue button). Student-typed messages route through `TutorService.handleStudentMessage(...)`.

### Student progression / level system
- Tile list view: [features/progress/student_progress_list.dart](lib/features/progress/student_progress_list.dart) + [features/progress/goal_tile.dart](lib/features/progress/goal_tile.dart).
- Conductor logic: [services/tutor/conductor.dart](lib/services/tutor/conductor.dart) — picks question types by progress band (<0.2 guiding, <0.4 mc/explain, <0.7 complete/socratic, ≥0.7 write/socratic), applies an `AnswerQuality`-based delta scaled by question type & difficulty, adapts difficulty over a 5-answer window, and recomputes the parent root's progress as the average of its children. Goal completion clears selection, advances to the next incomplete root/subgoal, fires sound + splash.
- Per-user persistence in `accounts/{uid}/progress/{goalId}` via [services/progress/progress_service.dart](lib/services/progress/progress_service.dart).

### Teacher dashboard

- Goal authoring: [features/goals/goals_page.dart](lib/features/goals/goals_page.dart) — three-pane layout (roots / children / editor) with drag-and-drop reparent and reorder ([dnd.dart](lib/features/goals/dnd.dart), [tree_utils.dart](lib/features/goals/tree_utils.dart)). Subtree backup/restore for safe deletes lives in [goals_service.dart](lib/services/goal/goals_service.dart) (`backupSubtree` / `deleteSubtree` / `restoreSubtree`).
- AI-instruction authoring: [features/instructions/instructions_editor_page.dart](lib/features/instructions/instructions_editor_page.dart) — left pane lists `instructions/{docId}` documents, middle pane lists named sections, right pane is a markdown `CodeField` editor. Save persists the whole `sections` map back to Firestore.
- Account admin: [features/account/accounts_page.dart](lib/features/account/accounts_page.dart) — paginated `DataTable`, search, toggle `mayUseGlobalKey`, delete account profile (does NOT delete the FirebaseAuth user).

### Authentication
- Email + password, Firebase Auth.
- [features/auth/sign_in_page.dart](lib/features/auth/sign_in_page.dart) is a single page that toggles into a register mode (extra first/last-name fields). On register it calls `AccountService.upsertAccount(...)` to seed the Firestore profile.
- [main.dart](lib/main.dart) wraps `MaterialApp.home` in a `StreamBuilder<User?>` + the global-key gate: signed-in users without `mayUseGlobalKey == true` and without a local key are routed to [LocalKeyGateScreen](lib/features/auth/local_key_gate_screen.dart).
- [boot_gate.dart](lib/boot_gate.dart) — holding Shift at startup opens a Safe Mode dialog that calls `resetAuthAndCacheAndExit()` ([core/firestore_safety.dart](lib/core/firestore_safety.dart)) to sign out, terminate Firestore, and delete `%LOCALAPPDATA%\firestore`/`firebase`/etc.

## 6. State management & data flow

### Pattern

`get_it` for DI; `ValueNotifier` + `ValueListenableBuilder` for reactivity. A custom [widgets/multi_value_listenable_builder.dart](lib/widgets/multi_value_listenable_builder.dart) combines several notifiers in a single builder. There is no Riverpod, Bloc, or `provider` outside the `flutter_chat_ui` composer contract (which requires reading a `ComposerHeightNotifier` injected by the package itself).

All services are registered as lazy singletons in [services/data_service.dart](lib/services/data_service.dart) and accessed through static getters on `DataService` (e.g. `DataService.tutor`, `DataService.goals`).

Notable `ValueNotifier`s:
- `AccountService.currentAccount` (the signed-in profile)
- `RoleService.isTeacher`
- `GlobalConfigService.config` + `LocalApiKeyStorage.isKeyPresent`
- `GoalsService.{selected,preferred,editorSelected}{Root,Child}Goal` — six notifiers tracking the active goal in different contexts
- `ProgressService.currentProgress` (the active subgoal)
- `TutorService.state` (`idle | working | hasFollowUp`)
- `SplashService.state` (goal-reached overlay payload)

### Student progress: UI → Firebase

1. Student answers a question via the chat composer.
2. `ChatWidget.onMessageSend` → `TutorService.handleStudentMessage(text)` routes to the appropriate `ChatRequestType` based on `_currentExerciseType`.
3. `TutorService.queryTutor(...)` builds an `input` JSON via `QuestionFormatter`, fetches instructions via `InstructionGenerator.generateInstructions(type)`, and calls `OpenaiConnector.sendRequest(...)`.
4. The returned response is parsed by `AIResponseParser.parse(...)` into a typed `ChatResponse`, then dispatched by `dispatchResponse(parsed, ctx)` ([services/tutor/responses/response_handlers.dart](lib/services/tutor/responses/response_handlers.dart)) to the matching `*Handler`.
5. Feedback handlers (`CodeFeedbackHandler`, `McqFeedbackHandler`, `SocraticFeedbackHandler`, `ExplainFeedbackHandler`) call `Conductor.updateProgress(quality)`, which:
   - Computes a delta scaled by question type, difficulty, and hint usage.
   - `clamp`s to [0,1] and writes via `ProgressService.upsert(Progress(goalID, progress))` to `accounts/{uid}/progress/{goalId}`.
   - Recomputes the root goal's progress as the average of its children and upserts that too.
   - On crossing 1.0, plays the goal-reached splash + sound and advances to the next incomplete subgoal via `_setTargetGoal()`.
6. `StatusSummary` responses route through `ReportService.updateForCurrentChildGoal(...)` and persist to `accounts/{uid}/status_reports/{goalId}`.

### Teacher-authored AI instructions → runtime prompt

1. Teacher edits `instructions/{docId}.sections{key: text}` in [InstructionsEditorPage](lib/features/instructions/instructions_editor_page.dart). Each `docId` is named after a `ChatRequestType` (e.g. `socraticQuestion`, `submitCode`); a special `alwaysInclude` doc holds shared instructions.
2. On every tutor request, [InstructionGenerator.generateInstructions(type)](lib/services/tutor/instruction_generator.dart) loads all instruction docs once (`InstructionsService.getAll()`), finds the doc whose id matches the `ChatRequestType` name, concatenates its sections, then appends the `alwaysInclude` sections at the end.
3. Each section is run through `_replaceTags(...)` which substitutes `{goal}`, `{subgoal}`, `{suggestions}`, and `{known concepts}` (case-insensitive, whitespace-tolerant) using the currently selected (or preferred) root/child goal and the concepts from all earlier root goals (computed in `_getMasteredConcepts`).
4. The assembled string is passed to `OpenaiConnector.sendRequest` as `instructions`. The user-turn payload is a JSON object built by [QuestionFormatter](lib/services/tutor/question_formatter.dart), e.g. `{"request_type":"socratic_question","difficulty":"medium"}`.
5. The connector keeps two history lists (`_allHistory`, `_sessionHistory`) of `{role, content}` items and includes one of them per call based on `PreviousInputs.includeAll | includeSession | newSession`. `instructions` is re-sent on every call (Responses API does not retain it). `store: false` so OpenAI does not retain state server-side.

## 7. Known limitations / TODOs / rough edges

No `// TODO` / `// FIXME` markers exist in `lib/`. Notable rough edges visible in the current code:

- **Local API key not used.** `LocalApiKeyStorage.saveKey(...)` writes to `SharedPreferences`, the gate screen requires it, but `OpenaiConnector._apiKey = Env.apiKey` always uses the build-time obfuscated key. Either the gate is purely informational or the wiring is incomplete.
- **`config/global` ApiKey field unused.** `GlobalConfig.apiKey` is parsed but never read by `OpenaiConnector` either. Only `GlobalConfig.model` is consumed.
- **Dead file.** [features/dashboard/editor_controller.dart](lib/features/dashboard/editor_controller.dart) is entirely commented out.
- **Commented-out fallback in [crash_recovery_screen.dart:41-47](lib/crash_recovery_screen.dart#L41-L47)** kept "in case".
- **Stream error handler is intentionally a no-op.** [firestore_safety.dart:89-97](lib/core/firestore_safety.dart#L89-L97) only `debugPrint`s on `permission-denied`; the comment notes that this should eventually call `resetAuthAndCacheAndExit()` once the stream-recovery flow is in place.
- **`pip install` runs every time the Output widget is mounted.** [output.dart:59-70](lib/features/dashboard/output.dart#L59-L70) unconditionally pip-installs `numpy`, `pandas`, `requests`, `matplotlib`, `scikit-learn`. Likely a no-op after the first run, but adds startup latency.
- **No sandboxing of student code.** The script runs in-process via `py_engine_desktop` with full host access.
- **`AccountService.dispose()` is never called.** Service is a `lazySingleton`; its auth subscription lives for the app's lifetime, which is fine but the `dispose()` is dead.
- **`_SwitchMap` extension** is reimplemented inside [account_service.dart](lib/services/account/account_service.dart) to avoid an `rxdart` dependency — duplicated logic could move to a shared util if used elsewhere.
- **Hard-coded admin UID** in [firestore.rules:12](firestore.rules#L12).
- **Windows-only.** No iOS/Android/macOS/Linux/Web Firebase configuration; web is not supported by `py_engine_desktop` anyway.
- **All UI text is Dutch and hard-coded** throughout services and widgets; no i18n layer.
- **`ChatRequestType.completeCodeQuestion` flow.** `CompleteCodeHandler` does set `_currentExerciseType` (so follow-up student replies route correctly), but worth re-verifying — earlier audit notes flagged the inverse and the file has been refactored since.
- **`dart_openai` is pinned to a personal fork** (`https://github.com/yvanvds/openai.git`) — any upstream changes need to be merged manually.
- **No automated tests.** `test/` directory is absent; only `flutter_test` is a dev-dep.
- **Background context.** Memory notes from a 2026-05-01 audit flagged a god-object `TutorService` (~483 lines) and a `lib/services/timeline/` of commented-out code; both have already been cleaned up. `TutorService` is now ~280 lines and dispatches via a per-type strategy in [response_handlers.dart](lib/services/tutor/responses/response_handlers.dart). The audit note in `memory/code_quality_audit.md` is partially stale.

## 8. Build & run

### Required config files

- **`.env`** at the repo root with `OPEN_AI_API_KEY=sk-...`. Consumed at build time by `envied` (see [services/tutor/env.dart](lib/services/tutor/env.dart)) and codegen'd into `env.g.dart`. Not committed.
- **`lib/firebase_options.dart`** — already committed (Windows config only). To re-target a different Firebase project, run `flutterfire configure`.
- **`firestore.rules`** + **`firestore.indexes.json`** — deploy via `firebase deploy --only firestore`.

### Commands

```bash
# Get dependencies
flutter pub get

# Generate envied + any other build-runner outputs (run after editing .env or @Envied fields)
dart run build_runner build --delete-conflicting-outputs

# Run on Windows desktop (only supported platform)
flutter run -d windows

# Static analysis
flutter analyze

# Tests (none currently exist, but the dependency is configured)
flutter test

# Build a release Windows executable
flutter build windows --release

# Package as an installer (.exe via Inno Setup) — see distribute_options.yaml + windows/packaging/
flutter pub global activate flutter_distributor
flutter_distributor release --name=windows
```

### Firebase emulator (configured but not auto-used)

`firebase.json` declares Auth (port 9099) and Firestore (port 8080) emulators; the app does not currently call `useFirestoreEmulator` / `useAuthEmulator` on startup. Wire those in if you want to develop against the emulators.

### Update channel

A release build hosts `public/version.json` at `https://ai-tutor-python.web.app/version.json` (deployed via `firebase deploy --only hosting`). On launch, [home_shell.dart:151-192](lib/home_shell.dart#L151-L192) fetches that manifest and, if newer, downloads `python_teacher_install.exe`, verifies SHA-256, and runs it `/VERYSILENT /NORESTART` before exiting.
