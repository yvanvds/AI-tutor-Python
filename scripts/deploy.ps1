<# 
  scripts/publish.ps1

  Builds the Flutter Windows app, packages a fixed-name installer with Fastforge,
  generates a simple index.html, and deploys to Firebase Hosting.

  Prereqs (installed & on PATH):
    - Flutter
    - Dart SDK (usually bundled with Flutter)
    - Node.js + npm
    - firebase-tools (npm i -g firebase-tools) OR provide FIREBASE_TOKEN
    - Inno Setup (ISCC.exe) for Fastforge EXE builds
    - fastforge (dart pub global activate fastforge)
#>



[CmdletBinding()]
param(
  # Optional Firebase Hosting site/target. If omitted, uses default from firebase.json.
  [string]$Site = "",

  # Optional: skip Flutter rebuild (useful when iterating on installer only)
  [switch]$SkipFlutterBuild
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

$PublicDir = Join-Path $RepoRoot "public"
$InstallerName = "python_teacher_install.exe"      # fixed output name per your Inno template
$InstallerPath = Join-Path $PublicDir $InstallerName

$Pubspec    = Join-Path $RepoRoot "pubspec.yaml"
$VersionDart= Join-Path $RepoRoot "lib\version.dart"
$PublicDir  = Join-Path $RepoRoot "public"
$Manifest   = Join-Path $PublicDir "version.json"
$Installer  = Join-Path $PublicDir "python_teacher_install.exe"

# ---- Checks ----
Write-Host "==> Checking prerequisites..." -ForegroundColor Cyan

if (-not (Test-Cmd "flutter")) { throw "Flutter is not on PATH." }
if (-not (Test-Cmd "dart")) { throw "Dart is not on PATH (comes with Flutter)." }

# Ensure fastforge available
Add-DartPubCacheToPath
if (-not (Test-Cmd "fastforge")) {
  Write-Host "fastforge not found. Installing..." -ForegroundColor Yellow
  dart pub global activate fastforge | Out-Host
  Add-DartPubCacheToPath
  if (-not (Test-Cmd "fastforge")) { throw "fastforge still not found after activation." }
}

# Firebase CLI
if (-not (Test-Cmd "firebase")) {
  Write-Host "firebase-tools not found. Installing globally with npm..." -ForegroundColor Yellow
  npm i -g firebase-tools | Out-Host
  if (-not (Test-Cmd "firebase")) { throw "firebase CLI still not found after install." }
}

# Inno Setup (ISCC.exe)
if (-not (Test-Cmd "ISCC.exe")) {
  Write-Host "WARNING: ISCC.exe (Inno Setup) not found on PATH. If Fastforge fails, add Inno to PATH." -ForegroundColor Yellow
}

# ---- Bump version in pubspec.yaml (simple +1 build; adapt as needed)
$yaml = Get-Content $Pubspec -Raw
if ($yaml -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)") {
  $ver     = $matches[1]
  $build   = [int]$matches[2] + 1
  $newYaml = $yaml -replace "version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)", "version: $ver+$build"
  Set-Content $Pubspec $newYaml -Encoding UTF8
  $fullVersion = "$ver+$build"
} else { throw "Could not find version in pubspec.yaml" }

# ---- Regenerate lib/version.dart
@"
/// Generated. Do not edit.
const String kAppVersion = '$fullVersion';
"@ | Set-Content $VersionDart -Encoding UTF8

# ---- Read version from pubspec.yaml ----
$Pubspec = Join-Path $RepoRoot "pubspec.yaml"
if (-not (Test-Path $Pubspec)) { throw "pubspec.yaml not found at $Pubspec" }

# naive parse: look for "version: x.y.z+build"
$Version = (Select-String -Path $Pubspec -Pattern '^\s*version:\s*([^\s#]+)') |
ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1

if (-not $Version) { $Version = "0.0.0+0" }

Write-Host "==> Project version: $Version" -ForegroundColor Green

# ---- Ensure public dir exists ----
if (-not (Test-Path $PublicDir)) { New-Item -ItemType Directory -Path $PublicDir | Out-Null }

# ---- Package with Fastforge (re-using the existing build) ----
Write-Host "==> Packaging installer with Fastforge..." -ForegroundColor Cyan

# We rely on your Inno template to write the fixed file name & location:
#   OutputDir=public
#   OutputBaseFilename=python_teacher_install
# So Fastforge should produce public\python_teacher_install.exe
fastforge package --platform windows --targets exe --skip-clean | Out-Host


# Some Fastforge versions create a versioned subfolder. Move/rename if found.
$Found = Get-ChildItem -Path $PublicDir -Recurse -Filter "*.exe" | 
Where-Object { $_.Name -like "*.exe" } |
Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($Found) {
  Write-Host "==> Moving $($Found.FullName) -> $InstallerPath" -ForegroundColor Yellow
  # Remove destination if it already exists
  if (Test-Path $InstallerPath) {
    Remove-Item $InstallerPath -Force
  }

  # Move instead of copy, to avoid duplicate uploads
  Move-Item -Path $Found.FullName -Destination $InstallerPath -Force

  # Clean up leftover directory if empty
  $ParentDir = Split-Path $Found.FullName -Parent
  if (Test-Path $ParentDir) {
    $filesLeft = Get-ChildItem -Path $ParentDir -Recurse -Force
    if (-not $filesLeft) {
      Write-Host "==> Removing empty folder $ParentDir" -ForegroundColor Yellow
      Remove-Item $ParentDir -Force -Recurse
    }
  }
}


if (-not (Test-Path $InstallerPath)) {
  throw "Installer not found at $InstallerPath. Check your Inno template OutputDir/OutputBaseFilename."
}

# ---- Compute SHA256 and size ----
$Hash = (Get-FileHash -Algorithm SHA256 -Path $InstallerPath).Hash
$SizeMB = [Math]::Round((Get-Item $InstallerPath).Length / 1MB, 2)

Write-Host "==> Installer ready: $InstallerPath ($SizeMB MB)" -ForegroundColor Green
Write-Host "==> SHA256: $Hash" -ForegroundColor Green

# ---- Write version.json (last step before deploy)
$domain = "https://ai-tutor-python.web.app" # e.g., ai-tutor.web.app
@"
{
  "version": "$fullVersion",
  "url": "$domain/python_teacher_install.exe",
  "sha256": "$hash"
}
"@ | Set-Content $Manifest -Encoding UTF8

# ---- Firebase deploy ----
Write-Host "==> Deploying to Firebase Hosting..." -ForegroundColor Cyan

# If FIREBASE_TOKEN is set, use it to avoid interactive login.
$FirebaseArgs = @("deploy", "--only", "hosting")
if ($Site -and $Site.Trim() -ne "") {
  # If you use multi-site hosting: firebase deploy --only hosting:<site>
  $FirebaseArgs = @("deploy", "--only", "hosting:$Site")
}
if ($env:FIREBASE_TOKEN) {
  $FirebaseArgs += @("--token", $env:FIREBASE_TOKEN)
}

firebase @FirebaseArgs | Out-Host

Write-Host "==> Done." -ForegroundColor Green
