#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# update.sh — Pull latest lifecycle changes and re-apply to all registered projects
#
# Usage: update.sh
#
# Environment variables:
#   LIFECYCLE_DIR  — Path to the ai-dev-lifecycle repo (default: ~/.ai-dev-lifecycle)
# -----------------------------------------------------------------------------

LIFECYCLE_DIR="${LIFECYCLE_DIR:-$HOME/.ai-dev-lifecycle}"
REGISTRY="$LIFECYCLE_DIR/.registered-projects"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

log()     { echo "$LOG_PREFIX [info]  $*"; }
log_ok()  { echo "$LOG_PREFIX [ok]    $*"; }
log_warn(){ echo "$LOG_PREFIX [warn]  $*"; }
log_err() { echo "$LOG_PREFIX [error] $*" >&2; }

# ── Preflight ─────────────────────────────────────────────────────────────────
log "ai-dev-lifecycle update starting"
log "LIFECYCLE_DIR: $LIFECYCLE_DIR"

if [[ ! -d "$LIFECYCLE_DIR" ]]; then
  log_err "LIFECYCLE_DIR does not exist: $LIFECYCLE_DIR"
  exit 1
fi

if [[ ! -d "$LIFECYCLE_DIR/.git" ]]; then
  log_err "LIFECYCLE_DIR is not a git repository: $LIFECYCLE_DIR"
  exit 1
fi

# ── Pull latest changes ───────────────────────────────────────────────────────
log "Pulling latest changes from remote..."

BEFORE_SHA="$(git -C "$LIFECYCLE_DIR" rev-parse HEAD)"

if git -C "$LIFECYCLE_DIR" pull --ff-only 2>&1 | while IFS= read -r line; do
    log "$line"
  done; then
  AFTER_SHA="$(git -C "$LIFECYCLE_DIR" rev-parse HEAD)"
  if [[ "$BEFORE_SHA" == "$AFTER_SHA" ]]; then
    log "Already up-to-date ($(git -C "$LIFECYCLE_DIR" rev-parse --short HEAD))"
  else
    log_ok "Updated: $BEFORE_SHA -> $AFTER_SHA"
  fi
else
  log_err "git pull --ff-only failed. The local repo may have diverged."
  log_err "Resolve manually in: $LIFECYCLE_DIR"
  exit 1
fi

# ── Re-apply to registered projects ──────────────────────────────────────────
if [[ ! -f "$REGISTRY" ]]; then
  log_warn "No registered projects found at: $REGISTRY"
  log "Nothing to re-apply."
  exit 0
fi

APPLY_SCRIPT="$LIFECYCLE_DIR/scripts/apply.sh"
if [[ ! -f "$APPLY_SCRIPT" ]]; then
  log_err "apply.sh not found: $APPLY_SCRIPT"
  exit 1
fi
chmod +x "$APPLY_SCRIPT"

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

log "Re-applying lifecycle to registered projects..."
log "Registry: $REGISTRY"

while IFS= read -r project_dir || [[ -n "$project_dir" ]]; do
  # Skip blank lines and comments
  [[ -z "$project_dir" || "$project_dir" == \#* ]] && continue

  if [[ ! -d "$project_dir" ]]; then
    log_warn "Project directory no longer exists — skipping: $project_dir"
    (( SKIP_COUNT++ )) || true
    continue
  fi

  if [[ ! -f "$project_dir/.devlifecycle.json" ]]; then
    log_warn "No .devlifecycle.json found in: $project_dir — skipping"
    (( SKIP_COUNT++ )) || true
    continue
  fi

  log "Re-applying to: $project_dir"
  if LIFECYCLE_DIR="$LIFECYCLE_DIR" bash "$APPLY_SCRIPT" "$project_dir" 2>&1 | \
      while IFS= read -r line; do log "  $line"; done; then
    log_ok "Successfully re-applied: $project_dir"
    (( SUCCESS_COUNT++ )) || true
  else
    log_err "Failed to re-apply: $project_dir"
    (( FAIL_COUNT++ )) || true
  fi

done < "$REGISTRY"

# ── Summary ───────────────────────────────────────────────────────────────────
log "---"
log "Update complete."
log "  Success : $SUCCESS_COUNT"
log "  Skipped : $SKIP_COUNT"
log "  Failed  : $FAIL_COUNT"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
