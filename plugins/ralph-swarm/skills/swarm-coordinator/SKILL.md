---
name: swarm-coordinator
description: This skill should be used when coordinating Agent Teams for parallel task execution, managing teammates, assigning tasks, and verifying completed work.
version: 2.0.0
user-invocable: false
---

# Swarm Coordinator

This skill defines the exact protocol for the lead agent to manage an Agent Teams swarm. The lead agent NEVER writes code. It creates the team, assigns tasks, monitors progress, verifies results, and drives to completion.

## Team Creation

1. **Read the state file** (`.ralph-swarm-state.json`) to get the `teamName`.
2. **Call `TeamCreate`** with `team_name` set to the value from the state file.
3. **Determine teammate count:**
   - If `--teammates <N>` flag was provided, use `N`.
   - Otherwise, auto-detect from `tasks.md`: compute parallel batches (see Runtime Parallelism Computation below) and use the size of the largest batch. Recommended: cap at 4, hard cap: 5.
4. **Determine agent type:**
   - If `--agent-type <type>` flag was provided, use that type for all teammates.
   - If the flag is `auto` or not provided, auto-detect from the project:
     - `.go` files present and/or `go.mod` exists --> `golang-pro`
     - `.ts` / `.tsx` files present and/or `package.json` with TypeScript --> `typescript-pro`
     - `.py` files present and/or `pyproject.toml` / `setup.py` exists --> `python-pro`
     - `.rs` files present and/or `Cargo.toml` exists --> `rust-pro`
     - `.ex` / `.exs` files present and/or `mix.exs` exists --> `elixir-expert`
     - SQL-heavy project (majority `.sql` files) --> `sql-pro`
     - Mixed languages or unclear --> `general-purpose`
5. **Spawn teammates** via the `Task` tool with the `team_name` parameter and `isolation: "worktree"`. Name teammates sequentially (e.g., `executor-1`, `executor-2`, ...).

## Runtime Parallelism Computation

Before assigning any tasks, the coordinator computes which tasks can run in parallel by analyzing file conflicts. This replaces manual phase grouping — the task planner produces vertical slices with file lists, and the coordinator figures out parallelism at runtime.

### Algorithm

1. **Parse the File Manifest** from the bottom of `tasks.md`. If the manifest is missing, parse the `Files:` section from each individual task.
2. **Build a conflict graph:** two tasks conflict if they share ANY file (whether CREATE or MODIFY). For each pair of tasks, check if their file lists intersect.
3. **Respect declared dependencies:** if TASK-B declares `Dependencies: TASK-A`, then TASK-B cannot be in the same batch as TASK-A or any earlier batch, regardless of file overlap.
4. **Compute batches using greedy coloring:**
   - **Batch 1:** Start with all tasks that have no dependencies (`Dependencies: None`). Among those, group tasks with no file conflicts together. Tasks that conflict with each other go into separate batches.
   - **Batch 2:** All tasks whose dependencies are fully satisfied by Batch 1, and that have no file conflicts with each other.
   - **Batch N:** All tasks whose dependencies are fully satisfied by Batches 1 through N-1, and that have no file conflicts with each other.
   - Continue until all tasks are assigned to a batch.
   - **Tie-breaking:** When a task could fit into multiple valid batches, always place it in the **earliest** valid batch. This maximizes parallelism by front-loading work.
5. **Store the computed batches** in the state file under `execution.batches` as an array of arrays:
   ```json
   {
     "execution": {
       "batches": [
         ["TASK-001", "TASK-002", "TASK-003"],
         ["TASK-004", "TASK-005"],
         ["TASK-006"]
       ]
     }
   }
   ```

### Example

Given these tasks and their files:
```
TASK-001: Files: migration.sql           | Dependencies: None
TASK-002: Files: auth_service.go, types.go | Dependencies: TASK-001
TASK-003: Files: user_service.go, types.go | Dependencies: TASK-001
TASK-004: Files: auth_handler.go, router.go | Dependencies: TASK-002
TASK-005: Files: user_handler.go, router.go | Dependencies: TASK-003
TASK-006: Files: (none, verification)      | Dependencies: TASK-004, TASK-005
```

Conflict analysis:
- TASK-002 and TASK-003 share `types.go` → they conflict.
- TASK-004 and TASK-005 share `router.go` → they conflict.

