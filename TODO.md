# Migration plan: Firebase → Azure (Entra ID + Cosmos DB for NoSQL)

This plan is meant to be executed across multiple separate Claude Code sessions, one step per session. Each step lists which files it touches, which are off-limits, and what "done" looks like. **No code is written yet** — only this plan.

## Architectural summary

**Target end state:**
- **Auth**: Microsoft Entra ID (school tenant) via MSAL. Replaces `firebase_auth` and the email/password flow in [lib/features/auth/sign_in_page.dart](lib/features/auth/sign_in_page.dart).
- **Data**: Azure Cosmos DB for NoSQL, accessed directly from the Flutter desktop client (no backend). Replaces `cloud_firestore`.
- **Roles**: Teacher vs student is encoded as an Entra **app role** (or group claim) on the access token. Replaces the `roles/{uid}` Firestore collection and [lib/services/role/role_service.dart](lib/services/role/role_service.dart) re-reads from token claims, not Cosmos.
- **Identity field**: every place that uses `_auth.currentUser?.uid` (Firebase uid, ~28 chars) becomes the Entra account's **Object ID** (`oid` claim, GUID). Stored in the same `uid` field across containers.

**Service-layer impact (these files change, public APIs do not):**
- [lib/core/firestore_paths.dart](lib/core/firestore_paths.dart) → renamed to `lib/core/cosmos_paths.dart`, exposes `CosmosPaths` returning typed container handles.
- [lib/core/firestore_safety.dart](lib/core/firestore_safety.dart) → renamed to `lib/core/cosmos_safety.dart`, exposes `safeCosmos` / `safeCosmosStream` and an Azure-aware `resetAuthAndCacheAndExit`.
- [lib/services/account/account_service.dart](lib/services/account/account_service.dart), [lib/services/role/role_service.dart](lib/services/role/role_service.dart), [lib/services/progress/progress_service.dart](lib/services/progress/progress_service.dart), [lib/services/status_report/report_service.dart](lib/services/status_report/report_service.dart), [lib/services/goal/goals_service.dart](lib/services/goal/goals_service.dart), [lib/services/instructions/instructions_service.dart](lib/services/instructions/instructions_service.dart), [lib/services/config/global_config_service.dart](lib/services/config/global_config_service.dart) → reimplemented against Cosmos. All `ValueNotifier`s and method signatures preserved so [features/](lib/features/) is untouched.
- Models that import `cloud_firestore` ([goal.dart](lib/services/goal/goal.dart), [account.dart](lib/services/account/account.dart), [progress.dart](lib/services/progress/progress.dart), [status_report.dart](lib/services/status_report/status_report.dart), [instruction.dart](lib/services/instructions/instruction.dart), [global_config.dart](lib/services/config/global_config.dart)) → drop the import. Replace `Timestamp` with `DateTime` and `FieldValue.serverTimestamp()` with a client-side `DateTime.now().toUtc().toIso8601String()` written into the doc.
- [lib/main.dart](lib/main.dart) → drop `Firebase.initializeApp`, drop the `FirebaseAuth.authStateChanges()` `StreamBuilder`, replace with an MSAL-driven auth state notifier.
- [lib/boot_gate.dart](lib/boot_gate.dart), [lib/crash_recovery_screen.dart](lib/crash_recovery_screen.dart) → keep the safe-mode shape, but the "reset" only needs to clear MSAL token cache + any local Cosmos response cache (nothing like the LOCALAPPDATA Firestore directories anymore).
- [lib/features/auth/sign_in_page.dart](lib/features/auth/sign_in_page.dart) → replaced by an MSAL "Sign in with school account" button. Register flow disappears (Entra owns identity).
- [lib/firebase_options.dart](lib/firebase_options.dart), [firestore.rules](firestore.rules), [firestore.indexes.json](firestore.indexes.json) → deleted in the final step.

