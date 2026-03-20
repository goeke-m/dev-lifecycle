#Requires -Version 5.1
<#
.SYNOPSIS
    Apply ai-dev-lifecycle configuration to a project (Windows PowerShell).

.DESCRIPTION
    Reads .devlifecycle.json from the project directory and symlinks lifecycle
    files, installs git hooks, generates agent instruction files, registers the
    project, and sets up a Windows Task Scheduler task for daily updates.

.PARAMETER ProjectDir
    Path to the project directory. Defaults to the current directory.

.EXAMPLE
    .\apply.ps1
    .\apply.ps1 -ProjectDir C:\Projects\my-project

.NOTES
    Symbolic links require either Developer Mode enabled or Administrator rights.
    Set LIFECYCLE_DIR environment variable to override the default ~/.ai-dev-lifecycle path.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ProjectDir = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Resolve paths ─────────────────────────────────────────────────────────────
$LifecycleDir = if ($env:LIFECYCLE_DIR) { $env:LIFECYCLE_DIR } else { Join-Path $HOME '.ai-dev-lifecycle' }
$ProjectDir   = (Resolve-Path $ProjectDir).Path
$ConfigFile   = Join-Path $ProjectDir '.devlifecycle.json'

# ── Colors / output helpers ───────────────────────────────────────────────────
function Write-Info    { param([string]$Msg) Write-Host "[info]  $Msg" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Msg) Write-Host "[ok]    $Msg" -ForegroundColor Green }
function Write-Warn    { param([string]$Msg) Write-Host "[warn]  $Msg" -ForegroundColor Yellow }
function Write-Err     { param([string]$Msg) Write-Host "[error] $Msg" -ForegroundColor Red }
function Write-Header  { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan -NoNewline; Write-Host "" }

# ── Symlink privilege check ───────────────────────────────────────────────────
function Test-SymlinkPrivilege {
    $testSrc = Join-Path $env:TEMP 'lifecycle-symtest-src.txt'
    $testDst = Join-Path $env:TEMP 'lifecycle-symtest-dst.txt'
    [System.IO.File]::WriteAllText($testSrc, 'test')
    try {
        New-Item -ItemType SymbolicLink -Path $testDst -Target $testSrc -Force -ErrorAction Stop | Out-Null
        Remove-Item $testDst -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
    finally {
        Remove-Item $testSrc -Force -ErrorAction SilentlyContinue
    }
}

# ── Create symlink (file) ─────────────────────────────────────────────────────
function New-Symlink {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$CanSymlink
    )

    if (-not (Test-Path $Source)) {
        Write-Warn "Source does not exist, skipping: $Source"
        return
    }

    $destDir = Split-Path $Destination -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    if (Test-Path $Destination) {
        $item = Get-Item $Destination -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            $existingTarget = $item.Target
            if ($existingTarget -eq $Source) {
                Write-Info "Symlink already up-to-date: $Destination"
                return
            }
            Write-Warn "Replacing existing symlink: $Destination -> $existingTarget"
            Remove-Item $Destination -Force
        }
        else {
            Write-Warn "File exists and is not a symlink — backing up: ${Destination}.bak"
            Move-Item $Destination "${Destination}.bak" -Force
        }
    }

    if ($CanSymlink) {
        New-Item -ItemType SymbolicLink -Path $Destination -Target $Source -Force | Out-Null
        Write-Ok "Linked: $Destination -> $Source"
    }
    else {
        # Fallback: copy the file and warn
        Copy-Item $Source $Destination -Force
        Write-Warn "Copied (no symlink privilege): $Destination <- $Source"
        Write-Warn "Enable Developer Mode or run as Administrator for true symlinks."
    }
}

# ── Symlink directory contents (flat) ─────────────────────────────────────────
function Sync-DirContents {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [bool]$CanSymlink
    )

    if (-not (Test-Path $SourceDir)) {
        Write-Warn "Source directory does not exist, skipping: $SourceDir"
        return
    }

    if (-not (Test-Path $DestDir)) {
        New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
    }

    Get-ChildItem -Path $SourceDir -File | ForEach-Object {
        New-Symlink -Source $_.FullName -Destination (Join-Path $DestDir $_.Name) -CanSymlink $CanSymlink
    }
}

