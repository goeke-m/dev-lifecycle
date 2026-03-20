#Requires -Version 5.1
<#
.SYNOPSIS
    Pull latest ai-dev-lifecycle changes and re-apply to all registered projects.

.DESCRIPTION
    Performs a fast-forward git pull on the lifecycle repo, then iterates over
    every registered project and re-runs apply.ps1 to keep files in sync.

.NOTES
    Set LIFECYCLE_DIR environment variable to override the default ~/.ai-dev-lifecycle path.
    This script is intended to be run by the Windows Task Scheduler task created by apply.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Paths ─────────────────────────────────────────────────────────────────────
$LifecycleDir = if ($env:LIFECYCLE_DIR) { $env:LIFECYCLE_DIR } else { Join-Path $HOME '.ai-dev-lifecycle' }
$Registry     = Join-Path $LifecycleDir '.registered-projects'

function Get-Timestamp { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
function Log      { param([string]$Msg) Write-Host "[$( Get-Timestamp )] [info]  $Msg" }
function Log-Ok   { param([string]$Msg) Write-Host "[$( Get-Timestamp )] [ok]    $Msg" -ForegroundColor Green }
function Log-Warn { param([string]$Msg) Write-Host "[$( Get-Timestamp )] [warn]  $Msg" -ForegroundColor Yellow }
function Log-Err  { param([string]$Msg) Write-Host "[$( Get-Timestamp )] [error] $Msg" -ForegroundColor Red }

# ── Preflight ─────────────────────────────────────────────────────────────────
Log "ai-dev-lifecycle update starting"
Log "LifecycleDir: $LifecycleDir"

if (-not (Test-Path $LifecycleDir)) {
    Log-Err "LifecycleDir does not exist: $LifecycleDir"
    exit 1
}

if (-not (Test-Path (Join-Path $LifecycleDir '.git'))) {
    Log-Err "LifecycleDir is not a git repository: $LifecycleDir"
    exit 1
}

# ── Pull latest ───────────────────────────────────────────────────────────────
Log "Pulling latest changes from remote..."

$BeforeSha = & git -C $LifecycleDir rev-parse HEAD 2>&1
if ($LASTEXITCODE -ne 0) {
    Log-Err "Could not determine current HEAD: $BeforeSha"
    exit 1
}

$PullOutput = & git -C $LifecycleDir pull --ff-only 2>&1
$PullExit   = $LASTEXITCODE

foreach ($line in $PullOutput) { Log $line }

if ($PullExit -ne 0) {
    Log-Err "git pull --ff-only failed. The local repo may have diverged."
    Log-Err "Resolve manually in: $LifecycleDir"
    exit 1
}

$AfterSha = & git -C $LifecycleDir rev-parse HEAD 2>&1
if ($BeforeSha -eq $AfterSha) {
    Log "Already up-to-date ($( & git -C $LifecycleDir rev-parse --short HEAD 2>&1 ))"
}
else {
    Log-Ok "Updated: $BeforeSha -> $AfterSha"
}

# ── Re-apply to registered projects ──────────────────────────────────────────
if (-not (Test-Path $Registry)) {
    Log-Warn "No registered projects found at: $Registry"
    Log "Nothing to re-apply."
    exit 0
}

$ApplyScript = Join-Path $LifecycleDir 'scripts\apply.ps1'
if (-not (Test-Path $ApplyScript)) {
    Log-Err "apply.ps1 not found: $ApplyScript"
    exit 1
}

$SuccessCount = 0
$SkipCount    = 0
$FailCount    = 0

Log "Re-applying lifecycle to registered projects..."
Log "Registry: $Registry"

$Projects = Get-Content $Registry -ErrorAction SilentlyContinue
foreach ($ProjectDir in $Projects) {
    $ProjectDir = $ProjectDir.Trim()
    if ([string]::IsNullOrWhiteSpace($ProjectDir) -or $ProjectDir.StartsWith('#')) { continue }

    if (-not (Test-Path $ProjectDir)) {
        Log-Warn "Project directory no longer exists — skipping: $ProjectDir"
        $SkipCount++
        continue
    }

    $ProjectConfig = Join-Path $ProjectDir '.devlifecycle.json'
    if (-not (Test-Path $ProjectConfig)) {
        Log-Warn "No .devlifecycle.json found in: $ProjectDir — skipping"
        $SkipCount++
        continue
    }

    Log "Re-applying to: $ProjectDir"
    try {
        $env:LIFECYCLE_DIR = $LifecycleDir
        $Output = & pwsh -NonInteractive -File $ApplyScript -ProjectDir $ProjectDir 2>&1
        foreach ($line in $Output) { Log "  $line" }

        if ($LASTEXITCODE -eq 0) {
            Log-Ok "Successfully re-applied: $ProjectDir"
            $SuccessCount++
        }
        else {
            Log-Err "apply.ps1 exited with code $LASTEXITCODE for: $ProjectDir"
            $FailCount++
        }
    }
    catch {
        Log-Err "Exception while re-applying $ProjectDir`: $($_.Exception.Message)"
        $FailCount++
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Log "---"
Log "Update complete."
Log "  Success : $SuccessCount"
Log "  Skipped : $SkipCount"
Log "  Failed  : $FailCount"

if ($FailCount -gt 0) {
    exit 1
}
