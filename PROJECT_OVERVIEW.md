<!-- META
last_updated_commit: 6a5f1676de7a5e77e7593f35f8f57a59523dd076
last_updated_at: 2026-05-09
-->

# PROJECT_OVERVIEW

## 1. High-level summary

`ai_tutor_python` is a Flutter desktop application that acts as a personalised Python tutor for students. A dark "study lamp" shell hosts a sidebar of sections (`Sessie`, `Leerpad`, plus teacher-only `Doelen` / `Lesinhoud` / `Instructies` / `Studenten`) and a top-bar mode switcher (`Uitleg | Oefenen | Vrij coderen`) that swaps between three workspace modes: a markdown-rendered explanation canvas tied to teacher-authored lesson content, a Python editor + runner with optional chat panel, and a free-coding playground. Multiple-choice quizzes are not a separate mode — they take over the workspace whenever an `ActiveMcq` is in flight. Behind the UI, a probabilistic LLM-backed tutor maintains a per-student Beta-distribution belief over each Learning Objective (LO) inside every subgoal, calibrates question difficulty per student, persists every graded turn for audit, and lets teachers edit the prompts and lesson content that shape its behaviour. Identity is tied to the school's Microsoft Entra tenant. Built and used by a Python teacher (Yvan) for his own classroom; UI is in Dutch.

## 2. Tech stack

- **Flutter SDK constraint:** Dart `^3.10.1` (see [pubspec.yaml](pubspec.yaml)). No explicit Flutter version pin.
- **Target platforms:** Windows desktop only. `distribute_options.yaml` packages a Windows `.exe` installer; an in-app updater fetches a manifest from `yvanvds.github.io/AI-tutor-Python/version.json` (GitHub Pages) and re-runs the installer ([core/update_info.dart](lib/core/update_info.dart)).

### Key packages (from [pubspec.yaml](pubspec.yaml))

**State / DI**
- `flutter_riverpod` — DI and reactivity; services are declared as `Provider` / `NotifierProvider` / `StateProvider` singletons and consumed via `ref.watch` / `ref.read` in `ConsumerWidget` / `ConsumerState`.
- `provider` — used only inside `flutter_chat_ui`'s custom-composer contract; not project-wide.

**Backend**
- `http` + `crypto` — used by the hand-rolled [core/cosmos_client.dart](lib/core/cosmos_client.dart) to talk to Azure Cosmos DB's REST API (no third-party Cosmos SDK).
- `url_launcher` — opens the system browser for the Microsoft Entra OAuth flow.
- `shared_preferences` — persists the Entra token bundle and the per-user OpenAI key.

**AI / LLM**
- `dart_openai` — pinned to a fork at `https://github.com/yvanvds/openai.git`. The connector uses `chat.completions` (`OpenAI.instance.chat.create` / `createStream`) plus a hand-rolled `<TEXT>...</TEXT><META>{...}</META>` envelope (see [services/tutor/responses/envelope_assembler.dart](lib/services/tutor/responses/envelope_assembler.dart)).
- `envied` (+ `envied_generator`) — obfuscates `OPEN_AI_API_KEY` and `COSMOS_KEY` from `.env` into [services/tutor/env.g.dart](lib/services/tutor/env.g.dart) and [services/config/azure_config.g.dart](lib/services/config/azure_config.g.dart).

**Code execution**
- `py_runner` — local Flutter package at [packages/py_runner/](packages/py_runner/) wrapping a long-lived `host.py` subprocess via `InstallerPyHostLocator`.

**Editor / UI**
- `flutter_code_editor`, `flutter_highlight`, `highlight` — the Python editor and its theming. Custom syntax map in [theme/code_theme.dart](lib/theme/code_theme.dart) replaces the default `monokai-sublime`.
- `flutter_chat_ui`, `flutter_chat_core`, `flyer_chat_text_message`, `flyer_chat_system_message`, `flyer_chat_text_stream_message` — the chat panel; the stream-message variant renders the in-flight tutor reply while it's still arriving.
- `gpt_markdown` — backs the new [widgets/tutor_markdown.dart](lib/widgets/tutor_markdown.dart) widget used for tutor-authored copy in chat bubbles, MCQ prompts, and MCQ feedback.
- `fl_chart` — line charts in the teacher's per-student detail drawer.
- `multi_split_view` — resizable editor / output split inside `PracticeView`.
- `lottie`, `loading_animation_widget`, `audioplayers` — confetti splash, spinner, sound effects.
- `google_fonts` (Inter Tight + JetBrains Mono per [theme/app_theme.dart](lib/theme/app_theme.dart)), `file_picker`. A bundled `monospace` family (`assets/fonts/SVBasicManual*.ttf`) is also declared.

**Misc**
- `path`, `path_provider`, `pub_semver`, `uuid`, `collection`.

**Dev**
- `flutter_test`, `integration_test`, `mocktail`, `fake_async`, `flutter_lints`, `build_runner`.

### Python execution approach

Python runs via `py_runner`, a local Flutter package at [packages/py_runner/](packages/py_runner/). `PyRunner` (configured with `InstallerPyHostLocator`) manages a long-lived Python host subprocess (`host.py`). `OutputService.run(code)` ([services/output/output_service.dart](lib/services/output/output_service.dart)) starts the host if needed, submits the code string, and streams `stdout`/`stderr` lines into `lines` (`ValueNotifier<List<OutputLine>>`). `OutputService.stop()` cancels the run handle; `OutputService.clear()` resets the visible log without touching an in-flight run. Interactive `input()` calls surface as `InputRequest` objects on `pendingInputRequest` and are rendered as an inline text field in [features/session/widgets/output_panel.dart](lib/features/session/widgets/output_panel.dart). There is no sandboxing — student code runs in a child process with full filesystem/network access.

### AI provider

OpenAI's chat.completions API, called via `dart_openai` (forked) in [services/tutor/openai_connector.dart](lib/services/tutor/openai_connector.dart). Both a non-streaming `sendRequest` and a streaming `sendRequestStream` (emitting `StreamTextDelta` / `StreamCompleted` / `StreamFailed` chunks) are exposed; the tutor service prefers streaming for student-facing question turns and uses non-streaming for grader and status calls. The connector also carries an opt-in `reasoning_effort` (currently hard-coded to `'low'`) for gpt-5 / o-series models. The model name comes from the Cosmos `config/global` doc (field `Model`), defaulting to `gpt-4o`. The API key is the build-time obfuscated `Env.apiKey`; per-user override via locally-stored OpenAI key is *saved* but not actually wired into `OpenaiConnector` (see TODOs).

History is managed client-side with two parallel logs capped at 50 entries each: `_allHistory` (across sessions) and `_sessionHistory` (current question chain). Each `sendRequest` chooses one of `includeAll | includeSession | newSession`. `instructions` is passed as a system message on every call; the user-turn content is a JSON string built by `QuestionFormatter`.

The model is required to wrap every reply in a `<TEXT>...</TEXT><META>{...}</META>` envelope. [EnvelopeAssembler](lib/services/tutor/responses/envelope_assembler.dart) parses this incrementally so the streaming path can flush visible text before `<META>` arrives. The legacy JSON-only output path is still supported as a fallback (handled in [ai_response_parser.dart](lib/services/tutor/responses/ai_response_parser.dart)).

## 3. Project structure

