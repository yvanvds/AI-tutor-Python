<#
  scripts/deploy.ps1

  Builds the Flutter Windows app, packages a fixed-name installer with Fastforge,
  updates public/version.json, commits version files (which triggers the GitHub
  Pages workflow that publishes /public), tags the commit, and creates a GitHub
  Release with the installer attached.

  Prereqs (installed & on PATH):
    - Flutter
    - Dart SDK (usually bundled with Flutter)
    - Inno Setup (ISCC.exe) for Fastforge EXE builds
    - fastforge (dart pub global activate fastforge)
    - GitHub CLI (gh) -- authenticated via `gh auth login`

  Notes:
    - Pages site:    https://yvanvds.github.io/AI-tutor-Python/
    - Release asset: https://github.com/yvanvds/AI-tutor-Python/releases/latest/download/python_teacher_install.exe
    - public/*.exe is gitignored, so the installer is never pushed via git;
      it is only attached to the GitHub Release.
#>

[CmdletBinding()]
param(
  # Optional: skip Flutter rebuild (useful when iterating on installer only)
  [switch]$SkipFlutterBuild,

  # Optional: skip the git push + release step (build & stage only)
  [switch]$SkipPublish
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Test-Cmd($name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  return $null -ne $cmd
}

function Add-DartPubCacheToPath {
  $pubCache = Join-Path $env:USERPROFILE ".pub-cache\bin"
  if (-not ($env:PATH -split ';' | Where-Object { $_ -eq $pubCache })) {
    $env:PATH = "$pubCache;$env:PATH"
  }
}

# ---- Paths & constants ----
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..") | Select-Object -ExpandProperty Path
Set-Location $RepoRoot

$Repo          = "yvanvds/AI-tutor-Python"
$PagesUrl      = "https://yvanvds.github.io/AI-tutor-Python"
$InstallerName = "python_teacher_install.exe"
$ReleaseAssetUrl = "https://github.com/$Repo/releases/latest/download/$InstallerName"

$PublicDir    = Join-Path $RepoRoot "public"
$InstallerPath= Join-Path $PublicDir $InstallerName
$Pubspec      = Join-Path $RepoRoot "pubspec.yaml"
$VersionDart  = Join-Path $RepoRoot "lib\version.dart"
$Manifest     = Join-Path $PublicDir "version.json"

# ---- Checks ----
Write-Host "==> Checking prerequisites..." -ForegroundColor Cyan

if (-not (Test-Cmd "flutter")) { throw "Flutter is not on PATH." }
if (-not (Test-Cmd "dart"))    { throw "Dart is not on PATH (comes with Flutter)." }
if (-not (Test-Cmd "git"))     { throw "git is not on PATH." }

# Ensure fastforge available
Add-DartPubCacheToPath
if (-not (Test-Cmd "fastforge")) {
  Write-Host "fastforge not found. Installing..." -ForegroundColor Yellow
  dart pub global activate fastforge | Out-Host
  Add-DartPubCacheToPath
  if (-not (Test-Cmd "fastforge")) { throw "fastforge still not found after activation." }
}

# Inno Setup (ISCC.exe)
if (-not (Test-Cmd "ISCC.exe")) {
  Write-Host "WARNING: ISCC.exe (Inno Setup) not found on PATH. If Fastforge fails, add Inno to PATH." -ForegroundColor Yellow
}

# GitHub CLI (only required when publishing)
if (-not $SkipPublish) {
  if (-not (Test-Cmd "gh")) {
    throw "GitHub CLI (gh) not found on PATH. Install from https://cli.github.com and run 'gh auth login', or rerun with -SkipPublish."
  }
  & gh auth status 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "gh is not authenticated. Run 'gh auth login' first, or rerun with -SkipPublish."
  }
}

# ---- Bump version in pubspec.yaml (simple +1 build) ----
$yaml = Get-Content $Pubspec -Raw
if ($yaml -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)") {
  $ver         = $matches[1]
  $build       = [int]$matches[2] + 1
  $newYaml     = $yaml -replace "version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)", "version: $ver+$build"
  Set-Content $Pubspec $newYaml -Encoding UTF8
  $fullVersion = "$ver+$build"
} else { throw "Could not find version in pubspec.yaml" }

Write-Host "==> New version: $fullVersion" -ForegroundColor Green

# ---- Regenerate lib/version.dart ----
@"
/// Generated. Do not edit.
const String kAppVersion = '$fullVersion';
"@ | Set-Content $VersionDart -Encoding UTF8

# ---- Ensure public dir exists ----
if (-not (Test-Path $PublicDir)) { New-Item -ItemType Directory -Path $PublicDir | Out-Null }

# ---- Package with Fastforge ----
if (-not $SkipFlutterBuild) {
  Write-Host "==> Packaging installer with Fastforge..." -ForegroundColor Cyan
  fastforge package --platform windows --targets exe --skip-clean | Out-Host

  # Some Fastforge versions create a versioned subfolder. Move/rename if found.
  $Found = Get-ChildItem -Path $PublicDir -Recurse -Filter "*.exe" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($Found -and $Found.FullName -ne $InstallerPath) {
    Write-Host "==> Moving $($Found.FullName) -> $InstallerPath" -ForegroundColor Yellow
    if (Test-Path $InstallerPath) { Remove-Item $InstallerPath -Force }
    Move-Item -Path $Found.FullName -Destination $InstallerPath -Force

    $ParentDir = Split-Path $Found.FullName -Parent
    if ((Test-Path $ParentDir) -and -not (Get-ChildItem -Path $ParentDir -Recurse -Force)) {
      Write-Host "==> Removing empty folder $ParentDir" -ForegroundColor Yellow
      Remove-Item $ParentDir -Force -Recurse
    }
  }
}

if (-not (Test-Path $InstallerPath)) {
  throw "Installer not found at $InstallerPath. Check your Inno template OutputDir/OutputBaseFilename."
}

# ---- Compute SHA256 and size ----
$Hash   = (Get-FileHash -Algorithm SHA256 -Path $InstallerPath).Hash
$SizeMB = [Math]::Round((Get-Item $InstallerPath).Length / 1MB, 2)

Write-Host "==> Installer ready: $InstallerPath ($SizeMB MB)" -ForegroundColor Green
Write-Host "==> SHA256: $Hash" -ForegroundColor Green

# ---- Write version.json ----
@"
{
  "version": "$fullVersion",
  "url": "$ReleaseAssetUrl",
  "sha256": "$Hash"
}
"@ | Set-Content $Manifest -Encoding UTF8

if ($SkipPublish) {
  Write-Host "==> -SkipPublish set; stopping before commit/release." -ForegroundColor Yellow
  exit 0
}

# ---- Build release notes from commits since the last v* tag ----
$lastTag = (& git tag --list "v*" --sort=-creatordate | Select-Object -First 1)
if ($lastTag) {
  $rangeArg = "$lastTag..HEAD"
  Write-Host "==> Building release notes from $rangeArg" -ForegroundColor Cyan
} else {
  $rangeArg = "-30"
  Write-Host "==> No previous v* tag found; using last 30 commits for release notes." -ForegroundColor Cyan
}
$commits = (& git log $rangeArg --no-merges --pretty=format:"- %s")
if (-not $commits) { $commits = "- $fullVersion" }

$tag       = "v$fullVersion"
$notesBody = @"
## Changes

$($commits -join "`n")

---
SHA256: ``$Hash``
Size: $SizeMB MB
"@

$notesFile = New-TemporaryFile
$notesBody | Set-Content -Path $notesFile -Encoding UTF8

# ---- Commit + tag + push (GitHub Pages workflow takes it from here) ----
Write-Host "==> Committing version bump..." -ForegroundColor Cyan
& git add $Pubspec $VersionDart $Manifest
& git commit -m "release: $fullVersion"
if ($LASTEXITCODE -ne 0) { throw "git commit failed." }

Write-Host "==> Tagging $tag..." -ForegroundColor Cyan
& git tag -a $tag -m "Release $fullVersion"
if ($LASTEXITCODE -ne 0) { throw "git tag failed." }

Write-Host "==> Pushing commit and tag..." -ForegroundColor Cyan
& git push origin HEAD
if ($LASTEXITCODE -ne 0) { throw "git push (commit) failed." }
& git push origin $tag
if ($LASTEXITCODE -ne 0) { throw "git push (tag) failed." }

# ---- Create GitHub Release with installer attached ----
Write-Host "==> Creating GitHub Release $tag..." -ForegroundColor Cyan
& gh release create $tag $InstallerPath `
    --repo $Repo `
    --title $fullVersion `
    --notes-file $notesFile.FullName
if ($LASTEXITCODE -ne 0) { throw "gh release create failed." }

Remove-Item $notesFile -Force -ErrorAction SilentlyContinue

Write-Host "==> Done." -ForegroundColor Green
Write-Host "    Pages:   $PagesUrl/" -ForegroundColor Green
Write-Host "    Release: https://github.com/$Repo/releases/tag/$tag" -ForegroundColor Green
