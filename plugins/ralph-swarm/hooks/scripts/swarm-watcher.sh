#!/bin/bash
set -euo pipefail

# Ralph Swarm Stop Hook — keeps the lead agent alive during execution.
# Reads hook input from stdin, inspects .ralph-swarm-state.json, and decides
# whether to block the exit (re-prompting the agent) or allow it.
#
# Completion is verified by checking task counts in the state file, not by
# trusting the agent's text output. The promise tag is treated as a REQUEST
# to exit — the hook independently validates that all tasks are accounted for.

STATE_FILE=".ralph-swarm-state.json"
HOOK_INPUT=$(cat)

# ── Helper: check if jq is available ──────────────────────────────────────────
has_jq() { command -v jq &>/dev/null; }

# ── Helper: portable file lock (mkdir-based) ──────────────────────────────────
STATE_LOCKDIR="${STATE_FILE}.lock"
_LOCK_HELD=false

acquire_lock() {
  local attempts=0
  while ! mkdir "$STATE_LOCKDIR" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ "$attempts" -ge 50 ]]; then
      rm -rf "$STATE_LOCKDIR"
      mkdir "$STATE_LOCKDIR" 2>/dev/null || true
      break
    fi
    sleep 0.1
  done
  _LOCK_HELD=true
}

release_lock() {
  if [[ "$_LOCK_HELD" == "true" ]]; then
    rm -rf "$STATE_LOCKDIR"
    _LOCK_HELD=false
  fi
}

# Ensure lock cleanup on exit
trap release_lock EXIT

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

# ── Helper: count completed + failed tasks from state ─────────────────────────
# Returns "completed failed total" as space-separated integers.
read_task_counts() {
  if has_jq; then
    local completed failed total
    completed=$(jq -r '(.execution.completedTasks | if type == "array" then length else 0 end)' "$STATE_FILE" 2>/dev/null || echo "0")
    failed=$(jq -r '(.execution.failedTasks | if type == "array" then length else 0 end)' "$STATE_FILE" 2>/dev/null || echo "0")
    total=$(jq -r '(.execution.totalTasks // 0)' "$STATE_FILE" 2>/dev/null || echo "0")
    echo "${completed} ${failed} ${total}"
  else
    echo "0 0 0"
  fi
}