```
lib/
├── main.dart                    # App entry; silent token refresh, auth + key gate, mounts AppShell
├── crash_recovery_screen.dart   # Shown on FlutterError or Cosmos auth failure
├── create_text_theme.dart       # Google Fonts text-theme helper (legacy; new theme is in theme/)
├── version.dart                 # const String kAppVersion
│
├── home_shell.dart              # DEAD — old NavigationRail shell
├── theme.dart                   # DEAD — old Material 3 schemes
│
├── theme/                       # Design tokens and theme
│   ├── app_theme.dart                # buildAppTheme() + AppMono (mono/tnum text styles)
│   ├── tokens.dart                   # AppColors / AppSpacing / AppRadius / AppDurations / AppCurves
│   └── code_theme.dart               # Syntax highlighting map for the Python editor
│
├── core/
│   ├── chat_request_type.dart   # enum of every request kind sent to the AI
│   ├── chat_response_type.dart  # parallel enum (declared but lightly used)
│   ├── question_difficulty.dart # easy | medium | hard
│   ├── answer_quality.dart      # wrong | partial | correct
│   ├── cosmos_client.dart       # Hand-rolled Cosmos REST client + BatchOperation
│   ├── cosmos_paths.dart        # Single source of truth for container handles + CosmosPartitions
│   ├── cosmos_doc_id.dart       # Composite id conventions (incl. turnHistory)
│   ├── cosmos_safety.dart       # safeCosmos / safeCosmosStream / pollingStream
│   ├── update_info.dart         # In-app installer-update helpers
│   ├── debounce.dart            # Generic debounce util
│   └── date_format.dart         # formatTs(DateTime) — yyyy-MM-dd HH:mm
│
├── services/                    # All declared as Riverpod providers
│   ├── auth/auth_service.dart   # Entra OAuth (PKCE + loopback) + token cache; authServiceProvider + isTeacherProvider
│   ├── account/                 # Account model (now embeds StudentCalibration) + AccountService
│   ├── chat/chat_service.dart   # Wraps flutter_chat InMemoryChatController; stream + MCQ helpers
│   ├── code/code_service.dart   # Wraps flutter_code_editor CodeController
│   ├── config/                  # GlobalConfigService, AzureConfig (envied), LocalApiKeyStorage
│   ├── debug/debug_session_recorder.dart  # Circular buffer (200 turns) of TurnRecord events; mirrors persisted turn_history doc and any follow-up the grader emitted
│   │
│   ├── content/                 # NEW — authored explanation blocks linked from goals
│   │   ├── content.dart                  # Content model (id mirrors subgoal id)
│   │   └── content_service.dart          # cachedAll / watchAll / watchById / upsert / delete
│   │
│   ├── module/                  # NEW — top-level grouping of root goals (v1: single 'python-basics')
│   │   ├── module.dart                   # Module model + defaultModuleId constant
│   │   └── module_service.dart           # ensureDefaultModule + cachedAll
│   │
│   ├── goal/
│   │   ├── goal.dart                     # Unified root + subgoal type; new subgoal-only fields: teachingTips, allowChains, objectives[LO], contentId, moduleId
│   │   ├── learning_objective.dart       # NEW — embedded LO: id, statement, kind (recall|apply|predict|reason), weight, optional
│   │   ├── goals_service.dart            # CRUD + reparent + DnD + import/export (v2 envelope; Add vs Replace; backfillModuleIds; preserves contentId across re-imports)
│   │   ├── goal_selection_notifier.dart  # GoalSelectionState + GoalSelectionNotifier
│   │   └── subtree_backup.dart           # Subtree backup/restore for delete-undo
│   │
│   ├── student_state/           # NEW — per-student probabilistic mastery state
│   │   ├── lo_belief.dart                # Beta(α, β) per (uid, subgoalId, loId) + lastQuestionType + lastPositiveAtCalibratedAt + recentNegativesAtCalibrated
│   │   ├── lo_beliefs_service.dart       # Cosmos `lo_beliefs` container; get/upsert/deleteAllForCurrentUser
│   │   ├── student_calibration.dart      # StudentCalibration + CalibrationAnswer (embedded on Account doc)
│   │   ├── turn_record.dart              # PersistedTurnRecord, TurnLoSignal, TurnAppliedSignal, TurnLoStatus, TurnSignalEvent (kind + severity)
│   │   └── turn_history_service.dart     # Append-only `turn_history`; watchStrongUnacknowledgedFor; listEventsFor; acknowledgeAllFor
│   │
│   ├── instructions/            # Instruction (sections map) + InstructionsService
│   ├── output/                  # OutputService + OutputController (binds widget)
│   ├── progress/                # Progress model (now derived cache) + ProgressService + teacher_signals
│   │   ├── progress.dart                 # Reduced to {goalID, progress, updatedAt, lastSessionAt}; recentAnswers/difficulty/concept-attribution fields removed
│   │   ├── progress_service.dart         # Reads/writes `progress`; best-effort `progress_history` sample on change
│   │   ├── progress_sample.dart          # One row of `progress_history` (time series)
│   │   └── teacher_signals.dart          # StudentStatus enum (active|idle), kRecentActivityWindow (7 days), computeStudentStatus, mostRecentlyActive, averageProgress
│   ├── progression/level_up_controller.dart   # NotifierProvider<LevelUpController, LevelUpEvent?> — overlay trigger (still inert)
│   ├── sound/sound_service.dart # Plays goal_reached/note/question/chime mp3s
│   ├── splash/splash_service.dart # Goal-reached overlay state
│   ├── status_report/           # StatusReport model + ReportService
│   └── tutor/
│       ├── tutor_service.dart           # Public API + plan→generate→request→parse→dispatch→grade→integrate cycle; mid-session curriculum watcher
│       ├── conductor.dart               # ~1400 lines: LO-belief mastery model, calibration, notch-drop, follow-up chains, signal events, degraded mode
│       ├── policy_constants.dart        # NEW — every numeric knob (mastery thresholds, evidence cap, decay half-life, calibration windows, signal weights, follow-up depths)
│       ├── belief_math.dart             # NEW — applyDecay, signalDeltas, applyEvidence, meetsMasteryMeanAndEvidence, isStuck, isPracticeable
│       ├── active_mcq.dart              # NEW — StateProvider<ActiveMcq?>; transient in-flight MCQ state (prompt + code + options + selected + feedback)
│       ├── openai_connector.dart        # chat.completions client (sync + streaming) + history
│       ├── instruction_generator.dart   # Assembles system prompt + envelope contract; new tags: {targetLOs}, {goalScopeLOs}, {teachingTips} (alias of legacy {suggestions}); {known concepts} now expands to empty for backward compat
│       ├── question_formatter.dart      # JSON-encodes user-turn payloads; question fns take targetLOs; grading fns take targetLOs + goalScopeLOs; new followUpAnswer + status helpers
│       ├── env.dart / env.g.dart        # Envied-obfuscated OPEN_AI_API_KEY
│       └── responses/
│           ├── chat_response.dart                  # Sealed parent for parsed AI replies
│           ├── ai_response_parser.dart             # Envelope + legacy-JSON parser
│           ├── envelope_assembler.dart             # Streaming <TEXT>/<META> assembler
│           ├── grader_payload.dart                 # NEW — typed signals coming back from grader (subgoalId, loId, signal, strength)
│           ├── graded_answer_builder.dart          # NEW — validates grader signals against scope; synthesises a fallback weak signal if all out-of-scope; sets hadFallback
│           ├── multiple_choice.dart, socratic_question.dart, complete_code.dart, explain_code.dart, write_code.dart   # Question response types
│           ├── code_feedback.dart, mcq_feedback.dart, explain_feedback.dart, socratic_feedback.dart                   # Grading response types (each carries a `GraderPayload` block)
│           ├── answer.dart, hint.dart, status_summary.dart, error_summary.dart                                        # Other response types
│           └── response_handlers.dart              # 13 *Handler classes + dispatchResponse(parsed, ctx); MultipleChoiceHandler shuffles options
│
├── features/
│   ├── shell/                   # Outer chrome
│   │   ├── app_shell.dart              # Top-level Scaffold: Sidebar + TopBar + body + overlays; switches lessonContent → LessonContentPage
│   │   ├── shell_state.dart            # Section enum {session, map, goals, lessonContent, instructions, students}; SessionMode {explain, practice, free}; Profile, profileProvider, modeProvider, sectionProvider, ambientProgressProvider
│   │   ├── sidebar.dart                # 72px icon rail; student vs teacher sections; debug + sign-out; teacher group includes new "Lesinhoud"
│   │   └── top_bar.dart                # Greeting / ModeSwitcher / StatStrip + 2px AmbientProgress
│   │
│   ├── session/                 # Workspace shown when Section.session is active
│   │   ├── session_view.dart           # Mode-driven left panel + animated chat panel (460px); chat hides while activeMcqProvider is non-null
│   │   ├── modes/
│   │   │   ├── explain_view.dart       # ~670 lines: full markdown renderer for authored Content (fenced code, callouts, headings, paragraphs); subgoal header pill + idx/total + "Vorige" + "Probeer het zelf" → practice mode
│   │   │   ├── practice_view.dart      # ObjectiveBanner + RunControls + Editor + OutputPanel (vertical split); when activeMcqProvider is non-null, mounts QuizView in place of editor/output
│   │   │   ├── quiz_view.dart          # Full MCQ surface: header pill + TutorMarkdown prompt + optional code card + 2-column option grid (badges A–F) + colored feedback panel + "Volgende"
│   │   │   └── free_view.dart          # "Speeltuin" header + reused PracticeView (no objective)
│   │   └── widgets/
│   │       ├── objective_banner.dart   # "Huidig doel" pill + title from goalSelectionProvider
│   │       ├── run_controls.dart       # Run/Stop/Reset/Hint/Send-to-tutor strip
│   │       └── output_panel.dart       # py_runner-backed runner + log view + interactive input
│   │
│   ├── lesson_content/                  # NEW — teacher-only "Lesinhoud" feature
│   │   └── lesson_content_page.dart    # Two-pane: read-only module/goal tree + markdown editor; bootstraps default module + backfills moduleId on goals; loads/saves Content doc keyed by subgoal id
│   │
│   ├── progress/
│   │   ├── leerpad_page.dart           # Student "Leerpad" — vertical stack of root-goal cards
│   │   ├── widgets/leerpad_card.dart   # Single root card (active expands to child chips + "Verder")
│   │   ├── widgets/leerpad_child_chip.dart  # Per-child chip with progress dot
│   │   ├── student_progress_list.dart  # Older list view; still used in teacher's read-only drawer
│   │   └── goal_tile.dart              # Optional `readOnly`; carries Progress? for teacher view
│   │
│   ├── chat/
│   │   ├── chat_widget.dart            # ChatHeader + flutter_chat_ui Chat; composer swap by TutorState / mcqPending
│   │   ├── mcq_options_widget.dart     # Inline MCQ options (single-column) used inside chat for socratic-flow MCQs; the full QuizView handles 2-col layout
│   │   └── widgets/
│   │       ├── chat_header.dart, tutor_avatar.dart, role_chip.dart, _chat_time.dart
│   │       ├── tutor_bubble.dart            # Now renders body via TutorMarkdown (markdown + syntax-highlighted fences)
│   │       ├── student_bubble.dart, chat_system_pill.dart
│   │       ├── composer_chrome.dart, composer_idle.dart, composer_thinking.dart,
│   │       └── composer_continue.dart, composer_mcq_disabled.dart
│   │
│   ├── auth/
│   │   ├── sign_in_page.dart, local_key_gate_screen.dart
│   │
│   ├── dashboard/                       # Mostly retired; only three files still referenced
│   │   ├── editor.dart                 # IN USE — CodeField bound to CodeService.controller
│   │   ├── debug_dialog.dart           # IN USE — Teacher-only dialog: wipe-all-progress; level-up overlay test; difficulty + question-type buttons; recent-turns list with full PersistedTurnRecord JSON
│   │   ├── dashboard.dart              # DEAD
│   │   ├── controllers.dart            # DEAD
│   │   ├── output.dart                 # DEAD
│   │   └── editor_controller.dart      # DEAD — entirely commented out
│   │
│   ├── goals/                          # Teacher: goal-tree CRUD + reparent + DnD; new export/import buttons (v2 JSON envelope; Add vs Replace; preserves contentId); goal_form has inline _LesinhoudRow that opens Lesinhoud
│   ├── instructions/                   # Teacher: doc/section editor over instructions/{id}.sections{}
│   └── account/
│       ├── accounts_page.dart          # Teacher: paginated DataTable; status dot + unacknowledged signal-event badge per student; helpers _activeRootTitle / _overallRootProgress
│       └── detail/                     # Right-hand peek drawer for one student
│           ├── student_detail_drawer.dart       # Hosts the four sections below
│           ├── student_status_summary.dart      # One-line "Recent actief op X" / "Geen recente activiteit"
│           ├── signal_events_section.dart       # NEW — strong + audit signal events from turn_history; "Bevestigen (n)" clears strong-event acks
│           ├── status_reports_section.dart      # Per-subgoal AI status reports
│           └── progress_history_charts.dart     # 30 days of progress_history line charts
│
└── widgets/                            # Reusable building blocks
    ├── tutor_markdown.dart                 # NEW — GptMarkdown wrapper with custom inline-code pill + fenced-code highlighting; used in chat, MCQ prompt, MCQ feedback
    ├── level_up_overlay.dart               # Full-screen level-up celebration; listens to levelUpControllerProvider (still inert)
    ├── goal_splash_overlay.dart            # Subgoal/goal-completion confetti splash
    ├── goal_crumb_in_app_bar.dart          # Crumb (legacy)
    ├── undo_snackbar.dart                  # Generic undo snackbar helper
    ├── add_input.dart, chips_editor.dart, inline_title.dart

packages/py_runner/                    # Local Flutter package — PyRunner, InstallerPyHostLocator, RunHandle, InputRequest
test/                                  # mocktail-based unit + widget tests; helpers/in_memory_cosmos.dart is the shared Cosmos fake
integration_test/                      # End-to-end flows on Windows desktop (#28)
├── app_test.dart                      # Single entrypoint running every flow in one app process
├── flows/                             # One file per user-visible flow (lesson, language switch, playground files)
└── harness/                           # AppHarness: GoalsApp over InMemoryCosmosClient + signed-in AuthService + seed data
public/                                # Landing page deployed to GitHub Pages by .github/workflows/static.yml
distribute_options.yaml                # flutter_distributor windows-exe job
windows/                               # Windows runner + packaging/Inno Setup config
docs/                                  # CONDUCTOR_POLICY.md, STUDENT_MODEL.md, LLM_CONTRACT.md (load-bearing for the conductor redesign)
TODO.md, TESTING_PLAN.md               # In-tree planning docs
```

