#!/usr/bin/env pwsh
# Master release pipeline for Python Teacher.
#
# Usage:
#   pwsh tooling/build_release.ps1                  # bumps +build, builds without school data, commits, tags, pushes, releases
#   pwsh tooling/build_release.ps1 -SkipPublish     # build only (no commit/tag/push/release)
#   pwsh tooling/build_release.ps1 -CheckOnly       # only step 2: the release .env and its check; bumps and builds nothing
#   pwsh tooling/build_release.ps1 -WithSchoolData  # emergency release, built from .env as before #308 (no step 2)
#
# Major/minor bump: edit pubspec.yaml to the new x.y.z+<currentBuild> first,
# then run the script - it bumps the +build by 1 (e.g. set 2.0.0+16, script
# produces 2.0.0+17).
#
# A release has no school data (#308, step 3). The school's settings come from
# the school file (#307) and from config/global (ApiKey, #337), and the app
# reaches the school's database with the user's own sign-in (#306, #336). The
# developer's .env stays as it is, for development: for the build, step 2 puts
# a release .env in its place - the school's values replaced by the
# placeholders CI uses, the values that are no school data kept - regenerates
# the envied files from it and checks on the Dart side that the build has no
# school data. The real .env and its generated files are put back after the
# build, also when something fails. Before the first release without school
# data, config/global needs ApiKey and the sign-in needs its roles and consent
# (README, Step 7).
#
# Sequence:
#   1. tooling/python/build_bundle.ps1
#   2. The release .env (not with -WithSchoolData): back up .env and the
#      envied files generated from it, write the release .env, regenerate
#      them, and run test/tooling/release_without_school_data_test.dart on
#      them. A failure stops the release before the version is bumped.
#   3. Bump pubspec.yaml +build
#   4. Regenerate lib/version.dart
#   5. flutter build windows --release; then the real .env and its generated
#      files go back, byte for byte
#   6. iscc.exe windows/packaging/exe/installer.iss -> public/PythonTeacherSetup.exe
#   7. Rename to public/python_teacher_install.exe (canonical asset filename the
#      auto-updater looks for - see kInstallerAssetName in
#      lib/core/github_release.dart)
#   8. Compute SHA256, write public/python_teacher_install.exe.sha256
#   9. Commit pubspec/version.dart + tag v<version> + push
#  10. gh release create v<version> with the installer AND its .sha256 attached
#  11. gh workflow run static.yml, so the website shows the new release (#291)
#
# The app reads the release straight from the GitHub Releases API (#50), so the
# tag and the two assets are the whole contract - there is no version.json to
# keep in lockstep any more. The .sha256 asset is not optional: without it the
# app cannot verify the download and refuses to offer the release.
#
# Output: public/python_teacher_install.exe (~250 MB; warns if >300 MB)
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - Inno Setup 6 on PATH or default install location
#   - git on PATH
#   - gh (GitHub CLI) authenticated (unless -SkipPublish)
#   - Internet access for step 1 (or a warm build_bundle cache)