**Untouched (off-limits across every step):**
- [lib/services/tutor/](lib/services/tutor/) — TutorService, Conductor, OpenaiConnector, InstructionGenerator, the entire `responses/` folder. None of it talks to Firestore directly.
- [lib/features/dashboard/](lib/features/dashboard/) — Python editor + output runner via `py_engine_desktop`.
- [lib/features/chat/](lib/features/chat/) — flutter_chat_ui composer island.
- [lib/services/code/](lib/services/code/), [lib/services/output/](lib/services/output/), [lib/services/chat/](lib/services/chat/), [lib/services/sound/](lib/services/sound/), [lib/services/splash/](lib/services/splash/) — local-only.
- [lib/services/tutor/env.dart](lib/services/tutor/env.dart) and the obfuscated `OPEN_AI_API_KEY` in `.env` — keep as-is (see open question on `Env.apiKey`).

**Packages added:** `azure_cosmosdb` or `azure_data_cosmos` (TBD — see open questions), `msal_flutter` or `microsoft_kiota_msal_dart` or `aad_oauth` (TBD), `dart_jsonwebtoken` (only if we end up parsing claims locally instead of relying on the MSAL package).

**Packages removed (in the final step):** `firebase_core`, `cloud_firestore`, `firebase_auth`.

## Container & partition key spec

| Container | Partition key | Doc id pattern | Notes |
|---|---|---|---|
| `accounts` | `/uid` | `uid` | One doc per user. Flat — no subcollections. Mirrors current `accounts/{uid}` doc. |
| `progress` | `/uid` | `${uid}_${goalId}` | **Restructure**: today this is the subcollection `accounts/{uid}/progress/{goalId}`. Becomes flat `{id, uid, goalId, progress, updatedAt}`. Per-user query is partition-scoped (`WHERE c.uid = @uid`), cheap. |
| `status_reports` | `/uid` | `${uid}_${goalId}` | Same flattening as progress, mirrors current `accounts/{uid}/status_reports/{goalId}`. Fields: `{id, uid, goalId, statusReport, updatedAt}`. |
| `goals` | `/type` (always `"goal"`) | Cosmos-generated id, kept stable across the migration | Single logical partition. Tree is small (≲100 docs) and shared by all users. Each doc carries `type: "goal"`. Existing fields kept: `title, description, parentId, order, optional, suggestions, knownConcepts`. |
| `instructions` | `/type` (always `"instruction"`) | matches current id (e.g. `system_prompt`) | Single logical partition. Doc shape: `{id, type, sections, updatedAt}`. |
| `config` | `/type` (always `"config"`) | `global` | Single doc. `{id: "global", type: "config", Model, ApiKey}`. |

**Roles**: no Cosmos container. Read from Entra app-role claim on the access token.

**Indexing**: default indexing policy is fine for everything. The only query that benefits from a composite index is `goals` filtered by `parentId` ordered by `order`, but with ≲100 docs in a single partition Cosmos will scan it in microseconds — leave the default policy.

## Real-time updates: replacement strategy

This is the biggest functional change. Firestore `snapshots()` listeners exist in every service. Cosmos has a change feed, but consuming it from a desktop client without a backend is awkward (long-running pull loops, lease container overhead).

**Decision**: keep the `Stream<T>` shape on the service public API. Internally implement each `watchX` / `streamX` as:
1. Emit current value on subscribe.
2. Re-read on a polling timer (default 5s for the active container, slower or stopped for hidden views — start with one global polling cadence).
3. Force a refresh immediately after any local mutation so the UI feels instant (write-through).

This is fine because:
- This is a single-user-at-a-time desktop app — no concurrent multi-client editing of one student's progress.
- The teacher-authored containers (`goals`, `instructions`, `config`) almost never change at runtime — polling them is cheap.
- The student data containers (`progress`, `status_reports`) only change in response to local actions, where refresh-on-write covers the vast majority of cases.

The polling implementation lives inside `safeCosmosStream` (or a dedicated `pollingStream` helper) so individual services don't reimplement it. **Step 1 owns this design** and every service step in Step 3+ just uses the helper.

## Revised step ordering (and why it differs from the proposal)

