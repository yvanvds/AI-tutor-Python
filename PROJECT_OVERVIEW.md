<!-- META
last_updated_commit: f71bc857a4bdd4cc1a7a06577dae83d808d72520
last_updated_at: 2026-05-03
-->

# PROJECT_OVERVIEW

## 1. High-level summary

`ai_tutor_python` is a Flutter desktop application that acts as a personalised Python tutor for students. A single window combines an embedded Python code editor + runner, a chat panel that talks to an LLM-backed tutor, and a teacher-authoring side (goals, AI instructions, accounts). The tutor adapts the type of exercise (guiding question, multiple choice, explain code, complete code, write code, Socratic) to the student's progress on a tree of teacher-defined "goals", stores per-student progress and status reports in Azure Cosmos DB, and lets teachers edit the prompts that shape the tutor's behaviour. Identity is tied to the school's Microsoft Entra tenant (formerly Azure AD). Built and used by a Python teacher (Yvan) for his own classroom; UI is in Dutch.

## 2. Tech stack

- **Flutter SDK constraint:** Dart `^3.10.1` (see [pubspec.yaml](pubspec.yaml)). No explicit Flutter version pin.
- **Target platforms:** Windows desktop only. `distribute_options.yaml` packages a Windows `.exe` installer; an in-app updater fetches a manifest from `ai-tutor-python.web.app/version.json` (Firebase Hosting — the only piece of Firebase still in play) and re-runs the installer ([core/update_info.dart](lib/core/update_info.dart)).

### Key packages (from [pubspec.yaml](pubspec.yaml))

**State / DI**
- `flutter_riverpod` — DI and reactivity; services are declared as `Provider` / `NotifierProvider` singletons and consumed via `ref.watch` / `ref.read` in `ConsumerWidget` / `ConsumerState`. Replaced the old `get_it` + `DataService` static-getter pattern.
- `provider` — used only inside `flutter_chat_ui`'s custom-composer contract (`ComposerHeightNotifier`); not project-wide.

**Backend**
- `http` + `crypto` — used by the hand-rolled [core/cosmos_client.dart](lib/core/cosmos_client.dart) to talk to Azure Cosmos DB's REST API (no third-party Cosmos SDK).
- `url_launcher` — opens the system browser for the Microsoft Entra OAuth flow (see auth section).
- `shared_preferences` — persists the Entra token bundle and the per-user OpenAI key.

**AI / LLM**
- `dart_openai` — pinned to a fork at `https://github.com/yvanvds/openai.git`. The connector uses `chat.completions` (`OpenAI.instance.chat.create` / `createStream`) — the Responses-API plumbing was replaced by streaming chat completions plus a hand-rolled `<TEXT>...</TEXT><META>{...}</META>` envelope (see [services/tutor/responses/envelope_assembler.dart](lib/services/tutor/responses/envelope_assembler.dart)).
- `envied` (+ `envied_generator`) — obfuscates `OPEN_AI_API_KEY` and `COSMOS_KEY` from `.env` into [services/tutor/env.g.dart](lib/services/tutor/env.g.dart) and [services/config/azure_config.g.dart](lib/services/config/azure_config.g.dart).

**Code execution**
- `py_engine_desktop` — embedded Python interpreter for desktop. Used in [features/dashboard/output.dart](lib/features/dashboard/output.dart) to `init()`, `pipInstall(...)`, and `startScript(path)` against a temp file.

**Editor / UI**
- `flutter_code_editor`, `flutter_highlight`, `highlight` — the Python editor and its theming.
- `flutter_chat_ui`, `flutter_chat_core`, `flyer_chat_text_message`, `flyer_chat_system_message`, `flyer_chat_text_stream_message` — the chat panel; the stream-message variant renders the in-flight tutor reply while it's still arriving.
- `fl_chart` — line charts in the teacher's per-student detail drawer.
- `multi_split_view` — resizable panels in the Dashboard.
- `lottie`, `loading_animation_widget`, `audioplayers` — confetti splash, spinner, sound effects.
- `google_fonts`, `file_picker`.

**Misc**
- `path`, `path_provider`, `pub_semver`, `uuid`, `collection`.

**Dev**
- `flutter_test`, `mocktail`, `fake_async`, `flutter_lints`, `build_runner`.

### Python execution approach

Python runs via `py_runner`, a local Flutter package at [packages/py_runner/](packages/py_runner/). `PyRunner` (configured with `InstallerPyHostLocator`) manages a long-lived Python host subprocess (`host.py`). [features/dashboard/output.dart](lib/features/dashboard/output.dart) calls `_output.run(code)` on `OutputService`, which starts the host if needed, submits the code string, and streams `stdout`/`stderr` lines into the output panel via `ValueNotifier<List<OutputLine>>`. Interactive `input()` calls are surfaced as `InputRequest` objects on `pendingInputRequest` and rendered as an inline text field in the output panel. There is no sandboxing — student code runs in a child process with full filesystem/network access.

### AI provider

