# Developer Onboarding

This document covers how to set up the dev-lifecycle on a new machine and how to apply it
to a project for the first time.

---

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `git` | Clone and update the lifecycle repo | [git-scm.com](https://git-scm.com) |
| `jq` | JSON config parsing in shell scripts | `brew install jq` / `apt install jq` / [Windows](https://jqlang.github.io/jq/download/) |
| `gh` (optional) | GitHub CLI for PR workflows | [cli.github.com](https://cli.github.com) |

---

## Step 1 — Clone the Lifecycle Repo (once per machine)

**Linux / macOS**
```bash
git clone https://github.com/goeke-m/dev-lifecycle.git ~/.dev-lifecycle
```

**Windows (PowerShell)**
```powershell
git clone https://github.com/goeke-m/dev-lifecycle.git "$env:USERPROFILE\.dev-lifecycle"
```

> The lifecycle repo lives at `~/.dev-lifecycle` on every machine. The apply scripts default
> to this path. You can override it with the `LIFECYCLE_DIR` environment variable if needed.

---

## Step 2 — Apply to a Project (once per project)

### 2a. Create the project config

Copy the example config into your project root and edit it:

```bash
cp ~/.dev-lifecycle/.devlifecycle.example.json /path/to/your-project/.devlifecycle.json
```

Open `.devlifecycle.json` and set at minimum:

```json
{
  "project": {
    "name": "your-project-name",
    "language": "csharp",
    "description": "What this project does"
  },
  "modules": {
    "coding-standards": { "enabled": true },
    "pr-workflows":     { "enabled": true },
    "testing":          { "enabled": true },
    "documentation":    { "enabled": true },
    "scaffolding":      { "enabled": false }
  },
  "hooks": {
    "pre-commit":  { "enabled": true },
    "commit-msg":  { "enabled": true }
  },
  "agents": {
    "claude":  { "enabled": true,  "rules": ["git-commits", "pr-standards", "testing", "csharp-conventions", "dotnet-architecture", "security", "data-practices", "database-schema", "performance-testing"] },
    "copilot": { "enabled": true,  "rules": ["git-commits", "pr-standards", "testing", "csharp-conventions", "dotnet-architecture", "security", "data-practices", "database-schema", "performance-testing"] },
    "cursor":  { "enabled": false, "rules": [] }
  }
}
```

**Language options:** `csharp` | `typescript`

### 2b. Run the apply script

**Linux / macOS**
```bash
cd /path/to/your-project
~/.dev-lifecycle/scripts/apply.sh
```

**Windows (PowerShell — run as Administrator or with Developer Mode enabled)**
```powershell
cd C:\path\to\your-project
~\.dev-lifecycle\scripts\apply.ps1
```

The script will:
- Symlink config files from enabled modules into your project
- Install git hooks into `.git/hooks/`
- Generate agent instruction files (`CLAUDE.md`, `.github/copilot-instructions.md`, etc.)
- Register your project for daily auto-updates
- Install a cron job (Linux/macOS) or Scheduled Task (Windows) to pull updates at 8am daily

### 2c. Commit the generated files

```bash
git add .devlifecycle.json CLAUDE.md
git add .github/copilot-instructions.md   # if copilot enabled
git add .cursor/rules/lifecycle.mdc       # if cursor enabled
git commit -m "chore: add dev-lifecycle configuration"
```

> **Why commit the generated files?**
> So every team member and every agent session gets the rules without running `apply.sh`.
> Only the person managing the lifecycle config needs to run it locally.

---

## Step 3 — Add CI Integration (once per project)

Add the lifecycle update check to your GitHub Actions workflows so the repo
gets a PR automatically when rules are updated:

```yaml
# .github/workflows/lifecycle-update.yml
name: Lifecycle Update Check
on:
  schedule:
    - cron: '0 9 * * 1'   # weekly, Monday 9am UTC
  workflow_dispatch:

jobs:
  check:
    uses: goeke-m/dev-lifecycle/.github/workflows/lifecycle-update.yml@main
    with:
      project-language: csharp
      enabled-agents: '["claude", "copilot"]'
```

For reusable build and test workflows, see [CI/CD Integration](#cicd-integration) below.

---

## Day-to-Day Usage

Once set up, the lifecycle is largely invisible:

| What happens | How |
|---|---|
| Commit message validated | `commit-msg` hook fires automatically on `git commit` |
| Code linted before commit | `pre-commit` hook fires automatically |
| Agent follows project rules | `CLAUDE.md` / `copilot-instructions.md` loaded automatically by each tool |
| Rules updated locally | Cron pulls lifecycle repo at 8am and regenerates agent files |
| Rules updated in CI | Weekly GH Action opens a PR if committed agent files are out of date |

### Manually regenerating agent files

If you update `.devlifecycle.json` or want to pull the latest rules immediately:

```bash
# Regenerate all enabled agents
~/.dev-lifecycle/scripts/apply.sh

# Or regenerate a single agent
~/.dev-lifecycle/scripts/generate-agent.sh claude /path/to/project /path/to/project/.devlifecycle.json
```

### Pulling the latest lifecycle rules manually

```bash
~/.dev-lifecycle/scripts/update.sh
```

This pulls `~/.dev-lifecycle` and re-applies to all registered projects.

---

## CI/CD Integration

Use the reusable workflows from this repo in your project's GitHub Actions. Reference them
with `uses:` — they are always pulled fresh from `main`.

### C# build and test

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  build:
    uses: goeke-m/dev-lifecycle/.github/workflows/build-csharp.yml@main
    with:
      dotnet-version: '9.0.x'
      project-path: src/MyApp/MyApp.csproj

  test:
    uses: goeke-m/dev-lifecycle/.github/workflows/test-csharp.yml@main
    with:
      dotnet-version: '9.0.x'
      project-path: src/MyApp/MyApp.csproj

  pr-check:
    if: github.event_name == 'pull_request'
    uses: goeke-m/dev-lifecycle/.github/workflows/pr-check.yml@main
```

### TypeScript build and test

```yaml
jobs:
  build:
    uses: goeke-m/dev-lifecycle/.github/workflows/build-typescript.yml@main
    with:
      node-version: '22'
      package-manager: npm

  test:
    uses: goeke-m/dev-lifecycle/.github/workflows/test-typescript.yml@main
    with:
      node-version: '22'
```

---

## Troubleshooting

### `apply.sh` says jq is not installed

```bash
# macOS
brew install jq

# Debian / Ubuntu
sudo apt-get install jq

# Windows (via winget)
winget install jqlang.jq
```

### `apply.sh` says LIFECYCLE_DIR does not exist

You haven't cloned the lifecycle repo yet, or you cloned it to a different path:

```bash
git clone https://github.com/goeke-m/dev-lifecycle.git ~/.dev-lifecycle
# or, if cloned elsewhere:
export LIFECYCLE_DIR=/path/to/dev-lifecycle
~/.dev-lifecycle/scripts/apply.sh
```

### Windows symlink errors

Symlinks on Windows require either **Developer Mode** (Settings → For Developers → Developer Mode)
or running PowerShell as Administrator. If neither is available, the script falls back to
copying files — you will need to re-run `apply.ps1` after pulling lifecycle updates instead
of relying on symlinks.

### Git hook not firing

Hooks must be executable. The apply script sets this, but if you cloned on Windows and
moved to Linux, permissions may have been lost:

```bash
chmod +x ~/.dev-lifecycle/hooks/*
~/.dev-lifecycle/scripts/apply.sh   # re-links hooks with correct permissions
```

### Cron job not running

Verify the cron entry was installed:
```bash
crontab -l | grep dev-lifecycle
```

If missing, re-run `apply.sh` or add manually:
```bash
(crontab -l; echo "0 8 * * * bash $HOME/.dev-lifecycle/scripts/update.sh >> $HOME/.dev-lifecycle-update.log 2>&1") | crontab -
```
