#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# apply.sh — Apply ai-dev-lifecycle configuration to a project
#
# Usage: apply.sh [project-dir]
#
# Environment variables:
#   LIFECYCLE_DIR  — Path to the ai-dev-lifecycle repo (default: ~/.ai-dev-lifecycle)
# -----------------------------------------------------------------------------

LIFECYCLE_DIR="${LIFECYCLE_DIR:-$HOME/.ai-dev-lifecycle}"
PROJECT_DIR="${1:-$(pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
CONFIG_FILE="$PROJECT_DIR/.devlifecycle.json"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}==> $*${RESET}"; }

# ── Preflight checks ──────────────────────────────────────────────────────────
header "ai-dev-lifecycle apply"
info "LIFECYCLE_DIR : $LIFECYCLE_DIR"
info "PROJECT_DIR   : $PROJECT_DIR"

if [[ ! -d "$LIFECYCLE_DIR" ]]; then
  error "LIFECYCLE_DIR does not exist: $LIFECYCLE_DIR"
  error "Clone the ai-dev-lifecycle repo first:"
  error "  git clone https://github.com/goeke-m/ai-dev-lifecycle.git $LIFECYCLE_DIR"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  error "'jq' is required but not installed."
  error "Install it via your package manager:"
  error "  macOS:  brew install jq"
  error "  Debian: apt-get install jq"
  error "  Fedora: dnf install jq"
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  error "Config file not found: $CONFIG_FILE"
  error "Copy the example config to get started:"
  error "  cp $LIFECYCLE_DIR/.devlifecycle.example.json $PROJECT_DIR/.devlifecycle.json"
  exit 1
fi

# Validate JSON
if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  error "Config file is not valid JSON: $CONFIG_FILE"
  exit 1
fi

# ── Helper: create symlink ────────────────────────────────────────────────────
# symlink_file <source> <dest>
symlink_file() {
  local src="$1"
  local dst="$2"
  local dst_dir
  dst_dir="$(dirname "$dst")"

  if [[ ! -f "$src" ]]; then
    warn "Source file does not exist, skipping: $src"
    return 0
  fi

  mkdir -p "$dst_dir"

  if [[ -L "$dst" ]]; then
    local existing_target
    existing_target="$(readlink "$dst")"
    if [[ "$existing_target" == "$src" ]]; then
      info "Symlink already up-to-date: $dst"
      return 0
    else
      warn "Replacing existing symlink: $dst -> $existing_target"
      rm "$dst"
    fi
  elif [[ -e "$dst" ]]; then
    warn "File exists and is not a symlink — backing up: ${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi

  ln -s "$src" "$dst"
  success "Linked: $dst -> $src"
}

# symlink_dir_contents <source-dir> <dest-dir>
symlink_dir_contents() {
  local src_dir="$1"
  local dst_dir="$2"

  if [[ ! -d "$src_dir" ]]; then
    warn "Source directory does not exist, skipping: $src_dir"
    return 0
  fi

  mkdir -p "$dst_dir"

  while IFS= read -r -d '' src_file; do
    local rel_path="${src_file#$src_dir/}"
    symlink_file "$src_file" "$dst_dir/$rel_path"
  done < <(find "$src_dir" -maxdepth 1 -type f -print0)
}

# ── Read config ───────────────────────────────────────────────────────────────
LANGUAGE="$(jq -r '.project.language // "csharp"' "$CONFIG_FILE")"
PROJECT_NAME="$(jq -r '.project.name // "unknown"' "$CONFIG_FILE")"

info "Project       : $PROJECT_NAME"
info "Language      : $LANGUAGE"

# ── Modules ───────────────────────────────────────────────────────────────────
header "Applying modules"

MODULES=(coding-standards scaffolding pr-workflows testing documentation)