OpenAI's chat.completions API, called via `dart_openai` (forked) in [services/tutor/openai_connector.dart](lib/services/tutor/openai_connector.dart). Both a non-streaming `sendRequest` and a streaming `sendRequestStream` (emitting `StreamTextDelta` / `StreamCompleted` / `StreamFailed` chunks) are exposed; the tutor service prefers streaming for student-facing turns and falls back to non-streaming for `status_summary` (which has no visible message). The connector also carries an opt-in `reasoning_effort` (currently hard-coded to `'low'`) for gpt-5 / o-series models. The model name comes from the Cosmos `config/global` doc (field `Model`), defaulting to `gpt-4o`. The API key is the build-time obfuscated `Env.apiKey`; per-user override via locally-stored OpenAI key in `SharedPreferences` (see [features/auth/local_key_gate_screen.dart](lib/features/auth/local_key_gate_screen.dart)) — note: that local key is *saved* but is not actually wired into `OpenaiConnector`, which always uses `Env.apiKey`. Worth confirming whether this is intentional.

History is managed client-side with two parallel logs capped at 50 entries each: `_allHistory` (across sessions) and `_sessionHistory` (current question chain). Each `sendRequest` chooses one of `includeAll | includeSession | newSession`. `instructions` is passed as a system message on every call; the user-turn content is a JSON string built by `QuestionFormatter`.

The model is required to wrap every reply in a `<TEXT>...</TEXT><META>{...}</META>` envelope (`<TEXT>` carries the student-facing markdown, `<META>` carries the typed JSON payload — type, options, quality, suspected_concepts, etc.). [EnvelopeAssembler](lib/services/tutor/responses/envelope_assembler.dart) parses this incrementally so the streaming path can flush visible text before `<META>` arrives. The legacy JSON-only output path is still supported as a fallback when an older model ignores the envelope contract (handled in [ai_response_parser.dart](lib/services/tutor/responses/ai_response_parser.dart)).

## 3. Project structure