# ── Preflight ─────────────────────────────────────────────────────────────────
Write-Header "ai-dev-lifecycle apply"
Write-Info "LifecycleDir : $LifecycleDir"
Write-Info "ProjectDir   : $ProjectDir"

if (-not (Test-Path $LifecycleDir)) {
    Write-Err "LifecycleDir does not exist: $LifecycleDir"
    Write-Err "Clone the ai-dev-lifecycle repo first:"
    Write-Err "  git clone https://github.com/goeke-m/ai-dev-lifecycle.git $LifecycleDir"
    exit 1
}

if (-not (Test-Path $ConfigFile)) {
    Write-Err "Config file not found: $ConfigFile"
    Write-Err "Copy the example config to get started:"
    Write-Err "  Copy-Item '$LifecycleDir\.devlifecycle.example.json' '$ProjectDir\.devlifecycle.json'"
    exit 1
}

# Parse JSON config
try {
    $Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
}
catch {
    Write-Err "Config file is not valid JSON: $ConfigFile"
    Write-Err $_.Exception.Message
    exit 1
}

$CanSymlink = Test-SymlinkPrivilege
if (-not $CanSymlink) {
    Write-Warn "Cannot create symbolic links. To enable symlinks on Windows:"
    Write-Warn "  1. Enable Developer Mode in Settings > System > For developers, OR"
    Write-Warn "  2. Run this script as Administrator."
    Write-Warn "Falling back to file copies (changes to lifecycle will NOT auto-propagate)."
}

# ── Read config ───────────────────────────────────────────────────────────────
$Language    = if ($Config.project.language)    { $Config.project.language }    else { 'csharp' }
$ProjectName = if ($Config.project.name)        { $Config.project.name }        else { 'unknown' }

Write-Info "Project      : $ProjectName"
Write-Info "Language     : $Language"

# ── Modules ───────────────────────────────────────────────────────────────────
Write-Header "Applying modules"

$Modules = @('coding-standards', 'scaffolding', 'pr-workflows', 'testing', 'documentation')

foreach ($Module in $Modules) {
    $ModuleCfg = $Config.modules.$Module
    $Enabled   = $ModuleCfg -and $ModuleCfg.enabled -eq $true

    if (-not $Enabled) {
        Write-Info "Module '$Module' is disabled — skipping"
        continue
    }

    Write-Info "Applying module: $Module"

    switch ($Module) {
        'pr-workflows' {
            $PrSrc = Join-Path $LifecycleDir 'modules\pr-workflows\github\PULL_REQUEST_TEMPLATE.md'
            $PrDst = Join-Path $ProjectDir '.github\PULL_REQUEST_TEMPLATE.md'
            New-Symlink -Source $PrSrc -Destination $PrDst -CanSymlink $CanSymlink
        }
        'documentation' {
            $DocSrc = Join-Path $LifecycleDir 'modules\documentation\templates'
            $DocDst = Join-Path $ProjectDir 'docs\templates'
            Sync-DirContents -SourceDir $DocSrc -DestDir $DocDst -CanSymlink $CanSymlink
        }
        default {
            $ModuleSrc = Join-Path $LifecycleDir "modules\$Module\$Language"
            Sync-DirContents -SourceDir $ModuleSrc -DestDir $ProjectDir -CanSymlink $CanSymlink
        }
    }

    Write-Ok "Module '$Module' applied"
}

# ── Git hooks ─────────────────────────────────────────────────────────────────
Write-Header "Installing git hooks"