for module in "${MODULES[@]}"; do
  enabled="$(jq -r ".modules[\"$module\"].enabled // false" "$CONFIG_FILE")"
  if [[ "$enabled" != "true" ]]; then
    info "Module '$module' is disabled — skipping"
    continue
  fi

  info "Applying module: $module"
  module_src="$LIFECYCLE_DIR/modules/$module/$LANGUAGE"

  case "$module" in
    pr-workflows)
      # Special case: symlink PR template into .github/
      github_src="$LIFECYCLE_DIR/modules/pr-workflows/github"
      pr_src="$github_src/PULL_REQUEST_TEMPLATE.md"
      pr_dst="$PROJECT_DIR/.github/PULL_REQUEST_TEMPLATE.md"
      symlink_file "$pr_src" "$pr_dst"
      ;;

    documentation)
      # Special case: symlink into docs/templates/
      doc_src="$LIFECYCLE_DIR/modules/documentation/templates"
      doc_dst="$PROJECT_DIR/docs/templates"
      mkdir -p "$doc_dst"
      symlink_dir_contents "$doc_src" "$doc_dst"
      ;;

    *)
      symlink_dir_contents "$module_src" "$PROJECT_DIR"
      ;;
  esac

  success "Module '$module' applied"
done

# ── Git hooks ─────────────────────────────────────────────────────────────────
header "Installing git hooks"

GIT_DIR="$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null || true)"
if [[ -z "$GIT_DIR" ]]; then
  warn "Project directory is not a git repo — skipping hook installation"
else
  HOOKS_DIR="$GIT_DIR/hooks"
  mkdir -p "$HOOKS_DIR"

  HOOK_NAMES=(pre-commit commit-msg)
  for hook in "${HOOK_NAMES[@]}"; do
    enabled="$(jq -r ".hooks[\"$hook\"].enabled // false" "$CONFIG_FILE")"
    if [[ "$enabled" != "true" ]]; then
      info "Hook '$hook' is disabled — skipping"
      continue
    fi

    hook_src="$LIFECYCLE_DIR/hooks/$hook"
    hook_dst="$HOOKS_DIR/$hook"

    if [[ ! -f "$hook_src" ]]; then
      warn "Hook source not found: $hook_src"
      continue
    fi

    chmod +x "$hook_src"
    symlink_file "$hook_src" "$hook_dst"
    success "Hook '$hook' installed"
  done
fi

# ── Agent generation ──────────────────────────────────────────────────────────
header "Generating agent instruction files"

AGENTS=(claude copilot cursor)
for agent in "${AGENTS[@]}"; do
  enabled="$(jq -r ".agents[\"$agent\"].enabled // false" "$CONFIG_FILE")"
  if [[ "$enabled" != "true" ]]; then
    info "Agent '$agent' is disabled — skipping"
    continue
  fi

  info "Generating agent: $agent"
  generate_script="$LIFECYCLE_DIR/scripts/generate-agent.sh"

  if [[ ! -f "$generate_script" ]]; then
    warn "generate-agent.sh not found: $generate_script"
    continue
  fi

  chmod +x "$generate_script"
  bash "$generate_script" "$agent" "$PROJECT_DIR" "$CONFIG_FILE"
  success "Agent '$agent' generated"
done

# ── Register project ──────────────────────────────────────────────────────────
header "Registering project"

REGISTRY="$LIFECYCLE_DIR/.registered-projects"
touch "$REGISTRY"

if grep -qxF "$PROJECT_DIR" "$REGISTRY"; then
  info "Project already registered: $PROJECT_DIR"
else
  echo "$PROJECT_DIR" >> "$REGISTRY"
  success "Registered project: $PROJECT_DIR"
fi

# ── Install cron job ──────────────────────────────────────────────────────────
header "Installing update cron job"

UPDATE_SCRIPT="$LIFECYCLE_DIR/scripts/update.sh"
CRON_CMD="0 8 * * * LIFECYCLE_DIR=$LIFECYCLE_DIR bash $UPDATE_SCRIPT >> $LIFECYCLE_DIR/update.log 2>&1"
CRON_MARKER="ai-dev-lifecycle-update"

# Check if cron entry already exists
if crontab -l 2>/dev/null | grep -q "$CRON_MARKER"; then
  info "Cron job already installed"
else
  # Add cron entry with a comment marker
  (
    crontab -l 2>/dev/null || true
    echo "# $CRON_MARKER"
    echo "$CRON_CMD"
  ) | crontab -
  success "Cron job installed: daily at 8am"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}ai-dev-lifecycle applied successfully to: $PROJECT_DIR${RESET}"
echo ""
