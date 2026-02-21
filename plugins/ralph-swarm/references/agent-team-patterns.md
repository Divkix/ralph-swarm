# Agent Team Patterns

Patterns and best practices for Agent Teams coordination in ralph-swarm. These are derived from real failure modes — each pattern exists because the opposite caused problems.

## 1. Worktree Isolation

**Always spawn teammates with `isolation: "worktree"`.**

Why: Without worktree isolation, teammates write to the same working directory. Two agents editing the same file simultaneously causes data loss. Git conflicts become unresolvable mid-session. One agent's `git checkout` nukes another agent's uncommitted work.

How:
- When spawning teammates via the `Task` tool, set `isolation: "worktree"`.
- Each teammate gets its own git worktree, branching from the current HEAD.
- Teammates commit to their own branches. The lead merges after verification.

Anti-pattern:
```
# WRONG: teammates share the working directory
Task(team_name="my-team", name="executor-1")  # no isolation

# RIGHT: each teammate gets a worktree
Task(team_name="my-team", name="executor-1", isolation="worktree")
```

## 2. Task Granularity

**One task = one atomic unit of work, completable by one agent in one turn.**

Why: If a task is too large, the agent loses context mid-way, makes mistakes, or runs out of output tokens. If a task is too small (e.g., "add one import statement"), the overhead of assigning, monitoring, and verifying exceeds the work itself.

Guidelines:
- A good task touches 1-5 files and takes 5-30 minutes of agent time.
- A task should have a clear "done" criteria: a test passes, a linter is clean, an endpoint returns the right response.
- If a task description is longer than 5 lines, it is probably too complex. Split it.

Examples of good tasks:
- "Implement the `UserService.Create()` method with input validation and unit tests."
- "Add the `/health` endpoint to the HTTP router with a 200 response."
- "Write migration 003 to add the `sessions` table with columns: id, user_id, token, expires_at."

Examples of bad tasks:
- "Build the authentication system." (too vague, too large)
- "Fix the bug." (no context, no verification criteria)
- "Add a comma to line 42." (too small, not worth the coordination overhead)

## 3. Batch Dependencies

**Never assign Batch N+1 tasks until ALL Batch N tasks are verified.**

Why: Batches are computed at runtime based on file conflicts and declared dependencies between vertical slice tasks. If Batch 1 creates the database schema and Batch 2 writes queries against it, starting Batch 2 before Batch 1 is verified means Batch 2 agents might code against a broken or incomplete schema. The result: wasted tokens, conflicting changes, and a debugging nightmare.

How batches are computed: The coordinator analyzes the File Manifest from tasks.md, builds a conflict graph (tasks sharing files conflict), respects declared dependencies, and groups non-conflicting, dependency-satisfied tasks into batches. This is done at runtime, not at planning time.

