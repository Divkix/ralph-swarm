#!/bin/bash
set -euo pipefail

# Ralph Swarm Stop Hook — keeps the lead agent alive during execution.
# Reads hook input from stdin, inspects .ralph-swarm-state.json, and decides
# whether to block the exit (re-prompting the agent) or allow it.

STATE_FILE=".ralph-swarm-state.json"
HOOK_INPUT=$(cat)

# ── Helper: check if jq is available ──────────────────────────────────────────
has_jq() { command -v jq &>/dev/null; }

# ── Helper: read a field from the state file ──────────────────────────────────
# Falls back to grep/sed when jq is missing.
read_state() {
  local field="$1"
  if has_jq; then
    jq -r "$field" "$STATE_FILE" 2>/dev/null || echo ""
  else
    # Crude fallback — works for simple top-level and one-level nested keys.
    # Translates ".execution.iteration" to a grep for "iteration".
    local key
    key=$(echo "$field" | sed 's/.*\.//')
    grep -o "\"${key}\"[[:space:]]*:[[:space:]]*[^,}]*" "$STATE_FILE" 2>/dev/null \
      | head -1 \
      | sed 's/.*:[[:space:]]*//' \
      | tr -d '"' \
      || echo ""
  fi
}

# ── Helper: update the iteration counter in the state file ────────────────────
increment_iteration() {
  local current="$1"
  local next=$((current + 1))
  if has_jq; then
    local tmp
    tmp=$(mktemp)
    jq ".execution.iteration = ${next}" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  else
    sed -i.bak "s/\"iteration\"[[:space:]]*:[[:space:]]*${current}/\"iteration\": ${next}/" "$STATE_FILE"
    rm -f "${STATE_FILE}.bak"
  fi
}

# ── Helper: clean up the state file ──────────────────────────────────────────
cleanup() {
  rm -f "$STATE_FILE"
}

# ── 1. No state file — nothing to do, allow exit ─────────────────────────────
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# ── 2. Read phase ─────────────────────────────────────────────────────────────
phase=$(read_state '.phase')

# If the user is reviewing the plan, let the session exit normally.
if [[ "$phase" == "planning-review" ]]; then
  exit 0
fi

# ── 3. Read iteration bounds ──────────────────────────────────────────────────
iteration=$(read_state '.execution.iteration')
max_iterations=$(read_state '.execution.maxIterations')

# Default to 0 / 10 when values are missing or empty.
iteration=${iteration:-0}
max_iterations=${max_iterations:-30}

# If we have exhausted iterations, clean up and allow exit.
if [[ "$iteration" -ge "$max_iterations" ]]; then
  cleanup
  exit 0
fi

# ── 4. Check for the completion promise ───────────────────────────────────────
if echo "$HOOK_INPUT" | grep -q '<promise>SWARM COMPLETE</promise>'; then
  cleanup
  exit 0
fi

# ── 5. Still executing — block exit and re-prompt ─────────────────────────────
increment_iteration "$iteration"
new_iteration=$((iteration + 1))

swarm_mode=$(read_state '.execution.swarm')
swarm_mode=${swarm_mode:-false}

if [[ "$swarm_mode" == "true" ]]; then
  prompt="You are the swarm lead. Check the TaskList for pending and in-progress tasks. "
  prompt+="Assign any unassigned tasks to idle teammates. Verify completed work by reviewing "
  prompt+="task outputs. If ALL tasks are done and verified, output exactly "
  prompt+="<promise>SWARM COMPLETE</promise> to finish. Otherwise, continue coordinating."
else
  prompt="You are in sequential execution mode. Read ${STATE_FILE} for the current task index "
  prompt+="and full task list. Execute the next incomplete task using the swarm-executor agent. "
  prompt+="After each task completes, update the state file and move to the next one. "
  prompt+="When ALL tasks are finished, output exactly <promise>SWARM COMPLETE</promise> to finish."
fi

# Emit the blocking decision as JSON on stdout.
if has_jq; then
  jq -n \
    --arg decision "block" \
    --arg reason "$prompt" \
    --arg sysMsg "Swarm iteration ${new_iteration}" \
    '{"decision":$decision,"reason":$reason,"systemMessage":$sysMsg}'
else
  # Manual JSON construction — values are safe (no user-controlled content).
  cat <<EOF
{"decision":"block","reason":"${prompt}","systemMessage":"Swarm iteration ${new_iteration}"}
EOF
fi