```
lib/
├── main.dart                    # App entry, silent token refresh, auth + key gate
├── home_shell.dart              # NavigationRail shell, sign-out, update check
├── crash_recovery_screen.dart   # Shown on FlutterError or Cosmos auth failure
├── theme.dart                   # Material 3 light/dark color schemes
├── create_text_theme.dart       # Google Fonts text-theme helper
├── version.dart                 # const String kAppVersion
│
├── core/
│   ├── chat_request_type.dart   # enum of every request kind sent to the AI
│   ├── chat_response_type.dart  # (parallel enum; declared but lightly used)
│   ├── question_difficulty.dart # easy | medium | hard
│   ├── answer_quality.dart      # wrong | partial | correct
│   ├── cosmos_client.dart       # Hand-rolled Cosmos REST client + BatchOperation
│   ├── cosmos_paths.dart        # Single source of truth for container handles
│   ├── cosmos_doc_id.dart       # Composite id conventions ({uid}_{goalId}, progress_history ids, …)
│   ├── cosmos_safety.dart       # safeCosmos / safeCosmosStream / pollingStream
│   ├── update_info.dart         # In-app installer-update helpers
│   └── debounce.dart            # Generic debounce util
│
├── services/                    # All declared as Riverpod providers
│   ├── auth/auth_service.dart   # Entra OAuth (PKCE + loopback) + token cache
│   ├── account/                 # Account model + AccountService (Cosmos)
│   ├── chat/chat_service.dart   # Wraps flutter_chat InMemoryChatController
│   ├── code/code_service.dart   # Wraps flutter_code_editor CodeController
│   ├── config/                  # GlobalConfigService, AzureConfig (envied),
│   │                            #   LocalApiKeyStorage
│   ├── debug/debug_session_recorder.dart  # Circular buffer (200 turns) of TurnRecord events for live debug export
│   ├── goal/                    # Goal model, GoalsService, SubtreeBackup
│   │   ├── goal_selection_notifier.dart # GoalSelectionState + GoalSelectionNotifier (NotifierProvider replacing 6 ValueNotifiers)
│   ├── instructions/            # Instruction (sections map) + InstructionsService
│   ├── output/                  # OutputService + OutputController (binds widget)
│   ├── progress/                # Progress model + ProgressService + helpers
│   │   ├── progress.dart                # Per-(uid, goalId) row: progress, difficulty,
│   │   │                                #   recentAnswers, lastSessionAt, recentConceptAttributions
│   │   ├── progress_service.dart        # Reads/writes `progress` + best-effort `progress_history` samples
│   │   ├── progress_sample.dart         # One row of `progress_history` (time series)
│   │   ├── concept_attribution.dart     # AI-emitted suspected-concept tag w/ at + quality
│   │   └── teacher_signals.dart         # Pure helpers: StudentStatus, isStruggling, rankConceptAttributions
│   │                            # (RoleService removed; teacher flag read directly from authServiceProvider)
│   ├── sound/sound_service.dart # Plays goal_reached/note/question/chime mp3s
│   ├── splash/splash_service.dart # Goal-reached overlay state
│   ├── status_report/           # StatusReport model + ReportService
│   └── tutor/
│       ├── tutor_service.dart           # Public API + request orchestration; streaming-first
│       ├── conductor.dart               # Mastery-streak progression, warm-up, diagnostic, difficulty
│       ├── openai_connector.dart        # chat.completions client (sync + streaming) + history
│       ├── instruction_generator.dart   # Assembles system prompt + envelope contract
│       ├── question_formatter.dart      # JSON-encodes user-turn payloads
│       ├── env.dart / env.g.dart        # Envied-obfuscated OPEN_AI_API_KEY
│       └── responses/                   # Typed AI-response models + dispatch
│           ├── chat_response.dart       # Sealed-ish interface + factory by "type"
│           ├── ai_response_parser.dart  # Envelope-first parser, legacy-JSON fallback
│           ├── envelope_assembler.dart  # Incremental <TEXT>/<META> parser for streaming
│           ├── suspected_concepts.dart  # Shared parser for the optional META field
│           ├── response_handlers.dart   # Per-type ResponseHandler + dispatchResponse()
│           ├── answer.dart, hint.dart, code_feedback.dart, mcq_feedback.dart,
│           │ explain_feedback.dart, socratic_feedback.dart, guiding_feedback.dart,
│           │ status_summary.dart, error_summary.dart   # Feedback/system payloads
│           └── socratic_question.dart, multiple_choice.dart, explain_code.dart,
│             complete_code.dart, write_code.dart, guiding_exercise.dart  # Exercises
│
├── features/
│   ├── auth/
│   │   ├── sign_in_page.dart           # Single "sign in with school account" button
│   │   └── local_key_gate_screen.dart  # Asks for OpenAI key if mayUseGlobalKey == false
│   ├── dashboard/                      # Default page: editor + run buttons + output + chat
│   │   ├── dashboard.dart              # MultiSplitView layout
│   │   ├── editor.dart                 # CodeField bound to CodeService.controller
│   │   ├── controllers.dart            # Run/Stop/Hint/Submit/Request-exercise toolbar
│   │   ├── output.dart                 # py_runner-backed runner + log view + interactive input
│   │   ├── debug_dialog.dart           # Teacher-only dialog to inspect/export DebugSessionRecorder buffer
│   │   └── editor_controller.dart      # Entirely commented-out, dead file
│   ├── chat/
│   │   ├── chat_widget.dart            # flutter_chat_ui Chat host, swaps composer by TutorState
│   │   ├── composer_continue_widget.dart  # "Continue" button when tutor has follow-up
│   │   ├── composer_wait_widget.dart       # Spinner composer while tutor is "working"
│   │   ├── composer_mcq_wait_widget.dart   # Disabled MCQ composer while waiting for response
│   │   └── mcq_options_widget.dart         # Clickable MCQ option buttons (replaces free-text for multiple-choice questions)
│   ├── goals/                          # Teacher: goal-tree CRUD + reparent + DnD
│   │   ├── goals_page.dart             # Three-pane: roots / children / editor
│   │   ├── root_pane.dart, root_row.dart, child_pane.dart, child_row.dart
│   │   ├── editor/{edit_goal_panel,goal_form,parent_field}.dart
│   │   ├── dnd.dart, drag_feedback.dart, tree_utils.dart
│   ├── instructions/                   # Teacher: doc/section editor over instructions/{id}.sections{}
│   │   ├── instructions_editor_page.dart   # + Markdown import/export via file_picker
│   │   ├── doc_list.dart, doc_header.dart, sections_list.dart,
│   │   │ section_header.dart, editor_pane.dart
│   ├── progress/                       # Student & teacher peek: all goals + progress bars
│   │   ├── student_progress_list.dart  # Optional `uid` arg flips into read-only/teacher mode
│   │   └── goal_tile.dart              # `readOnly` mode reveals difficulty + recentAnswers strip
│   └── account/
│       ├── accounts_page.dart          # Teacher: paginated table w/ status dot, drawer trigger
│       └── detail/                     # Right-hand peek drawer for one student
│           ├── student_detail_drawer.dart    # Drawer shell, streams progress/goals
│           ├── student_status_summary.dart   # Status dot + "lijkt te haperen op …" line
│           ├── status_reports_section.dart   # Per-subgoal AI status reports, collapsible
│           └── progress_history_charts.dart  # Per-root-goal `fl_chart` line charts (30-day window)
│
└── widgets/                            # Reusable building blocks
    ├── goal_crumb_in_app_bar.dart           # Title-bar crumb for current goal/subgoal
    ├── goal_splash_overlay.dart             # Full-screen splash on goal completion
    ├── add_input.dart, chips_editor.dart, inline_title.dart

packages/py_runner/                    # Local Flutter package — PyRunner, InstallerPyHostLocator, RunHandle, InputRequest
test/                                  # mocktail-based unit tests (conductor, tutor_service, progress, accounts, etc.)
public/version.json                    # Update manifest hosted at ai-tutor-python.web.app
firebase.json                          # Firebase Hosting config (no Firestore/Auth)
distribute_options.yaml                # flutter_distributor windows-exe job
windows/                               # Windows runner + packaging/Inno Setup config
TODO.md, TESTING_PLAN.md               # In-tree planning docs (worth reading)
```

## 4. Data model

All Cosmos container handles funnel through [core/cosmos_paths.dart](lib/core/cosmos_paths.dart). The database is `python-tutor`. Composite doc ids are minted in [core/cosmos_doc_id.dart](lib/core/cosmos_doc_id.dart).

### Containers (per-user partition: `/uid`)

**`accounts/{uid}`** — student or teacher profile. One doc per user, doc id == partition key == Entra Object ID. Model: [services/account/account.dart](lib/services/account/account.dart).
- `id: string`, `uid: string`
- `email: string`
- `firstName: string`, `lastName: string`
- `targetGoal: string` (a goal id; written but not currently read by selection logic)
- `mayUseGlobalKey: bool` — gate for using the bundled API key vs requiring a per-user local key
- `createdAt: string` (ISO 8601), `updatedAt: string` (ISO 8601)