Protocol:
1. Create and assign all Batch N tasks.
2. Monitor until every Batch N task is either completed or failed.
3. Run the batch-level verification gate (see pattern #4).
4. Only then create Batch N+1 tasks.

Edge case: If a Batch N task fails after 3 retries and is marked failed, the coordinator must decide:
- If the failed task is a prerequisite for Batch N+1 tasks (declared in their `Dependencies` field), those dependent tasks must also be marked failed or reassigned as fix tasks.
- If the failed task is independent (no later tasks depend on it), Batch N+1 can proceed.

## 4. Verification Gates

**Run tests after each batch, not just each task.**

Why: Individual tasks might pass their own tests but break integration. A function might work in isolation but conflict with another function written by a different teammate in the same batch. Batch-level verification catches these cross-task regressions.

Two levels of verification:

### Task-Level Verification
- Run after each task completion.
- Scope: the specific tests or checks mentioned in the task description.
- Example: "Run `go test ./pkg/auth/...` to verify the auth service."

### Batch-Level Verification
- Run after all tasks in a batch are complete.
- Scope: the full test suite + lint + type-check for the affected area.
- Example: "Run `make test && make lint` to verify Batch 2 integration."

### Final Verification
- Run after all batches complete.
- Scope: the entire project test suite, lint, build.
- Example: "Run `make test && make lint && make build` to verify everything."

If any verification gate fails, create targeted fix tasks from the error output and assign them before proceeding.

## 5. Teammate Communication

**Use `SendMessage` with `type: "message"` for task feedback. Never broadcast for routine updates.**

Why: Broadcasting sends a message to every teammate. If you have 4 teammates and broadcast "task 3 is done", you just burned tokens on 3 agents that do not care about task 3. Broadcasting also interrupts agents mid-work, forcing them to process an irrelevant message before continuing.

When to use `type: "message"` (direct message):
- Assigning a new task to a specific teammate.
- Sending verification failure output to the teammate who owns the task.
- Asking a teammate for status or clarification.
- Acknowledging a teammate's completion message.

When to use `type: "broadcast"`:
- A critical blocker that affects everyone (e.g., "the database is down, stop all DB tasks").
- A schema change that invalidates multiple teammates' work.
- Never for routine status updates. Never.

## 6. Failure Handling

**3 strikes per task, then mark as failed and create a fix task.**

Why: Some tasks are genuinely broken — bad requirements, impossible constraints, or flaky infrastructure. Retrying indefinitely wastes tokens. The 3-strike rule cuts losses.

Protocol:
1. Teammate completes a task and notifies the coordinator.
2. Coordinator runs verification. If it fails, send error output to the teammate.
3. Teammate attempts a fix and re-notifies. (Strike 1.)
4. Coordinator verifies again. If it fails, send updated error output. (Strike 2.)
5. Teammate attempts again. (Strike 3.)
6. If verification still fails after Strike 3:
   - Mark the task as failed via `TaskUpdate`.
   - Add the task index to `execution.failedTasks` in the state file.
   - Create a new "fix" task with the accumulated error context.
   - Assign the fix task to a different teammate if available.

Tracking strikes: The coordinator tracks strike count per task in memory (not in the state file). If the session restarts, strike counts reset — this is acceptable because resumption is already a form of retry.

## 7. Cost Control

**Prefer fewer teammates with more tasks over many teammates with few tasks.**

Why: Each teammate has overhead — spawning, context loading, worktree creation, shutdown. A teammate that completes 1 task and idles is wasteful. A teammate that completes 5 tasks amortizes the overhead.

Guidelines:
- If you have 8 tasks across 2 batches of 4, use 4 teammates (not 8).
- If you have 3 tasks total, use 2 teammates (or even 1 in sequential mode).
- The sweet spot is 3-4 teammates for most projects.
- 5 teammates is the hard cap. Beyond that, the coordinator itself becomes the bottleneck.

Token cost multipliers:
- Each idle teammate waiting for work still costs tokens (context maintenance).
- Teammates in worktrees have slight overhead from git operations.
- Large projects with big `node_modules` or `vendor/` directories increase worktree setup time.

Decision framework:
```
if total_tasks <= 3:
    use sequential mode (no teammates)
elif total_tasks <= 6:
    use 2 teammates
elif total_tasks <= 12:
    use 3-4 teammates
else:
    use 4 teammates (cap)
```

## 8. Merge Strategy

**Teammates push to branches. The lead merges after verification.**

Why: If teammates merge their own work, merge conflicts between teammates go undetected until the next teammate pulls. The lead agent, having full visibility of all tasks, is the only one who can resolve cross-task conflicts correctly.

Protocol:
1. Each teammate works in their worktree on an auto-created branch (e.g., `ralph-executor-1-add-auth`).
2. When a task is complete, the teammate commits and pushes to their branch.
3. The coordinator verifies the branch:
   - Check out the branch (or inspect the worktree).
   - Run task-level and batch-level verification.
4. If verification passes, the coordinator merges the branch into the base branch:
   - Use fast-forward merge when possible (`git merge --ff-only`).
   - If fast-forward is not possible, do a regular merge.
   - If there are conflicts, resolve them or create a fix task.
5. After merging, the coordinator ensures the base branch still passes all tests.
6. Do NOT rebase teammate branches onto the updated base mid-execution — it causes confusion and lost work. Only merge forward.

Merge order: Merge in batch order. All Batch 1 branches merge before any Batch 2 branches. Within a batch, merge in task completion order (first finished, first merged).

## Summary

| Pattern                 | Rule                                                    | Violation Cost                          |
|-------------------------|---------------------------------------------------------|-----------------------------------------|
| Worktree Isolation      | Always use `isolation: "worktree"`                      | Data loss, unresolvable conflicts       |
| Task Granularity        | 1-5 files, 5-30 min, clear done criteria                | Context loss, wasted tokens             |
| Batch Dependencies      | Complete Batch N before starting Batch N+1              | Broken integration, cascading failures  |
| Verification Gates      | Test after each task AND each batch                     | Undetected regressions                  |
| Teammate Communication  | DM for routine, broadcast only for critical blockers    | Token waste, unnecessary interruptions  |
| Failure Handling        | 3 strikes then mark failed                              | Infinite retry loops, token drain       |
| Cost Control            | Fewer teammates with more tasks                         | Overhead exceeds productivity           |
| Merge Strategy          | Lead merges after verification, never teammates         | Undetected conflicts, lost work         |
