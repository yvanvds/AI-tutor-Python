#!/usr/bin/env pwsh
# Build the bundled Python interpreter that ships with Python Teacher.
# Reads tooling/python/manifest.toml; produces build/python_bundle/.
# See PYTHON_IMPLEMENTATION.md section 4.1 for context.
#
# Idempotent: if build/python_bundle/MANIFEST_LOCK.json already records
# the same release_tag + sha256 + package set as the manifest, exits as
# a no-op.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Keep the bundle hermetic: ignore the user's per-user site-packages
# (e.g. %APPDATA%\Roaming\Python\Python314\site-packages from a co-installed
# system Python). Without this, pip would skip installing packages already
# present in user-site, leaving them out of the bundle.
$env:PYTHONNOUSERSITE = '1'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot  = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$ManifestFile = Join-Path $ScriptDir 'manifest.toml'
$CacheDir     = Join-Path $ScriptDir '.cache'
$BundleDir    = Join-Path $RepoRoot  'build\python_bundle'
$PythonDir    = Join-Path $BundleDir 'python'
$PythonExe    = Join-Path $PythonDir 'python.exe'
$LockFile     = Join-Path $BundleDir 'MANIFEST_LOCK.json'

function Read-Manifest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Manifest not found: $Path" }
    $section = ''
    $result  = @{}
    foreach ($raw in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(?<s>[^\]]+)\]$') {
            $section = $Matches.s
            if (-not $result.ContainsKey($section)) { $result[$section] = @{} }
            continue
        }
        if ($line -match '^(?<k>[A-Za-z_][A-Za-z0-9_-]*)\s*=\s*"(?<v>[^"]*)"\s*(#.*)?$') {
            if (-not $section) { throw "manifest.toml: key '$($Matches.k)' outside any [section]" }
            $result[$section][$Matches.k] = $Matches.v
        }
    }
    return $result
}

function Write-Step { param([string]$msg) Write-Host "[build_bundle] $msg" }

# --- Parse + validate manifest -------------------------------------------------

$cfg = Read-Manifest -Path $ManifestFile
if (-not $cfg.ContainsKey('python'))   { throw "manifest.toml: missing [python] section" }
if (-not $cfg.ContainsKey('packages')) { throw "manifest.toml: missing [packages] section" }

$python = $cfg['python']
$pkgs   = $cfg['packages']

foreach ($k in 'version','release_tag','asset','sha256') {
    if (-not $python.ContainsKey($k) -or -not $python[$k]) {
        throw "manifest.toml [python] is missing required key '$k'"
    }
}
if ($python['sha256'] -match '<.*>') {
    throw "manifest.toml [python].sha256 still contains a placeholder; fill it in first"
}
if ($pkgs.Count -eq 0) {
    throw "manifest.toml [packages] is empty; expected at least one package"
}

# --- Idempotency: skip if lock file matches ------------------------------------

$cachedRequested = @{}
foreach ($name in $pkgs.Keys) { $cachedRequested[$name] = $pkgs[$name] }

if ((Test-Path -LiteralPath $LockFile) -and (Test-Path -LiteralPath $PythonExe)) {
    try {
        $lock = Get-Content -LiteralPath $LockFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $sameInterp = ($lock.python.release_tag -eq $python['release_tag']) -and
                      ($lock.python.sha256      -eq $python['sha256'])
        $samePkgs = $true
        $lockNames = @($lock.packages.PSObject.Properties.Name) | Sort-Object
        $cfgNames  = @($pkgs.Keys) | Sort-Object
        if (($lockNames -join ',') -ne ($cfgNames -join ',')) {
            $samePkgs = $false
        } else {
            foreach ($name in $cfgNames) {
                if ($lock.packages.$name.requested -ne $pkgs[$name]) { $samePkgs = $false; break }
            }
        }
        if ($sameInterp -and $samePkgs) {
            Write-Step "Bundle already matches manifest (cache hit). Nothing to do."
            exit 0
        }
    } catch {
        Write-Step "Lock file unreadable ($($_.Exception.Message)); rebuilding."
    }
}

