#!/bin/bash
set -euo pipefail

# Ralph Swarm SessionStart Hook — loads persisted swarm state into the session
# so the agent picks up where it left off.

STATE_FILE=".ralph-swarm-state.json"

# ── Helper: check if jq is available ──────────────────────────────────────────
has_jq() { command -v jq &>/dev/null; }

# ── Helper: read a field from the state file ──────────────────────────────────
read_state() {
  local field="$1"
  if has_jq; then
    jq -r "$field // empty" "$STATE_FILE" 2>/dev/null || echo ""
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
else
  progress="Phase: ${phase}"
fi

# ── Build system message ──────────────────────────────────────────────────────
summary="Ralph Swarm active: ${name:-unnamed}"
summary+=" | Goal: ${goal:-none}"
summary+=" | ${progress}"
summary+=" | Mode: ${mode_label}"
summary+=" | Commands: /ralph-swarm:status, /ralph-swarm:cancel"

# Emit system message JSON.
if has_jq; then
  jq -n --arg msg "$summary" '{"systemMessage":$msg}'
else
  cat <<EOF
{"systemMessage":"${summary}"}
EOF
fi
