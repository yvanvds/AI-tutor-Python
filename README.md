# AI-tutor-Python

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python) [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=coverage)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python) [![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python) [![Vulnerabilities](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=vulnerabilities)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python)

A Windows desktop application that acts as a personal AI tutor for Python students. A single window combines:

- an embedded Python editor with a **Run** button (no separate Python install needed — the runtime is bundled),
- a chat panel where an OpenAI-backed tutor asks the student questions, gives hints, marks answers, and adapts the difficulty,
- a teacher side where you author the *goals* (a tree of learning objectives) and the *instructions* (the prompts that shape the tutor's behaviour) without touching any code,
- per-student progress tracking, status reports, and history charts.

The tutor follows a teacher-defined goal tree, picks the type of exercise (multiple choice, explain-this-code, complete-the-code, write-code, Socratic question, …), and only marks a sub-goal as mastered once the student answers correctly across several different question types. The app is in Dutch and English: the interface, the lessons and what the tutor writes.


---

> **For now the app only works for students of SMA Arcadia.** They sign in with their Arcadia Microsoft account, and the teacher switches the account on. A version you can use outside the school is being worked on: follow [#261](https://github.com/yvanvds/AI-tutor-Python/issues/261).

## ⚠️ This build cannot be used as-is

The published binaries are hard-wired to **our school's Microsoft 365 (Entra ID) tenant** — only accounts in that tenant can sign in, and they are the only accounts the configured Azure Cosmos DB will accept. If you download a release from this repository and run it, you will get stuck on the sign-in screen.

To use this project in your own classroom you have to **build your own copy** with your own credentials. The good news: you do not need to touch any of the Dart code. You only need to:

1. Create three things in the cloud (one Entra app registration, one Cosmos DB account, one OpenAI API key).
2. Paste six values into a `.env` file.
3. Run two commands to produce a Windows installer.

The rest of this README walks through that. No prior Flutter/Dart experience is required, but you should be comfortable opening the Azure portal, copying GUIDs, and running PowerShell commands.

---

## What you will end up with

A `python_teacher_install.exe` (Inno Setup installer, ~150 MB) that you can hand to students. After install they sign in once with their school Microsoft account and the app remembers them. There is also a built-in updater: publish a GitHub release with the installer attached and every running copy will offer to update itself.

---

## Prerequisites on your machine

You need these tools installed once. All free.

1. **Flutter SDK 3.47.1** — <https://docs.flutter.dev/get-started/install/windows>. After installing run `flutter doctor` and fix any red items, especially the Visual Studio "Desktop development with C++" workload (required for Windows builds). This is the exact version CI installs (`FLUTTER_VERSION` in [.github/workflows/build.yml](.github/workflows/build.yml)). An older SDK now fails `flutter pub get` outright, because `pubspec.yaml` requires `sdk: ^3.13.1` (the Dart version bundled with Flutter 3.47.1). Building works on newer ones, but `dart format` output differs between Dart versions, so only this one is guaranteed to agree with CI's format gate.
2. **Git** — <https://git-scm.com/download/win>.
3. **Inno Setup 6** — <https://jrsoftware.org/isdl.php>. Used by the packaging step to produce the `.exe` installer.
4. A code editor (VS Code recommended) — only needed if you want to edit Dutch text or tweak settings.

---

## Step 1 — Create an OpenAI API key

1. Go to <https://platform.openai.com/api-keys>.
2. Sign in (or create an OpenAI account) and click **Create new secret key**.
3. Copy the key (`sk-...`). It goes in your database, as `ApiKey` in `config/global` ([Step 6](#step-6--first-run-and-bootstrapping-content)).
4. Make sure the OpenAI account has billing set up and a usage limit you are comfortable with — every student message costs a few tenths of a cent.

The default model is `gpt-4o`, configurable later from inside the app (Teacher → settings).

---

## Step 2 — Create the Microsoft Entra app registration

This is what lets your students sign in with their school Microsoft account.

1. Sign in to <https://portal.azure.com> as a tenant admin (or ask your IT person — they need to do this once).
2. Go to **Microsoft Entra ID** → **App registrations** → **New registration**.
   - **Name:** `AI Tutor Python` (anything you like).
   - **Supported account types:** *Accounts in this organizational directory only* (single-tenant).
   - **Redirect URI:** leave blank for now, we set it in the next step.
   - Click **Register**.
3. On the new app's **Overview** page, copy:
   - **Application (client) ID** → this is your `ENTRA_CLIENT_ID`.
   - **Directory (tenant) ID** → this is your `ENTRA_TENANT_ID`.
4. Go to **Authentication** → **Add a platform** → **Mobile and desktop applications** → check **Custom redirect URIs** and add exactly `http://localhost` (no port, no trailing slash). Save.
5. Go to **API permissions** and make sure these *delegated* Microsoft Graph permissions are listed: `openid`, `profile`, `email`, `offline_access`. Add any that are missing, then click **Grant admin consent for &lt;your tenant&gt;**.
6. Go to **App roles** → **Create app role**:
   - **Display name:** `Teacher`
   - **Allowed member types:** *Users/Groups*
   - **Value:** `Teacher` (must be exactly this string — the code checks for it)
   - **Description:** anything.
   - Enable the role.
7. Assign the role to yourself: go to **Enterprise applications** → search for the same app → **Users and groups** → **Add user/group** → pick yourself → assign the `Teacher` role. Students do not need any role assignment; they just need to exist in your tenant.

> **Why no client secret?** This is a desktop app, so authentication uses PKCE + a loopback redirect — no secret to leak.

---

## Step 3 — Create the Azure Cosmos DB

This stores accounts, goals, progress, instructions, and status reports.

1. In the Azure portal, **Create a resource** → **Azure Cosmos DB** → **Azure Cosmos DB for NoSQL**.
2. Pick a subscription and resource group, give it an account name (e.g. `mypython-tutor`), pick a region close to you, **Capacity mode: Serverless** (cheapest for classroom use). Click **Review + create**.
3. Once deployed, open the account → **Data Explorer** → **New Database** named exactly **`python-tutor`**.
4. Inside that database, create the containers below. The **partition key** column matters — get it right.

   | Container name   | Partition key |
   |------------------|---------------|
   | `accounts`       | `/uid`        |
   | `progress`       | `/uid`        |
   | `progress_history` | `/uid`      |
   | `status_reports` | `/uid`        |
   | `playground_files` | `/uid`      |
   | `lo_beliefs`     | `/uid`        |
   | `turn_history`   | `/uid`        |
   | `grade_proposals` | `/uid`       |
   | `reports`        | `/uid`        |
   | `goals`          | `/type`       |
   | `instructions`   | `/type`       |
   | `config`         | `/type`       |
   | `content`        | `/type`       |
   | `modules`        | `/type`       |
   | `milestones`     | `/type`       |
   | `questions`      | `/subgoalId`  |
   | `translations`   | `/language`   |
   | `turn_content`   | `/uid`        |
   | `podium`         | `/type`       |

   The list the app actually uses is `lib/core/cosmos_paths.dart` — every
   container it can open is declared there, with its partition key in the doc
   comment. This table is checked against that file by
   `test/core/cosmos_paths_readme_parity_test.dart`, so the two cannot drift
   apart unnoticed again.

   **Updating an existing deployment:** a new app version can add a container
   (`reports` arrived with report publishing, #150), and nothing creates it
   in your account for you. After an update, compare this table with the
   containers in your database. A container that is still missing shows up
   in the app as `Container "<name>" does not exist in Cosmos database
   "python-tutor"` (#170) — create it with the partition key listed above.

   `questions` (the question bank, #185) is the one container the app can
   run without: until it exists, students practise as before and nothing is
   stored or served from it (#186), and the teacher's **Questions** page
   says the container is missing. Its partition key is `/subgoalId`, not
   `/uid` or `/type`.

   `translations` (translated lessons and goal texts, #206) can be missing
   too: until it exists, every student sees the lessons and goal texts in
   Dutch, whatever language they picked in Options. Its partition key is
   `/language`. From the Azure CLI:
   `az cosmosdb sql container create --account-name <account> --resource-group <group> --database-name python-tutor --name translations --partition-key-path /language --partition-key-version 2`

   `turn_content` (the question, answer and feedback of each oefening,
   #228) can be missing too: until it exists, nothing of it is stored and
   the students practise as before. Create it with **Time to Live on, no
   default** (`defaultTtl: -1`; in the Data Explorer: *Time to Live* → *On
   (no default)*): every doc sets its own `ttl` and expires at the end of
   the school year, but only in a container with TTL on — without it the
   docs are kept forever. From the Azure CLI:
   `az cosmosdb sql container create --account-name <account> --resource-group <group> --database-name python-tutor --name turn_content --partition-key-path /uid --partition-key-version 2 --ttl -1`

   `podium` (the class podium, #221) is a container of its own since #338;
   before, it was the partition `podium` of `config`. Students write their
   places there, so with access through their own sign-in (#306) they need
   read and write on `podium` but only read on `config`. Until it exists,
   nobody gets a place on the podium; `tooling/badges/podium_backfill.py`
   can fill in those places afterwards. Create it before you release the
   version that moves the podium, then copy the places that are still in
   `config` with `python tooling/badges/podium_copy.py` (a dry run; add
   `--apply` to write). Run the copy again once `MinimumVersion` keeps the
   older builds out, for places they wrote in `config` in the meantime. The
   old docs stay in `config` until you remove them. From the Azure CLI:
   `az cosmosdb sql container create --account-name <account> --resource-group <group> --database-name python-tutor --name podium --partition-key-path /type --partition-key-version 2`

   An existing deployment may still have a `period_start_snapshots`
   container: nothing writes or reads it since formula v1.0.16 (#191), and
   a fresh deployment does not need it.

5. Go to **Settings** → **Keys**. Copy:
   - **URI** → this is your `COSMOS_ENDPOINT` (looks like `https://yourname.documents.azure.com:443/`).
   - **PRIMARY KEY** → this is your `COSMOS_KEY`. Treat it like a password.

> Cosmos serverless billing is roughly per-request. With one classroom polling every 5 seconds you should land well under €5/month, but check your own subscription's cost alerts.

---

## Step 4 — Get the source code and configure `.env`

```powershell
git clone https://github.com/yvanvds/AI-tutor-Python.git
cd AI-tutor-Python
```

Create a file named `.env` in the repo root (the same folder as `pubspec.yaml`) with **exactly these six lines**, replacing the placeholders with the values you collected in steps 1–3:

```
OPEN_AI_API_KEY=sk-your-openai-key-here
COSMOS_ENDPOINT=https://yourname.documents.azure.com:443/
COSMOS_KEY=your-cosmos-primary-key-here
ENTRA_TENANT_ID=00000000-0000-0000-0000-000000000000
ENTRA_CLIENT_ID=00000000-0000-0000-0000-000000000000
ENTRA_REDIRECT_URI=http://localhost
```

A few things to know:

- The file is **gitignored** — it will not get committed. Do not paste it into a chat or screenshot.
- The values are read at build time by the `envied` package. Keep the file private: it holds your own keys.
- `ENTRA_REDIRECT_URI` must be exactly `http://localhost` to match step 2.4.
- `OPEN_AI_API_KEY` is only a fallback. The school's key comes from `ApiKey` in `config/global` ([Step 6](#step-6--first-run-and-bootstrapping-content)); the app uses this value only while that field is empty. With `dummy` here there is no fallback, and `ApiKey` is the only key.
- There is a seventh, **optional** line — `GITHUB_OAUTH_CLIENT_ID` — for in-app bug reports. Leave it out and everything else works; the Options panel simply says it cannot sign in to GitHub. [Step 8](#step-8-optional--in-app-bug-reports-github-oauth-app) sets it up.

---

## Step 5 — Build the installer

From the repo root, in PowerShell:

```powershell
# Download Dart/Flutter dependencies
flutter pub get

# Generate the obfuscated env file from your .env (re-run this if you change .env)
dart run build_runner build --delete-conflicting-outputs

# Build the embedded Python interpreter students' code runs on (needs internet;
# takes a few minutes the first time, then it is cached)
pwsh tooling/python/build_bundle.ps1

# Quick sanity check: open the app on your machine
flutter run -d windows
```

**About that Python bundle.** The app runs student code in an interpreter it ships itself, which the installer places next to the executable. A `flutter run` build has no installer, so it looks for a development bundle instead: if `build_bundle.ps1` has been run, `flutter run -d windows` finds `build/python_bundle/` on its own and the **Run** button works. Skip the bundle step and the app still starts, but pressing **Run** shows a red "no Python environment found" message that tells you exactly this and names the script to run. (Release builds never do this lookup — they use only what the installer put in place.)

To point a dev build at some *other* interpreter, set **both** `PY_RUNNER_PYTHON` and `PY_RUNNER_HOST_SCRIPT` (an interpreter and a path to `packages/py_runner/python/host.py`) before launching; setting only one is ignored. The checked-in VS Code launch configuration already does this.

If `flutter run` opens a window with a sign-in screen and you can sign in with your school account, your config is correct. Close it and build the installer:

```powershell
# Build a release executable
flutter build windows --release

# Package it as an Inno Setup installer
flutter pub global activate flutter_distributor   # one-time
flutter_distributor release --name=windows
```

The installer ends up in `dist/<version>/python_teacher_install.exe`. That is the file you give to your students.

---

## Step 6 — First run and bootstrapping content

When you start the app for the first time:

1. Sign in with your own (Teacher-role) Microsoft account. The app creates an `accounts/{your-uid}` document automatically.
2. Because you have the `Teacher` role, you will see the teacher pages in the sidebar: **Goals**, **Lesson content**, **Questions**, **Instructions**, **Students**, …
3. **Instructions.** The prompts that shape the tutor are in [instructions-export.md](instructions-export.md). Go to **Instructions** and use **Import from Markdown** to load it. Each document's id is the name of a request type in `ChatRequestType` ([lib/core/chat_request_type.dart](lib/core/chat_request_type.dart)), plus `alwaysInclude`, which goes along with every call; the file is the full list. It can lag behind what runs live, so if you have access to a working deployment, export a fresh copy there first (**Export all to Markdown**).

   Placeholders filled in at runtime: `{goal}`, `{subgoal}`, `{teachingTips}`, `{targetLOs}` and `{goalScopeLOs}`. The old name `{suggestions}` still works as `{teachingTips}`; `{known concepts}` is replaced by nothing.
4. **Goals and lessons.** You do not build the goal tree by hand. The goal files and their lessons are in `Goal Generator Cowork Project/AI Tutor for Python Goals Generator/` (`goals/` and `lessons/`). [tooling/curriculum/push_goal.py](tooling/curriculum/push_goal.py) writes a goal and its Dutch lessons to the database (`plan` first for a dry run, then `push`), and [tooling/translations/translations.py](tooling/translations/translations.py) `push` writes the English texts. Both need Python 3 and read the Cosmos values from your `.env`.
5. **The OpenAI key.** In the Cosmos Data Explorer, open the document `global` in the `config` container (partition key `config`), or create it, and set `ApiKey` to the key from Step 1:

   ```json
   { "id": "global", "type": "config", "Model": "gpt-4o", "ApiKey": "sk-..." }
   ```

   Every account with the school's key (the **KEY** switch on the **Students** page) calls OpenAI with it; the other accounts use a key of their own, entered in the app. A new key reaches every open app within a few seconds, without a new build. While `ApiKey` is empty, the app falls back on `OPEN_AI_API_KEY` from `.env` (Step 4); without that, the tutor sends nothing and tells the student that the school has not set a key yet. Changing the model in the app leaves `ApiKey` as it is. From a script, `tooling/evaluation/cosmos.py` can read the document and write it back with `ApiKey` filled in (partition key `config`).
6. Optional: edit `config/global` from the Cosmos Data Explorer if you want to switch to a different OpenAI model (e.g. `gpt-4o-mini` for cheaper runs). The field is `Model`. `MinimumVersion` (#165) is optional: set it (for example `2.6.0`) to keep every older build out — such a build shows an update screen instead of the app until it is updated, so a device that keeps declining the update cannot go on writing documents in an outdated shape. Leave it out, or blank, to allow every build. `QuestionBankMinimum` and `QuestionBankShare` (#186) are optional too: once the question bank holds at least `QuestionBankMinimum` questions that fit what the tutor is about to ask (default 8) and that the student has not had, the question comes from the bank instead of being generated with a chance of `QuestionBankShare` (0 to 1, default 0.5; 0 switches serving from the bank off). See `docs/CONDUCTOR_POLICY.md` §2.7. `TurnContentKeepUntil` (#228) is optional as well: the day, `MM-DD`, until which the question, answer and feedback of each oefening are kept in `turn_content` (midnight Belgian time; default `07-01`, the end of the school year). See `docs/CONDUCTOR_POLICY.md` §8.4.

Once that is done, hand the installer to a student. They sign in with their school account, the app creates their profile automatically, and the tutor starts at the first incomplete subgoal.

---

## Step 7 (optional) — Updates

On launch a release build asks GitHub for this repository's latest release
(`https://api.github.com/repos/yvanvds/AI-tutor-Python/releases/latest`,
unauthenticated) and offers to download the new installer if the tag is
higher than the running version. A release has to carry two assets:

- `python_teacher_install.exe` — the installer, found by that name (a lone
  `.exe` under another name is accepted too).
- `python_teacher_install.exe.sha256` — its checksum, in `sha256sum` shape.
  Without it the download cannot be verified and the release is not offered.

`tooling/build_release.ps1` builds, tags and publishes both. Drafts and
pre-releases are skipped by GitHub's `/releases/latest` itself, so a
pre-release tag is never pushed at a student.

To point the app at your own fork, change `kReleaseOwner` / `kReleaseRepo` in
[lib/core/github_release.dart](lib/core/github_release.dart). If you do not
need auto-updates, you can ignore this entirely; the app still works.

---

## Step 8 (optional) — In-app bug reports (GitHub OAuth app)

**Options → Bug reports** lets a student file a GitHub issue from inside the
app, with the debug payload of the running session attached. Signing in uses
GitHub's **OAuth device flow**: the app shows an eight-character code, the
student approves it at `https://github.com/login/device` in a browser they are
already signed into, and the app receives a token. No personal access token,
no scope picking, nothing to paste.

That needs one OAuth app registered under the account that owns the issue
tracker. It is the only part of this feature that cannot come from the code.
**Without it the app still runs**; the Bug reports card just says the build was
compiled without a client id and offers no sign-in.

### 8.1 — Register the OAuth app

1. Sign in to <https://github.com> as the account that owns the repository
   issues should be filed on (`yvanvds/AI-tutor-Python`, or your fork).
2. Go to <https://github.com/settings/applications/new> — the same page as
   **Settings → Developer settings → OAuth Apps → New OAuth App**. This is an
   *OAuth App*, **not** a GitHub App and **not** a personal access token.
3. Fill in:
   - **Application name:** `AI Tutor Python` (students see this on the
     approval screen, so name it something they will recognise).
   - **Homepage URL:** `https://github.com/yvanvds/AI-tutor-Python` (your
     fork's URL if you forked).
   - **Redirect URI:** the form requires one, but the device flow never
     redirects, so the value is never used. Put the homepage URL again, and
     leave **Allow wildcard matching** off. (GitHub used to call this field
     *Authorization callback URL*; it is the same thing renamed.)
   - **Enable Device Flow:** ✅ **tick this.** It is the one setting that
     matters — without it GitHub answers every request with
     `device_flow_disabled`. If the checkbox is not on the registration form
     in your account, click **Register application** first, then open the new
     app's settings page, tick **Enable Device Flow**, and click **Update
     application**.
   - **Expire user access tokens:** ❌ **untick this.** It is on by default.
     Leaving it on makes every student's token die after eight hours and hands
     the app a `refresh_token` to exchange for a new one — which this app does
     not do: it stores only the access token, so the next bug report after
     eight hours fails with GitHub's raw `Bad credentials` and no prompt to
     sign in again. Since bug reports are occasional, that is very nearly
     every report. Unticked, the token is long-lived, scoped to
     `public_repo`, kept per device, and revocable at any time from the app's
     page or the student's own settings. If you would rather keep expiry on,
     the app needs refresh-token support first.
4. Click **Register application**.
5. On the app's page, copy the **Client ID** (it looks like `Ov23li…`). It is
   public — it ships inside the installer by design.
6. **Do not generate a client secret.** GitHub no longer creates one for you at
   registration; there is a **Generate a new client secret** button on the
   app's page afterwards. Do not press it. The device flow has no secret, which
   is exactly why it suits an app handed out to students; a secret compiled
   into the binary would be a secret handed out with it.

### 8.2 — Put the client id in `.env`

Add a seventh line to the `.env` from [Step 4](#step-4--get-the-source-code-and-configure-env):

```
GITHUB_OAUTH_CLIENT_ID=Ov23liYourClientIdHere
```

Then regenerate and rebuild:

```powershell
dart run build_runner build
flutter build windows --release
```

### 8.3 — The scope, and what students approve

The app requests exactly one scope: **`public_repo`**.

- It is the narrowest OAuth-app scope that can create an issue on a public
  repository. There is no issues-only scope in the OAuth-app model — that
  granularity exists only for GitHub Apps and fine-grained personal access
  tokens — and the empty scope is read-only, so it cannot post anything.
- `repo`, which most examples use, is deliberately *not* requested: it would
  also give the app write access to every **private** repository the student
  can see.
- Be aware that `public_repo` is not repository-scoped: it grants write access
  to the student's *public* repositories too. That is a limitation of OAuth
  apps, not of this code, and it is what the GitHub approval screen tells the
  student before they approve.
- Nothing is granted at registration time. The scope is requested per student,
  each of whom approves it once on GitHub. You do not tick any scope box when
  registering the app.
- If you move the repository into a GitHub **organisation** that has OAuth App
  access restrictions turned on, an org owner also has to approve this app for
  the organisation.

The scope is a single constant, `kGitHubOAuthScope` in
[lib/services/github/github_device_flow.dart](lib/services/github/github_device_flow.dart);
the repository issues go to is `kBugReportRepo` in
[lib/services/github/github_issue_service.dart](lib/services/github/github_issue_service.dart).

The token that comes back is stored per device in `SharedPreferences`, next to
the student's own OpenAI key — the same place the pasted token used to live.
A device that already has a token from the old paste-a-token flow keeps
working; the card offers **Disconnect** to clear it.

---

## The school file

A school file lets students point the app at their school without a build of its own ([#307](https://github.com/yvanvds/AI-tutor-Python/issues/307)). It is a small JSON file with no keys or passwords in it, so the teacher can share it freely — on the learning platform, by mail, on a USB stick:

```json
{
  "formatVersion": 1,
  "schoolName": "Example School",
  "tenantId": "<Directory (tenant) ID from Step 2>",
  "clientId": "<Application (client) ID from Step 2>",
  "databaseEndpoint": "https://<your-account>.documents.azure.com:443/",
  "databaseName": "python-tutor"
}
```

`databaseName` is optional (default `python-tutor`). So is `databaseAccess`, how the app reaches the database: `"masterKey"` (the default) with the database key of the build, or `"signIn"` with the user's own sign-in ([#306](https://github.com/yvanvds/AI-tutor-Python/issues/306)). A build without school data uses the sign-in for every school file, with or without this field ([#336](https://github.com/yvanvds/AI-tutor-Python/issues/336)), so the school file of an existing install keeps working as it is. The sign-in needs roles on the database and admin consent in the tenant first: see [Access with the user's own sign-in](#access-with-the-users-own-sign-in-for-an-administrator). The app refuses a file that has a field named like a key, token or password, and a file with a newer `formatVersion` than it knows; it then says why and changes nothing.

How the app uses it:

- **First start.** When the app has no school yet, it asks: *I have a file from my school* (pick the file, then sign in) or *Continue without a school* (the stand-alone mode, [#261](https://github.com/yvanvds/AI-tutor-Python/issues/261)). Nothing is chosen for the student.
- **Kept.** The imported file is stored as `school.json` in the app's data folder, and the next start goes straight to that school.
- **Options.** The *School* card shows the school's name, imports another school file, or leaves the school. In the stand-alone mode it imports a school file. Switching asks for a restart; the data of the stand-alone mode and of the school stay apart.

A build that has a school configuration in its `.env` (Step 4) starts in that school as before, without asking.

The school's OpenAI key is not in the school file either: it is `ApiKey` in the school's own `config/global` (Step 6), so every school pays for its own use.

Today only SMA Arcadia's setup exists. The school file only spreads the configuration: a school that wants the school mode still needs Steps 2 and 3 (its own app registration and database, with its content), and until access through the user's own sign-in is switched on ([#306](https://github.com/yvanvds/AI-tutor-Python/issues/306)) a build made with that school's `.env` as well. The sign-in needs the roles and the consent of the next section.

---

## Access with the user's own sign-in (for an administrator)

With `"databaseAccess": "signIn"` in the school file, or in any build without school data ([The school file](#the-school-file)), the app reaches the database with the user's own sign-in instead of the database key ([#306](https://github.com/yvanvds/AI-tutor-Python/issues/306)). Cosmos DB then decides itself what each user may do, from roles you assign. Without those roles and the consent below, the database refuses every request of the app (403), so set them up before you switch the sign-in on. Both need administrator rights and happen outside the app, once per school.

You need:

- **Two security groups** in Entra ID: one with the students, one with the teachers. Which groups (new ones, or groups the school already has) is the school's choice. Copy each group's **Object ID** (**Microsoft Entra ID** → **Groups** → the group → **Overview**). Give the teachers' group the same people as the `Teacher` app role of [Step 2](#step-2--create-the-microsoft-entra-app-registration): the app role decides which pages the app shows, the group what the database allows.
- **The Azure CLI** (`az`), signed in with `az login` as someone who may manage the Cosmos DB account (for example *Owner* or *DocumentDB Account Contributor* on it).

### Admin consent

The app asks Entra for a token for the database, with the delegated permission `user_impersonation` of Azure Cosmos DB. Grant it once for the whole organisation, so that no student ever sees a consent screen:

1. In the Azure portal, go to **Microsoft Entra ID** → **App registrations** → the app of Step 2 → **API permissions**.
2. **Add a permission** → **APIs my organization uses** → search for **Azure Cosmos DB** → **Delegated permissions** → tick **`user_impersonation`** → **Add permissions**.
3. Click **Grant admin consent for &lt;your tenant&gt;** and confirm. The *Status* column now says *Granted*.

### Roles per container

Cosmos DB has two built-in data roles, and they are all this needs:

| Role | Role definition id |
|------|--------------------|
| Cosmos DB Built-in Data Reader | `00000000-0000-0000-0000-000000000001` |
| Cosmos DB Built-in Data Contributor | `00000000-0000-0000-0000-000000000002` |

A role reaches a whole container, or the whole database, never a partition or a single document.

Teachers get Data Contributor on the whole database. Students get, per container, what the app does there in a student's session: **read and write** is Data Contributor, **read** is Data Reader, **none** is no role.

| Container | Students | What a student's session does there |
|-----------|----------|-------------------------------------|
| `accounts` | read and write | creates the profile at the first sign-in; streak, XP and badges after each oefening |
| `progress` | read and write | the progress per goal after each oefening; a reset or an import in Options |
| `progress_history` | read and write | a progress sample after each oefening |
| `status_reports` | read and write | the report per subgoal |
| `lo_beliefs` | read and write | what the student masters, after each oefening |
| `turn_history` | read and write | a record per graded answer |
| `turn_content` | read and write | the question, the answer and the feedback of each oefening |
| `playground_files` | read and write | the files of the Playground |
| `questions` | read and write | stores a new question and counts each answer; shared by all students |
| `podium` | read and write | claims a place on the class podium; shared by all students |
| `goals` | read | the goal tree |
| `instructions` | read | the tutor's prompts |
| `config` | read | `global` (the school's settings) and `classes` (the timetable) |
| `content` | read | the lessons |
| `translations` | read | the lessons and goal texts in another language |
| `milestones` | read | the report dates |
| `reports` | read | the student's own published reports |
| `modules` | none | not opened in a student's session |
| `grade_proposals` | none | not opened in a student's session |

The writes in the containers students only read are the teacher's: the Goals, Lesson content, Instructions, Classes, Milestones and Reports pages, and the school's model in Options. The list is worked out from the code: `kStudentAccess` in [lib/core/cosmos_paths.dart](lib/core/cosmos_paths.dart) says, per container, where the writes come from, and `test/core/cosmos_student_access_test.dart` checks that this table and the commands below say the same, for every container.

The assignments, from PowerShell. Fill in the first five lines; `$db` is the `databaseName` of the school file:

```powershell
$account     = "<cosmos-account-name>"
$group       = "<resource-group>"
$db          = "python-tutor"
$students    = "<object id of the students' group>"
$teachers    = "<object id of the teachers' group>"
$reader      = "00000000-0000-0000-0000-000000000001"  # Cosmos DB Built-in Data Reader
$contributor = "00000000-0000-0000-0000-000000000002"  # Cosmos DB Built-in Data Contributor

# Teachers: read and write on the whole database
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db" --principal-id $teachers --role-definition-id $contributor

# Students: read and write
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/accounts" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/progress" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/progress_history" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/status_reports" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/lo_beliefs" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/turn_history" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/turn_content" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/playground_files" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/questions" --principal-id $students --role-definition-id $contributor
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/podium" --principal-id $students --role-definition-id $contributor

# Students: read
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/goals" --principal-id $students --role-definition-id $reader
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/instructions" --principal-id $students --role-definition-id $reader
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/config" --principal-id $students --role-definition-id $reader
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/content" --principal-id $students --role-definition-id $reader
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/translations" --principal-id $students --role-definition-id $reader
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/milestones" --principal-id $students --role-definition-id $reader
az cosmosdb sql role assignment create --account-name $account --resource-group $group --scope "/dbs/$db/colls/reports" --principal-id $students --role-definition-id $reader

# What is assigned now
az cosmosdb sql role assignment list --account-name $account --resource-group $group --output table
```

Good to know:

- **It takes a few minutes.** A new role assignment, or a change to who is in a group, can take a few minutes to reach the database. Until then those requests still get a 403: wait before you change anything else.
- **Containers stay with the teacher.** A token from a sign-in cannot create or delete containers; the roles above only cover the documents in them. Create a container as in [Step 3](#step-3--create-the-azure-cosmos-db), with the portal or `az cosmosdb sql container create`. A version that adds a container adds a row to the table above: create the container and give it its role before you release that version.
- **The class podium.** Builds from before #338 write the podium in `config`, which students may only read, so that write is refused. Keep those builds out with `MinimumVersion` (Step 6) before you switch the sign-in on.
- **The teacher's tooling** (`tooling/`) keeps reaching the database with the key from `.env`; the roles do not change it.

### Check it before you switch

[tooling/school/check_signin_access.py](tooling/school/check_signin_access.py) tries every kind of request the app makes, with a token from your own sign-in, on a test container of its own. It refuses a container the app uses. Run it as a teacher once the consent and the roles are in place:

```powershell
# A test container (partition key /pk, or any other but /id)
az cosmosdb sql container create --account-name $account --resource-group $group --database-name $db --name signin_check --partition-key-path /pk --partition-key-version 2

# Sign in (a browser opens) and try create, read, query, replace with If-Match, a transactional batch and delete
python tooling/school/check_signin_access.py --container signin_check --database $db

# Remove the test container again
az cosmosdb sql container delete --account-name $account --resource-group $group --database-name $db --name signin_check
```

It reads the tenant, the app's client id and the database endpoint from `.env` (`ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `COSMOS_ENDPOINT`) and prints none of them, nor the token: only each step's status code, and for a 403 the permission that is missing. The sign-in is the app's own (a browser, then back to `http://localhost`), so the app registration needs no change. It ends with exit code 0 when every step answered as the app expects. As a teacher it checks the role on the whole database; to check a role on a single container and a group as well, give the students' group Data Contributor on the test container (`--scope "/dbs/$db/colls/signin_check"`) and run it again signed in with an account in that group (the browser asks which account). Then switch the sign-in on in the school file ([The school file](#the-school-file)).

---

## Running the tests

Two layers, both without an Entra tenant or a live Cosmos DB:

```powershell
# Unit + widget tests (test/): real widgets and services over in-memory fakes
flutter test

# End-to-end flows (integration_test/): the real app on the Windows desktop,
# with Cosmos swapped for an in-memory database and sign-in bypassed
flutter test integration_test -d windows

# One flow on its own
flutter test integration_test/flows/lesson_flow.dart -d windows
```

The integration harness lives in `integration_test/harness/`. It boots the real
root widget (`GoalsApp`) with an in-memory `CosmosClient`, a signed-in
`AuthService`, an in-memory `SharedPreferences`, a temp playground directory,
the update check off and the LLM blocked, so a flow drives the real shell,
pages and services end to end. The bypass exists only under `integration_test/`
— it is never compiled into `flutter build windows`. Every flow is registered in
`integration_test/app_test.dart` and runs in one app process: on Windows,
Flutter can only launch the app for the first test file of a
`flutter test integration_test` invocation, so the flows under `flows/`
deliberately carry no `_test` suffix.

Both layers run in CI ([.github/workflows/build.yml](.github/workflows/build.yml)):
the unit tests in the `SonarQube` job, the flows in a separate `integration`
job that builds the desktop runner and launches the real app on a Windows
runner.

### Website screenshots

The screenshots on the website (`public/screenshots/`) are made from the
running app, through the same harness, with an invented demo class — no real
names and nothing from Cosmos
([integration_test/screenshots/demo_seed.dart](integration_test/screenshots/demo_seed.dart)):

```powershell
# Every screen, dark, in Dutch and in English, plus Practice in light:
# public/screenshots/nl/*.png and public/screenshots/en/*.png
flutter test integration_test/screenshots/site_screenshots.dart -d windows

# One screen (or `--name "\(en"` for one language)
flutter test integration_test/screenshots/site_screenshots.dart -d windows --name practice
```

Run it when a screen the site shows has changed visibly, not on every release:
the images are committed, and every refresh lands in the git history. It is
not part of the integration suite, and CI never runs it. Like the flows, it
builds and launches the Windows app, so close a running copy of the app
first.

## Project structure

For a deeper architectural tour — services, data model, how the tutor decides what to ask next — read [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md). It is the source of truth for the codebase shape and stays current as the code evolves.

## Contributing

This is a personal classroom project, not a product. Issues and PRs are welcome but expect slow turnaround. If you fork it for your own school, you are encouraged to do so — that is exactly what the build instructions above are for.

## License

Licensed under the GNU General Public License v3.0 — see [LICENSE.md](LICENSE.md) for the full text.

In short: you are free to use, study, modify, and redistribute this code, including for your own classroom. If you distribute a modified version, you must do so under the same license and make your source available. This means the project (and any forks) cannot be turned into a closed-source commercial product.
