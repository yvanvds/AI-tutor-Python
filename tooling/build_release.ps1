#!/usr/bin/env pwsh
# Master release build for Python Teacher.
# Usage: pwsh tooling/build_release.ps1
#
# Sequence:
#   1. tooling/python/build_bundle.ps1  — download + pip-install bundled python
#   2. flutter build windows --release
#   3. iscc.exe windows/packaging/exe/installer.iss
#
# Output: public/PythonTeacherSetup.exe
# Expected installer size: ~250 MB. Script warns if > 300 MB.
#
# Prerequisites:
#   - Flutter SDK on PATH
#   - Inno Setup 6 on PATH or in its default install location
#   - Internet access for step 1 (or a warm build_bundle cache)

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot   = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$IssScript  = Join-Path $RepoRoot 'windows\packaging\exe\installer.iss'
$PublicDir  = Join-Path $RepoRoot 'public'
$Installer  = Join-Path $PublicDir 'PythonTeacherSetup.exe'

function Write-Step { param([string]$Msg) Write-Host "`n[build_release] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[build_release] $Msg" -ForegroundColor Green }

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

# --- 1. Python bundle ----------------------------------------------------------

Write-Step "Step 1/3: Python bundle"
$BundleScript = Join-Path $ScriptDir 'python\build_bundle.ps1'
& pwsh -NonInteractive -File $BundleScript
if ($LASTEXITCODE -ne 0) { throw "build_bundle.ps1 failed (exit $LASTEXITCODE)" }

# --- 2. Flutter release build --------------------------------------------------

Write-Step "Step 2/3: flutter build windows --release"
Push-Location $RepoRoot
try {
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

# --- 3. Inno Setup -------------------------------------------------------------

Write-Step "Step 3/3: Inno Setup"
$iscc = Find-Iscc
Write-Host "          ISCC: $iscc"

New-Item -ItemType Directory -Force -Path $PublicDir | Out-Null
& $iscc $IssScript
if ($LASTEXITCODE -ne 0) { throw "ISCC.exe failed (exit $LASTEXITCODE)" }

if (-not (Test-Path -LiteralPath $Installer)) {
    throw "Expected $Installer after ISCC build; check OutputDir in installer.iss."
}

$sizeMB = [math]::Round((Get-Item -LiteralPath $Installer).Length / 1MB, 1)
Write-Ok "Installer: $Installer ($sizeMB MB)"

if ($sizeMB -gt 300) {
    Write-Warning "Installer is ${sizeMB} MB — larger than expected ~250 MB. Check bundle contents."
}
