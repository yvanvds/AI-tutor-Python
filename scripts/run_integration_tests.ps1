# CI driver for the Windows-desktop integration suite (#81).
#
# Why this exists: flutter_tools has a long-standing, intermittent race on
# Windows in which its temp listener file disappears mid-run and the tool then
# dies during "finalization of test" with a PathNotFoundException — killing
# the whole test process, so every test after the abort point reports "did
# not complete". Upstream: flutter/flutter#144008 (open, no fix version).
# Observed here on Flutter 3.47.1 on the GitHub windows-latest runner: two
# identical failures and one pass on the same commit — see #81 for the
# evidence trail. Because the aggregated entry point runs every flow in one
# process (see integration_test/app_test.dart), one abort used to lose the
# entire suite and turn main red with nothing wrong in the code.
#
# Strategy (options 1 + 3 from #81, both kept narrow):
#
#   1. Run the aggregated entry point once — the fast path, and on Windows
#      the only way to run all flows in one invocation (the app launches only
#      for the first test file of an invocation).
#   2. If it fails WITH the tooling-abort signature, fall back to running
#      each integration_test/flows/*.dart in its own invocation (every flow
#      is a standalone entry point by design), so a repeat abort costs one
#      flow instead of the suite. Each flow gets one retry, again only on
#      the signature.
#   3. A failure WITHOUT the signature is a real test failure: it fails the
#      job immediately and is never retried, so no genuine signal is masked.
#      Green always means every test passed in an invocation that ran to
#      completion, and every contained abort is annotated with ::warning so
#      the flake rate stays visible in the workflow UI.
#
# Local runs don't need this script: `flutter test integration_test -d windows`.

[CmdletBinding()]
param(
  # The command invoked as `<command> test <target> -d windows`. Overridable
  # so the retry/fallback control flow can be exercised against a stub
  # without building the app (see #81).
  [string]$FlutterCommand = 'flutter'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# The signature of the upstream race, and only it: both lines must be present
# for a failure to count as a tooling abort. A test failure, a compile error
# or a device-launch failure matches neither, and is therefore never retried.
$finalizationPattern = 'unhandled error during finalization of test'
$listenerPattern = 'flutter_test_listener'

$script:abortCount = 0

function Invoke-FlutterTest {
  param([string]$Target)
  Write-Host "== $FlutterCommand test $Target -d windows =="
  & $FlutterCommand test $Target -d windows --reporter expanded 2>&1 |
    Tee-Object -Variable outputLines
  $exitCode = $LASTEXITCODE
  $text = ($outputLines | ForEach-Object { "$_" }) -join "`n"
  [pscustomobject]@{
    ExitCode       = $exitCode
    IsToolingAbort = ($exitCode -ne 0) -and
      ($text -match $finalizationPattern) -and
      ($text -match $listenerPattern)
  }
}

function Write-AbortWarning {
  param([string]$What)
  $script:abortCount++
  Write-Host ("::warning title=flutter_tools abort contained (issue 81)::" +
    "$What died in flutter_tools finalization (temp listener-file race, " +
    "upstream flutter/flutter#144008), not on a test failure. " +
    "Occurrence $($script:abortCount) in this job.")
}

$aggregated = Invoke-FlutterTest -Target 'integration_test'
if ($aggregated.ExitCode -eq 0) {
  Write-Host 'Aggregated integration run passed.'
  exit 0
}
if (-not $aggregated.IsToolingAbort) {
  Write-Host ('::error::Integration tests failed without the flutter_tools ' +
    'abort signature - a real failure. Not retrying (see #81).')
  exit $aggregated.ExitCode
}

Write-AbortWarning 'The aggregated run (integration_test/app_test.dart)'
Write-Host ('Falling back to one invocation per flow so a repeat abort ' +
  'costs one flow, not the suite (#81).')

$flowFiles = Get-ChildItem -Path (Join-Path $repoRoot 'integration_test/flows') `
  -Filter '*.dart' | Sort-Object Name
if (-not $flowFiles) {
  Write-Host ('::error::No flow files found under integration_test/flows - ' +
    'refusing to pass on an empty fallback.')
  exit 1
}

$failedFlows = @()
foreach ($flow in $flowFiles) {
  $target = "integration_test/flows/$($flow.Name)"
  $result = Invoke-FlutterTest -Target $target
  if ($result.ExitCode -eq 0) { continue }
  if ($result.IsToolingAbort) {
    Write-AbortWarning $target
    # One retry, and only because the failure was the tooling race.
    $result = Invoke-FlutterTest -Target $target
    if ($result.ExitCode -eq 0) { continue }
    if ($result.IsToolingAbort) { Write-AbortWarning "$target (retry)" }
  }
  $failedFlows += $target
  Write-Host "::error::$target failed in the per-flow fallback."
}

if ($env:GITHUB_STEP_SUMMARY) {
  $summary = @(
    '### Integration tests: per-flow fallback used (#81)'
    ''
    "flutter_tools aborts contained in this job: $($script:abortCount)"
    ''
  )
  if ($failedFlows) {
    $summary += "Failed flows: $($failedFlows -join ', ')"
  }
  else {
    $summary += ('All flows passed individually; every test ran to ' +
      'completion in a passing invocation.')
  }
  $summary | Add-Content -Path $env:GITHUB_STEP_SUMMARY
}

if ($failedFlows) {
  Write-Host "Per-flow fallback failed for: $($failedFlows -join ', ')"
  exit 1
}
Write-Host ("All flows passed in the per-flow fallback " +
  "($($script:abortCount) tooling abort(s) contained).")
exit 0
