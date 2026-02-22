# Execution Protocol

This is the canonical execution protocol referenced by both `/ralph-swarm:start` (Step 7) and `/ralph-swarm:go` (Step 5). It covers both sequential and swarm execution modes.

## Pre-Execution State Update

Before beginning execution, update `.ralph-swarm-state.json`:

- Set `phase` to `"execution"`
- Parse `<specPath>/tasks.md` to extract all tasks
- Set `execution.totalTasks` to the count
- Set `execution.taskIndex` to `0`
- Set `execution.completedTasks` to `[]`
- Set `execution.failedTasks` to `[]`
- Set `execution.iteration` to `0`
- Set `execution.swarm` to match the `--swarm` flag (or `flags.swarm`)
- Populate `execution.tasks` array with objects: `{"id": 1, "title": "...", "status": "pending", "dependsOn": [...]}`

## Pre-Execution Snapshot

Before executing the first task, record the rollback point:
1. Run `git rev-parse HEAD` and store as `execution.snapshotCommit` in the state file.
2. This enables rollback to pre-execution state if needed via `/ralph-swarm:rollback`.

## Sequential Mode (--swarm is false)

1. Read the tasks list from the state file.
2. Find the first task with `status` of `"pending"` whose `dependsOn` tasks are all `"completed"`.
3. If no eligible task exists:
   - If there are still `"pending"` tasks but all are blocked by `"failed"` tasks, mark all blocked tasks as `"failed"` in `execution.failedTasks`, set `phase` to `"complete"` in the state file, then output `<promise>SWARM COMPLETE</promise>` with a summary of what succeeded and what failed.
   - If all tasks are `"completed"`, verify `execution.completedTasks` + `execution.failedTasks` accounts for `execution.totalTasks`, set `phase` to `"complete"`, then output `<promise>SWARM COMPLETE</promise>`
4. Delegate the eligible task to a `swarm-executor` agent (or general-purpose agent) using the Task tool:
   - Pass the full task description, acceptance criteria, relevant files list
   - Pass the content of the relevant spec files (research.md, requirements.md, design.md)
   - Pass CLAUDE.md content
   - Instruction: "Execute this task completely. Follow the acceptance criteria. Report what files you created or modified and whether all criteria are met."
5. After the agent completes:
   - Read the agent's output to determine success or failure
   - Advance `execution.taskIndex`
6. Delegate verification to a `swarm-verifier` agent (subagent_type: `ralph-swarm:swarm-verifier`):
   - Pass: the task's verification commands, acceptance criteria, and list of files the executor reported changing.
   - If VERIFICATION_PASS: update the task status to `"completed"` and append to `execution.completedTasks`.
   - If VERIFICATION_FAIL: send failure details back to executor for retry (up to 3 total attempts). If all retries exhausted, mark as `"failed"` and append to `execution.failedTasks`.
   - If the swarm-verifier agent type is not available, run verification commands inline via Bash as a fallback.
7. If `flags.commit` is true and the task succeeded:
   - Stage ONLY the files the executor reported changing: `git add <file1> <file2> ...`
   - NEVER use `git add -A` or `git add .` — these can stage sensitive files (.env, credentials).
   - If the executor did not report files, use `git diff --name-only` filtered against the task's declared file list.
   - Commit: `feat(swarm): <task title> [<name>]`
8. The **stop hook** (`swarm-watcher.sh`) will detect the active execution phase and re-inject you with a prompt to continue the next task. You do not need to loop manually — just complete the current task and let the hook handle continuation.

## TeamCreate Enforcement (NON-NEGOTIABLE)

> **NON-NEGOTIABLE: TeamCreate is REQUIRED for Swarm Mode**
>
> The following are **PROHIBITED** — violating any of these will cause the stop hook to reject your completion:
>
> - **DO NOT** use the Task tool with `run_in_background` as a substitute for creating an Agent Team.
> - **DO NOT** spawn independent subagents via the Task tool instead of creating a team with TeamCreate.
> - **DO NOT** rationalize skipping TeamCreate for "efficiency", "optimization", or "deep dependency chains".
> - **DO NOT** set `execution.teamCreated` to `true` without actually calling TeamCreate first.
>
> **Understand the difference:**
> - **Wrong:** `Task` tool with `run_in_background: true` and no `team_name` — this spawns fire-and-forget subagents with no shared TaskList, no coordinator loop, no team.
> - **Right:** `TeamCreate` first, then `Task` tool with `team_name` parameter — this creates a proper Agent Team with shared TaskList and coordinator oversight.
>
> The stop hook (`swarm-watcher.sh`) enforces this: if `execution.swarm` is `true` but `execution.teamCreated` is `false`, the hook will **block exit** and demand you call TeamCreate. There is no workaround.

