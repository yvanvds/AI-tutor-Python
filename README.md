# AI-tutor-Python

[![Quality Gate Status](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python) [![Coverage](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=coverage)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python) [![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=sqale_rating)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python) [![Vulnerabilities](https://sonarcloud.io/api/project_badges/measure?project=yvanvds_AI-tutor-Python&metric=vulnerabilities)](https://sonarcloud.io/summary/new_code?id=yvanvds_AI-tutor-Python)

A Windows desktop application that acts as a personal AI tutor for Python students. A single window combines:

- an embedded Python editor with a **Run** button (no separate Python install needed — the runtime is bundled),
- a chat panel where an OpenAI-backed tutor asks the student questions, gives hints, marks answers, and adapts the difficulty,
- a teacher side where you author the *goals* (a tree of learning objectives) and the *instructions* (the prompts that shape the tutor's behaviour) without touching any code,
- per-student progress tracking, status reports, and history charts.

The tutor follows a teacher-defined goal tree, picks the type of exercise (multiple choice, explain-this-code, complete-the-code, write-code, Socratic question, …), and only marks a sub-goal as mastered once the student answers correctly across several different question types. UI is in Dutch.


---

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
3. Copy the key (`sk-...`). You will paste it as `OPEN_AI_API_KEY` later.
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
   | `goals`          | `/type`       |
   | `instructions`   | `/type`       |
   | `config`         | `/type`       |
   | `content`        | `/type`       |
   | `modules`        | `/type`       |

   The list the app actually uses is `lib/core/cosmos_paths.dart` — every
   container it can open is declared there, with its partition key in the doc
   comment. This table is checked against that file by
   `test/core/cosmos_paths_readme_parity_test.dart`, so the two cannot drift
   apart unnoticed again.

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
- `OPEN_AI_API_KEY` and `COSMOS_KEY` are obfuscated into the compiled binary at build time via the `envied` package. They are *not* shipped in plaintext, but they *are* shipped — anyone determined enough can extract them from the binary. Treat the build as roughly as secret as the keys themselves.
- `ENTRA_REDIRECT_URI` must be exactly `http://localhost` to match step 2.4.
- There is a seventh, **optional** line — `GITHUB_OAUTH_CLIENT_ID` — for in-app bug reports. Leave it out and everything else works; the Options panel simply says it cannot sign in to GitHub. [Step 8](#step-8-optional--in-app-bug-reports-github-oauth-app) sets it up.

---

## Step 5 — Build the installer

From the repo root, in PowerShell:

```powershell
# Download Dart/Flutter dependencies
flutter pub get

# Generate the obfuscated env file from your .env (re-run this if you change .env)
dart run build_runner build --delete-conflicting-outputs

# Quick sanity check: open the app on your machine
flutter run -d windows
```

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
2. Because you have the `Teacher` role, you will see extra navigation items: **Goals**, **Instructions**, **Accounts**.
3. Go to **Instructions** and create the prompt documents. Each document's **id** must match a request type the tutor uses. The minimum set to get a working tutor:
   - `alwaysInclude` — global instructions injected on every call (tone, language, etc.).
   - `socraticQuestion`, `multipleChoiceQuestion`, `explainCode`, `completeCode`, `writeCodeQuestion`, `guidingQuestion` — one per exercise type.
   - `submitCode`, `submitMcqAnswer`, `submitExplain`, `submitSocratic`, `submitGuiding` — feedback prompts.
   - `statusSummary` — periodic per-subgoal report.

   You can use `{goal}`, `{subgoal}`, `{suggestions}`, and `{known concepts}` as placeholders in any section. They get filled in at runtime from the active goal.
4. Go to **Goals** and build your goal tree. Roots are top-level themes ("Variables", "Loops", …); children are concrete subgoals. The tutor walks the tree in order.
5. Optional: edit `config/global` from the Cosmos Data Explorer if you want to switch to a different OpenAI model (e.g. `gpt-4o-mini` for cheaper runs). The field is `Model`.

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
app, with the debug payload of a recent tutor turn attached. Signing in uses
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
   - **Authorization callback URL:** the form requires one, but the device
     flow never uses it. Put the homepage URL again.
   - **Enable Device Flow:** ✅ **tick this.** It is the one setting that
     matters — without it GitHub answers every request with
     `device_flow_disabled`. If the checkbox is not on the registration form
     in your account, click **Register application** first, then open the new
     app's settings page, tick **Enable Device Flow**, and click **Update
     application**.
4. Click **Register application**.
5. On the app's page, copy the **Client ID** (it looks like `Ov23li…`). It is
   public — it ships inside the installer by design.
6. **Do not generate a client secret.** The device flow has none, which is
   exactly why it suits an app handed out to students; a secret compiled into
   the binary would be a secret handed out with it.

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

## Project structure

For a deeper architectural tour — services, data model, how the tutor decides what to ask next — read [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md). It is the source of truth for the codebase shape and stays current as the code evolves.

## Contributing

This is a personal classroom project, not a product. Issues and PRs are welcome but expect slow turnaround. If you fork it for your own school, you are encouraged to do so — that is exactly what the build instructions above are for.

## License

Licensed under the GNU General Public License v3.0 — see [LICENSE.md](LICENSE.md) for the full text.

In short: you are free to use, study, modify, and redistribute this code, including for your own classroom. If you distribute a modified version, you must do so under the same license and make your source available. This means the project (and any forks) cannot be turned into a closed-source commercial product.