The proposed Step 2 (auth swap) before Step 4 (account/progress migration) leaves [lib/services/account/account_service.dart](lib/services/account/account_service.dart) reading Firestore by a uid that no longer exists — Entra OIDs (GUIDs) and Firebase uids (random 28-char strings) don't overlap. So between Step 2 and Step 4, every signed-in user would see "no account doc" until their Firestore record is recreated, which means `mayUseGlobalKey` and `targetGoal` are wrong, the `LocalKeyGateScreen` triggers wrongly, etc. Not a hard break, but enough that I'd rather not ask Yvan to live in that state across multiple sessions.

**Revision**: do Step 3 (read-mostly containers, `goals` / `instructions` / `config`) **before** the auth swap, since those don't depend on `uid` at all. Then do auth + per-user data (`accounts` / `progress` / `status_reports`) **together** in one step, because they're tightly uid-coupled.

This collapses the proposal's 7 steps to 6 and keeps the app continuously runnable, except for the brief moment in Step 4 where you sign out of Firebase and back in via Entra.

---

## Step 0 — Provision Azure + add packages + config plumbing

**Goal**: get every Azure resource and credential we need into Yvan's hands, plus the SDKs into [pubspec.yaml](pubspec.yaml). Nothing wired up. App still runs unchanged on Firebase.