## 4. Data model

All Cosmos container handles funnel through [core/cosmos_paths.dart](lib/core/cosmos_paths.dart). The database is `python-tutor`. Composite doc ids are minted in [core/cosmos_doc_id.dart](lib/core/cosmos_doc_id.dart).

The LO-belief redesign added four new containers (`content`, `modules`, `lo_beliefs`, `turn_history`) and substantially changed two existing ones (`goals` gained five fields; `progress` was reduced to a derived cache).

### Containers (per-user partition: `/uid`)

**`accounts/{uid}`** — student or teacher profile. Doc id == partition key == Entra Object ID. Model: [services/account/account.dart](lib/services/account/account.dart).
- `id: string`, `uid: string`
- `email: string`
- `firstName: string`, `lastName: string`
- `targetGoal: string` (a goal id; written but not currently read by selection logic)
- `mayUseGlobalKey: bool`
- `createdAt: string` (ISO 8601), `updatedAt: string` (ISO 8601)
- **`calibration: object`** — embedded `StudentCalibration` (STUDENT_MODEL §"Account doc"):
  - `difficulty: 'easy' | 'medium' | 'hard'` — current difficulty notch (defaults to `medium`)
  - `recentAnswers: CalibrationAnswer[]` — rolling at-calibrated answer window (capped at `PolicyConstants.calibrationWindow` = 10), each `{quality, difficulty, at}`
  - `recentQuestionTypes: string[]` — cross-LO ring buffer for variety rotation (capped at `PolicyConstants.recentQuestionTypesWindow` = 5)

