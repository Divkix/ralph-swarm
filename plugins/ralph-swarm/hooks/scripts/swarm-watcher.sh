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
if echo "$HOOK_INPUT" | grep -q '<promise>SWARM COMPLETE</promise>'; then
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
  prompt="You claimed completion but the task counts don't add up. "
  prompt+="State file shows ${completed} completed + ${failed} failed = ${accounted} accounted, "
  prompt+="but totalTasks is ${total}. ${remaining} tasks are still unaccounted for. "
  prompt+="Continue executing remaining tasks. When genuinely ALL tasks are done, "
  prompt+="update completedTasks/failedTasks in the state file, set phase to \"complete\", "
  prompt+="then output <promise>SWARM COMPLETE</promise>."

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
    tc_prompt="CRITICAL: You are in swarm mode but you NEVER called TeamCreate. "
    tc_prompt+="You MUST call TeamCreate with team_name from the state file BEFORE doing anything else. "
    tc_prompt+="DO NOT use the Task tool with run_in_background as a substitute. "
    tc_prompt+="DO NOT spawn independent subagents. "
    tc_prompt+="Call TeamCreate NOW, then set execution.teamCreated to true in the state file, "
    tc_prompt+="then proceed with swarm execution using the Agent Team."
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
  prompt="You are the swarm lead coordinating an Agent Team (created via TeamCreate). "
  prompt+="All work MUST be done by Agent Team teammates, NOT by Task tool subagents. "
  prompt+="Check the TaskList for pending and in-progress tasks. "
  prompt+="Assign any unassigned tasks to idle teammates via TaskUpdate. Verify completed work by reviewing "
  prompt+="task outputs. When ALL tasks are done and verified, update the state file "
  prompt+="(completedTasks, failedTasks, totalTasks must reconcile), set phase to \"complete\", "
  prompt+="then output <promise>SWARM COMPLETE</promise> to finish. Otherwise, continue coordinating."
else
  prompt="You are in sequential execution mode. Read ${STATE_FILE} for the current task index "
  prompt+="and full task list. Execute the next incomplete task using the swarm-executor agent. "
  prompt+="After each task completes, update the state file (completedTasks/failedTasks arrays). "
  prompt+="When ALL tasks are finished, set phase to \"complete\" in the state file, "
  prompt+="then output <promise>SWARM COMPLETE</promise> to finish."
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