# ── Helper: update the iteration counter in the state file ────────────────────
increment_iteration() {
  local current="$1"
  local next=$((current + 1))
  acquire_lock
  if has_jq; then
    local tmp
    tmp=$(mktemp)
    jq ".execution.iteration = ${next}" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
  else
    sed -i.bak "s/\"iteration\"[[:space:]]*:[[:space:]]*${current}/\"iteration\": ${next}/" "$STATE_FILE"
    rm -f "${STATE_FILE}.bak"
  fi
  release_lock
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

# If the agent already set phase to "complete", verify task counts before trusting it.
if [[ "$phase" == "complete" ]]; then
  read -r completed failed total <<< "$(read_task_counts)"
  accounted=$((completed + failed))
  if [[ "$total" -gt 0 && "$accounted" -ge "$total" ]]; then
    cleanup
    exit 0
  fi
  # Phase says complete but the numbers don't add up — fall through to block.
fi

# ── 3. Read iteration bounds ──────────────────────────────────────────────────
iteration=$(read_state '.execution.iteration')
max_iterations=$(read_state '.execution.maxIterations')

# Default to 0 / 30 when values are missing or empty.
iteration=${iteration:-0}
max_iterations=${max_iterations:-30}

# If we have exhausted iterations, clean up and allow exit.
if [[ "$iteration" -ge "$max_iterations" ]]; then
  cleanup
  exit 0
fi

# ── 4. Check for the completion promise (verified against task counts) ────────
# The promise is treated as a request to exit. We independently verify that
# all tasks are accounted for (completed + failed >= total) before allowing it.
if echo "$HOOK_INPUT" | grep -qiE '<promise>\s*SWARM\s+COMPLETE\s*</promise>'; then
  read -r completed failed total <<< "$(read_task_counts)"
  accounted=$((completed + failed))
  if [[ "$total" -eq 0 || "$accounted" -ge "$total" ]]; then
    cleanup
    exit 0
  fi
  # Promise claimed but tasks remain — block exit with a correction prompt.
  increment_iteration "$iteration"
  new_iteration=$((iteration + 1))
  remaining=$((total - accounted))
  prompt="PREMATURE COMPLETION REJECTED - Follow these steps in order:"
  prompt+=$'\n'"1. Task counts don't add up: ${completed} completed + ${failed} failed = ${accounted}, but totalTasks = ${total}. ${remaining} tasks unaccounted."
  prompt+=$'\n'"2. Read .ralph-swarm-state.json to identify remaining tasks with status 'pending' or 'in-progress'."
  prompt+=$'\n'"3. Execute each remaining task."
  prompt+=$'\n'"4. Update completedTasks/failedTasks arrays in the state file after each task."
  prompt+=$'\n'"5. When ALL tasks are accounted for: set phase to \"complete\", then output <promise>SWARM COMPLETE</promise>."

  if has_jq; then
    jq -n \
      --arg decision "block" \
      --arg reason "$prompt" \
      --arg sysMsg "Swarm iteration ${new_iteration} — premature completion rejected" \
      '{"decision":$decision,"reason":$reason,"systemMessage":$sysMsg}'
  else
    cat <<EOF
{"decision":"block","reason":"${prompt}","systemMessage":"Swarm iteration ${new_iteration} — premature completion rejected"}
EOF
  fi
  exit 0
fi

# ── 5. Still executing — block exit and re-prompt ─────────────────────────────
increment_iteration "$iteration"
new_iteration=$((iteration + 1))

swarm_mode=$(read_state '.execution.swarm')
swarm_mode=${swarm_mode:-false}

# ── 5a. TeamCreate enforcement — block exit if swarm but no team created ─────
if [[ "$swarm_mode" == "true" ]]; then
  team_created=$(read_state '.execution.teamCreated')
  team_created=${team_created:-false}
  if [[ "$team_created" != "true" ]]; then
    # TeamCreate was never called — block exit and force the AI to call it
    tc_prompt="TEAMCREATE REQUIRED - Follow these steps in order:"
    tc_prompt+=$'\n'"1. You are in swarm mode but TeamCreate was NEVER called."
    tc_prompt+=$'\n'"2. Read .ralph-swarm-state.json to get the teamName."
    tc_prompt+=$'\n'"3. Call TeamCreate with team_name set to the teamName value."
    tc_prompt+=$'\n'"4. Set execution.teamCreated to true in the state file."
    tc_prompt+=$'\n'"5. Proceed with swarm execution using the Agent Team."
    tc_prompt+=$'\n'"PROHIBITED: Task tool with run_in_background, independent subagents."
    if has_jq; then
      jq -n \
        --arg decision "block" \
        --arg reason "$tc_prompt" \
        --arg sysMsg "Swarm iteration ${new_iteration} — TeamCreate REQUIRED" \
        '{"decision":$decision,"reason":$reason,"systemMessage":$sysMsg}'
    else
      cat <<EOF
{"decision":"block","reason":"${tc_prompt}","systemMessage":"Swarm iteration ${new_iteration} — TeamCreate REQUIRED"}
EOF
    fi
    exit 0
  fi
fi

if [[ "$swarm_mode" == "true" ]]; then
  prompt="SWARM COORDINATOR LOOP - Follow these steps in order:"
  prompt+=$'\n'"1. Call TaskList to see all pending, in-progress, and completed tasks."
  prompt+=$'\n'"2. For unassigned pending tasks: assign to idle teammates via TaskUpdate."
  prompt+=$'\n'"3. For completed tasks: verify work by delegating to swarm-verifier agent."
  prompt+=$'\n'"4. Update .ralph-swarm-state.json: sync completedTasks, failedTasks arrays."
  prompt+=$'\n'"5. If ALL tasks done (completedTasks + failedTasks = totalTasks):"
  prompt+=$'\n'"   a. Set phase to \"complete\" in the state file."
  prompt+=$'\n'"   b. Output exactly: <promise>SWARM COMPLETE</promise>"
  prompt+=$'\n'"6. If tasks remain: continue coordinating."
  prompt+=$'\n'"RULE: All work done by Agent Team teammates, NOT Task tool subagents."
else
  prompt="SEQUENTIAL EXECUTION LOOP - Follow these steps in order:"
  prompt+=$'\n'"1. Read ${STATE_FILE} to get the current task index and task list."
  prompt+=$'\n'"2. Find the next task with status 'pending' whose dependencies are all 'completed'."
  prompt+=$'\n'"3. Delegate it to a swarm-executor agent via the Task tool."
  prompt+=$'\n'"4. After completion: update completedTasks/failedTasks arrays in the state file."
  prompt+=$'\n'"5. If ALL tasks done: set phase to \"complete\", output <promise>SWARM COMPLETE</promise>."
  prompt+=$'\n'"6. If tasks remain: the stop hook will re-inject you for the next task."
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