**Manual / portal work (Yvan does this — Claude can't):**
- Create a Cosmos DB for NoSQL account in the school's existing Azure subscription. Recommend **serverless** mode (see open questions). Database name: `python-tutor`.
- Create the six containers from the spec table above with the exact partition keys listed.
- Register an Entra app for the desktop client (public client / native, redirect URI for MSAL desktop). Add an app role `Teacher`. Optionally a group claim.
- Capture: Cosmos endpoint URL, Cosmos primary key (or AAD-based RBAC role assignment for the user — see open questions), Entra tenant ID, app (client) ID, redirect URI.

**Code changes:**
- Add to [pubspec.yaml](pubspec.yaml): the chosen Cosmos package, the chosen MSAL package. Keep all Firebase packages.
- Create `lib/services/config/azure_config.dart` (new file): a single class holding `cosmosEndpoint`, `cosmosKey` (or token provider), `tenantId`, `clientId`, `redirectUri`, sourced from `--dart-define` flags or an extended `.env` via `envied`.
- Add `azure_config.g.dart` to `.gitignore` if going the `envied` route.
- Document required `--dart-define`s or `.env` entries at the top of `azure_config.dart` and in a short comment block in [README](#) (or in this TODO).

**Off-limits:** every service file, [lib/core/firestore_*](lib/core/), [lib/main.dart](lib/main.dart), [features/](lib/features/).

**Done when:** `flutter pub get` succeeds, `flutter analyze` clean, app runs, sign-in still works, all features still work — i.e. zero behavioral change. The new packages are present but unused.

---

## Step 1 — Cosmos data layer scaffolding (no service migrated)

**Goal**: build the equivalent of [lib/core/firestore_paths.dart](lib/core/firestore_paths.dart) + [lib/core/firestore_safety.dart](lib/core/firestore_safety.dart) for Cosmos. Provide a thin client wrapper so future steps don't sprinkle SDK calls everywhere.

**Code changes:**
- New `lib/core/cosmos_client.dart`: lazy singleton `CosmosClient`. Initialized once with `azureConfig` + a token provider (which in Step 4 becomes "MSAL acquireTokenSilent for the Cosmos resource"; for now, can use the master key or a stub). Exposes `container(name)` returning a typed container handle.
- New `lib/core/cosmos_paths.dart`: `CosmosPaths` with one accessor per container (`accounts()`, `progress()`, `statusReports()`, `goals()`, `instructions()`, `config()`). Mirrors the API shape of `FsPaths` so service migrations are mechanical.
- New `lib/core/cosmos_safety.dart`: `safeCosmos<T>(Future<T> Function() op)` and `safeCosmosStream<T>(...)`. Catches Cosmos's permission/throttling errors (HTTP 401/403/429), routes 401/403 to `CrashRecoveryScreen` like `safeFirestore` does today. **Also implement the polling-based `pollingStream<T>(Future<T> Function() fetch, {Duration interval})` here** — every service in later steps relies on it.
- New `lib/core/cosmos_doc_id.dart` (small utility): helpers like `progressDocId(uid, goalId) => '${uid}_${goalId}'` so the doc-id convention is in one place.

**Off-limits:** every service file (no migrations yet), [lib/main.dart](lib/main.dart), [lib/firebase_options.dart](lib/firebase_options.dart), the `firestore_*` files (still in use, leave them), [features/](lib/features/).

**Done when:** `flutter analyze` clean, app still runs on Firebase, `CosmosClient` can be instantiated and a smoke-test read against an empty container succeeds (write a one-off `dart run` script or just verify in a temporary `main.dart` snippet that you delete before committing). The scaffolding is unused by any service.

**Reminders for the future session executing this step:**
- The polling interval, max retries, and 429 backoff policy are decided here. Pick once, don't relitigate later.
- `safeCosmosStream` semantics: it should expose a `Stream<T>` whose first emission happens immediately (not after the first poll interval). Otherwise every screen flashes a spinner.

---

## Step 2 — Migrate the read-mostly, non-uid containers (`goals`, `instructions`, `config`)

**Goal**: prove the data layer works end-to-end on the lowest-risk surface area before touching auth or per-user data. Auth is still Firebase, accounts are still in Firestore.

**Code changes:**
- Rewrite [lib/services/goal/goals_service.dart](lib/services/goal/goals_service.dart) against `CosmosPaths.goals()`. Replace `_collection.where(...).snapshots()` with `pollingStream` over a SQL query (`SELECT * FROM c WHERE c.parentId = @parentId ORDER BY c.order`). Keep every public method signature and every `ValueNotifier`. Replace the `applyOrder` batch with a Cosmos transactional batch (same partition key, so it works in one logical partition).
- Rewrite [lib/services/instructions/instructions_service.dart](lib/services/instructions/instructions_service.dart). The Firestore `withConverter` pattern goes away; the service handles `(de)serialization` directly through the model's existing `toMap`/`fromMap`. Public API unchanged.
- Rewrite [lib/services/config/global_config_service.dart](lib/services/config/global_config_service.dart). Single doc read, polling stream, public API unchanged. **Keep the existing `LocalApiKeyStorage` instance and `localStorage` getter** even though the `apiKey` field on `GlobalConfig` is dead — that's a pre-existing rough edge, not this migration's job.
- Update [lib/services/goal/goal.dart](lib/services/goal/goal.dart), [lib/services/instructions/instruction.dart](lib/services/instructions/instruction.dart), [lib/services/config/global_config.dart](lib/services/config/global_config.dart) to drop `package:cloud_firestore/cloud_firestore.dart`. Replace `Timestamp` → `DateTime` (parse from ISO 8601 string), `FieldValue.serverTimestamp()` → `DateTime.now().toUtc().toIso8601String()` written into the doc. Add `id` and the constant `type` field on serialization for the partition key.
- Update [lib/services/goal/subtree_backup.dart](lib/services/goal/subtree_backup.dart) only if its data shape needs adjustment.
- **Data**: before running the app for this step, manually copy the existing Firestore `goals`, `instructions`, and `config/global` data into Cosmos via the portal Data Explorer (or save it for the Step 6 script and accept that the dev environment is empty until then). Yvan's call.

**Off-limits:** [lib/services/account/account_service.dart](lib/services/account/account_service.dart), [lib/services/progress/progress_service.dart](lib/services/progress/progress_service.dart), [lib/services/status_report/report_service.dart](lib/services/status_report/report_service.dart), [lib/services/role/role_service.dart](lib/services/role/role_service.dart), [lib/main.dart](lib/main.dart), [lib/firebase_options.dart](lib/firebase_options.dart), [lib/features/auth/](lib/features/auth/), [features/](lib/features/) in general (UI must stay unchanged).

**Done when:**
- `flutter analyze` clean.
- App runs, sign-in via Firebase still works.
- Manual test plan:
  1. Open the goals page ([lib/features/goals/goals_page.dart](lib/features/goals/goals_page.dart)). Verify root goals load.
  2. Create / rename / reorder / delete a goal. Verify the change persists across an app restart.
  3. Open the instructions editor ([lib/features/instructions/instructions_editor_page.dart](lib/features/instructions/instructions_editor_page.dart)). Edit a section, save, restart, verify.
  4. Verify `globalConfig.config.value` is non-null after a few seconds (the polling stream emitted).
  5. Verify the chat / tutor flow still works (it consumes goals + instructions + config indirectly via TutorService).
- The `roles`, `accounts`, `progress`, `status_reports` containers are still untouched. RoleService, AccountService, ProgressService, ReportService still talk to Firestore. The app is in a hybrid state but fully functional.

**Reminders for the future session:**
- Reuse `CosmosPaths` and `safeCosmos` — don't reinvent.
- Don't change any service's public API. The `features/goals/`, `features/instructions/` UI must build with zero edits.
- When implementing `streamRoots` etc., remember `pollingStream` must emit synchronously on first subscribe (the goals tree UI assumes a value is available within one frame).

---

## Step 3 — Migrate auth (Entra/MSAL) + per-user containers in one shot

**Goal**: replace `firebase_auth` with MSAL, replace the role doc with token claims, and migrate `accounts`, `progress`, `status_reports` to Cosmos. These move together because they all key on `uid` — splitting them would leave the app reading user data by a stale identity.

**Code changes — auth:**
- Add an `AuthService` (new file, `lib/services/auth/auth_service.dart`) that wraps the chosen MSAL package. It exposes:
  - `ValueNotifier<AccountIdentity?> currentUser` (or a stream) where `AccountIdentity = (oid, displayName, email, isTeacher)` derived from MSAL account + token claims.
  - `Future<void> signIn()`, `Future<void> signOut()`, `Future<String> getCosmosToken()` (for AAD-RBAC) or no-op if using the Cosmos master key.
  - On startup: `acquireTokenSilent` first; only show the interactive sign-in screen if that fails.
- Wire `AuthService` into [lib/services/data_service.dart](lib/services/data_service.dart) like the other services.
- Rewrite [lib/features/auth/sign_in_page.dart](lib/features/auth/sign_in_page.dart): single "Sign in with school account" button (and an explanatory note). Drop the email/password/register flow entirely.
- Update [lib/main.dart](lib/main.dart): remove `Firebase.initializeApp` and the `FirebaseAuth.authStateChanges()` `StreamBuilder`. Listen to `AuthService.currentUser` instead. Keep the `MultiValueListenableBuilder` shape and the `LocalKeyGateScreen` decision logic.
- Update [lib/services/role/role_service.dart](lib/services/role/role_service.dart): drop the Firestore listener; derive `isTeacher` from `AuthService.currentUser.value?.isTeacher`. Keep the `ValueNotifier<bool> isTeacher` public API.

**Code changes — per-user data:**
- Rewrite [lib/services/account/account_service.dart](lib/services/account/account_service.dart) against `CosmosPaths.accounts()`. The constructor subscribes to `AuthService.currentUser` instead of `FirebaseAuth.authStateChanges()`. `currentUid` getter returns the Entra OID. Replace `_doc(uid).snapshots()` with `pollingStream`. **Move profile creation off the sign-in page**: in `AuthService` post-sign-in (or in `AccountService`'s reaction to `currentUser`), if the Cosmos doc doesn't exist, create it from the MSAL account's name + email claims. The `upsertAccount` path stays for the teacher UI in [lib/features/account/accounts_page.dart](lib/features/account/accounts_page.dart) but its caller list shrinks.
- Rewrite [lib/services/progress/progress_service.dart](lib/services/progress/progress_service.dart). Note the doc-id change: today `_col(uid).doc(goalID).set(...)` writes to `accounts/{uid}/progress/{goalId}`. New code writes to `progress` container with id `${uid}_${goalId}` and partition key `uid`. The `Progress` model gets a `uid` field on serialization. Public API (`getAll`, `watchAll`, `getByGoalId`, `streamByGoalId`, `upsert`, `delete`, `currentProgress`) unchanged.
- Rewrite [lib/services/status_report/report_service.dart](lib/services/status_report/report_service.dart) the same way. `StatusReport` model gets a `uid` field on serialization.
- Update [lib/services/account/account.dart](lib/services/account/account.dart), [lib/services/progress/progress.dart](lib/services/progress/progress.dart), [lib/services/status_report/status_report.dart](lib/services/status_report/status_report.dart): drop `cloud_firestore` import, replace `Timestamp` with `DateTime`, replace `FieldValue.serverTimestamp()` with client-side ISO string. Remove the dead `Account.update` static (it's a transaction wrapper that no `features/` file uses — verify with a quick grep before deleting).
- Update [lib/home_shell.dart](lib/home_shell.dart) line 123: replace `FirebaseAuth.instance.signOut()` with `DataService.auth.signOut()`.
- Update [lib/features/account/accounts_page.dart](lib/features/account/accounts_page.dart) line 276: change the warning text from "FirebaseAuth user" to "Entra user" (or generic "school account").

**Off-limits:** [lib/services/goal/](lib/services/goal/), [lib/services/instructions/](lib/services/instructions/), [lib/services/config/](lib/services/config/) (already done), [features/](lib/features/) **except** the two files explicitly listed above ([sign_in_page.dart](lib/features/auth/sign_in_page.dart), [accounts_page.dart](lib/features/account/accounts_page.dart) line 276), [lib/firebase_options.dart](lib/firebase_options.dart) and [firestore.rules](firestore.rules) (deleted in Step 5, not now — `firebase_core` and `firebase_auth` are still imported indirectly during this step? **Actually no**: we drop both `firebase_core` and `firebase_auth` initialization here, and we should also drop the `cloud_firestore` imports from the migrated files. Leaving `firebase_options.dart` on disk is fine; it just becomes unused).

**Done when:**
- `flutter analyze` clean.
- Manual test plan:
  1. Cold start the app. The sign-in page shows the MSAL button. Sign in with a school account.
  2. Verify that `currentAccount` populates (poll-based, may take a beat). Check that `firstName`/`lastName` come from the Entra `name` claim and `email` from the `email`/`upn` claim.
  3. Sign in with the teacher account. Verify `RoleService.isTeacher.value` is `true` and the teacher UI shows.
  4. Sign in with a student account. Verify `isTeacher` is `false`.
  5. Open the chat and answer a tutor question. Verify progress updates persist (re-open app, progress is still there).
  6. Open status reports view. Verify writes persist.
  7. Open the teacher accounts page. Verify the "may use global key" toggle still works.
  8. Sign out → sign back in. Verify the account doc is reused, not duplicated.
- **Note**: this step necessarily breaks Firebase auth. If something goes wrong, rolling back means reverting commits — there's no in-app fallback. Plan for the session to keep changes in one branch and not merge until manual testing passes.

**Reminders for the future session:**
- The MSAL package's threading and Windows redirect-URI handling is fiddly; lean on the package's example app patterns rather than improvising.
- Cosmos auth: if going AAD-RBAC, every Cosmos call needs a fresh AAD token for the `https://<account>.documents.azure.com` resource. Cache it inside `CosmosClient` and refresh on 401.
- Don't introduce a new state library; stick to `ValueNotifier`.
- The `LocalApiKeyStorage` / `mayUseGlobalKey` flow continues to work as-is. Don't reshape it.

---

## Step 4 — Remove Firebase entirely

**Goal**: delete the dead Firebase code path so the codebase isn't carrying two SDKs.

**Code changes:**
- Remove from [pubspec.yaml](pubspec.yaml): `firebase_core`, `cloud_firestore`, `firebase_auth`. Run `flutter pub get`.
- Delete [lib/firebase_options.dart](lib/firebase_options.dart).
- Delete [firestore.rules](firestore.rules), [firestore.indexes.json](firestore.indexes.json), and any `firebase.json` / `.firebaserc` if they exist at the repo root.
- Delete [lib/core/firestore_paths.dart](lib/core/firestore_paths.dart) and [lib/core/firestore_safety.dart](lib/core/firestore_safety.dart) (they should already be unused after Step 3 — verify with a grep).
- In [lib/boot_gate.dart](lib/boot_gate.dart) and [lib/crash_recovery_screen.dart](lib/crash_recovery_screen.dart), the calls into `resetAuthAndCacheAndExit()` now point at the Azure-aware version that lives in `cosmos_safety.dart` (already created in Step 1). Drop the LOCALAPPDATA Firestore directory cleanup logic from that function — it's pointing at directories that no longer exist.
- Grep the codebase for any remaining `firebase` / `Firestore` / `FieldValue` / `Timestamp` references. There should be none.

**Off-limits:** none specifically — but no behavioral changes, only deletions.

**Done when:**
- `flutter pub get` succeeds with Firebase packages absent.
- `flutter analyze` clean.
- Manual smoke test: same flow as Step 3, app behaves identically.
- `git grep -i firebase lib/` returns nothing (modulo this TODO file).

---

## Step 5 — Production data migration script + cutover checklist

**Goal**: get the existing Firestore production data (Yvan's class data) into Cosmos exactly once, then flip the production app over.

**Code changes:**
- New `scripts/migrate_firestore_to_cosmos.dart` (a one-off `dart run` script, not part of the app). Steps: (1) read all Firestore collections via the Admin SDK (or the public client SDK with a one-time admin login), (2) transform each doc to its Cosmos shape (flatten `accounts/{uid}/progress/*` → `progress` with composite ids, ditto for `status_reports`, add `type` fields where needed), (3) upsert into Cosmos via the same `CosmosClient`. The script must be **idempotent** (re-runnable without duplication) — use deterministic doc ids everywhere.
- A short `MIGRATION_CUTOVER.md` (or extend this TODO with a final checklist section): pre-cutover snapshot, run-the-script command, post-cutover verification queries (count of accounts, count of progress, spot-check a known student), rollback note ("if it goes wrong, the Firestore data still exists; revert the binary, point users back to the previous build").
- A user-uid mapping table: this is the trickiest part. Existing Firestore docs are keyed by Firebase uid; new code expects Entra OID. Two options:
  1. Build a `firebase_uid → entra_oid` map by hand (Yvan can list his class's emails and look up each Entra OID once), feed it into the script as a JSON file. The script rewrites `uid` in every account/progress/status_report doc during transformation.
  2. Have the migration script accept an email-keyed export and let it look up Entra OIDs via the Microsoft Graph API.

  Recommend option 1 — Yvan's class is small, the manual list is ~20 minutes of work and zero ambiguity.

**Off-limits:** [lib/](lib/) (the script must not depend on app runtime state).

**Done when:**
- The script runs against a Firestore export (or live Firestore) and populates an empty Cosmos account correctly.
- Spot-check: pick three students, sign in as each in the new build, verify their progress and status reports are intact.
- Cutover checklist exists in repo and Yvan has run through it once on a non-production Cosmos account.

---

## Per-step guardrails (worth re-reading at the start of each session)

- **Reuse `safeCosmos` and `CosmosPaths`.** Don't reinvent in service files.
- **Service public APIs are fixed.** Every `ValueNotifier`, every method signature on `GoalsService` / `AccountService` / `ProgressService` / `ReportService` / `InstructionsService` / `GlobalConfigService` / `RoleService` stays identical. If a feature file under [features/](lib/features/) needs editing because of a service change, that's a sign you broke the contract — go back and fix the service instead.
- **Don't touch the OpenAI / tutor pipeline.** [lib/services/tutor/](lib/services/tutor/) (especially [conductor.dart](lib/services/tutor/conductor.dart), [tutor_service.dart](lib/services/tutor/tutor_service.dart), [openai_connector.dart](lib/services/tutor/openai_connector.dart), [instruction_generator.dart](lib/services/tutor/instruction_generator.dart), the `responses/` folder) consumes services through `DataService.*` and doesn't need to change.
- **Don't touch the Python runner.** [lib/features/dashboard/](lib/features/dashboard/) is independent of any of this.
- **Don't fix unrelated rough edges as part of this migration.** The unused `LocalApiKeyStorage` wiring, the dead `config/global.ApiKey` field, the dead [editor_controller.dart](lib/features/dashboard/editor_controller.dart), the always-pip-install in [output.dart](lib/features/dashboard/output.dart), the unused `Account.update` static — leave them (or delete `Account.update` only if Step 3 actually requires touching that file, since it's already in scope). Note any of these that become relevant in passing, don't actively chase them.
- **Real-time means polling.** Don't try to be clever with Cosmos change feed from the desktop client. The polling helper from Step 1 is the answer everywhere.
- **No automated tests exist.** Every step's "done when" must include a concrete manual test plan, not just "compiles and analyzes clean."

---

## Open questions for Yvan to answer before Step 0

1. **Cosmos auth model**: AAD-RBAC (every request authorized by the user's Entra access token, no shared secrets) or Cosmos master key (simpler, but a long-lived secret has to ship with the desktop binary)? Given the explicit "I don't care about students tampering" stance, the master key is acceptable and a lot simpler. **Recommendation: master key**, embedded the same way `OPEN_AI_API_KEY` is embedded today (via `envied` obfuscation). If you ever change your mind, AAD-RBAC is a Step-0.5 swap.

2. **Cosmos throughput**: serverless or provisioned (manual / autoscale)? For a single classroom's traffic, serverless is dramatically cheaper and has no idle cost. **Recommendation: serverless**.

3. **MSAL package**: there are several Flutter MSAL options and none are first-party from Microsoft for desktop. Candidates: `msal_flutter` (mobile-focused, may not work on Windows), `aad_oauth` (manual OAuth2 flow, works everywhere but you handle the PKCE flow yourself), or rolling our own with `oauth2` + `flutter_web_auth_2`. **Recommendation**: investigate `aad_oauth` first — Windows desktop support is the gating factor. If it falls short, fall back to a hand-rolled OAuth2 + system browser flow. Decide in Step 0 so Step 3 doesn't block.

4. **Cosmos package**: `azure_cosmosdb` (community) is the most mature pub.dev option but hasn't seen recent updates; `azure_data_cosmos` is newer but thinner. Or call the Cosmos REST API directly via `package:http` (well-documented, no SDK dependency, ~200 LOC for the operations we need). **Recommendation**: REST + `http` directly. It's the safest long-term bet given how thin our usage is — 90% of what we do is `query`, `read`, `upsert`, `delete` on six containers. Confirm in Step 0.

5. **`Env.apiKey` obfuscation**: today the OpenAI key is obfuscated by `envied` via [lib/services/tutor/env.dart](lib/services/tutor/env.dart). The Firebase config in [lib/firebase_options.dart](lib/firebase_options.dart) is plain text but that's a Firebase artifact — not a secret in the same sense. Question: should the Cosmos master key (if we go that route) and the Entra client ID/tenant ID be obfuscated the same way? Client ID + tenant ID are not secrets and can be plain text. The Cosmos master key **should** be obfuscated. Confirm before Step 0.

6. **Updater + Windows-only constraint**: the in-app updater (whatever it currently is — out of my view) and Windows-only build target stay unchanged. Confirm there's no Mac/Linux/iOS Entra build that would force a different MSAL package.

7. **Data migration timing**: do you want Step 2 (the read-mostly migration) to start with empty Cosmos containers and let you populate test data manually via the portal, or should I include a tiny "copy goals/instructions/config from Firestore" snippet inside Step 2 itself? **Recommendation**: empty containers in Step 2, since the goal-tree is small and easy to recreate manually for dev purposes; reserve the migration script for production cutover in Step 5.
