---
description: Cancel active swarm, shutdown teammates, cleanup state
argument-hint: ""
allowed-tools: "*"
---

# ralph-swarm:cancel

Cancel an active ralph-swarm session, shut down any running teammates, and clean up state. Spec files are preserved unless cancelled during planning (incomplete specs are removed).

## Step 1: Load State

1. Read `.ralph-swarm-state.json` from the project root using the Read tool.
2. If the file does not exist, output this message and stop:
   ```
   No active swarm to cancel. Nothing to do.
   ```
3. Parse the JSON. Extract `name`, `goal`, `phase`, `specPath`, `execution.swarm`, and `execution` fields.

## Step 2: Shut Down Swarm Team (if applicable)

Only if `execution.swarm` is `true` AND `phase` is `"execution"`:

1. **Attempt to read the team config** to discover teammates:
   - The team name would be `"ralph-<name>"` based on the swarm naming convention.
   - Read `~/.claude/teams/ralph-<name>/config.json` using the Read tool.
   - If the file exists, parse the `members` array to get teammate names.

2. **Send shutdown requests to all teammates:**
   - For each teammate name found in the config, use the **SendMessage** tool:
     ```
     type: "shutdown_request"
     recipient: "<teammate-name>"
     content: "Swarm cancelled by user. Shutting down."
     ```
   - Do not wait indefinitely for responses. Send all shutdown requests, then wait 5 seconds (using Bash `sleep 5` or similar).

3. **Delete the team:**
   - Call **TeamDelete** to remove the team and its task list.
   - If TeamDelete fails (e.g., teammates still active), report the warning but continue with cleanup. The teammates will eventually time out.

4. If the team config file does not exist (team was never created or already cleaned up), skip this step silently.

## Step 2.5: Clean Up Orphaned Worktrees

Regardless of swarm mode, check for and clean up orphaned worktrees:

1. List worktrees: `git worktree list`
2. Identify orphaned worktrees with paths containing `ralph-` or `.claude/worktrees/`
3. Remove each: `git worktree remove <path> --force`
4. Prune stale metadata: `git worktree prune`

If no orphaned worktrees are found, skip silently. If removal fails for any worktree, warn but continue.

## Step 2.7: Clean Up Partial Specs (Planning Phase Only)

Only if `phase` is `"planning"`:

1. Delete the spec directory: `rm -rf <specPath>`
2. If the spec files were committed, create a commit removing them:
   - `git add <specPath>` (stages the deletion)
   - `git commit -m "chore(swarm): remove partial specs for <name>"`
   - If nothing was committed (files were never staged), skip the commit.

If `phase` is NOT `"planning"`, skip this step entirely — specs are preserved.

## Step 3: Remove State File

Delete `.ralph-swarm-state.json` from the project root using Bash:

```bash
rm -f .ralph-swarm-state.json
```

Verify deletion by checking the file no longer exists.

## Step 4: Report Cancellation

Output a summary:

```
Swarm cancelled.

Name:        <name>
Goal:        <goal>
Phase at cancellation: <phase>
```

If `execution.completedTasks` is greater than 0:
```
Completed tasks: <completedTasks>/<totalTasks>
Note: Changes from completed tasks remain in the working tree. Review with `git diff` or `git status`.
```

If `phase` was `"planning"` (partial specs were removed):
```
Partial spec files removed from: <specPath>

To restart, run /ralph-swarm:start "your goal"
```

If `phase` was NOT `"planning"` (specs preserved):
```
Spec files preserved at: <specPath>
  - research.md
  - requirements.md
  - design.md
  - tasks.md

To restart, run /ralph-swarm:start "your goal"
To reuse this plan, copy the spec files and edit as needed.
```

Only list spec files that actually exist (check with Read or Bash `ls`).

## Important Rules

- **NEVER delete spec files once planning is complete.** During planning phase, partial specs are removed on cancel.
- **NEVER delete any code changes** that were made during execution. They are in the working tree and the user can review them with `git status` and `git diff`.
- **NEVER run `git checkout .` or `git reset --hard`** or any destructive git command. Cancelling the swarm only removes the orchestration state, not the work product.
- If anything goes wrong during cleanup (e.g., TeamDelete fails), report the issue but still remove the state file. A stale state file is worse than orphaned team resources.