[CmdletBinding()]
param(
    [switch]$SkipPublish,
    [switch]$CheckOnly,
    [switch]$WithSchoolData
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot    = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$IssScript   = Join-Path $RepoRoot 'windows\packaging\exe\installer.iss'
$PublicDir   = Join-Path $RepoRoot 'public'
$IsccOutput  = Join-Path $PublicDir 'PythonTeacherSetup.exe'
$Installer   = Join-Path $PublicDir 'python_teacher_install.exe'
$Pubspec     = Join-Path $RepoRoot 'pubspec.yaml'
$VersionDart = Join-Path $RepoRoot 'lib\version.dart'
$Checksum    = Join-Path $PublicDir 'python_teacher_install.exe.sha256'
$EnvFile     = Join-Path $RepoRoot '.env'
$Repo        = 'yvanvds/AI-tutor-Python'

# The .env keys that are school data. A release gets the placeholders of CI's
# .env (.github/workflows/build.yml), which the app reads as "no school"
# (SchoolConfig.isMissingValue): no school configuration, no database key and
# no fallback for the school's AI key.
$SchoolEnvValues = [ordered]@{
    'OPEN_AI_API_KEY'    = 'dummy'
    'COSMOS_ENDPOINT'    = 'https://dummy.documents.azure.com:443/'
    'COSMOS_KEY'         = 'dummy'
    'ENTRA_TENANT_ID'    = '00000000-0000-0000-0000-000000000000'
    'ENTRA_CLIENT_ID'    = '00000000-0000-0000-0000-000000000000'
    'ENTRA_REDIRECT_URI' = 'http://localhost'
}

# The .env keys that are no school data: a release keeps their line from .env
# as it is. GITHUB_OAUTH_CLIENT_ID is the public id of the OAuth app the bug
# reporter signs in with (README, Step 8), in both modes.
$KeptEnvKeys = @('GITHUB_OAUTH_CLIENT_ID')

# The Dart-side check of step 2. Envied may obfuscate a value, so searching
# the build output for one proves nothing; this test reads the generated files
# the build compiles. Without its --dart-define it is skipped.
$ReleaseCheckTest  = 'test/tooling/release_without_school_data_test.dart'
$ReleaseCheckGroup = 'a release without school data'

function Write-Step { param([string]$Msg) Write-Host "`n[build_release] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[build_release] $Msg" -ForegroundColor Green }

function Test-Cmd { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

# Write a text file as UTF-8 WITHOUT a byte-order mark.
#
# `Set-Content -Encoding UTF8` emits a BOM on Windows PowerShell 5.1 (PowerShell
# 7 does not). The CI format gate (`dart format --set-exit-if-changed`) strips
# the BOM from lib/version.dart, so a release commit made from 5.1 would turn
# `main` red. [IO.File]::WriteAllText with UTF8Encoding($false) is BOM-less on
# every PowerShell version. Content is written verbatim, so callers pass the
# trailing newline themselves.
function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Find-Iscc {
    $inPath = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    # The per-user install location comes first: Inno Setup's installer offers
    # it when run without admin rights, and that is where this machine has it.
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    throw @"
ISCC.exe not found.
Install Inno Setup 6 from https://jrsoftware.org/isinfo.php
then either add it to PATH or install it in one of:
  %LOCALAPPDATA%\Programs\Inno Setup 6\   (per-user install)
  C:\Program Files (x86)\Inno Setup 6\
"@
}

# --- The release .env (#308, step 3) ------------------------------------------
#
# Nothing here prints a value from .env: the check below asserts on booleans
# only, and the kept lines are copied, never shown.

# Every envied class under lib/ (`@Envied(`): the .env keys it reads and the
# file build_runner generates from it. A key that is in neither list at the
# top stops the release: whether it is school data is a decision, not a
# default.
function Get-EnviedSources {
    $found = @()
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'lib') -Recurse -File -Filter '*.dart') {
        if ($file.Name.EndsWith('.g.dart')) { continue }
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($text -notmatch '@Envied\(') { continue }
        $found += [pscustomobject]@{
            Source    = $file.FullName
            Generated = [IO.Path]::ChangeExtension($file.FullName, '.g.dart')
            EnvKeys   = @([regex]::Matches($text, "varName:\s*'([A-Z0-9_]+)'") | ForEach-Object { $_.Groups[1].Value })
        }
    }
    if ($found.Count -eq 0) { throw 'No envied class found under lib/.' }
    $known = @($SchoolEnvValues.Keys) + $KeptEnvKeys
    foreach ($source in $found) {
        foreach ($key in $source.EnvKeys) {
            if ($known -notcontains $key) {
                throw "$($source.Source) reads the .env key $key, which this script does not know. Add it to SchoolEnvValues (school data, replaced) or KeptEnvKeys (kept) at the top of tooling/build_release.ps1."
            }
        }
    }
    return $found
}

# build_runner keeps what it generated in .dart_tool/build. It does not notice
# a change to .env (a hidden file, which envied reads straight from disk), so
# without this it could hand back the files it generated from the other one.
function Clear-BuildRunnerCache {
    $cache = Join-Path $RepoRoot '.dart_tool\build'
    if (Test-Path -LiteralPath $cache) { Remove-Item -LiteralPath $cache -Recurse -Force }
}

