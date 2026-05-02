# AI-tutor-Python

A Windows desktop application that acts as a personal AI tutor for Python students. A single window combines:

- an embedded Python editor with a **Run** button (no separate Python install needed — the runtime is bundled),
- a chat panel where an OpenAI-backed tutor asks the student questions, gives hints, marks answers, and adapts the difficulty,
- a teacher side where you author the *goals* (a tree of learning objectives) and the *instructions* (the prompts that shape the tutor's behaviour) without touching any code,
- per-student progress tracking, status reports, and history charts.

The tutor follows a teacher-defined goal tree, picks the type of exercise (multiple choice, explain-this-code, complete-the-code, write-code, Socratic question, …), and only marks a sub-goal as mastered once the student answers correctly across several different question types. UI is in Dutch.

Built by a Python teacher (Yvan, [@yvanvds](https://github.com/yvanvds)) for his own classroom.

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

A `python_teacher_install.exe` (Inno Setup installer, ~150 MB) that you can hand to students. After install they sign in once with their school Microsoft account and the app remembers them. There is also a built-in updater: if you publish a new `version.json` to a web host, every running copy will offer to update itself.

---

## Prerequisites on your machine

You need these tools installed once. All free.

1. **Flutter SDK 3.10.1 or newer** — <https://docs.flutter.dev/get-started/install/windows>. After installing run `flutter doctor` and fix any red items, especially the Visual Studio "Desktop development with C++" workload (required for Windows builds).
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
4. Inside that database, create six containers. The **partition key** column matters — get it right.

   | Container name   | Partition key |
   |------------------|---------------|
   | `accounts`       | `/uid`        |
   | `progress`       | `/uid`        |
   | `progress_history` | `/uid`      |
   | `status_reports` | `/uid`        |
   | `goals`          | `/type`       |
   | `instructions`   | `/type`       |
   | `config`         | `/type`       |

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

## Step 7 (optional) — Self-hosted updates

The app checks `https://ai-tutor-python.web.app/version.json` on launch and offers to download a new installer if the version is higher. To redirect that to your own host:

- Edit the URL in [lib/core/update_info.dart](lib/core/update_info.dart) (search for `version.json`).
- Host a JSON file with `{ "version": "1.0.2+17", "url": "https://your.host/python_teacher_install.exe", "sha256": "..." }`.

If you do not need auto-updates, you can ignore this entirely; the app still works.

---

## Project structure

For a deeper architectural tour — services, data model, how the tutor decides what to ask next — read [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md). It is the source of truth for the codebase shape and stays current as the code evolves.

## Contributing

This is a personal classroom project, not a product. Issues and PRs are welcome but expect slow turnaround. If you fork it for your own school, you are encouraged to do so — that is exactly what the build instructions above are for.

## License

No license file is included yet. Until one is added, treat this code as "all rights reserved" by the author for legal purposes, but feel free to fork for non-commercial educational use; open an issue if you want clarification.