$GitDir = & git -C $ProjectDir rev-parse --git-dir 2>$null
if (-not $GitDir) {
    Write-Warn "Project directory is not a git repo — skipping hook installation"
}
else {
    # git rev-parse returns a relative path; resolve it
    if (-not [System.IO.Path]::IsPathRooted($GitDir)) {
        $GitDir = Join-Path $ProjectDir $GitDir
    }
    $HooksDir = Join-Path $GitDir 'hooks'
    if (-not (Test-Path $HooksDir)) { New-Item -ItemType Directory -Path $HooksDir -Force | Out-Null }

    $HookNames = @('pre-commit', 'commit-msg')
    foreach ($Hook in $HookNames) {
        $HookCfg = $Config.hooks.$Hook
        $Enabled  = $HookCfg -and $HookCfg.enabled -eq $true

        if (-not $Enabled) {
            Write-Info "Hook '$Hook' is disabled — skipping"
            continue
        }

        $HookSrc = Join-Path $LifecycleDir "hooks\$Hook"
        $HookDst = Join-Path $HooksDir $Hook

        if (-not (Test-Path $HookSrc)) {
            Write-Warn "Hook source not found: $HookSrc"
            continue
        }

        New-Symlink -Source $HookSrc -Destination $HookDst -CanSymlink $CanSymlink
        Write-Ok "Hook '$Hook' installed"
    }
}

# ── Agent generation ──────────────────────────────────────────────────────────
Write-Header "Generating agent instruction files"

$Agents = @('claude', 'copilot', 'cursor')
foreach ($Agent in $Agents) {
    $AgentCfg = $Config.agents.$Agent
    $Enabled   = $AgentCfg -and $AgentCfg.enabled -eq $true

    if (-not $Enabled) {
        Write-Info "Agent '$Agent' is disabled — skipping"
        continue
    }

    Write-Info "Generating agent: $Agent"
    $GenerateScript = Join-Path $LifecycleDir 'scripts\generate-agent.ps1'

    if (-not (Test-Path $GenerateScript)) {
        Write-Warn "generate-agent.ps1 not found: $GenerateScript"
        continue
    }

    & pwsh -NonInteractive -File $GenerateScript -AgentName $Agent -ProjectDir $ProjectDir -ConfigFile $ConfigFile
    Write-Ok "Agent '$Agent' generated"
}

# ── Register project ──────────────────────────────────────────────────────────
Write-Header "Registering project"

$Registry = Join-Path $LifecycleDir '.registered-projects'
if (-not (Test-Path $Registry)) { New-Item -ItemType File -Path $Registry -Force | Out-Null }

$Existing = Get-Content $Registry -ErrorAction SilentlyContinue
if ($Existing -contains $ProjectDir) {
    Write-Info "Project already registered: $ProjectDir"
}
else {
    Add-Content -Path $Registry -Value $ProjectDir
    Write-Ok "Registered project: $ProjectDir"
}

# ── Install Task Scheduler task ───────────────────────────────────────────────
Write-Header "Installing Windows Task Scheduler update task"

$TaskName   = 'ai-dev-lifecycle-daily-update'
$UpdateScript = Join-Path $LifecycleDir 'scripts\update.ps1'

$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Info "Scheduled task '$TaskName' already exists"
}
else {
    try {
        $Action  = New-ScheduledTaskAction `
            -Execute 'pwsh.exe' `
            -Argument "-NonInteractive -File `"$UpdateScript`"" `
            -WorkingDirectory $LifecycleDir

        $Trigger = New-ScheduledTaskTrigger -Daily -At '08:00'

        $Settings = New-ScheduledTaskSettingsSet `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30) `
            -StartWhenAvailable

        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $Action `
            -Trigger $Trigger `
            -Settings $Settings `
            -Description 'Daily ai-dev-lifecycle update — keeps lifecycle files in sync across registered projects.' `
            -RunLevel Limited `
            -Force | Out-Null

        Write-Ok "Scheduled task '$TaskName' created (daily at 8:00 AM)"
    }
    catch {
        Write-Warn "Could not create scheduled task (may require elevated prompt): $($_.Exception.Message)"
        Write-Warn "Run this script as Administrator to install the scheduled task."
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "ai-dev-lifecycle applied successfully to: $ProjectDir" -ForegroundColor Green
Write-Host ""