**`progress`** — *derived cache* of subgoal completion. Doc id `${uid}_${goalId}`, partition key `uid`. Model: [services/progress/progress.dart](lib/services/progress/progress.dart). The previous `recentAnswers`, `difficulty`, and `recentConceptAttributions` fields are **gone** — answer history now lives on `account.calibration` and per-LO beliefs; concept attributions are subsumed by per-LO `TurnSignalEvent`s on `turn_history`.
- `id: string`, `uid: string`, `goalId: string`
- `progress: double` (0.0–1.0) — aggregated from per-LO beliefs
- `updatedAt: string`, `lastSessionAt: string`

**`progress_history`** — append-only time series. Doc id = ISO timestamp + random suffix from [CosmosDocId.progressHistory](lib/core/cosmos_doc_id.dart); partition key `uid`. Model: [services/progress/progress_sample.dart](lib/services/progress/progress_sample.dart). Drives the per-root-goal line charts in the teacher detail drawer.
- `id: string`, `uid: string`, `goalId: string`
- `progress: double`, `difficulty: string`
- `quality: string?` (optional `wrong | partial | correct`)
- `isWarmUp: bool` (legacy field; the new conductor doesn't have a warm-up phase but writes `false` for compatibility), `at: string`

**`status_reports`** — Doc id `${uid}_${goalId}`, partition key `uid`. Model: [services/status_report/status_report.dart](lib/services/status_report/status_report.dart).
- `id: string`, `uid: string`, `goalID: string`
- `statusReport: string`
- `updatedAt: string`

**`lo_beliefs`** *(new)* — one doc per `(uid, subgoalId, loId)`. Doc id `${uid}_${subgoalId}_${loId}`, partition key `uid`. Source of truth for student mastery state. Model: [services/student_state/lo_belief.dart](lib/services/student_state/lo_belief.dart).
- `id: string`, `type: 'lo_belief'`, `uid: string`, `subgoalId: string`, `loId: string`
- `alpha: double`, `beta: double` — Beta-distribution hyperparameters; mean = α/(α+β), evidence = α+β
- `lastUpdatedAt: string`
- `lastQuestionType: string?` — last `ChatRequestType.name` that probed this LO (used by conductor §2.2 type rotation)
- `lastPositiveAtCalibratedAt: string?` — set when a positive signal arrives at-or-above the student's calibration at the time of the answer; one-way ratchet (never reset by calibration shifts) and required for mastery condition 3 (CONDUCTOR_POLICY §4.1/4.3)
- `recentNegativesAtCalibrated: int` — consecutive negatives at calibration, resets on any positive at any difficulty (CONDUCTOR_POLICY §2.3 notch-drop rule)

**`turn_history`** *(new)* — append-only audit trail; one doc per graded turn (CONDUCTOR_POLICY §8.1). Doc id = ISO timestamp + random suffix; partition key `uid`. Model: [services/student_state/turn_record.dart](lib/services/student_state/turn_record.dart). Consumed by the debug dialog and the teacher drawer's Signal Events section. Each doc captures: targets (`subgoalId`, `targetLoIds`, `selectionReason`), question (`type`, `difficulty`), result (`quality`, `signals[]` of `TurnLoSignal`, `appliedDeltas[]` of `TurnAppliedSignal`, `loStatus[]` of `TurnLoStatus`), calibration before/after, subgoal progress before/after, plus `events[]` of `TurnSignalEvent`. Each event has a `kind` (one of `stuckLoAdvance`, `singleLoDeadlock`, `repeatedDemotions`, `sustainedLlmFailure`, `cascadeHalt`, `emptyObjectivesBlock`, `subgoalDeletedRedirect`) and `severity` (`strong` drives the dashboard badge until `acknowledged: true`; `audit` is visible-only).

**`playground_files`** *(new, #31)* — one doc per saved playground file. Doc id `${uid}_${name}`, partition key `uid`. Fields: `name`, `code`, `updatedAt` (ISO, the sync stamp), `deleted` (a delete leaves a tombstone so it propagates instead of the file returning on the next sync). Written by [services/playground/playground_files_service.dart](lib/services/playground/playground_files_service.dart); reconciled with the local `<documents>/AI Tutor Python/playground/<uid>/` directory by [services/playground/playground_sync_service.dart](lib/services/playground/playground_sync_service.dart), which keeps a `_sync.json` sidecar per machine (content hash + last agreed `updatedAt`) so a file changed on two machines produces a `<name> conflict` copy instead of losing either version. Local-first: the playground still works offline and every remote step is best-effort.

### Containers (single-partition: `/type`)

**`goals`** — flat collection forming a tree via `parentId`. `type: "goal"`. Model: [services/goal/goal.dart](lib/services/goal/goal.dart). Subgoal-only fields are present on the type for every doc but only meaningful on subgoals.
- `id: string`, `type: "goal"`
- `title: string`, `description: string?`
- `parentId: string?` — null for roots
- `order: int` — manual ordering, spaced by 1000 (rewritten transactionally on reorder)
- `optional: bool`
- **`teachingTips: string[]`** *(new — was `suggestions`)* — free-form prose hints to the LLM, surfaced in prompts as `{teachingTips}` (legacy `{suggestions}` still works as alias)
- **`allowChains: bool`** *(new)* — when `true`, the conductor allows follow-up chain depth 2 inside this subgoal (default `false`)
- **`objectives: LearningObjective[]`** *(new)* — ordered list of LOs `{id, statement, kind, weight, optional}`. `kind ∈ {recall, apply, predict, reason}` gates which question types the conductor may pick (CONDUCTOR_POLICY §2.2)
- **`contentId: string?`** *(new)* — optional reference to a `content` doc holding the authored explanation block (id mirrors the subgoal id when set)
- **`moduleId: string`** *(new)* — parent module id; empty string means "not yet backfilled" (Lesinhoud treats those as belonging to the default module)

**`content`** *(new)* — authored markdown explanation blocks rendered by `ExplainView`. `type: "content"`. Model: [services/content/content.dart](lib/services/content/content.dart).
- `id: string` — mirrors the subgoal id so re-imports of the goal tree can't orphan content
- `title: string`, `body: string` (markdown), `updatedAt: string`

**`modules`** *(new)* — top-level grouping of root goals. `type: "module"`. v1 has a single bootstrapped `python-basics` doc. Model: [services/module/module.dart](lib/services/module/module.dart). `ModuleService.ensureDefaultModule()` is idempotent (collisions on the deterministic id collapse safely under concurrent clients).
- `id: string`, `title: string`, `order: int`, `updatedAt: string`

**`instructions`** — teacher-edited prompt fragments. `type: "instruction"`. Model: [services/instructions/instruction.dart](lib/services/instructions/instruction.dart).
- `id: string` (matches a `ChatRequestType` enum name plus a special `alwaysInclude`)
- `sections: map<string, string>`
- `updatedAt: string`

**`config`** — single doc with id `global`. `type: "config"`. Model: [services/config/global_config.dart](lib/services/config/global_config.dart).
- `Model: string` (OpenAI model id, e.g. `gpt-4o`)
- `ApiKey: string` (parsed but not used by `OpenaiConnector`)

### Identity & roles

There is no `roles/{uid}` container. The teacher flag rides on the Entra access token's `roles` app-role claim and is decoded once in [auth_service.dart](lib/services/auth/auth_service.dart); a thin `isTeacherProvider` wraps the bool for widget consumption.

### Local persistence

- **`shared_preferences` key `azure_auth_tokens_v1`** — JSON bundle of `{access_token, refresh_token, id_token, access_token_expiry}` written by [auth_service.dart](lib/services/auth/auth_service.dart). Per the school's "students tampering is OK" stance (TODO.md), no OS keychain.
- **`shared_preferences` key `local_api_key`** — per-device OpenAI key set via [LocalKeyGateScreen](lib/features/auth/local_key_gate_screen.dart).

## 5. Core features & their entry points

### Authentication (Microsoft Entra ID, OAuth 2.0 + PKCE)

Identity is hand-rolled against Entra because the Microsoft-supplied Flutter packages wrap `webview_flutter`, which has no Windows desktop platform implementation. See [services/auth/auth_service.dart](lib/services/auth/auth_service.dart):

1. `AuthService.signIn()` generates a PKCE verifier/challenge and a random `state`, binds a `dart:io` `HttpServer` on a random localhost port, opens the Entra `/authorize` endpoint via `url_launcher`.
2. Entra redirects to `http://localhost:<port>/?code=…&state=…`. The local server captures the request, returns a small "you can close this tab" page, surfaces the code.
3. POST to `/token` with the code + verifier → `{access_token, refresh_token, id_token, expires_in}`.
4. Persist the bundle in `shared_preferences`, decode the id_token JWT to populate `currentUser` (Notifier state of type `AccountIdentity?`) with `oid`, name, email, given/family name, and an `isTeacher` flag from the `roles` claim.
5. On startup, [main.dart](lib/main.dart) calls `tryAcquireTokenSilent()` *before the first frame*. Silent refresh uses the stored refresh_token; on failure the cache is cleared and the user goes back to sign-in.

The Entra app registration must declare `http://localhost` (no port) under "Mobile and desktop applications".

### App shell (Sidebar + TopBar + body)

[features/shell/app_shell.dart](lib/features/shell/app_shell.dart) is the top-level Scaffold. It composes:

- A 72px [Sidebar](lib/features/shell/sidebar.dart) with two student sections (`Sessie`, `Leerpad`) and, for teachers only, a `Docent` group (`Doelen`, `Lesinhoud`, `Instructies`, `Studenten`). A debug button is shown in `kDebugMode` and opens [DebugDialog](lib/features/dashboard/debug_dialog.dart).
- A [TopBar](lib/features/shell/top_bar.dart) with three slots: a `Hoi {name}` greeting + subline on the left, a centred `ModeSwitcher` pill (visible only in `Section.session`), and a `StatStrip` with a streak chip and an XP/level pill on the right (still placeholder — Phase 6). A 2px gradient `AmbientProgress` line sits along the very top edge.
- The active body, switched on `sectionProvider`: `SessionView`, `LeerpadPage`, `GoalsPage`, **`LessonContentPage`** (new), `InstructionsEditorPage`, or `AccountsPage`. If a teacher-only section is selected and the user is not a teacher, the shell bounces back to `Section.session`.
- Two stacked overlays: [GoalSplashOverlay](lib/widgets/goal_splash_overlay.dart) and [LevelUpOverlay](lib/widgets/level_up_overlay.dart).

[shell_state.dart](lib/features/shell/shell_state.dart) defines `Section` (`session, map, goals, lessonContent, instructions, students`) and `SessionMode` (`explain, practice, free`). MCQs are not a separate `SessionMode` — they take over the practice surface whenever `activeMcqProvider` is non-null.

### Session view (mode-driven workspace)

[features/session/session_view.dart](lib/features/session/session_view.dart) renders the body for `Section.session`. It watches `modeProvider` and shows one of three mode views in the left panel, with an animated 460px chat panel on the right that hides while an MCQ is active or in `free` mode:

- **Uitleg** ([explain_view.dart](lib/features/session/modes/explain_view.dart), ~670 lines) — full markdown-rendered explanation canvas. Parses fenced ` ```python ` blocks, callouts (`> [!info]`), headings, paragraphs and renders them as styled cards (code with syntax highlighting, colored callouts with icons, sized headings). Renders subgoal header pill with root concept and `idx / total` counter; footer has "Vorige" ghost button and "Probeer het zelf" accent button (→ practice mode). Source is the authored `Content` doc linked from `Goal.contentId`; falls back to a placeholder when no content has been authored yet.
- **Oefenen** ([practice_view.dart](lib/features/session/modes/practice_view.dart)) — `ObjectiveBanner` + `RunControls` + `Editor` + `OutputPanel` with `multi_split_view`. When `activeMcqProvider != null`, it mounts [QuizView](lib/features/session/modes/quiz_view.dart) in place of the editor/output split.
- **Quiz (sub-mode of Oefenen)** ([quiz_view.dart](lib/features/session/modes/quiz_view.dart)) — full MCQ surface: header pill + `TutorMarkdown` prompt + optional code card (syntax highlighted) + 2-column option grid (badges A–F) + colored feedback panel (green/red, rendered via `TutorMarkdown`) + "Volgende" advance button. Reads/writes `activeMcqProvider`.
- **Vrij coderen** ([free_view.dart](lib/features/session/modes/free_view.dart)) — "speeltuin" header strip over a re-used `PracticeView(showObjective: false)`.

[ObjectiveBanner](lib/features/session/widgets/objective_banner.dart) reads the active goal from `goalSelectionProvider`. [RunControls](lib/features/session/widgets/run_controls.dart) renders Run/Stop as a pill button, plus ghost icon buttons for Reset, Hint (`tutorService.requestHint(code)`), and Send-to-tutor (`tutorService.submitCode(code)`).

### Python code panel (editor + execution)

- Editor: [features/dashboard/editor.dart](lib/features/dashboard/editor.dart) renders `CodeField` bound to the singleton `CodeService.controller`, themed via `tutorCodeTheme`. `CodeService.setText(...)` is how the tutor pushes new starter code.
- Runner: [features/session/widgets/output_panel.dart](lib/features/session/widgets/output_panel.dart) reads `outputServiceProvider` and renders an animated header (idle/running/ok/error pill), the line list with stdout/stderr styling, and an inline input row whenever `pendingInputRequest` is non-null.

### AI chat panel

- [features/chat/chat_widget.dart](lib/features/chat/chat_widget.dart) hosts `flutter_chat_ui`'s `Chat`, bound to `ChatService.controller`. A `ChatHeader` strip sits above the list. Composer swaps based on tutor state and MCQ flag (`composer_thinking`, `composer_continue`, `composer_mcq_disabled`, `composer_idle`).
- Bubbles: [tutor_bubble.dart](lib/features/chat/widgets/tutor_bubble.dart) (now renders body via `TutorMarkdown` for markdown + syntax-highlighted fences) with optional [RoleChip](lib/features/chat/widgets/role_chip.dart) (`uitleg | voorbeeld | denkvraag | goed`); [student_bubble.dart](lib/features/chat/widgets/student_bubble.dart); system messages as a centred [chat_system_pill.dart](lib/features/chat/widgets/chat_system_pill.dart).
- Streaming render: in-flight tutor replies use a `TextStreamMessage` placeholder. `ChatService.startStream/updateStream/completeStream/failStream` drive a `StreamState` exposed via `streamStateProvider`. `ChatService.addMcqOptions(...)` inserts a custom message that flips `mcqPendingProvider` true.

### Lesson content authoring (teacher)

[features/lesson_content/lesson_content_page.dart](lib/features/lesson_content/lesson_content_page.dart) is a teacher-only "Lesinhoud" page with a two-pane layout: a read-only module/goal tree on the left (module headers → root goals → subgoals, grouped by `moduleId`), a markdown editor on the right. On `initState()` it bootstraps the default module (`ModuleService.ensureDefaultModule()`) and runs `GoalsService.backfillModuleIds()` to populate `moduleId` on legacy docs. Selecting a subgoal loads its linked `Content` doc (or creates a blank one keyed by the subgoal id). Save upserts the `Content` doc and sets `Goal.contentId` if needed; a "Disconnect" action clears `Goal.contentId` while preserving the content doc. The subgoal editor in [features/goals/editor/goal_form.dart](lib/features/goals/editor/goal_form.dart) embeds an inline `_LesinhoudRow` showing whether content exists, with a one-click "Bewerk"/"Maak" handoff.

### Student progression / mastery (LO-belief model)

This is the heart of the redesign — the previous three-phase (guiding/warm-up/practice) conductor and 5-answer streak are gone, replaced by Bayesian belief tracking documented in `docs/CONDUCTOR_POLICY.md` and `docs/STUDENT_MODEL.md`. Numeric constants live in [services/tutor/policy_constants.dart](lib/services/tutor/policy_constants.dart); arithmetic in [services/tutor/belief_math.dart](lib/services/tutor/belief_math.dart).

**LO belief.** Each `(uid, subgoalId, loId)` carries a Beta(α, β) belief in `lo_beliefs`. Mean α/(α+β) is the posterior probability of correct answers; α+β is evidence strength. Beliefs are read with lazy exponential decay (half-life `PolicyConstants.decayHalfLife` = 60 days) so untouched LOs drift back toward the (1, 1) prior. `applyEvidence()` enforces an evidence cap (20) with a cap-then-shrink rule that scales existing excess down before adding new deltas, preserving relative ratios.

**Mastery (CONDUCTOR_POLICY §4.1).** An LO is mastered when **all three** hold: (1) mean ≥ 0.8, (2) evidence ≥ 4, (3) `lastPositiveAtCalibratedAt` is set (i.e. at least one positive signal at the student's calibration *at the time of that answer* — never reset by calibration shifts). There is no streak counter.

**Subgoal progression.** A subgoal advances when every non-optional LO is either mastered or stuck (evidence ≥ 8 AND mean < 0.6), and at least one is mastered. On advance, a cascade auto-skips already-mastered subgoals up to a depth cap; exceeding it halts and surfaces the student on that subgoal as a `cascadeHalt` event.

**Question selection (CONDUCTOR_POLICY §1–2).** The conductor picks the lowest-mean unmastered LO (weight as tiebreaker), with a recency guard against immediate re-probing. Question type is gated by LO `kind` (`recall` → MCQ/Socratic, `apply` → code completion/write, `predict` → MCQ/explain/Socratic, `reason` → explain/Socratic) and rotated against `account.calibration.recentQuestionTypes` for cross-LO variety. When all LOs are mastered, top-up picks the lowest-mean *practiceable* LO (mean between 0.5 and saturation); if none remain, returns `blocked: saturated`.

**Calibration (STUDENT_MODEL "Account doc").** A per-student notch (`easy | medium | hard`) maintained on `account.calibration`. Promoted when 4+ recent at-calibration answers reach ≥75% correct; demoted when 3+ recent reach ≥60% wrong/partial. Three consecutive demotions emits a `repeatedDemotions` strong event (once).

**Notch-drop (CONDUCTOR_POLICY §2.3).** Two consecutive negatives at the student's calibration on the *same LO* (without a positive in between) drops that LO's question difficulty by one notch for the next probe. The override lifts on the next positive at calibration. Tracked via `LoBelief.recentNegativesAtCalibrated`.

**Follow-up chains (CONDUCTOR_POLICY §6).** When the grader emits a follow-up question, the tutor presents it and grades the student's reply via `ChatRequestType.followUpAnswer`. Follow-up signals are capped to `weak` strength and the difficulty multiplier is forced to `medium`, regardless of the original probe's settings. Default depth cap is 1; subgoals with `allowChains: true` allow depth 2.

**Degraded mode (CONDUCTOR_POLICY §7.3).** The grader-fallback rate is tracked in a rolling window. When the threshold is exceeded (e.g. ≥3 fallbacks in the last 5 grading calls), the conductor enters degraded mode: `planNext()` returns a `degraded` plan, `TutorService` surfaces a Dutch system message ("Er is iets mis met de feedback…"), and a `sustainedLlmFailure` strong event is emitted. New questions halt until the session resets.

**Mid-session curriculum watch (CONDUCTOR_POLICY §7.4).** `TutorService` subscribes to the active root's children stream. If the active subgoal is deleted, the student is redirected to the next unmastered subgoal (`subgoalDeletedRedirect` audit event). If a new LO is added, the cached `progress` value is recomputed so a previously 1.0 subgoal flips back below.

**Persistence model.** `LoBeliefsService` reads/writes `lo_beliefs` (one upsert per affected LO per turn). `AccountService.setCalibration()` writes the embedded calibration substructure. `ProgressService.upsert` writes the derived `progress` cache and a best-effort `progress_history` sample. `TurnHistoryService.append()` writes a full `PersistedTurnRecord` to `turn_history` (best-effort — Cosmos blips don't dead-end the student flow).

**Student-facing surfaces.**
- [features/progress/leerpad_page.dart](lib/features/progress/leerpad_page.dart) — stack of [LeerpadCard](lib/features/progress/widgets/leerpad_card.dart)s, one per root goal; active card expands to show child chips ([leerpad_child_chip.dart](lib/features/progress/widgets/leerpad_child_chip.dart)) and a "Verder" CTA.
- [features/progress/student_progress_list.dart](lib/features/progress/student_progress_list.dart) + [goal_tile.dart](lib/features/progress/goal_tile.dart) — older list view, still used inside the teacher detail drawer.

### Level-up overlay

[services/progression/level_up_controller.dart](lib/services/progression/level_up_controller.dart) holds a nullable `LevelUpEvent`; [LevelUpOverlay](lib/widgets/level_up_overlay.dart) listens and fades in a celebration card. As of HEAD, no producer calls `push(...)` — wired but inert. TODO.md "Phase 6 — level-up trigger" tracks the open trigger decision.

### Teacher dashboard

- **Goal authoring:** [features/goals/goals_page.dart](lib/features/goals/goals_page.dart) — three-pane layout (roots / children / editor) with drag-and-drop reparent and reorder. Subtree backup/restore lives in [goals_service.dart](lib/services/goal/goals_service.dart). Reorder and subtree-delete use a Cosmos transactional batch since every doc shares the `/type = "goal"` partition. New **Export goals** / **Import goals** actions serialize to a v2 JSON envelope (`{version: 2, exportedAt, goals: [{goal, subgoals}, …]}`) including `moduleId`, `teachingTips`, `allowChains`, `objectives[]`, and `contentId`. Import offers two modes: **Add** (strict — aborts on any id collision) and **Replace** (upserts by id while preserving each existing `contentId` link, then deletes any goals not in the imported file). The subgoal editor surfaces an inline `_LesinhoudRow` showing whether authored content exists with a one-click handoff to the Lesinhoud page.
- **Lesinhoud:** [features/lesson_content/lesson_content_page.dart](lib/features/lesson_content/lesson_content_page.dart) — see "Lesson content authoring" above.
- **AI-instruction authoring:** [features/instructions/instructions_editor_page.dart](lib/features/instructions/instructions_editor_page.dart) — left pane lists instruction docs, middle lists named sections, right is a markdown `CodeField` editor. Save persists the whole `sections` map back to Cosmos. Supports importing/exporting Markdown via `file_picker`.
- **Account admin:** [features/account/accounts_page.dart](lib/features/account/accounts_page.dart) — paginated `DataTable` with columns EMAIL (with "last active" subtext), NAAM, STREAK (placeholder em-dash), HUIDIG DOEL (computed via `_activeRootTitle`), VOORTGANG (bar + % via `_overallRootProgress`), STATUS (active/idle dot + red badge with unacknowledged-strong-event count from `TurnHistoryService.watchStrongUnacknowledgedFor(uid)`), SLEUTEL (global-key switch), ACTIES (delete). Tapping a row opens [features/account/detail/student_detail_drawer.dart](lib/features/account/detail/student_detail_drawer.dart), which composes:
  - [student_status_summary.dart](lib/features/account/detail/student_status_summary.dart) — one-line "Recent actief op X" / "Geen recente activiteit" header.
  - [signal_events_section.dart](lib/features/account/detail/signal_events_section.dart) *(new)* — strong + audit events from `turn_history`, newest-first; severity dot + Dutch label per `TurnSignalEventKind`; "Bevestigen (n)" button calls `acknowledgeAllFor(uid)`.
  - The read-only goal/progress list (older `GoalTile` view).
  - [status_reports_section.dart](lib/features/account/detail/status_reports_section.dart) — per-subgoal AI status reports.
  - [progress_history_charts.dart](lib/features/account/detail/progress_history_charts.dart) — 30 days of progress-history line charts.
- **Debug dialog:** [features/dashboard/debug_dialog.dart](lib/features/dashboard/debug_dialog.dart) — teacher-only, `kDebugMode` only. "Wipe all progress" deletes `progress`, `progress_history`, `lo_beliefs`, `turn_history` for the current uid and resets calibration. "Show level-up overlay" tests the overlay. Difficulty picker + 5 question-type buttons trigger probes manually. A recent-turns list shows each turn's request type, quality, selection reason, follow-up depth, target LOs, calibration before/after, fallback flag, follow-up question, and signal events; tapping a turn pops a dialog with the full `PersistedTurnRecord` JSON.

### Crash recovery

[crash_recovery_screen.dart](lib/crash_recovery_screen.dart) is pushed onto the navigator by `safeCosmos` on Cosmos 401/403, and by `FlutterError.onError` for unhandled errors. Single button calls `resetAuthAndCacheAndExit()` ([core/cosmos_safety.dart](lib/core/cosmos_safety.dart)).

## 6. State management & data flow

### Pattern

`flutter_riverpod` for both DI and reactivity. Services are declared as `Provider<T>` (immutable), `NotifierProvider<N, S>` (mutable state machine), or `StateProvider<T>` (simple mutable value) and consumed via `ref.watch` / `ref.read` in `ConsumerWidget` / `ConsumerState`.

`ValueNotifier` + `ValueListenableBuilder` is still used for leaf state inside services where Riverpod granularity would be overkill (`OutputService.lines`, `OutputService.isRunning`, `OutputService.pendingInputRequest`).

Notable Riverpod providers:
- **Identity / account:** `authServiceProvider`, `isTeacherProvider`, `accountServiceProvider`, `localApiKeyStorageProvider`
- **Curriculum / content:** `goalsServiceProvider`, `goalSelectionProvider`, `globalConfigServiceProvider`, `instructionsServiceProvider`, `moduleServiceProvider` *(new)*, `contentServiceProvider` *(new)*
- **Tutor / mastery:** `tutorServiceProvider`, `chatServiceProvider`, `loBeliefsServiceProvider` *(new)*, `turnHistoryServiceProvider` *(new)*, `splashServiceProvider`, `outputServiceProvider`
- **Shell / UI:** `sectionProvider`, `modeProvider`, `ambientProgressProvider`, `profileProvider`
- **Chat-flow state:** `streamStateProvider`, `mcqPendingProvider`, `activeMcqProvider` *(new — non-null while an MCQ is in flight; takes over the practice surface)*
- **Progression:** `levelUpControllerProvider`

### Cosmos REST + polling

[core/cosmos_client.dart](lib/core/cosmos_client.dart) is a hand-rolled REST client (~420 lines) that signs requests with HMAC-SHA256 over the canonical Cosmos auth payload (`MasterKeyAuth`). It supports `read`, `query` (with continuation-token pagination), `create`, `upsert`, `replace`, `delete`, and atomic `executeBatch` for multi-doc transactions within a single partition. 429s are retried internally up to 3 times honouring `x-ms-retry-after-ms`, capped at 5 s; 401/403 surface as `CosmosException` with `isAuthError == true`.

Reactivity is built on **polling**: [`pollingStream`](lib/core/cosmos_safety.dart) emits an immediate first fetch on subscribe, then ticks on `kCosmosPollInterval` (5 s) without overlapping requests. `safeCosmos` wraps one-shots and pushes `CrashRecoveryScreen` on auth errors; `safeCosmosStream` logs auth/throttle errors flowing through a stream without swallowing them.

### Boot flow

1. `WidgetsFlutterBinding.ensureInitialized()` and `FlutterError.onError` wired to the recovery screen.
2. A `ProviderContainer` is created manually; `authServiceProvider.notifier.tryAcquireTokenSilent()` is awaited *before* `runApp`. The container is handed to `UncontrolledProviderScope`.
3. `GoalsApp` (`ConsumerWidget`) watches `authServiceProvider`, `accountServiceProvider`, and `localApiKeyStorageProvider`:
   - `identity == null` → `SignInPage`.
   - account doc still loading → spinner.
   - `!mayUseGlobalKey && !hasLocalKey` → `LocalKeyGateScreen`.
   - else → `AppShell`.
4. `AppShell.initState` schedules `_checkForUpdate()` once after the first frame.
5. `AccountService` listens to the auth identity. On a new identity it calls `_ensureProfile`, subscribes to `watchAccount(uid)`, and on the first non-null emission calls `TutorService.initializeSession(force: true)` once per uid.

### One graded turn (UI → grader → beliefs → audit)

1. Student answers via the chat composer (or picks an MCQ option in `QuizView` / `mcq_options_widget`).
2. `ChatWidget.onMessageSend` (or the MCQ click handler) → `TutorService.handleStudentMessage(text)` routes to a `ChatRequestType` based on the in-flight plan (`submitCode`, `mcqAnswer`, `explainAnswer`, `socraticFeedback`, `followUpAnswer`).
3. `TutorService.queryTutor(...)` builds an `input` JSON via `QuestionFormatter` (grading payloads now carry `target_los` *and* `goal_scope_los` so the grader can validate signals against the active root's full LO set). `InstructionGenerator.generateInstructions(type)` assembles the system prompt as `envelopeContract + alwaysInclude + typeSpecific`, with `{targetLOs}`, `{goalScopeLOs}`, `{teachingTips}` (alias `{suggestions}`), `{goal}`, `{subgoal}` substituted; legacy `{known concepts}` expands to empty. Streamable types call `OpenaiConnector.sendRequestStream`; grader and `status` calls go through non-streaming `sendRequest`.
4. The response is parsed by `AIResponseParser.parse(...)` (envelope-first, legacy-JSON fallback) into a `ChatResponse` subtype and dispatched via `dispatchResponse(parsed, ctx)` in [response_handlers.dart](lib/services/tutor/responses/response_handlers.dart) to one of 13 `*Handler` classes. Each handler receives a `TutorContext` of small callbacks so the strategy code stays free of cross-service knowledge.
5. **Question handlers** (`SocraticQuestion`, `MultipleChoice`, `CompleteCode`, `ExplainCode`, `WriteCode`) set the in-flight exercise type, push starter code into `CodeService` if relevant, and play a sound. `MultipleChoiceHandler` shuffles the option list with `Random()` before passing it to `setActiveMcq()` to defeat positional bias in the LLM's option ordering — the grader only sees the option *text* the student picked, so round-trip integrity is preserved.
6. **Grading handlers** (`CodeFeedback`, `McqFeedback`, `ExplainFeedback`, `SocraticFeedback`) call `TutorService.integrateGradedAnswer(...)`:
   - [graded_answer_builder.dart](lib/services/tutor/responses/graded_answer_builder.dart) validates each `GraderPayload` signal against the `scopeSubgoals` (the active root's children). If every signal is out-of-scope or malformed, it synthesises a single weak signal on the originally-targeted LO (positive/neutral/negative from the grader's overall quality) and sets `hadFallback = true` for degraded-mode tracking.
   - `Conductor.integrateAnswer(...)` reads the affected `LoBelief`s (with decay), maps each signal through `belief_math.signalDeltas(kind, strength, askedDifficulty)` to (αDelta, βDelta), applies them via `applyEvidence` (cap-then-shrink at 20), updates `lastPositiveAtCalibratedAt` / `recentNegativesAtCalibrated`, and persists each affected belief. It then updates `account.calibration` (window append, possible promote/demote), recomputes the cached subgoal `progress` value, and detects subgoal advancement.
   - On advancement, the cascade fires (auto-skipping already-mastered subgoals up to the cap), surfaces sounds + splash, and arms the next exercise; on cap-overflow it emits `cascadeHalt`.
   - Strong/audit events are appended to the in-flight `PersistedTurnRecord` (e.g. `stuckLoAdvance`, `singleLoDeadlock`, `repeatedDemotions`, `sustainedLlmFailure`, `cascadeHalt`, `emptyObjectivesBlock`, `subgoalDeletedRedirect`).
   - `TurnHistoryService.append(record)` writes the full audit doc.
   - The handler returns one of `IntegrateOutcome.advancing | followUpPresented | continuing`. If a follow-up was emitted by the grader and the conditions in `_shouldPresentFollowUp()` pass (depth ≤ cap; LO not stuck; allowChains for depth 2), the tutor stores it and asks the chained question; otherwise the handler chains into `requestExercise()`.
7. **Status / hint / answer handlers** apply their effects and don't update beliefs. `StatusSummary` routes through `ReportService.updateForCurrentChildGoal(...)` and persists to `status_reports`. `Hint` calls `Conductor.hintProvided()` (no-op under the new model; kept for compatibility). `Answer` is a generic non-graded reply.

### Teacher-authored AI instructions → runtime prompt

1. Teacher edits `instructions/{docId}.sections{key: text}` in [InstructionsEditorPage](lib/features/instructions/instructions_editor_page.dart). Each `docId` is named after a `ChatRequestType`; a special `alwaysInclude` doc holds shared instructions.
2. On every tutor request, [InstructionGenerator.generateInstructions(type)](lib/services/tutor/instruction_generator.dart) reads instruction docs from `InstructionsService.cachedAll`, finds the doc whose id matches the `ChatRequestType` name, concatenates its sections, then assembles the prompt as `envelopeContract + alwaysInclude + typeSpecific` (deliberate order for prompt-cache prefix stability).
3. Each section is run through `_replaceTags(...)` which substitutes `{goal}`, `{subgoal}`, `{teachingTips}` (alias `{suggestions}`), `{targetLOs}`, `{goalScopeLOs}` (case-insensitive, whitespace-tolerant). `{known concepts}` is silently expanded to empty for backward compatibility with old instruction docs.
4. The assembled string is sent to `OpenaiConnector` as the system message. The user-turn payload is a JSON object built by [QuestionFormatter](lib/services/tutor/question_formatter.dart). Question helpers take `targetLOs: List<LearningObjective>`; grading helpers take `targetLOs` + `goalScopeLOs`; new `followUpAnswer()` carries the follow-up question, student answer, optional rationale, and chain depth.
5. The connector keeps two history lists capped at 50 entries each, and includes one of them per call based on `PreviousInputs.includeAll | includeSession | newSession`. The streaming path only records the user turn into history once the stream finalises successfully and the parsed response isn't an `ErrorResponse`.

## 7. Known limitations / TODOs / rough edges

See [TODO.md](TODO.md) for the current planning doc. The load-bearing design docs are `docs/CONDUCTOR_POLICY.md`, `docs/STUDENT_MODEL.md`, and `docs/LLM_CONTRACT.md`. Notable rough edges visible in the code itself:

- **Lesson content is half-wired.** The Lesinhoud authoring page works end-to-end, but only some subgoals have authored `Content`. `ExplainView` falls back to a placeholder where no content exists, and the markdown renderer is the canvas's only content source — there's no curriculum tree of "lessons" yet.
- **Module management UI is deferred.** `ModuleService.ensureDefaultModule()` bootstraps `python-basics`; there's no UI to create or rename modules. The Lesinhoud tree groups by `moduleId`, so adding more modules later is structurally cheap.
- **Level-up overlay is wired but inert.** [LevelUpOverlay](lib/widgets/level_up_overlay.dart) listens to `levelUpControllerProvider`, but no producer calls `push(...)` yet. Profile gamification fields (`level`, `xp`, `streak`) in [shell_state.dart](lib/features/shell/shell_state.dart) are placeholders. TODO.md "Phase 6" tracks the trigger.
- **Dead UI files left on disk.** [home_shell.dart](lib/home_shell.dart), [theme.dart](lib/theme.dart), [features/dashboard/dashboard.dart](lib/features/dashboard/dashboard.dart), [features/dashboard/output.dart](lib/features/dashboard/output.dart), [features/dashboard/controllers.dart](lib/features/dashboard/controllers.dart), and [features/dashboard/editor_controller.dart](lib/features/dashboard/editor_controller.dart) are no longer referenced.
- **Cosmos auth is master-key.** [cosmos_client.dart](lib/core/cosmos_client.dart) has an `AadTokenAuth` stub for the eventual swap to per-user AAD RBAC; until then every authenticated student holds the database master key.
- **No realtime listeners.** All cross-device updates rely on a 5 s `pollingStream` tick.
- **Local API key not used.** `LocalApiKeyStorage.saveKey(...)` writes to `SharedPreferences`, the gate screen requires it, but `OpenaiConnector._apiKey = Env.apiKey` always uses the build-time obfuscated key.
- **`config/global` ApiKey field unused.** Only `GlobalConfig.model` is consumed by `OpenaiConnector`.
- **Tokens stored unencrypted.** The Entra token bundle lives in `shared_preferences`. Per the school's "I don't care if students tamper" stance.
- **`crash_recovery_screen.dart` has an unreachable `exit(0)`** after `resetAuthAndCacheAndExit()`.
- **No sandboxing of student code.** The script runs in a child process via `py_runner` with full filesystem/network access.
- **`dart_openai` is pinned to a personal fork** (`https://github.com/yvanvds/openai.git`).
- **Windows-only.** No iOS/Android/macOS/Linux/Web target.
- **All UI text is Dutch and hard-coded** throughout services and widgets; no i18n layer.
- **Goal import "Replace" mode preserves contentId but not authored Content docs themselves.** A re-imported tree keeps the link, but if the imported tree omits a subgoal, the link is dropped and the orphaned `Content` doc is left in the container.
- **`isWarmUp` is a vestigial field** on `progress_history` samples — the new conductor has no warm-up phase but writes `false` for backward compatibility with the existing time-series.

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
  `OPEN_AI_API_KEY` and `COSMOS_KEY` are obfuscated at build time via `envied`; the others are not secrets.

- **Entra app registration prerequisites** (Azure Portal → App registrations → your app):
  - "Authentication" → add `http://localhost` as a redirect URI under "Mobile and desktop applications".
  - "App roles" → define a `Teacher` role and assign it to teacher accounts.
  - "API permissions" → `openid`, `profile`, `email`, `offline_access` (delegated, Microsoft Graph).

- **Cosmos DB** account with database `python-tutor` and containers:
  - per-user (partition `/uid`): `accounts`, `progress`, `progress_history`, `status_reports`, `lo_beliefs`, `turn_history`, `playground_files`
  - single-partition (partition `/type`): `goals`, `instructions`, `config`, `content`, `modules`

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

# Tests (mocktail-based unit + widget tests under test/)
flutter test

# End-to-end flows on the Windows desktop (integration_test/, issue #28):
# real app root + shell + services, in-memory Cosmos, bypassed sign-in.
# All flows run from one entrypoint (app_test.dart) in one app process;
# a single flow: flutter test integration_test/flows/<flow>.dart -d windows
flutter test integration_test -d windows

# Build a release Windows executable
flutter build windows --release

# Package as an installer (.exe via Inno Setup) — see distribute_options.yaml + windows/packaging/
flutter pub global activate flutter_distributor
flutter_distributor release --name=windows
```

### Update channel

A release build publishes a manifest at `https://yvanvds.github.io/AI-tutor-Python/version.json` (GitHub Pages, served from a GitHub Releases asset). On launch, [app_shell.dart](lib/features/shell/app_shell.dart) fetches that manifest and, if newer, downloads `python_teacher_install.exe`, verifies SHA-256, and runs it `/VERYSILENT /NORESTART` before exiting.
