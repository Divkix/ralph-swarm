---
name: swarm-coordinator
description: This skill should be used when coordinating Agent Teams for parallel task execution, managing teammates, assigning tasks, and verifying completed work.
version: 1.0.0
user-invocable: false
---

# Swarm Coordinator

This skill defines the exact protocol for the lead agent to manage an Agent Teams swarm. The lead agent NEVER writes code. It creates the team, assigns tasks, monitors progress, verifies results, and drives to completion.

## Team Creation

1. **Read the state file** (`.ralph-swarm-state.json`) to get the `teamName`.
2. **Call `TeamCreate`** with `team_name` set to the value from the state file.
3. **Determine teammate count:**
   - If `--teammates <N>` flag was provided, use `N`.
   - Otherwise, auto-detect from `tasks.md`: count the phase with the most parallel tasks — that number is the max useful teammates. Cap at 5.
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
5. **Spawn teammates** via the `Task` tool with the `team_name` parameter and `isolation: "worktree"`. Name teammates sequentially (e.g., `worker-1`, `worker-2`, ...).

## Task Assignment

1. **Read `tasks.md`** and parse all phases and their tasks.
2. **Create `TaskCreate` entries for Phase 0 first.** Phase 0 tasks are blocking prerequisites — nothing else starts until they are done.
3. **Wait for Phase 0 completion** before creating Phase 1+ tasks. Do NOT speculatively create later-phase tasks.
4. **Assign tasks via `TaskUpdate`** with `owner` set to the teammate's name (e.g., `worker-1`).
5. **Prefer phase order:** assign all Phase 1 tasks before any Phase 2 tasks.
6. **Independent tasks within a single phase** can be assigned to different teammates simultaneously — this is the core parallelism advantage.
7. **Set up dependencies** via `TaskUpdate` with `addBlockedBy` when tasks within the same phase have ordering constraints.

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
   - Increment `execution.iteration` on each monitoring cycle.

## Completion

1. **All tasks completed and verified:** once every task across all phases is marked completed:
   - Run the **final verification suite** — the full test suite + lint + any project-specific checks defined in `tasks.md`.
   - **If final verification passes:** output `<promise>SWARM COMPLETE</promise>` and update the state file phase to `"complete"`.
   - **If final verification fails:** create targeted fix tasks from the failure output, assign them to available teammates, and re-enter the monitoring loop.
2. **Update the state file** to `phase: "complete"` and set `execution.swarm` summary fields.

## Rules

These are non-negotiable. Violating them breaks the swarm.

1. **Never write code yourself.** The coordinator only coordinates. All code changes are done by teammates.
2. **Never skip verification.** Every task completion claim must be verified by running the specified checks.
3. **Message teammates by name, not by ID.** Use the `name` field from the team config (e.g., `worker-1`), never the `agentId` UUID.
4. **Three-strike rule:** if a teammate fails a task 3 times (3 consecutive verification failures on the same task), mark the task as failed via `TaskUpdate`, add its index to `execution.failedTasks`, and move on. Do not waste more tokens on it.
5. **Always update `.ralph-swarm-state.json` after state changes.** This is the single source of truth for resumability. If the session crashes and restarts, the state file is how we know where we left off.
6. **Never broadcast routine updates.** Use `SendMessage` with `type: "message"` to individual teammates. Reserve `type: "broadcast"` for critical blockers only.
7. **Shutdown teammates when done.** After all work is complete and verified, send `type: "shutdown_request"` to each teammate before finishing.