Computed batches:
- **Batch 1:** [TASK-001] (only task with no dependencies)
- **Batch 2:** [TASK-002] (depends on TASK-001; conflicts with TASK-003 on types.go)
- **Batch 3:** [TASK-003] (depends on TASK-001; had to wait because of TASK-002 conflict)
- **Batch 4:** [TASK-004] (depends on TASK-002; conflicts with TASK-005 on router.go)
- **Batch 5:** [TASK-005] (depends on TASK-003; had to wait because of TASK-004 conflict)
- **Batch 6:** [TASK-006] (depends on TASK-004, TASK-005)

If TASK-002 and TASK-003 did NOT share `types.go`, they would both be in Batch 2 and run in parallel.

## Task Assignment

1. **Compute batches** using the algorithm above.
2. **Create `TaskCreate` entries for Batch 1 tasks.** These are the first tasks to execute.
3. **Assign Batch 1 tasks** to available teammates via `TaskUpdate` with `owner`.
4. **Wait for Batch 1 completion** before creating or assigning Batch 2 tasks. Do NOT speculatively create later-batch tasks.
5. **When all tasks in the current batch are completed and verified**, advance to the next batch: create tasks, assign to teammates.
6. **Independent tasks within a single batch** can be assigned to different teammates simultaneously — this is the core parallelism advantage.
7. **If agents hit an unexpected file conflict** not predicted by the manifest (e.g., a transitive dependency), they use `SendMessage` to coordinate with the lead, who may re-sequence the conflicting tasks.

## Monitoring

After assigning tasks, enter the monitoring loop:

1. **Periodically call `TaskList`** to check overall progress.
2. **When a teammate sends a completion message via `SendMessage`**, verify the work:
   - If the teammate is in a worktree, pull their changes or inspect the files directly.
   - Run the verification commands specified in `tasks.md` for that task (tests, lint, type-check, etc.).
   - **If verification passes:** mark the task as completed via `TaskUpdate` with `status: "completed"`.
   - **If verification fails:** send the teammate the error output via `SendMessage` with a clear description of what failed. The task remains `in_progress`.
3. **Track counts:** maintain running totals of completed and failed tasks. Update `.ralph-swarm-state.json` after every state change:
   - Update `execution.completedTasks` array with completed task indices.
   - Update `execution.failedTasks` array with failed task indices.
   - Update `execution.currentBatch` to reflect which batch is active.
   - Increment `execution.iteration` on each monitoring cycle.

## Completion

1. **All tasks completed and verified:** once every task across all batches is marked completed:
   - Run the **final verification suite** — the full test suite + lint + any project-specific checks defined in `tasks.md`.
   - **If final verification passes:** verify that `execution.completedTasks` + `execution.failedTasks` accounts for all `execution.totalTasks`, set `phase` to `"complete"` in the state file, then output `<promise>SWARM COMPLETE</promise>`. The stop hook independently verifies these counts before allowing exit.
   - **If final verification fails:** create targeted fix tasks from the failure output, assign them to available teammates, and re-enter the monitoring loop.
2. **Update the state file** to `phase: "complete"` and set `execution.swarm` summary fields.

## Rules

These are non-negotiable. Violating them breaks the swarm.

1. **Never write code yourself.** The coordinator only coordinates. All code changes are done by teammates.
2. **Never skip verification.** Every task completion claim must be verified by running the specified checks.
3. **Message teammates by name, not by ID.** Use the `name` field from the team config (e.g., `executor-1`), never the `agentId` UUID.
4. **Three-strike rule:** if a teammate fails a task 3 times (3 consecutive verification failures on the same task), mark the task as failed via `TaskUpdate`, add its index to `execution.failedTasks`, and move on. Do not waste more tokens on it.
5. **Always update `.ralph-swarm-state.json` after state changes.** This is the single source of truth for resumability. If the session crashes and restarts, the state file is how we know where we left off.
6. **Never broadcast routine updates.** Use `SendMessage` with `type: "message"` to individual teammates. Reserve `type: "broadcast"` for critical blockers only.
7. **Shutdown teammates when done.** After all work is complete and verified, send `type: "shutdown_request"` to each teammate before finishing.
8. **Complete batch N before starting batch N+1.** Batches encode both file-conflict and dependency constraints. Skipping ahead risks conflicts and broken builds.