**`progress`** — flattened from the old subcollection. Doc id `${uid}_${goalId}`, partition key `uid`. Model: [services/progress/progress.dart](lib/services/progress/progress.dart).
- `id: string`, `uid: string`, `goalId: string`
- `progress: double` (0.0–1.0)
- `updatedAt: string`, `lastSessionAt: string` — both refreshed on every write
- `difficulty: string` — last calibrated difficulty (`easy | medium | hard`); restored on subgoal resume
- `recentAnswers: string[]` — rolling answer-quality window (length ≤ 5, oldest-first)
- `recentConceptAttributions: object[]` — last ≤ 20 AI-emitted suspected-concept tags `{concept, at, quality}` (purely for teacher signals; nothing reads this in the student loop)

**`progress_history`** — append-only time series. Doc id is an ISO-timestamp + random suffix from [CosmosDocId.progressHistory](lib/core/cosmos_doc_id.dart); partition key `uid`. Model: [services/progress/progress_sample.dart](lib/services/progress/progress_sample.dart). Written best-effort by `ProgressService.upsert` whenever the persisted progress value actually changes (so the root-goal recompute writes are skipped). Drives the per-root-goal line charts in the teacher detail drawer.
- `id: string`, `uid: string`, `goalId: string`
- `progress: double`, `difficulty: string`
- `quality: string?` — optional `wrong | partial | correct`
- `isWarmUp: bool`, `at: string` (ISO 8601)

**`status_reports`** — flattened similarly. Doc id `${uid}_${goalId}`, partition key `uid`. Model: [services/status_report/status_report.dart](lib/services/status_report/status_report.dart).
- `id: string`, `uid: string`, `goalID: string`
- `statusReport: string`
- `updatedAt: string`

### Containers (single-partition: `/type`)

The tree of goals and the prompt fragments are tiny shared resources, so they live in one logical partition keyed by a constant `type` field (see `CosmosPartitions`).