# Copies .env and the generated envied files to a folder of their own outside
# the repo, with their hashes, so Restore-EnvFiles can put back exactly these.
function Backup-EnvFiles {
    param([Parameter(Mandatory)]$Sources)
    if (-not (Test-Path -LiteralPath $EnvFile)) { throw ".env not found in $RepoRoot." }
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('python-teacher-release-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    try {
        $saved = @()
        $paths = @($EnvFile) + @($Sources | ForEach-Object { $_.Generated })
        for ($i = 0; $i -lt $paths.Count; $i++) {
            $path = $paths[$i]
            $copy = Join-Path $dir ('{0}_{1}' -f $i, (Split-Path -Leaf $path))
            $existed = Test-Path -LiteralPath $path
            $hash = $null
            if ($existed) {
                Copy-Item -LiteralPath $path -Destination $copy
                $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
            }
            $saved += [pscustomobject]@{ Path = $path; Copy = $copy; Existed = $existed; Hash = $hash }
        }
    } catch {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
    return [pscustomobject]@{ BackupDir = $dir; Files = $saved; KeepsGitHubOAuth = $false }
}

# Writes the release .env over the real one and regenerates the envied files
# from it.
function Use-ReleaseEnv {
    param([Parameter(Mandatory)]$State)
    $real = [IO.File]::ReadAllLines($EnvFile)
    $lines = @()
    foreach ($key in $SchoolEnvValues.Keys) { $lines += "$key=$($SchoolEnvValues[$key])" }
    foreach ($key in $KeptEnvKeys) {
        $line = $real | Where-Object { $_ -match "^\s*$key\s*=" } | Select-Object -Last 1
        if (-not $line) { continue }
        $lines += $line
        if ($key -eq 'GITHUB_OAUTH_CLIENT_ID') {
            $value = ($line -replace "^\s*$key\s*=", '').Trim().Trim('"', "'")
            $State.KeepsGitHubOAuth = $value.Length -gt 0
        }
    }
    Write-Utf8NoBom -Path $EnvFile -Content (($lines -join "`n") + "`n")

    foreach ($file in $State.Files) {
        if ($file.Path -ne $EnvFile -and (Test-Path -LiteralPath $file.Path)) {
            Remove-Item -LiteralPath $file.Path -Force
        }
    }
    Clear-BuildRunnerCache
    Push-Location $RepoRoot
    try {
        & dart run build_runner build
        if ($LASTEXITCODE -ne 0) { throw "build_runner failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
    foreach ($file in $State.Files) {
        if (-not (Test-Path -LiteralPath $file.Path)) { throw "build_runner did not write $($file.Path)." }
    }
}

# Runs the Dart-side check on the generated files. The JSON reporter tells a
# passed test from a skipped one, so a check that did not run never passes
# for one that did.
function Test-ReleaseEnv {
    param([Parameter(Mandatory)]$State)
    $defines = @('--dart-define=RELEASE_WITHOUT_SCHOOL_DATA=true')
    if ($State.KeepsGitHubOAuth) { $defines += '--dart-define=RELEASE_KEEPS_GITHUB_OAUTH=true' }
    Push-Location $RepoRoot
    try {
        $out = @(& flutter test $ReleaseCheckTest --plain-name $ReleaseCheckGroup --reporter json @defines)
        $exit = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    $names = @{}
    $errors = @{}
    $passed = @()
    $failed = @()
    foreach ($line in $out) {
        $text = "$line".Trim()
        if (-not $text.StartsWith('{')) { continue }
        try { $e = ConvertFrom-Json -InputObject $text } catch { continue }
        if (-not $e.PSObject.Properties['type']) { continue }
        switch ($e.type) {
            'testStart' { $names["$($e.test.id)"] = $e.test.name }
            'error'     { $errors["$($e.testID)"] = $e.error }
            'testDone' {
                if ($e.hidden) { break }
                $name = $names["$($e.testID)"]
                if ($e.skipped) { $failed += "$name (skipped)" }
                elseif ($e.result -eq 'success') { $passed += $name }
                else {
                    $failed += "$name ($($e.result))"
                    if ($errors.ContainsKey("$($e.testID)")) { $failed += "    $($errors["$($e.testID)"])" }
                }
            }
        }
    }
    if ($exit -ne 0 -or $failed.Count -gt 0 -or $passed.Count -eq 0) {
        if ($failed.Count -eq 0) { $failed = @("no test passed (flutter test exit $exit)") }
        throw "The build is not without school data; no release. $ReleaseCheckTest says:`n  $($failed -join "`n  ")"
    }
    foreach ($name in $passed) { Write-Host "          ok: $name" }
}

# Puts back .env and the generated files exactly as Backup-EnvFiles found
# them, checked by hash, and empties the build_runner cache, which holds what
# was generated from the release .env. Keeps the backup when anything did not
# go back.
function Restore-EnvFiles {
    param([Parameter(Mandatory)]$State)
    $problems = @()
    foreach ($file in $State.Files) {
        try {
            if ($file.Existed) {
                Copy-Item -LiteralPath $file.Copy -Destination $file.Path -Force
                if ((Get-FileHash -Algorithm SHA256 -LiteralPath $file.Path).Hash -ne $file.Hash) { $problems += $file.Path }
            } elseif (Test-Path -LiteralPath $file.Path) {
                Remove-Item -LiteralPath $file.Path -Force
            }
        } catch {
            $problems += $file.Path
        }
    }
    try {
        Clear-BuildRunnerCache
    } catch {
        Write-Warning "Could not empty .dart_tool\build. Run 'dart run build_runner clean' and then 'dart run build_runner build' before you build for development."
    }
    if ($problems.Count -gt 0) {
        throw "Could not put back $($problems -join ', '). The originals are in $($State.BackupDir) (numbered in the order .env, then the generated files); copy them back by hand."
    }
    Remove-Item -LiteralPath $State.BackupDir -Recurse -Force
    Write-Ok 'The real .env and the files generated from it are back.'
}

# --- Prerequisite checks -----------------------------------------------------

if ($CheckOnly -and $WithSchoolData) {
    throw '-CheckOnly checks the release .env, which -WithSchoolData does not use; pick one.'
}
if (-not (Test-Cmd 'flutter')) { throw 'Flutter is not on PATH.' }
if (-not (Test-Cmd 'git'))     { throw 'git is not on PATH.' }
if (-not $WithSchoolData -and -not (Test-Cmd 'dart')) { throw 'dart is not on PATH (it comes with Flutter).' }
if (-not $SkipPublish -and -not $CheckOnly) {
    if (-not (Test-Cmd 'gh')) {
        throw "GitHub CLI (gh) not found on PATH. Install from https://cli.github.com and run 'gh auth login', or rerun with -SkipPublish."
    }
    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "gh is not authenticated. Run 'gh auth login' first, or rerun with -SkipPublish."
    }
}

# --- 1. Python bundle --------------------------------------------------------

if (-not $CheckOnly) {
    Write-Step 'Step 1/11: Python bundle'
    $BundleScript = Join-Path $ScriptDir 'python\build_bundle.ps1'
    # Invoke in the current PowerShell session (works on both Windows PowerShell 5.1
    # and PowerShell 7). $ErrorActionPreference=Stop in the bundle script will
    # propagate failures via exception, so $LASTEXITCODE alone is not sufficient.
    & $BundleScript
    if ($LASTEXITCODE -gt 0) { throw "build_bundle.ps1 failed (exit $LASTEXITCODE)" }
}

# From step 2 to step 5 the release .env stands in for the real one; the
# finally puts the real one back, also when a step fails or is interrupted.
$releaseEnv = $null
try {
    # --- 2. The release .env -------------------------------------------------

    if ($WithSchoolData) {
        Write-Step 'Step 2/11: -WithSchoolData: no release .env'
        Write-Warning 'This release is built with the school data of .env and its generated files as they are, as before #308 (step 3). Use it only for an emergency.'
    } else {
        Write-Step 'Step 2/11: the release .env, without school data, and its check'
        $sources = Get-EnviedSources
        $releaseEnv = Backup-EnvFiles -Sources $sources
        Use-ReleaseEnv -State $releaseEnv
        Test-ReleaseEnv -State $releaseEnv
        Write-Ok 'The build has no school data.'
    }

    if (-not $CheckOnly) {
        # --- 3. Bump pubspec.yaml +build -------------------------------------

        Write-Step 'Step 3/11: bump version in pubspec.yaml'
        $yaml = Get-Content -LiteralPath $Pubspec -Raw
        if ($yaml -notmatch 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
            throw "Could not find 'version: x.y.z+n' in pubspec.yaml"
        }
        $ver         = $matches[1]
        $build       = [int]$matches[2] + 1
        $fullVersion = "$ver+$build"
        $newYaml     = $yaml -replace 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', "version: $fullVersion"
        # The numeric a.b.c.d form Inno Setup's VersionInfoVersion requires; '+' is a
        # compile error there, so the build number becomes the fourth field (#55).
        $versionInfo = "$ver.$build"
        # $newYaml already ends with the file's own trailing newline (Get-Content -Raw).
        Write-Utf8NoBom -Path $Pubspec -Content $newYaml
        Write-Ok "Version: $fullVersion"

        # --- 4. Regenerate lib/version.dart ----------------------------------

        Write-Step 'Step 4/11: regenerate lib/version.dart'
        $versionDartContent = @"
/// Generated. Do not edit.
const String kAppVersion = '$fullVersion';

"@
        Write-Utf8NoBom -Path $VersionDart -Content $versionDartContent

        # --- 5. Flutter release build ----------------------------------------

        Write-Step 'Step 5/11: flutter build windows --release'
        Push-Location $RepoRoot
        try {
            & flutter build windows --release
            if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
        } finally {
            Pop-Location
        }
    }
} finally {
    if ($null -ne $releaseEnv) { Restore-EnvFiles -State $releaseEnv }
}

if ($CheckOnly) {
    Write-Ok 'Done (-CheckOnly): a release built now has no school data. Nothing was bumped or built.'
    exit 0
}

# --- 6. Inno Setup -----------------------------------------------------------

Write-Step 'Step 6/11: Inno Setup'
$iscc = Find-Iscc
Write-Host "          ISCC: $iscc"

New-Item -ItemType Directory -Force -Path $PublicDir | Out-Null

# ISCC resolves relative paths in the .iss file from the current working
# directory, not from the .iss file's location (despite the comment in
# installer.iss). Push to the .iss directory so OutputDir, SetupIconFile, and
# SourceDir resolve as documented in the .iss file.
$IssDir = Split-Path -Parent $IssScript
Push-Location $IssDir
try {
    # Stamp the version in (#55). Without these the .iss falls back to its
    # 0.0.0 defaults and the install registers itself with Windows at that
    # version, which is what Apps & Features and the uninstall key's
    # DisplayVersion show. pubspec.yaml stays the single source of truth.
    & $iscc "/DAppVersion=$fullVersion" "/DAppVersionInfo=$versionInfo" (Split-Path -Leaf $IssScript)
    if ($LASTEXITCODE -ne 0) { throw "ISCC.exe failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $IsccOutput)) {
    throw "Expected $IsccOutput after ISCC build; check OutputBaseFilename in installer.iss."
}

# --- 7. Rename to canonical asset filename ----------------------------------

Write-Step 'Step 7/11: rename installer to canonical asset filename'
if (Test-Path -LiteralPath $Installer) { Remove-Item -LiteralPath $Installer -Force }
Move-Item -LiteralPath $IsccOutput -Destination $Installer -Force

$sizeMB = [math]::Round((Get-Item -LiteralPath $Installer).Length / 1MB, 1)
Write-Ok "Installer: $Installer ($sizeMB MB)"
if ($sizeMB -gt 300) {
    Write-Warning "Installer is ${sizeMB} MB - larger than expected ~250 MB. Check bundle contents."
}

# --- 8. Write the checksum asset ---------------------------------------------

Write-Step 'Step 8/11: compute SHA256 + write the .sha256 asset'
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Installer).Hash.ToLowerInvariant()
# `sha256sum` shape, so it is usable by hand as well as by the app. BOM-less:
# a leading U+FEFF ends up in front of the hash and turns every comparison
# into a mismatch, which is how the old manifest died (#45).
Write-Utf8NoBom -Path $Checksum -Content "$hash  python_teacher_install.exe`n"
Write-Ok "SHA256: $hash"

if ($SkipPublish) {
    Write-Step '-SkipPublish set; stopping before commit/tag/push/release.'
    exit 0
}

# --- 9. Commit + tag + push --------------------------------------------------

Write-Step 'Step 9/11: commit + tag + push'

# Release notes from commits since the last v* tag (built BEFORE the release
# commit so the notes describe what is being released, not the release commit
# itself).
$lastTag = (& git tag --list 'v*' --sort=-creatordate | Select-Object -First 1)
if ($lastTag) {
    $rangeArg = "$lastTag..HEAD"
} else {
    $rangeArg = '-30'
}
# Git writes UTF-8, but PowerShell decodes a native command's output with
# [Console]::OutputEncoding - the OEM code page (850) on this machine - so a
# subject with a non-ASCII character came out garbled: λ as "╬╗", — as "ÔÇö"
# (#295). Read the log as UTF-8 and put the console back afterwards.
$prevOutputEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $commits = (& git log $rangeArg --no-merges --pretty=format:'- %s')
} finally {
    [Console]::OutputEncoding = $prevOutputEncoding
}
if (-not $commits) { $commits = "- $fullVersion" }

$tag       = "v$fullVersion"
$notesBody = @"
## Changes

$($commits -join "`n")

---
SHA256: ``$hash``
Size: $sizeMB MB
"@

$notesFile = New-TemporaryFile
$notesBody | Set-Content -LiteralPath $notesFile.FullName -Encoding UTF8

& git add $Pubspec $VersionDart
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
& git commit -m "release: $fullVersion"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
& git tag -a $tag -m "Release $fullVersion"
if ($LASTEXITCODE -ne 0) { throw 'git tag failed.' }
& git push origin HEAD
if ($LASTEXITCODE -ne 0) { throw 'git push (commit) failed.' }
& git push origin $tag
if ($LASTEXITCODE -ne 0) { throw 'git push (tag) failed.' }

# --- 10. GitHub release -------------------------------------------------------

Write-Step "Step 10/11: gh release create $tag"
# Both assets: the app finds the installer by name and reads its hash from the
# .sha256 next to it. A release without the second one is not offerable (#50).
& gh release create $tag $Installer $Checksum `
    --repo $Repo `
    --title $fullVersion `
    --notes-file $notesFile.FullName
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed.' }

Remove-Item -LiteralPath $notesFile.FullName -Force -ErrorAction SilentlyContinue

# --- 11. Refresh the website -------------------------------------------------

Write-Step 'Step 11/11: deploy the website with the new release'
# The download section on the site shows the latest release's version, date,
# size and SHA-256, which static.yml reads when it deploys (#291). The push in
# step 9 already started a deploy, but before step 10 made the release, so that
# one shows the previous version. A `release: published` trigger cannot do this
# instead: the github-pages environment only lets `main` deploy, and a release
# run is on the tag. So start a run on main now that the release exists.
# Dispatch, never `gh run rerun`: rerunning the Pages workflow piles up
# duplicate artifacts and the deploy fails. The release itself is done at this
# point, so a failure here is a warning, not an error.
& gh workflow run static.yml --repo $Repo --ref main
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not start the website deploy; the site shows the previous version until the next one. Start it with: gh workflow run static.yml --repo $Repo --ref main"
}

Write-Ok "Done. Release: https://github.com/$Repo/releases/tag/$tag"
