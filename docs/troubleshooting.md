# Troubleshooting

This guide covers common problems across setup, apply, hooks, agent generation, CI/CD,
and auto-updates. If your issue is not listed here, open a discussion in the repository.

---

## Table of Contents

- [Machine Setup](#machine-setup)
- [apply.sh / apply.ps1](#applysh--applyps1)
- [Git Hooks](#git-hooks)
- [Agent File Generation](#agent-file-generation)
- [Symlinked Modules](#symlinked-modules)
- [Auto-Update (Cron / Task Scheduler)](#auto-update-cron--task-scheduler)
- [CI/CD and Reusable Workflows](#cicd-and-reusable-workflows)
- [Windows-Specific Issues](#windows-specific-issues)
- [Tool-Specific Issues](#tool-specific-issues)
- [General Debugging](#general-debugging)

---

## Machine Setup

### `LIFECYCLE_DIR does not exist`

```
[error] LIFECYCLE_DIR does not exist: /home/you/.ai-dev-lifecycle
```

The lifecycle repo has not been cloned, or was cloned to a different path.

```bash
# Clone to the default location
git clone https://github.com/goeke-m/ai-dev-lifecycle.git ~/.ai-dev-lifecycle

# Or point to wherever you cloned it
export LIFECYCLE_DIR=/custom/path/ai-dev-lifecycle
~/.ai-dev-lifecycle/scripts/apply.sh
```

To make the override permanent, add the export to your shell profile (`~/.bashrc`, `~/.zshrc`).

---

### `jq: command not found`

```
[error] 'jq' is required but not installed.
```

| Platform | Command |
|---|---|
| macOS | `brew install jq` |
| Debian / Ubuntu | `sudo apt-get install jq` |
| Fedora / RHEL | `sudo dnf install jq` |
| Windows (winget) | `winget install jqlang.jq` |
| Windows (choco) | `choco install jq` |

After installing, verify: `jq --version`

---

### `dotnet: command not found` in hooks

The `pre-commit` hook calls `dotnet format` for C# projects. If `dotnet` is not on your
PATH inside the hook environment:

```bash
# Find where dotnet is installed
which dotnet

# Add to your shell profile, then reload it
echo 'export PATH="$PATH:/usr/share/dotnet"' >> ~/.bashrc
source ~/.bashrc

# Re-link hooks to pick up the updated PATH
~/.ai-dev-lifecycle/scripts/apply.sh
```

---

## apply.sh / apply.ps1

### `Config file not found`

```
[error] Config file not found: /path/to/project/.devlifecycle.json
```

You need to create a config file in the project root before running apply:

```bash
cp ~/.ai-dev-lifecycle/.devlifecycle.example.json .devlifecycle.json
# Edit .devlifecycle.json, then re-run:
~/.ai-dev-lifecycle/scripts/apply.sh
```

---

### `Config file is not valid JSON`

```
[error] Config file is not valid JSON: .devlifecycle.json
```

Validate the file:

```bash
jq empty .devlifecycle.json
```

`jq` will print the exact line and position of the syntax error. Common causes:
- Trailing comma after the last item in an array or object
- Missing closing `}` or `]`
- Unescaped special characters in a string value

---

### Module files not appearing in the project

If a module is enabled but its files are not symlinked, check:

1. **Is the language set correctly?** The script looks for files in
   `modules/{module}/{language}/`. If your config says `"language": "csharp"` but the
   files are under `typescript/`, nothing will be linked.

   ```bash
   jq '.project.language' .devlifecycle.json
   ls ~/.ai-dev-lifecycle/modules/coding-standards/
   ```

2. **Is the module directory empty?** Some modules may not have files for every language yet.

3. **Did the script report a warning?**

   ```bash
   ~/.ai-dev-lifecycle/scripts/apply.sh 2>&1 | grep -i warn
   ```

---

### `apply.sh` backs up an existing file unexpectedly

```
[warn] File exists and is not a symlink — backing up: .editorconfig.bak
```

The project already had a file at the target path that was not a lifecycle symlink.
The original file has been moved to `.editorconfig.bak`. Review it:

```bash
diff .editorconfig .editorconfig.bak
```

If the backup contains customisations you want to keep, merge them into the lifecycle
module file and open a PR. If it is safe to discard, delete it:

```bash
rm .editorconfig.bak
```

---

## Git Hooks

### Hooks not firing on `git commit`

**1. Check the hook is installed:**

```bash
ls -la .git/hooks/
# Should show symlinks pointing to ~/.ai-dev-lifecycle/hooks/
```

If missing, re-run `apply.sh`.

**2. Check the hook is executable:**

```bash
ls -la ~/.ai-dev-lifecycle/hooks/pre-commit
# Should show -rwxr-xr-x
```

If not:

```bash
chmod +x ~/.ai-dev-lifecycle/hooks/*
```

**3. Check the hook is not being skipped:**

Some Git GUIs and IDE integrations bypass hooks by default. Check your tool's settings.
If someone committed with `git commit --no-verify`, hooks were intentionally skipped —
this should not be done without a documented reason.

---

### `pre-commit` hook fails for TypeScript but `lint-staged` is not installed

The pre-commit hook checks for `lint-staged` in `package.json`. If it is not present,
the hook skips silently. To enable TypeScript linting on commit:

```bash
npm install --save-dev lint-staged
```

Then add a `lint-staged` config to `package.json`:

```json
"lint-staged": {
  "*.ts": ["eslint --fix", "prettier --write"],
  "*.tsx": ["eslint --fix", "prettier --write"]
}
```

---

### `commit-msg` hook rejects a valid commit message

The hook enforces Conventional Commits. The full pattern is:

```
<type>(<optional scope>): <description>
```

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `build`,
`perf`, `revert`

Common reasons for rejection:

| Problem | Example | Fix |
|---|---|---|
| Missing type | `Update README` | `docs: update README` |
| Wrong case | `Feat: add login` | `feat: add login` |
| Missing colon | `feat add login` | `feat: add login` |
| Subject too long | Subject > 100 characters | Shorten the description |
| Extra space before colon | `feat : add login` | `feat: add login` |

To check your message before committing:

```bash
echo "your commit message" | bash ~/.ai-dev-lifecycle/hooks/commit-msg /dev/stdin
```

---

## Agent File Generation

### Generated file is empty or contains only the header

`generate-agent.sh` found no enabled rules for the agent. Check:

```bash
# Verify the agent is enabled and has rules listed
jq '.agents.claude' .devlifecycle.json
```

Expected output:
```json
{
  "enabled": true,
  "rules": ["git-commits", "testing", "csharp-conventions"]
}
```

If `rules` is empty or missing, add the rule names you want included.

---

### `[warn] Rule file not found, skipping`

```
[warn]  Rule file not found, skipping: /home/you/.ai-dev-lifecycle/agents/rules/my-rule.md
```

The rule name listed in `.devlifecycle.json` does not match any file in `agents/rules/`.
List available rules:

```bash
ls ~/.ai-dev-lifecycle/agents/rules/
```

Check for typos in your config. Rule names are the filename without `.md`:
`csharp-conventions` → `agents/rules/csharp-conventions.md`

---

### Placeholders like `{{PROJECT_NAME}}` appear literally in the output

The `generate-agent.sh` script substitutes placeholders from `.devlifecycle.json`.
If a placeholder is still present in the output, the corresponding config key is missing
or set to `null`.

```bash
# Check your config has all required fields
jq '.project' .devlifecycle.json
```

Required fields:

```json
{
  "project": {
    "name": "my-project",
    "language": "csharp",
    "description": "What this project does"
  }
}
```

---

### `CLAUDE.md` is not being picked up by Claude Code

Claude Code loads `CLAUDE.md` from the current working directory and all parent
directories. Ensure:

1. The file exists at the project root: `ls CLAUDE.md`
2. You have opened the project from its root directory, not a subdirectory
3. The file is not listed in `.gitignore`

---

### Copilot instructions not taking effect

GitHub Copilot loads instructions from `.github/copilot-instructions.md`. Ensure:

1. The file is committed — Copilot reads it from the repository, not just from disk
2. You are using Copilot in an IDE that supports instruction files (VS Code with the
   GitHub Copilot extension v1.100+, Visual Studio 2022 17.10+)

---

## Symlinked Modules

### Symlinks are broken after cloning on another machine

Symlinks committed to git point to absolute paths (e.g. `/home/you/.ai-dev-lifecycle/...`).
If that path does not exist on the new machine, the symlinks will be broken.

**Fix:** run `apply.sh` on the new machine after cloning the lifecycle repo. The script
will replace broken symlinks with new ones pointing to the correct local path.

```bash
git clone https://github.com/goeke-m/ai-dev-lifecycle.git ~/.ai-dev-lifecycle
cd /path/to/project
~/.ai-dev-lifecycle/scripts/apply.sh
```

---

### Config files from the module are out of date

If the lifecycle repo has been updated but the symlinks in your project still point to
the old content — this should not happen with symlinks (they always reflect the current
file). If you are seeing stale content:

```bash
# Verify the symlink target is correct
readlink .editorconfig
# Should point to ~/.ai-dev-lifecycle/modules/coding-standards/csharp/.editorconfig

# Pull the latest lifecycle content
~/.ai-dev-lifecycle/scripts/update.sh
```

---

## Auto-Update (Cron / Task Scheduler)

### Cron job not installed

Verify:

```bash
crontab -l | grep ai-dev-lifecycle
```

If missing, install manually:

```bash
(crontab -l 2>/dev/null; echo "# ai-dev-lifecycle-update"; echo "0 8 * * * LIFECYCLE_DIR=$HOME/.ai-dev-lifecycle bash $HOME/.ai-dev-lifecycle/scripts/update.sh >> $HOME/.ai-dev-lifecycle-update.log 2>&1") | crontab -
```

Or re-run `apply.sh` — it installs the cron job automatically.

---

### Update script fails with `git pull` conflicts

If someone has made local changes to the lifecycle repo that conflict with upstream:

```bash
cd ~/.ai-dev-lifecycle
git status          # see what is modified
git stash           # stash local changes
git pull --ff-only  # pull upstream
git stash pop       # re-apply local changes (if needed)
```

If you have intentional local modifications to the lifecycle repo, open a PR to merge
them upstream rather than keeping them as local overrides — local overrides will be
overwritten by future updates.

---

### Registered project no longer exists

If a project directory was moved or deleted, `update.sh` will log a warning and skip it.
To clean up the registry:

```bash
# View registered projects
cat ~/.ai-dev-lifecycle/.registered-projects

# Remove a stale entry
grep -v "/old/path/to/project" ~/.ai-dev-lifecycle/.registered-projects > /tmp/projects.tmp
mv /tmp/projects.tmp ~/.ai-dev-lifecycle/.registered-projects
```

---

### Windows Task Scheduler task not running

Verify the task exists:

```powershell
Get-ScheduledTask -TaskName "ai-dev-lifecycle-update"
```

If missing, re-run `apply.ps1` as Administrator to reinstall it.

To run it immediately for testing:

```powershell
Start-ScheduledTask -TaskName "ai-dev-lifecycle-update"
```

Check the log:

```powershell
Get-Content "$env:USERPROFILE\.ai-dev-lifecycle-update.log" -Tail 50
```

---

## CI/CD and Reusable Workflows

### `uses: goeke-m/ai-dev-lifecycle/...` — workflow not found

Ensure:

1. The workflow file exists in `.github/workflows/` in the `ai-dev-lifecycle` repo
2. The repo is **public**, or the consuming repo is in the same GitHub organisation
3. The workflow file has `on: workflow_call:` at the top

```bash
# Verify the file exists
gh api repos/goeke-m/ai-dev-lifecycle/contents/.github/workflows
```

---

### Reusable workflow: `Input required and not supplied`

A required input to the reusable workflow was not passed. Check the workflow's `inputs:`
definition and ensure all required inputs are provided in the consuming workflow's `with:`
block.

---

### `setup-lifecycle` composite action: symlinks not resolving in CI

In CI, the runner's home directory differs from a developer machine. The composite action
checks out the lifecycle repo to `~/.ai-dev-lifecycle` on the runner. If symlinks committed
to the project repo point to a developer's home path, they will not resolve.

**Do not commit symlinks to the project repo.** Committed files should be the generated
agent files (`CLAUDE.md`, etc.) and the `.devlifecycle.json` config — not symlinks to
local module files.

---

### Coverage report not uploading in `test-csharp.yml`

Ensure `coverlet` is referenced in the test project:

```bash
dotnet list package | grep coverlet
```

If missing:

```bash
dotnet add tests/MyApp.Tests package coverlet.collector
```

And that the `runsettings` file is present and referenced in the workflow input.

---

## Tool-Specific Issues

### `dotnet format` reports violations but you cannot see which file

```bash
dotnet format --verify-no-changes --verbosity diagnostic
```

This prints the full list of files and rules that would be changed.

---

### ESLint config not found in the project

The `eslint.config.js` file is symlinked from the lifecycle module. If ESLint cannot
find it, the symlink may be broken:

```bash
ls -la eslint.config.js
# If it shows a broken symlink (red in most terminals):
~/.ai-dev-lifecycle/scripts/apply.sh
```

---

### `vitest` cannot find the base config

If you are using `mergeConfig` to extend the base Vitest config and it fails to resolve:

```typescript
// vitest.config.ts in your project
import { mergeConfig } from 'vitest/config'
import baseConfig from './vitest.config.base'  // symlinked from lifecycle

export default mergeConfig(baseConfig, {
  test: {
    // project-specific overrides
  }
})
```

Ensure the symlink is in place:

```bash
ls -la vitest.config.base.ts
```

---

## General Debugging

### Run apply.sh with verbose output

```bash
bash -x ~/.ai-dev-lifecycle/scripts/apply.sh 2>&1 | less
```

`-x` prints every command as it executes, making it easy to see exactly where a failure occurs.

### Check the update log

```bash
# Linux / macOS
tail -100 ~/.ai-dev-lifecycle-update.log

# Windows
Get-Content "$env:USERPROFILE\.ai-dev-lifecycle-update.log" -Tail 100
```

### Verify the lifecycle repo is clean and up to date

```bash
cd ~/.ai-dev-lifecycle
git status          # should be clean
git log --oneline -5  # check you are on the latest commits
git pull --ff-only
```

### Re-run apply from scratch

If you are unsure of the state of your project's lifecycle setup, re-running `apply.sh`
is always safe — it is idempotent:

```bash
~/.ai-dev-lifecycle/scripts/apply.sh /path/to/project
```

It will skip already-correct symlinks, back up any conflicting files, and reinstall hooks
and agent files cleanly.