**`goals`** — flat collection forming a tree via `parentId`. `type: "goal"`. Model: [services/goal/goal.dart](lib/services/goal/goal.dart).
- `id: string`, `type: "goal"`
- `title: string`, `description: string?`
- `parentId: string?` — null for roots
- `order: int` — manual ordering, spaced by 1000 (and rewritten transactionally on reorder; see [goals_service.dart#L147](lib/services/goal/goals_service.dart#L147))
- `optional: bool`
- `suggestions: string[]` — interpolated into AI instructions as `{suggestions}`
- `knownConcepts: string[]` — earlier-root concepts treated as "mastered" when prompting

**`instructions`** — teacher-edited prompt fragments. `type: "instruction"`. Model: [services/instructions/instruction.dart](lib/services/instructions/instruction.dart).
- `id: string` (matches a `ChatRequestType` enum name, e.g. `socraticQuestion`, `submitCode`, plus a special `alwaysInclude`)
- `sections: map<string, string>` — flexible bag of named text sections
- `updatedAt: string`

**`config`** — single doc with id `global`. `type: "config"`. Model: [services/config/global_config.dart](lib/services/config/global_config.dart).
- `Model: string` (OpenAI model id, e.g. `gpt-4o`)
- `ApiKey: string` (parsed but not used by `OpenaiConnector` — see TODOs)

### Identity & roles

There is no `roles/{uid}` container. The teacher flag rides on the Entra access token's `roles` app-role claim and is decoded once in [auth_service.dart#L386-L390](lib/services/auth/auth_service.dart#L386-L390). [RoleService](lib/services/role/role_service.dart) just mirrors `AuthService.currentUser.isTeacher` into a `ValueNotifier<bool>` so feature widgets keep using `DataService.role.isTeacher`.

### Local persistence

- **`shared_preferences` key `azure_auth_tokens_v1`** — JSON bundle of `{access_token, refresh_token, id_token, access_token_expiry}` written by [auth_service.dart](lib/services/auth/auth_service.dart). The school's stance is "students tampering is OK" (see TODO.md), so no OS keychain.
- **`shared_preferences` key `local_api_key`** — per-device OpenAI key set via [LocalKeyGateScreen](lib/features/auth/local_key_gate_screen.dart) ([services/config/local_api_key_storage.dart](lib/services/config/local_api_key_storage.dart)).

## 5. Core features & their entry points

### Authentication (Microsoft Entra ID, OAuth 2.0 + PKCE)

The old Firebase Auth flow is gone. Identity is now hand-rolled against Entra because the Microsoft-supplied Flutter packages (`aad_oauth`) wrap `webview_flutter`, which has no Windows desktop platform implementation. See [services/auth/auth_service.dart](lib/services/auth/auth_service.dart) for the full flow:

1. `AuthService.signIn()` generates a PKCE verifier/challenge and a random `state`, binds a `dart:io` `HttpServer` on a random localhost port, opens the Entra `/authorize` endpoint in the system browser via `url_launcher`.
2. Entra redirects to `http://localhost:<port>/?code=…&state=…`. The local server captures the request, returns a small "you can close this tab" HTML page, and surfaces the code.
3. POST to `/token` with the code + verifier → `{access_token, refresh_token, id_token, expires_in}`.
4. Persist the bundle in `shared_preferences`, decode the id_token JWT to populate `currentUser` (ValueNotifier<AccountIdentity?>) with `oid` (partition key), display name, email, given/family name, and an `isTeacher` flag derived from the `roles` claim.
5. On startup, [main.dart](lib/main.dart) calls `tryAcquireTokenSilent()` *before the first frame* so a returning user lands on `HomeShell` instead of flashing `SignInPage`. Silent refresh uses the stored refresh_token; on failure the cache is cleared and the user goes back to sign-in.

The Entra app registration must declare `http://localhost` (no port) under "Mobile and desktop applications"; Microsoft accepts any matching loopback port (see comment in [auth_service.dart#L24-L30](lib/services/auth/auth_service.dart#L24-L30)).

### Python code panel (editor + execution)

- Editor: [features/dashboard/editor.dart](lib/features/dashboard/editor.dart) renders `CodeField` bound to the singleton `CodeService.controller` ([services/code/code_service.dart](lib/services/code/code_service.dart)). `CodeService.setText(...)` is how the tutor pushes new starter code.
- Toolbar (Run/Stop/Hint/Submit/Request-exercise): [features/dashboard/controllers.dart](lib/features/dashboard/controllers.dart).
- Runner: [features/dashboard/output.dart](lib/features/dashboard/output.dart) — reads `outputServiceProvider` via Riverpod `ref`. `OutputService.run(code)` starts the `PyRunner` host if not yet running, submits code, and streams lines into `lines` (`ValueNotifier<List<OutputLine>>`). Interactive `input()` prompts arrive as `InputRequest` on `pendingInputRequest` and are rendered as a live text-field row; the student's answer is forwarded back via `OutputService.submitInput(value)`. Other widgets that need to trigger a run call `ref.read(outputServiceProvider).run(code)` directly.

### AI chat panel

- [features/chat/chat_widget.dart](lib/features/chat/chat_widget.dart) hosts `flutter_chat_ui`'s `Chat`, bound to `ChatService.controller`. Composer swaps based on `TutorService.state` (`idle | working | hasFollowUp`) between the default composer, [composer_wait_widget.dart](lib/features/chat/composer_wait_widget.dart) (spinner), and [composer_continue_widget.dart](lib/features/chat/composer_continue_widget.dart) (Continue button). Student-typed messages route through `TutorService.handleStudentMessage(...)`.
- Streaming render: in-flight tutor replies use a `TextStreamMessage` placeholder (`flyer_chat_text_stream_message`). [ChatService](lib/services/chat/chat_service.dart) exposes a `streamState` `ValueNotifier` that the message builder watches; `startStream` / `updateStream` / `completeStream` / `failStream` drive it. On completion the placeholder is swapped for a regular `TextMessage` (or removed if no visible text was emitted).

### Student progression / level system

- Tile list view: [features/progress/student_progress_list.dart](lib/features/progress/student_progress_list.dart) + [features/progress/goal_tile.dart](lib/features/progress/goal_tile.dart). Both accept an optional `uid`/`readOnly` to render the same widgets in the teacher detail drawer with action buttons hidden and per-subgoal teacher annotations (calibrated difficulty pill + colour-coded recent-answers dots) revealed.
- Conductor logic: [services/tutor/conductor.dart](lib/services/tutor/conductor.dart) — runs three phases per subgoal: **guiding** (single `guidingQuestion` request whose `understanding` accumulates to ≥ 0.8 to advance), **warm-up** (1–3 questions on resumed sessions where progress ≥ 0.5; correct answers do *not* re-credit a streak the student already earned, but wrong/partial answers and difficulty adaptation behave normally), and **practice**. Practice picks a random `_practiceTypes` entry (excluding the previous one) and considers the subgoal mastered after a streak of 3 correct answers spanning ≥ 2 distinct question types. Mastery triggers a one-shot **diagnostic** `writeCodeQuestion` on the *next* subgoal — answering it correctly fast-forwards past that subgoal too. Difficulty adapts on a 5-answer window (4 correct + ≤ 1 hint → up; 3 wrong or 4 wrong+partial → down). Hint usage gates the upgrade. Persisted per-subgoal state (`difficulty`, `recentAnswers`, `lastSessionAt`, `recentConceptAttributions`) survives restarts and is restored in `_resetSubgoalState`. Concept attributions from feedback turns are filtered through `GoalsService.getKnownConceptsInScope` (current root + earlier roots' `knownConcepts`) before being persisted; out-of-scope tags are logged and dropped.
- Per-user persistence: `progress` container via [services/progress/progress_service.dart](lib/services/progress/progress_service.dart). Each upsert that *changes* the persisted progress value also writes a `progress_history` sample (best-effort — failures are logged so the user-visible upsert isn't poisoned). Root-progress recomputes set `recordHistory: false` to avoid duplicating child trajectories.

### Teacher dashboard

- Goal authoring: [features/goals/goals_page.dart](lib/features/goals/goals_page.dart) — three-pane layout (roots / children / editor) with drag-and-drop reparent and reorder ([dnd.dart](lib/features/goals/dnd.dart), [tree_utils.dart](lib/features/goals/tree_utils.dart)). Subtree backup/restore for safe deletes lives in [goals_service.dart](lib/services/goal/goals_service.dart) (`backupSubtree` / `deleteSubtree` / `restoreSubtree`); the data shape is captured in [services/goal/subtree_backup.dart](lib/services/goal/subtree_backup.dart). Reorder and subtree-delete use a Cosmos transactional batch since every doc shares the `/type = "goal"` partition.
- AI-instruction authoring: [features/instructions/instructions_editor_page.dart](lib/features/instructions/instructions_editor_page.dart) — left pane lists `instructions/{docId}` documents, middle pane lists named sections, right pane is a markdown `CodeField` editor. Save persists the whole `sections` map back to Cosmos. The page also supports importing/exporting Markdown via `file_picker`.
- Account admin: [features/account/accounts_page.dart](lib/features/account/accounts_page.dart) — paginated `DataTable` with a status dot per student (active / idle / struggling, computed by [teacher_signals.dart](lib/services/progress/teacher_signals.dart)), search, toggle `mayUseGlobalKey`, delete account profile (does NOT delete the Entra user — that's a tenant-admin operation). Tapping a row opens [features/account/detail/student_detail_drawer.dart](lib/features/account/detail/student_detail_drawer.dart), an end-drawer that streams the student's progress docs, the read-only goal/progress list, the per-subgoal AI status reports, and 30 days of progress-history line charts (one chart per root goal via `fl_chart`, with the root's average overlaid on the children).

### Crash recovery

- [crash_recovery_screen.dart](lib/crash_recovery_screen.dart) — pushed onto the navigator by `safeCosmos` on Cosmos 401/403, and by `FlutterError.onError` for unhandled errors. Single button calls `resetAuthAndCacheAndExit()` ([core/cosmos_safety.dart](lib/core/cosmos_safety.dart)).

The Shift-on-startup safe-mode boot gate (`boot_gate.dart`) has been removed.

## 6. State management & data flow

### Pattern

`flutter_riverpod` for both DI and reactivity. Services are declared as `Provider<T>` (immutable) or `NotifierProvider<N, S>` (mutable) at the file level and consumed via `ref.watch(...)` / `ref.read(...)` in `ConsumerWidget` / `ConsumerState` subclasses. The old `get_it` / `DataService` static-getter pattern and the `MultiValueListenableBuilder` widget have been removed.

`ValueNotifier` + `ValueListenableBuilder` is still used for leaf state *inside* services where Riverpod granularity would be overkill (e.g. `OutputService.lines`, `OutputService.isRunning`, `OutputService.pendingInputRequest`).

Notable Riverpod providers:
- `authServiceProvider` — `NotifierProvider<AuthService, AccountIdentity?>` (Entra identity after silent refresh / sign-in / sign-out)
- `accountServiceProvider` — `NotifierProvider` for the Cosmos account doc (polled)
- `localApiKeyStorageProvider` — `NotifierProvider<LocalApiKeyStorage, bool>` (`isKeyPresent`)
- `goalSelectionProvider` — `NotifierProvider<GoalSelectionNotifier, GoalSelectionState>` — single immutable state object replacing six old `ValueNotifier`s on `GoalsService` (selected/preferred root+child goals, editor selection, `cachedRoots`)
- `globalConfigServiceProvider`, `instructionsServiceProvider` — config + instructions, with an `InstructionsService.cachedAll` snapshot for hot path (avoids Cosmos round-trip per AI turn)
- `progressServiceProvider`, `tutorServiceProvider`, `chatServiceProvider`, `splashServiceProvider`, `outputServiceProvider`
- Leaf `ValueNotifier`s still used inside `OutputService` (`lines`, `isRunning`, `pendingInputRequest`) and `ChatService.streamState` for in-flight stream rendering

### Cosmos REST + polling

[core/cosmos_client.dart](lib/core/cosmos_client.dart) is a hand-rolled REST client (~420 lines) that signs requests with HMAC-SHA256 over the canonical Cosmos auth payload (`MasterKeyAuth`). It supports `read`, `query` (with continuation-token pagination), `create`, `upsert`, `replace`, `delete`, and atomic `executeBatch` for multi-doc transactions within a single partition. 429s are retried internally up to 3 times honouring `x-ms-retry-after-ms`, capped at 5 s; 401/403 surface as `CosmosException` with `isAuthError == true`.

Cosmos has a change feed but consuming it from a desktop client is awkward, so reactivity is built on **polling**: [`pollingStream`](lib/core/cosmos_safety.dart#L81) emits an immediate first fetch on subscribe, then ticks on `kCosmosPollInterval` (5 s) without overlapping requests. `safeCosmos` wraps one-shots and pushes `CrashRecoveryScreen` on auth errors; `safeCosmosStream` logs auth/throttle errors flowing through a stream without swallowing them. Every service that exposes a `watchX` stream stacks them as `safeCosmosStream(pollingStream(() => safeCosmos(() => fetch())))`.

### Boot flow

1. `WidgetsFlutterBinding.ensureInitialized()` and `FlutterError.onError` wired to the recovery screen.
2. A `ProviderContainer` is created manually; `authServiceProvider.notifier.tryAcquireTokenSilent()` is awaited *before* `runApp` so the first frame already knows the auth state. The container is handed to `UncontrolledProviderScope`.
3. `GoalsApp` (`ConsumerWidget`) watches `authServiceProvider`, `accountServiceProvider`, and `localApiKeyStorageProvider`:
   - `identity == null` → `SignInPage`.
   - account doc still loading on first sign-in → spinner.
   - `!mayUseGlobalKey && !hasLocalKey` → `LocalKeyGateScreen`.
   - else → `HomeShell`.
4. `HomeShell.initState` schedules `checkForUpdate()` once after the first frame.
5. `AccountService` listens to the auth identity via its provider. On a new identity it calls `_ensureProfile` (fire-and-forget create), subscribes to `watchAccount(uid)`, and on the first non-null emission calls `TutorService.initializeSession(force: true)` once per uid (deduped via `_lastInitedUid`).

### Student progress: UI → Cosmos

1. Student answers a question via the chat composer.
2. `ChatWidget.onMessageSend` → `TutorService.handleStudentMessage(text)` routes to the appropriate `ChatRequestType` based on `_currentExerciseType`.
3. `TutorService.queryTutor(...)` builds an `input` JSON via `QuestionFormatter`, fetches instructions via `InstructionGenerator.generateInstructions(type)`, and picks the streaming or non-streaming connector path. Streamable types call `OpenaiConnector.sendRequestStream(...)`; `status_summary` (and any other type with `streamable: false`) goes through `sendRequest(...)`.
4. **Streaming path:** `_runStream` opens the chunk stream, appends each `StreamTextDelta` to a buffer rendered via `ChatService.updateStream`, then on `StreamCompleted` calls `ChatService.completeStream` (which swaps the placeholder for a final `TextMessage`) and dispatches the parsed `ChatResponse`. The first `addTutorMessage` from a handler is suppressed in the streaming context because the prompt has already been shown via the stream. Transport / parse failures yield a `StreamFailed` chunk, surface as a system message, and retry once (`_maybeRetryStream`).
5. **Non-streaming path:** the connector returns `ConnectorOk(output) | ConnectorFailure(error, stack, message)`; `AIResponseParser.parse(...)` handles both the envelope output (`<TEXT>...</TEXT><META>{...}</META>`) and legacy JSON-only output. On failure the tutor surfaces a system message and may retry once (`_maybeRetry`).
6. Either way the parsed response is dispatched by `dispatchResponse(parsed, ctx)` ([services/tutor/responses/response_handlers.dart](lib/services/tutor/responses/response_handlers.dart)) to the matching `*Handler`. Each handler receives a `TutorContext` of small callbacks (`startNewCode`, `addTutorMessage`, `addSystemMessage`, `setExerciseType`, `setFollowUp`, `requestExercise`, `maybeRetry`) so the strategy code stays free of `DataService` knowledge.
7. Feedback handlers (`CodeFeedbackHandler`, `McqFeedbackHandler`, `SocraticFeedbackHandler`, `ExplainFeedbackHandler`) call `Conductor.updateProgress(quality)` and then `Conductor.recordConceptAttributions(suspectedConcepts)`. The conductor:
   - Updates the mastery streak (`+1` on correct, reset on wrong, no-op on partial), tracks the set of distinct question types in the streak, and adapts difficulty over a 5-answer window. Hint usage is reset on every answer.
   - Mastery (streak ≥ 3 across ≥ 2 distinct types) writes `progress: 1.0`, recomputes the parent root, fires sound + splash, advances to the next incomplete subgoal, and arms a one-shot diagnostic `writeCodeQuestion` for that next subgoal. Otherwise it persists the current "display" progress (a function of the streak position).
   - Filters AI-emitted suspected concepts against `getKnownConceptsInScope(rootGoal)` and appends accepted tags to `Progress.recentConceptAttributions` (window of 20).
   - On warm-up, suppresses the positive streak bump for correct answers (the student already earned this last session) but still applies wrong/partial flow and difficulty adaptation.
   - Returns whether a follow-up message is allowed; if no, the handler chains into `requestExercise` to pick the next exercise type.
8. `ProgressService.upsert` writes the `progress` doc and, on actual change, also writes a `progress_history` sample tagged with `quality` and `isWarmUp`. `StatusSummary` responses route through `ReportService.updateForCurrentChildGoal(...)` and persist to the `status_reports` container.

### Teacher-authored AI instructions → runtime prompt

1. Teacher edits `instructions/{docId}.sections{key: text}` in [InstructionsEditorPage](lib/features/instructions/instructions_editor_page.dart). Each `docId` is named after a `ChatRequestType` (e.g. `socraticQuestion`, `submitCode`); a special `alwaysInclude` doc holds shared instructions.
2. On every tutor request, [InstructionGenerator.generateInstructions(type)](lib/services/tutor/instruction_generator.dart) reads instruction docs from `InstructionsService.cachedAll` (the polling watcher's last snapshot, falling back to a Cosmos round-trip on cold start), finds the doc whose id matches the `ChatRequestType` name, concatenates its sections, then assembles the prompt as `envelopeContract + alwaysInclude + typeSpecific`. The order is deliberate: the envelope contract is identical on every request (best cache prefix), `alwaysInclude` is stable across types (second-best), and the type-specific block varies.
3. Each section is run through `_replaceTags(...)` which substitutes `{goal}`, `{subgoal}`, `{suggestions}`, and `{known concepts}` (case-insensitive, whitespace-tolerant) using the currently selected (or preferred) root/child goal and the concepts from all earlier root goals (computed in `_getMasteredConcepts`).
4. The assembled string is sent to `OpenaiConnector` as the system message. The user-turn payload is a JSON object built by [QuestionFormatter](lib/services/tutor/question_formatter.dart), e.g. `{"request_type":"socratic_question","difficulty":"medium"}`.
5. The connector keeps two history lists (`_allHistory`, `_sessionHistory`) of `{role, content}` items capped at 50 entries each, and includes one of them per call based on `PreviousInputs.includeAll | includeSession | newSession`. Instructions are re-sent on every call. The streaming path only records the user turn into history once the stream finalises successfully and the parsed response isn't an `ErrorResponse` — so a failed stream doesn't poison history.

## 7. Known limitations / TODOs / rough edges

See [TODO.md](TODO.md) for the current planning doc. The previous `docs/` folder of Markdown specs (data, UX, security, roadmap, etc.) was deleted in commit `29a21e6` — historical context lives in git only. Notable rough edges visible in the code itself:

- **Cosmos auth is master-key.** [cosmos_client.dart](lib/core/cosmos_client.dart) already has an `AadTokenAuth` stub for the eventual swap to per-user AAD RBAC ("Step 3" in the comments); until then every authenticated student holds the database master key. The migration plan in [TODO.md](TODO.md) tracks this.
- **No realtime listeners.** All cross-device updates rely on a 5 s `pollingStream` tick. Teacher-edits-while-student-is-active have a brief lag, and the polling cost on serverless RU/s billing is real but small at our scale.
- **Local API key not used.** `LocalApiKeyStorage.saveKey(...)` writes to `SharedPreferences`, the gate screen requires it, but `OpenaiConnector._apiKey = Env.apiKey` always uses the build-time obfuscated key. Either the gate is purely informational or the wiring is incomplete.
- **`config/global` ApiKey field unused.** `GlobalConfig.apiKey` is parsed but never read by `OpenaiConnector` either. Only `GlobalConfig.model` is consumed.
- **Tokens stored unencrypted.** The Entra token bundle lives in `shared_preferences` (per the school's "I don't care if students tamper" stance, see [auth_service.dart#L18-L21](lib/services/auth/auth_service.dart#L18-L21)). Students with shell access can read another student's refresh token from `%APPDATA%\com.example\ai_tutor_python\shared_preferences.json`.
- **Dead file.** [features/dashboard/editor_controller.dart](lib/features/dashboard/editor_controller.dart) is entirely commented out.
- **Dead branch in `crash_recovery_screen.dart`.** The file has both `await resetAuthAndCacheAndExit(); exit(0);` and a commented-out fallback. The `exit(0)` is unreachable because the helper already exits.
- **No sandboxing of student code.** The script runs in a child process via `py_runner` with full filesystem/network access.
- **`dart_openai` is pinned to a personal fork** (`https://github.com/yvanvds/openai.git`) — any upstream changes need to be merged manually.
- **Windows-only.** `py_engine_desktop` is desktop-only and the launcher is Windows-flavoured (`.exe` installer, `%LOCALAPPDATA%` reset path). No iOS/Android/macOS/Linux/Web.
- **All UI text is Dutch and hard-coded** throughout services and widgets; no i18n layer.

## 8. Build & run

### Required config files

- **`.env`** at the repo root (gitignored). Required entries:
  ```
  OPEN_AI_API_KEY=sk-...
  COSMOS_ENDPOINT=https://<account>.documents.azure.com:443/
  COSMOS_KEY=<primary-master-key>
  ENTRA_TENANT_ID=<tenant-guid>
  ENTRA_CLIENT_ID=<app-registration-client-id>
  ENTRA_REDIRECT_URI=http://localhost
  ```
  `OPEN_AI_API_KEY` and `COSMOS_KEY` are obfuscated at build time via `envied`; the others are not secrets (Microsoft's OAuth model treats client_id/tenant_id/redirect_uri as public).

- **Entra app registration prerequisites** (Azure Portal → App registrations → your app):
  - "Authentication" → add `http://localhost` as a redirect URI under "Mobile and desktop applications".
  - "App roles" → define a `Teacher` role and assign it to teacher accounts.
  - "API permissions" → `openid`, `profile`, `email`, `offline_access` (delegated, Microsoft Graph).

- **Cosmos DB** account with database `python-tutor` and containers `accounts` (`/uid`), `progress` (`/uid`), `status_reports` (`/uid`), `goals` (`/type`), `instructions` (`/type`), `config` (`/type`).

### Commands

```powershell
# Get dependencies
flutter pub get

# Generate envied + any other build-runner outputs (run after editing .env)
dart run build_runner build --delete-conflicting-outputs

# Run on Windows desktop (only supported platform)
flutter run -d windows

# Static analysis
flutter analyze

# Tests (mocktail-based unit tests under test/)
flutter test

# Build a release Windows executable
flutter build windows --release

# Package as an installer (.exe via Inno Setup) — see distribute_options.yaml + windows/packaging/
flutter pub global activate flutter_distributor
flutter_distributor release --name=windows
```

### Update channel

A release build hosts `public/version.json` at `https://ai-tutor-python.web.app/version.json` (deployed via `firebase deploy --only hosting` — Firebase Hosting is the only piece of Firebase still used). On launch, [home_shell.dart#L146-L187](lib/home_shell.dart#L146-L187) fetches that manifest and, if newer, downloads `python_teacher_install.exe`, verifies SHA-256, and runs it `/VERYSILENT /NORESTART` before exiting.
