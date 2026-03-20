#Requires -Version 5.1
<#
.SYNOPSIS
    Generate AI agent instruction files for a project.

.DESCRIPTION
    Reads the ai-dev-lifecycle config, assembles rule files based on what is
    enabled, applies them to the agent-specific template, and writes the
    resulting file into the correct location in the project directory.

.PARAMETER AgentName
    The agent to generate for: claude, copilot, or cursor.

.PARAMETER ProjectDir
    Path to the project directory.

.PARAMETER ConfigFile
    Path to the .devlifecycle.json config file.

.EXAMPLE
    .\generate-agent.ps1 -AgentName claude -ProjectDir C:\Projects\my-app -ConfigFile C:\Projects\my-app\.devlifecycle.json

.NOTES
    Set LIFECYCLE_DIR environment variable to override ~/.ai-dev-lifecycle.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('claude', 'copilot', 'cursor')]
    [string]$AgentName,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$ProjectDir,

    [Parameter(Mandatory = $true, Position = 2)]
    [string]$ConfigFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Paths ─────────────────────────────────────────────────────────────────────
$LifecycleDir = if ($env:LIFECYCLE_DIR) { $env:LIFECYCLE_DIR } else { Join-Path $HOME '.ai-dev-lifecycle' }
$AgentsDir    = Join-Path $LifecycleDir 'agents'
$RulesDir     = Join-Path $AgentsDir 'rules'
$TemplateFile = Join-Path $AgentsDir "$AgentName\template.md"

function Write-Info { param([string]$Msg) Write-Host "[info]  $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "[ok]    $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[warn]  $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "[error] $Msg" -ForegroundColor Red }

# ── Validation ────────────────────────────────────────────────────────────────
if (-not (Test-Path $ConfigFile)) {
    Write-Err "Config file not found: $ConfigFile"
    exit 1
}

if (-not (Test-Path $TemplateFile)) {
    Write-Err "Template not found for agent '$AgentName': $TemplateFile"
    exit 1
}

# ── Parse config ──────────────────────────────────────────────────────────────
try {
    $Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
}
catch {
    Write-Err "Config file is not valid JSON: $ConfigFile"
    Write-Err $_.Exception.Message
    exit 1
}

# ── Determine output path ─────────────────────────────────────────────────────
$OutputFile = switch ($AgentName) {
    'claude'  { Join-Path $ProjectDir 'CLAUDE.md' }
    'copilot' { Join-Path $ProjectDir '.github\copilot-instructions.md' }
    'cursor'  { Join-Path $ProjectDir '.cursor\rules\lifecycle.mdc' }
}

# ── Read config values ────────────────────────────────────────────────────────
$ProjectName  = if ($Config.project.name)        { $Config.project.name }        else { 'Unknown Project' }
$Language     = if ($Config.project.language)    { $Config.project.language }    else { 'csharp' }
$Description  = if ($Config.project.description) { $Config.project.description } else { '' }

# Enabled rules for this agent
$AgentConfig  = $Config.agents.$AgentName
$EnabledRules = if ($AgentConfig -and $AgentConfig.rules) { $AgentConfig.rules } else { @() }

# Enabled modules list
$EnabledModules = ($Config.modules.PSObject.Properties |
    Where-Object { $_.Value.enabled -eq $true } |
    Select-Object -ExpandProperty Name) -join ', '

# ── Language command hints ────────────────────────────────────────────────────
$BuildCmd, $TestCmd, $LintCmd = switch ($Language) {
    'csharp'     { 'dotnet build', 'dotnet test', 'dotnet format --verify-no-changes' }
    'typescript' { 'npm run build', 'npm test', 'npm run lint' }
    default      { '<build command>', '<test command>', '<lint command>' }
}

# ── Assemble rules content ────────────────────────────────────────────────────
$RulesContent = ''

foreach ($RuleName in $EnabledRules) {
    if ([string]::IsNullOrWhiteSpace($RuleName)) { continue }

    $RuleFile = Join-Path $RulesDir "$RuleName.md"

    if (-not (Test-Path $RuleFile)) {
        Write-Warn "Rule file not found, skipping: $RuleFile"
        continue
    }

    Write-Info "Including rule: $RuleName"
    $RuleContent = Get-Content $RuleFile -Raw

    if ([string]::IsNullOrWhiteSpace($RulesContent)) {
        $RulesContent = $RuleContent
    }
    else {
        $RulesContent = "$RulesContent`n`n---`n`n$RuleContent"
    }
}

if ([string]::IsNullOrWhiteSpace($RulesContent)) {
    $RulesContent = '*No rules configured for this agent. Add rules to .devlifecycle.json under agents.' + $AgentName + '.rules.*'
}

# ── Load template and substitute placeholders ─────────────────────────────────
$OutputContent = Get-Content $TemplateFile -Raw

$Replacements = @{
    '{{PROJECT_NAME}}'    = $ProjectName
    '{{DESCRIPTION}}'     = $Description
    '{{LANGUAGE}}'        = $Language
    '{{ENABLED_MODULES}}' = $EnabledModules
    '{{BUILD_CMD}}'       = $BuildCmd
    '{{TEST_CMD}}'        = $TestCmd
    '{{LINT_CMD}}'        = $LintCmd
    '{{RULES_CONTENT}}'   = $RulesContent
}

foreach ($Key in $Replacements.Keys) {
    $OutputContent = $OutputContent.Replace($Key, $Replacements[$Key])
}

# ── Write output ──────────────────────────────────────────────────────────────
$OutputDir = Split-Path $OutputFile -Parent
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$Header = @"
<!-- Auto-generated by ai-dev-lifecycle. Do not edit manually. -->
<!-- Source: https://github.com/goeke-m/ai-dev-lifecycle -->
<!-- Regenerate: pwsh -File `$LifecycleDir\scripts\generate-agent.ps1 -AgentName $AgentName -ProjectDir $ProjectDir -ConfigFile $ConfigFile -->

"@

[System.IO.File]::WriteAllText($OutputFile, $Header + $OutputContent + "`n", [System.Text.Encoding]::UTF8)

Write-Ok "Generated: $OutputFile"