## Swarm Mode (--swarm is true)

1. Create an Agent Team using the **TeamCreate** tool:
   - `team_name`: `"ralph-<name>"`
   - `description`: `"Swarm execution for: <goal>"`
   - **Immediately after TeamCreate succeeds**, update the state file: set `execution.teamCreated` to `true`. This MUST happen before any other swarm action (batch computation, task creation, teammate spawning, etc.). If TeamCreate fails, do NOT set this field — report the error and stop.

2. **Compute parallel batches** using the coordinator's Runtime Parallelism Computation algorithm (see `swarm-coordinator` skill):
   - Parse the File Manifest from tasks.md to build a file-conflict graph.
   - Group non-conflicting, dependency-satisfied tasks into batches.
   - Store batches in the state file under `execution.batches`.

3. Create tasks in the team's task list using **TaskCreate** for Batch 1 tasks only:
   - `subject`: task title
   - `description`: full task description including file list, verification command, all relevant spec file contents, and CLAUDE.md content
   - `activeForm`: present continuous form of the task (e.g., "Implementing user auth" for "Implement user auth")

4. Set up dependencies using **TaskUpdate** with `addBlockedBy` based on each task's `Dependencies` field.

5. Determine teammate count:
   - If `flags.teammates` is `"auto"`: use the size of the largest batch, recommended cap at 4 (hard cap: 5), minimum 2
   - If `flags.teammates` is a number: use that exact number, capped at 10

6. Spawn teammates using the **Task** tool with `team_name` and `name` parameters:
   - Agent type: `flags.agentType` if not `"auto"`, otherwise `"swarm-executor"` (fall back to default if agent type does not exist)
   - Names: `executor-1`, `executor-2`, ..., `executor-N`
   - Instruction for each: "You are a swarm executor on team `ralph-<name>`. Check the TaskList for available tasks (pending, no owner, not blocked). Claim one by setting yourself as owner via TaskUpdate. Execute it fully. Mark it completed via TaskUpdate. Then check TaskList again for more work. When no tasks remain, go idle."

7. Assign Batch 1 tasks to teammates using **TaskUpdate** with `owner` field.

8. You are the **coordinator**. Your loop:
   - Check **TaskList** to monitor progress
   - When all tasks in the current batch are completed, advance to the next batch: create tasks from the next batch via **TaskCreate**, assign to available teammates
   - Update `execution.currentBatch` in the state file after each batch transition
   - If a teammate reports a failure, decide whether to retry (assign to a different teammate) or mark as failed
   - Keep the execution state file in sync: update `execution.completedTasks`, `execution.failedTasks`, and individual task statuses
   - When ALL batches are complete:
     - If `flags.commit` is true: stage and commit all changes with `feat(swarm): complete <name>`
     - Send `shutdown_request` to all teammates via **SendMessage**
     - Wait briefly for shutdown responses
     - Call **TeamDelete** to clean up the team
     - Verify that `execution.completedTasks` + `execution.failedTasks` accounts for `execution.totalTasks`
     - Set `phase` to `"complete"` in the state file
     - Output exactly: `<promise>SWARM COMPLETE</promise>`

## Branch Merge Protocol (Swarm Mode)

After a teammate's task passes verification:

1. Identify the teammate's worktree branch name (from the Task tool result).
2. From the main working directory, merge the branch:
   - Prefer fast-forward: `git merge --ff-only <branch>`
   - If ff fails, regular merge: `git merge <branch> --no-edit`
   - If merge conflicts: create a fix task with `git diff --name-only --diff-filter=U` output and assign to a teammate.
3. Run the task's verification command on the merged result to catch integration issues.
4. Merge ALL Batch N branches before starting Batch N+1 work.
5. Within a batch, merge in task completion order.
