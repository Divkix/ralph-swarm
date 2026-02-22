#!/bin/bash
set -euo pipefail

# Ralph Swarm SessionStart Hook — loads persisted swarm state into the session
# so the agent picks up where it left off.

STATE_FILE=".ralph-swarm-state.json"

# ── Helper: check if jq is available ──────────────────────────────────────────
has_jq() { command -v jq &>/dev/null; }

# ── Helper: escape a string for safe embedding in JSON ────────────────────────
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ── Helper: read a field from the state file ──────────────────────────────────
read_state() {
  local field="$1"
  if has_jq; then
    jq -r "if $field == null then empty else $field end" "$STATE_FILE" 2>/dev/null || echo ""
  else
    local key
    key=$(echo "$field" | sed 's/.*\.//')
    grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*" "$STATE_FILE" 2>/dev/null \
      | head -1 \
      | sed 's/.*:[[:space:]]*//' \
      | tr -d '"' \
      || echo ""
  fi
}

# ── No state file — exit silently ─────────────────────────────────────────────
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# ── Read state fields ─────────────────────────────────────────────────────────
name=$(read_state '.name')
goal=$(read_state '.goal')
phase=$(read_state '.phase')
swarm_mode=$(read_state '.execution.swarm')
iteration=$(read_state '.execution.iteration')
max_iterations=$(read_state '.execution.maxIterations')

# Determine mode label.
if [[ "$swarm_mode" == "true" ]]; then
  mode_label="swarm (parallel)"
else
  mode_label="sequential"
fi

# ── Build progress summary ────────────────────────────────────────────────────
progress=""
# "executing" is a legacy alias for "execution" — kept for backwards compatibility
if [[ "$phase" == "execution" || "$phase" == "executing" ]]; then
  if has_jq; then
    total_tasks=$(jq -r '.execution.totalTasks // (.execution.tasks | length) // 0' "$STATE_FILE" 2>/dev/null || echo "0")
    completed_tasks=$(jq -r 'if .execution.completedTasks | type == "number" then .execution.completedTasks elif .execution.completedTasks | type == "array" then (.execution.completedTasks | length) else ([.execution.tasks[]? | select(.status == "completed" or .status == "done")] | length) end' "$STATE_FILE" 2>/dev/null || echo "0")
  else
    total_tasks="?"
    completed_tasks="?"
  fi
  progress="Tasks: ${completed_tasks}/${total_tasks} completed, iteration ${iteration:-0}/${max_iterations:-30}"
elif [[ "$phase" == "planning" ]]; then
  paused_after=$(read_state '.pausedAfter')
  # "null" string check needed: grep/sed fallback returns literal "null" when jq is absent
  if [[ -n "$paused_after" && "$paused_after" != "null" ]]; then
    # Compute the next command based on which phase we paused after
    case "$paused_after" in
      research)      next_cmd="/ralph-swarm:requirements" ;;
      requirements)  next_cmd="/ralph-swarm:design" ;;
      design)        next_cmd="/ralph-swarm:tasks" ;;
      tasks)         next_cmd="/ralph-swarm:go" ;;
      *)             next_cmd="/ralph-swarm:status" ;;
    esac
    progress="Phase: planning | Paused after: ${paused_after}. Next: ${next_cmd}"
  else
    progress="Phase: planning (in progress)"
    spec_path=$(read_state '.specPath')
    # "null" string check needed: grep/sed fallback returns literal "null" when jq is absent
    if [[ -n "$spec_path" && "$spec_path" != "null" && -d "$spec_path" ]]; then
      partial_count=$(find "$spec_path" -maxdepth 1 \( -name 'research-*.md' -o -name 'requirements-*.md' -o -name 'design-*.md' \) 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$partial_count" -gt 0 ]]; then
        progress="${progress} | ${partial_count} partial file(s) from interrupted parallel planning"
      fi
    fi
  fi
else
  progress="Phase: ${phase}"
fi

# ── Check for orphaned worktrees (swarm mode execution only) ──────────────────
if [[ "$phase" == "execution" ]] && [[ "$swarm_mode" == "true" ]]; then
  orphan_count=$(git worktree list 2>/dev/null | grep -c 'ralph-' || echo "0")
  if [[ "$orphan_count" -gt 0 ]]; then
    orphan_warning=" | WARNING: ${orphan_count} orphaned worktree(s). Run /ralph-swarm:cancel to clean up."
  else
    orphan_warning=""
  fi
else
  orphan_warning=""
fi

# ── Build system message ──────────────────────────────────────────────────────
summary="Ralph Swarm active: ${name:-unnamed}"
summary+=" | Goal: ${goal:-none}"
summary+=" | ${progress}"
summary+=" | Mode: ${mode_label}"
summary+=" | Commands: /ralph-swarm:status, /ralph-swarm:cancel"
summary+="${orphan_warning}"

# Emit system message JSON.
if has_jq; then
  jq -n --arg msg "$summary" '{"systemMessage":$msg}'
else
  cat <<EOF
{"systemMessage":"$(json_escape "$summary")"}
EOF
fi
