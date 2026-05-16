#!/usr/bin/env pwsh
# Master release pipeline for Python Teacher.
#
# Usage:
#   pwsh tooling/build_release.ps1                # bumps +build, builds, commits, tags, pushes, releases
#   pwsh tooling/build_release.ps1 -SkipPublish   # build only (no commit/tag/push/release)
#
# Major/minor bump: edit pubspec.yaml to the new x.y.z+<currentBuild> first,
# then run the script - it bumps the +build by 1 (e.g. set 2.0.0+16, script
# produces 2.0.0+17).
#
# Sequence:
#   1. Bump pubspec.yaml +build
#   2. Regenerate lib/version.dart
#   3. tooling/python/build_bundle.ps1
#   4. flutter build windows --release
#   5. iscc.exe windows/packaging/exe/installer.iss -> public/PythonTeacherSetup.exe
#   6. Rename to public/python_teacher_install.exe (canonical asset filename used
#      by public/version.json + auto-updater in lib/core/update_info.dart)
#   7. Compute SHA256, write public/version.json
#   8. Commit pubspec/version.dart/version.json + tag v<version> + push
#   9. gh release create v<version> with installer attached
#
# Output: public/python_teacher_install.exe (~250 MB; warns if >300 MB)
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - Inno Setup 6 on PATH or default install location
#   - git on PATH
#   - gh (GitHub CLI) authenticated (unless -SkipPublish)
#   - Internet access for step 3 (or a warm build_bundle cache)

[CmdletBinding()]
param(
    [switch]$SkipPublish
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
$Manifest    = Join-Path $PublicDir 'version.json'
$Repo            = 'yvanvds/AI-tutor-Python'
$ReleaseAssetUrl = "https://github.com/$Repo/releases/latest/download/python_teacher_install.exe"

function Write-Step { param([string]$Msg) Write-Host "`n[build_release] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[build_release] $Msg" -ForegroundColor Green }

function Test-Cmd { param([string]$Name) return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }

function Find-Iscc {
    $inPath = Get-Command iscc.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    $candidates = @(
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    throw @"
ISCC.exe not found.
Install Inno Setup 6 from https://jrsoftware.org/isinfo.php
then either add it to PATH or place it in 'C:\Program Files (x86)\Inno Setup 6\'.
"@
}

# --- Prerequisite checks -----------------------------------------------------

if (-not (Test-Cmd 'flutter')) { throw 'Flutter is not on PATH.' }
if (-not (Test-Cmd 'git'))     { throw 'git is not on PATH.' }
if (-not $SkipPublish) {
    if (-not (Test-Cmd 'gh')) {
        throw "GitHub CLI (gh) not found on PATH. Install from https://cli.github.com and run 'gh auth login', or rerun with -SkipPublish."
    }
    & gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "gh is not authenticated. Run 'gh auth login' first, or rerun with -SkipPublish."
    }
}

# --- 1. Bump pubspec.yaml +build --------------------------------------------

Write-Step 'Step 1/9: bump version in pubspec.yaml'
$yaml = Get-Content -LiteralPath $Pubspec -Raw
if ($yaml -notmatch 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
    throw "Could not find 'version: x.y.z+n' in pubspec.yaml"
}
$ver         = $matches[1]
$build       = [int]$matches[2] + 1
$fullVersion = "$ver+$build"
$newYaml     = $yaml -replace 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', "version: $fullVersion"
Set-Content -LiteralPath $Pubspec -Value $newYaml -Encoding UTF8
Write-Ok "Version: $fullVersion"

# --- 2. Regenerate lib/version.dart -----------------------------------------

Write-Step 'Step 2/9: regenerate lib/version.dart'
@"
/// Generated. Do not edit.
const String kAppVersion = '$fullVersion';
"@ | Set-Content -LiteralPath $VersionDart -Encoding UTF8

# --- 3. Python bundle --------------------------------------------------------

Write-Step 'Step 3/9: Python bundle'
$BundleScript = Join-Path $ScriptDir 'python\build_bundle.ps1'
& pwsh -NonInteractive -File $BundleScript
if ($LASTEXITCODE -ne 0) { throw "build_bundle.ps1 failed (exit $LASTEXITCODE)" }

# --- 4. Flutter release build ------------------------------------------------

Write-Step 'Step 4/9: flutter build windows --release'
Push-Location $RepoRoot
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# --- 5. Inno Setup -----------------------------------------------------------

Write-Step 'Step 5/9: Inno Setup'
$iscc = Find-Iscc
Write-Host "          ISCC: $iscc"

New-Item -ItemType Directory -Force -Path $PublicDir | Out-Null
& $iscc $IssScript
if ($LASTEXITCODE -ne 0) { throw "ISCC.exe failed (exit $LASTEXITCODE)" }

if (-not (Test-Path -LiteralPath $IsccOutput)) {
    throw "Expected $IsccOutput after ISCC build; check OutputBaseFilename in installer.iss."
}

# --- 6. Rename to canonical asset filename ----------------------------------

Write-Step 'Step 6/9: rename installer to canonical asset filename'
if (Test-Path -LiteralPath $Installer) { Remove-Item -LiteralPath $Installer -Force }
Move-Item -LiteralPath $IsccOutput -Destination $Installer -Force

$sizeMB = [math]::Round((Get-Item -LiteralPath $Installer).Length / 1MB, 1)
Write-Ok "Installer: $Installer ($sizeMB MB)"
if ($sizeMB -gt 300) {
    Write-Warning "Installer is ${sizeMB} MB - larger than expected ~250 MB. Check bundle contents."
}

# --- 7. Write version.json ---------------------------------------------------

Write-Step 'Step 7/9: compute SHA256 + write public/version.json'
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Installer).Hash
@"
{
  "version": "$fullVersion",
  "url": "$ReleaseAssetUrl",
  "sha256": "$hash"
}
"@ | Set-Content -LiteralPath $Manifest -Encoding UTF8
Write-Ok "SHA256: $hash"

if ($SkipPublish) {
    Write-Step '-SkipPublish set; stopping before commit/tag/push/release.'
    exit 0
}

# --- 8. Commit + tag + push --------------------------------------------------

Write-Step 'Step 8/9: commit + tag + push'

# Release notes from commits since the last v* tag (built BEFORE the release
# commit so the notes describe what is being released, not the release commit
# itself).
$lastTag = (& git tag --list 'v*' --sort=-creatordate | Select-Object -First 1)
if ($lastTag) {
    $rangeArg = "$lastTag..HEAD"
} else {
    $rangeArg = '-30'
}
$commits = (& git log $rangeArg --no-merges --pretty=format:'- %s')
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

& git add $Pubspec $VersionDart $Manifest
if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
& git commit -m "release: $fullVersion"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
& git tag -a $tag -m "Release $fullVersion"
if ($LASTEXITCODE -ne 0) { throw 'git tag failed.' }
& git push origin HEAD
if ($LASTEXITCODE -ne 0) { throw 'git push (commit) failed.' }
& git push origin $tag
if ($LASTEXITCODE -ne 0) { throw 'git push (tag) failed.' }

# --- 9. GitHub release -------------------------------------------------------

Write-Step "Step 9/9: gh release create $tag"
& gh release create $tag $Installer `
    --repo $Repo `
    --title $fullVersion `
    --notes-file $notesFile.FullName
if ($LASTEXITCODE -ne 0) { throw 'gh release create failed.' }

Remove-Item -LiteralPath $notesFile.FullName -Force -ErrorAction SilentlyContinue

Write-Ok "Done. Release: https://github.com/$Repo/releases/tag/$tag"
