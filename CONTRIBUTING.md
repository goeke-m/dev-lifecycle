# Contributing to dev-lifecycle

This repo is a shared development lifecycle toolkit. Contributions keep it useful and
current. This document covers how to add or update rules, modules, hooks, and workflows.

---

## What Lives Here

| Directory | What it contains | Who changes it |
|---|---|---|
| `agents/rules/` | Markdown rule files assembled into agent instructions | Anyone |
| `agents/*/template.md` | Per-agent instruction template (structure, not content) | Rarely |
| `modules/` | Config files symlinked into consuming projects | Anyone |
| `hooks/` | Git hooks (pre-commit, commit-msg) | Anyone |
| `.github/workflows/` | Reusable GitHub Actions workflows | Anyone |
| `scripts/` | apply, update, generate-agent scripts | Carefully |
| `docs/` | Onboarding and reference documentation | Anyone |

---

## Adding or Updating a Rule

Rules live in `agents/rules/` as standalone Markdown files. Each file covers one topic
and can be included or excluded per project in `.devlifecycle.json`.

### 1. Create or edit the rule file

```bash
# New rule
touch agents/rules/my-topic.md

# Existing rule
code agents/rules/csharp-conventions.md
```

**Rule file structure:**

```markdown
# Topic Name

One-sentence summary of what this rule covers and why it matters.

---

## Section Heading

Explanation of the guideline.

### Sub-rule or pattern name

More detail, with code examples where helpful.

\`\`\`csharp
// Good
// Bad
\`\`\`
```

**Conventions:**
- Lead with the rule, then the rationale — not the other way around
- Include a `// Good` and `// Bad` example for every non-obvious guideline
- Use `---` between top-level sections
- End with a checklist if the rule is complex enough to warrant one
- Cross-reference other rule files rather than duplicating content

### 2. Add to the example config

If the rule is new, add it to the relevant agent rules lists in `.devlifecycle.example.json`:

```json
"agents": {
  "claude": {
    "rules": ["git-commits", "...", "my-topic"]
  }
}
```

### 3. Test locally

Generate the agent file for a test project to verify the rule renders correctly:

```bash
bash scripts/generate-agent.sh claude /tmp/test-project /tmp/test-project/.devlifecycle.json
cat /tmp/test-project/CLAUDE.md
```

---

## Adding a Module

Modules are files that get symlinked into consuming projects. A module should contain
config or tooling files that belong at the project root (or a known subdirectory).

### 1. Create the module directory and files

```
modules/
  my-module/
    csharp/
      some-config-file.json
    typescript/
      some-config-file.json
```

If the module is language-agnostic, place files directly in `modules/my-module/`.

### 2. Handle the module in `apply.sh` and `apply.ps1`

Open `scripts/apply.sh` and add a `case` entry if the module needs special placement
(e.g. into a subdirectory rather than the project root). If it follows the default
pattern (files go to project root), no change is needed.

### 3. Document in the README

Add a row to the modules table in `README.md`.

---

## Updating a Reusable Workflow

Reusable workflows in `.github/workflows/` are referenced by consuming projects as
`uses: goeke-m/dev-lifecycle/.github/workflows/name.yml@main`. Changes take effect
immediately on the next run in consuming repos — there is no versioning step.

**Before changing a reusable workflow:**
- Check whether the change is breaking (removes or renames an input, changes required
  secrets, etc.). Breaking changes require communicating to all consuming projects.
- For non-breaking additions (new optional input, new step), just merge.

---

## Commit and PR Standards

All contributions follow the same standards enforced on consuming projects.

**Commit messages:** Conventional Commits format
```
feat(rules): add observability conventions
fix(hooks): handle staged files with spaces in path
docs: update onboarding troubleshooting section
refactor(scripts): extract symlink helper function
```

**PR description:** Use the PR template. Include:
- What changed and why
- Whether consuming projects need to take any action (e.g. re-run `apply.sh`)
- For rule changes: a brief note on what guidance was added or updated

**Branch naming:** `feat/`, `fix/`, `docs/`, `refactor/` prefix.

---

## Testing Changes Locally

Before opening a PR, test your changes against a real project:

```bash
# Pull your branch
cd ~/.dev-lifecycle
git fetch && git checkout your-branch

# Apply to a test project
bash scripts/apply.sh /path/to/test-project

# Verify the generated agent file looks right
cat /path/to/test-project/CLAUDE.md

# Check that hooks work
cd /path/to/test-project
git commit --allow-empty -m "test: verify hooks"
```

Switch back to `main` when done:
```bash
cd ~/.dev-lifecycle && git checkout main
```

---

## What Not to Put Here

- **Project-specific config** — `.devlifecycle.json` in each project handles that
- **Secrets or credentials** — never, under any circumstances
- **Opinions without rationale** — every rule should explain why, not just what
- **Duplicate content** — cross-reference existing rules rather than copy-pasting
- **Generated files** — the outputs of `generate-agent.sh` live in consuming projects, not here