# --- Download / cache the install_only tarball ---------------------------------

New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
$tarball = Join-Path $CacheDir $python['asset']
$expectedSha = $python['sha256'].ToLowerInvariant()
$downloadUrl = "https://github.com/astral-sh/python-build-standalone/releases/download/$($python['release_tag'])/$($python['asset'])"

$needDownload = $true
if (Test-Path -LiteralPath $tarball) {
    $existingSha = (Get-FileHash -LiteralPath $tarball -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($existingSha -eq $expectedSha) {
        Write-Step "Cached tarball matches sha256."
        $needDownload = $false
    } else {
        Write-Step "Cached tarball sha mismatch; re-downloading."
        Remove-Item -LiteralPath $tarball -Force
    }
}

if ($needDownload) {
    Write-Step "Downloading $($python['asset']) ..."
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tarball -UseBasicParsing
    } finally {
        $ProgressPreference = $prevProgress
    }
    $newSha = (Get-FileHash -LiteralPath $tarball -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($newSha -ne $expectedSha) {
        throw "SHA-256 mismatch for $($python['asset']). Expected $expectedSha, got $newSha"
    }
}

# --- Extract -------------------------------------------------------------------

if (Test-Path -LiteralPath $BundleDir) {
    Write-Step "Removing existing $BundleDir ..."
    Remove-Item -LiteralPath $BundleDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $BundleDir | Out-Null

Write-Step "Extracting tarball to $BundleDir ..."
& tar.exe -xzf $tarball -C $BundleDir
if ($LASTEXITCODE -ne 0) { throw "tar extraction failed (exit $LASTEXITCODE)" }

if (-not (Test-Path -LiteralPath $PythonExe)) {
    throw "Expected $PythonExe after extraction; install_only layout may have changed"
}

# --- pip install pinned packages ----------------------------------------------

$pkgArgs = foreach ($name in ($pkgs.Keys | Sort-Object)) { "$name==$($pkgs[$name])" }
Write-Step "Installing packages: $($pkgArgs -join ', ')"
# -s: also belt-and-braces against user-site leakage during install.
& $PythonExe -s -m pip install --no-warn-script-location --disable-pip-version-check @pkgArgs
if ($LASTEXITCODE -ne 0) { throw "pip install failed (exit $LASTEXITCODE)" }

# --- Pre-compile to .pyc (best-effort, non-fatal) -----------------------------

Write-Step "Pre-compiling to .pyc ..."
& $PythonExe -s -m compileall -q $PythonDir
if ($LASTEXITCODE -ne 0) {
    Write-Warning "[build_bundle] compileall reported errors (exit $LASTEXITCODE) - non-fatal."
}

# --- Resolve installed versions ------------------------------------------------

$resolvedPkgs = [ordered]@{}
foreach ($name in ($pkgs.Keys | Sort-Object)) {
    $installed = $null
    $showOutput = & $PythonExe -s -m pip show --disable-pip-version-check $name
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in $showOutput) {
            if ($line -match '^Version:\s*(.+)$') { $installed = $Matches[1].Trim(); break }
        }
    }
    $resolvedPkgs[$name] = [ordered]@{
        requested = $pkgs[$name]
        installed = $installed
    }
}

# --- Write MANIFEST_LOCK.json --------------------------------------------------

$lockData = [ordered]@{
    python = [ordered]@{
        version     = $python['version']
        release_tag = $python['release_tag']
        asset       = $python['asset']
        sha256      = $python['sha256']
    }
    packages = $resolvedPkgs
    built_at = (Get-Date).ToUniversalTime().ToString('o')
}
$lockData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $LockFile -Encoding utf8

Write-Step "Done. Bundle at $BundleDir"
