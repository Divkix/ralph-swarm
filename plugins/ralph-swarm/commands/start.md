---
description: Plan and execute a task with optional Agent Teams parallelism
argument-hint: <"goal"> [--swarm] [--yolo] [--teammates <n>] [--agent-type <type>] [--max-iterations <n>] [--commit] [--no-commit]
allowed-tools: "*"
---

# ralph-swarm:start

You are the **swarm lead**. Your job is to orchestrate planning and execution. You NEVER write code directly — you delegate everything to specialized agents.

## Step 0: Read Project Context

Before doing anything else:

1. Check if `CLAUDE.md` exists in the project root. If it does, read it with the Read tool and internalize its rules. Every agent you delegate to must also receive the CLAUDE.md content as context.
2. Check if `.ralph-swarm-state.json` already exists. If it does, warn the user: "A swarm is already active. Run `/ralph-swarm:cancel` first or `/ralph-swarm:status` to check progress." Then stop.

## Step 1: Parse Arguments

Parse `$ARGUMENTS` to extract the following:

| Parameter | Extraction Rule | Default |
|-----------|----------------|---------|
| **goal** | First quoted string (e.g., `"implement user auth"`) or all text before the first `--` flag | REQUIRED — if missing, error: "Usage: `/ralph-swarm:start \"your goal here\"` [flags]" |
| **name** | Derive from goal: lowercase, kebab-case, first 3-4 meaningful words (strip articles/prepositions). E.g., "implement user authentication flow" -> "implement-user-auth" | derived |
| **--swarm** | Boolean flag, present = true | `false` |
| **--yolo** | Boolean flag, present = true | `false` |
| **--teammates N** | Integer following the flag | `"auto"` |
| **--agent-type TYPE** | String following the flag | `"auto"` |
| **--max-iterations N** | Integer following the flag | `30` |
| **--commit** | Boolean flag, present = true | `true` |
| **--no-commit** | Boolean flag, present = true (overrides --commit) | n/a |

**Commit logic:** Default is `true` regardless of `--yolo`. If `--no-commit` is explicitly set, always `false`. If `--commit` is explicitly set, always `true`.

**Orphan flag handling:** If `--teammates` or `--agent-type` are provided without `--swarm`, emit a warning: `Warning: --teammates has no effect without --swarm. Running in sequential mode.` (and analogous for --agent-type). Continue execution normally.

## Step 1.5: Validate Flag Combinations

Before proceeding to state file creation, validate the parsed flags:

1. If `--teammates` or `--agent-type` are set but `--swarm` is false:
   - Print: "Warning: --<flag> has no effect without --swarm. Running in sequential mode."
   - Continue normally. Do not error.

2. If `--swarm` is set:
   - Verify that Agent Teams functionality is available (the TeamCreate tool exists in your tool set).
   - If not available, error: "Error: --swarm requires Agent Teams support. Check that your Claude Code version supports Agent Teams."
   - Stop execution.

3. If `--teammates` is provided as a number and is > 10:
   - Print: "Warning: --teammates capped at 10. Using 10."
   - Set teammates to 10.

4. If `--teammates` is provided as a number and is < 1:
   - Error: "Error: --teammates must be at least 1."
   - Stop execution.

## Step 2: Create State File

Write `.ralph-swarm-state.json` in the project root with this exact structure:

```json
{
  "name": "<name>",
  "goal": "<goal>",
  "phase": "planning",
  "mode": "sequential",
  "specPath": "./specs/<name>/",
  "teamName": "ralph-<name>",
  "flags": {
    "swarm": false,
    "yolo": false,
    "commit": true,
    "teammates": "auto",
    "agentType": "auto"
  },
  "planning": {
    "research": "pending",
    "requirements": "pending",
    "design": "pending",
    "tasks": "pending"
  },
  "execution": {
    "swarm": false,
    "teamCreated": false,
    "teammates": 0,
    "agentType": "auto",
    "taskIndex": 0,
    "totalTasks": 0,
    "completedTasks": [],
    "failedTasks": [],
    "batches": [],
    "currentBatch": 0,
    "iteration": 0,
    "maxIterations": 30,
    "tasks": []
  },
  "createdAt": "<ISO 8601 timestamp>"
}
```

Populate all fields from parsed arguments. Use Bash to write the file via a heredoc or use the Write tool.

## Step 3: Create Specs Directory

Create the directory `./specs/<name>/` using Bash:

```
mkdir -p ./specs/<name>/
```

## Step 4: Run Planning Phases (Sequential)

Execute these four phases in strict order. Each phase delegates to a specialized agent using the **Task tool** (subagent). Pass the following context to EVERY agent:

- The full **goal**
- The **CLAUDE.md** content (if it exists)
- The **spec path** for output
- Any **output from prior phases** (e.g., research.md feeds into requirements)

### Phase 4a: Research

- Delegate to `swarm-researcher` agent type (subagent_type: `swarm-researcher`)
- Instruction: "Research the codebase and external sources for: `<goal>`. Save findings to `<specPath>/research.md`. Follow the research protocol exactly. Signal completion with RESEARCH_COMPLETE."
- Pass: goal, CLAUDE.md content, project root path
- After completion: Read `<specPath>/research.md` to verify it was created
- Update state: set `planning.research` to `"complete"`

### Phase 4b: Requirements

- Delegate to `swarm-requirements` agent type if it exists, otherwise use a general-purpose agent
- Instruction: "Based on the research at `<specPath>/research.md`, produce detailed requirements for: `<goal>`. Save to `<specPath>/requirements.md`."
- The requirements.md must include:
  - Functional requirements (numbered, testable)
  - Non-functional requirements (performance, security, compatibility)
  - Acceptance criteria for each requirement
  - Out-of-scope items (explicit exclusions)
  - Dependencies on external systems or libraries
- Pass: goal, CLAUDE.md content, research.md content
- After completion: Read `<specPath>/requirements.md` to verify
- Update state: set `planning.requirements` to `"complete"`

### Phase 4c: Architecture/Design

- Delegate to `swarm-architect` agent type if it exists, otherwise use a general-purpose agent
- Instruction: "Based on the research at `<specPath>/research.md` and requirements at `<specPath>/requirements.md`, produce an architecture/design document for: `<goal>`. Save to `<specPath>/design.md`."
- The design.md must include:
  - High-level architecture (components, data flow)
  - File-by-file change plan (which files to create/modify, what changes)
  - Interface contracts (function signatures, types, API shapes)
  - Error handling strategy
  - Testing strategy (what to test, how)
  - Migration/rollback plan if applicable
- Pass: goal, CLAUDE.md content, research.md content, requirements.md content
- After completion: Read `<specPath>/design.md` to verify
- Update state: set `planning.design` to `"complete"`

### Phase 4d: Task Breakdown

- Delegate to `swarm-task-planner` agent type if it exists, otherwise use a general-purpose agent
- Instruction: "Based on all specs in `<specPath>/`, break the work into vertical feature slices for: `<goal>`. Save to `<specPath>/tasks.md`."
- The tasks.md must use this exact format:

```markdown
# Implementation Tasks: <name>

**Date:** [current date]
**Design Source:** design.md
**Total Tasks:** [count]
**Slicing Strategy:** vertical (each task = complete feature slice)

## TASK-001: [Feature Slice Title]

**Complexity:** S | M | L
**Files:**
- CREATE: `path/to/file`
- MODIFY: `path/to/file` — [what changes]
**Dependencies:** None
**Description:**
[End-to-end slice description, precise enough for an agent to execute without ambiguity]
**Context to Read:**
- design.md, section "[relevant section]"
- `[existing file path]` — [why to read it]
**Verification:**
```bash
[exact command to verify]
```

## TASK-002: [Feature Slice Title]
...

---

## File Manifest

| Task | Files Touched |
|------|---------------|
| TASK-001 | `file1`, `file2` |
| TASK-002 | ... |

## Risk Register

| Task | Risk | Mitigation |
|------|------|------------|
| TASK-xxx | [what could go wrong] | [how to handle it] |
```

- Each task is a vertical slice delivering complete functionality end-to-end (not a horizontal layer)
- Each task must declare exact file lists (`Files: CREATE/MODIFY`) — this enables runtime parallelism computation
- Each task must be completable in a single agent session (1-5 files, if larger, split it)
- Tasks must be ordered by dependency (foundational slices first)
- Include a final "verification" task that runs the full test suite and linting
- The File Manifest at the bottom provides quick conflict scanning for the coordinator
- The task format is mode-independent — the same tasks.md works for both sequential and swarm execution
- Pass: goal, CLAUDE.md content, all prior spec files
- After completion: Read `<specPath>/tasks.md` to verify
- Update state: set `planning.tasks` to `"complete"`, set `phase` to `"planning-complete"`

## Step 5: Commit Spec Files (if --commit)

If the `commit` flag is `true`:

1. Stage all files in `./specs/<name>/`:
   ```
   git add ./specs/<name>/
   ```
2. Commit with message:
   ```
   chore(swarm): generate spec files for <name>
   ```
3. If the commit fails, warn but do not abort.

## Step 6: Decide Next Action

### If --yolo is true:

Proceed directly to **Step 7 (Execution Phase)**. Do not pause.

### If --yolo is false:

1. Update state: set `phase` to `"planning-review"`
2. Display a summary to the user:
   - Print the total number of tasks from tasks.md
   - Print a brief one-line summary of each task (number + title)
   - Print the execution mode: "sequential" or "swarm (parallel)"
3. Tell the user:
   ```
   Plan ready for review. Spec files are at ./specs/<name>/
   Edit the spec files if needed, then run /ralph-swarm:go to start execution.
   Run /ralph-swarm:cancel to abort.
   ```
4. **STOP HERE.** Do not proceed to execution. The stop hook will allow the session to exit because phase is "planning-review".

## Step 7: Execution Phase

Update state file:
- Set `phase` to `"execution"`
- Parse `<specPath>/tasks.md` to extract all tasks
- Set `execution.totalTasks` to the count
- Set `execution.taskIndex` to `0`
- Set `execution.swarm` to match the `--swarm` flag
- Populate `execution.tasks` array with objects: `{"id": 1, "title": "...", "status": "pending", "dependsOn": [...]}`

### Sequential Mode (--swarm is false):

1. Read the tasks list from state
2. Find the first task with status `"pending"` whose dependencies are all `"completed"`
3. Delegate that task to `swarm-executor` agent type (or general-purpose agent)
   - Pass: full task description, relevant spec files, CLAUDE.md content, list of files involved
   - Instruction: "Execute this task. When complete, report what you did and what files you changed."
4. After the agent completes:
   - Update the task status to `"completed"` in the state file (or `"failed"` if it errored)
   - Append task index to `execution.completedTasks` (or `execution.failedTasks`)
   - Advance `execution.taskIndex`
5. If `--commit` is true, commit the changes with message: `feat(swarm): <task title> [<name>]`
6. The **stop hook** will re-inject you with a prompt to continue to the next task
7. When ALL tasks are completed:
   - Verify that `execution.completedTasks` + `execution.failedTasks` accounts for all `execution.totalTasks` in the state file
   - Set `phase` to `"complete"` in the state file
   - Then output exactly: `<promise>SWARM COMPLETE</promise>`
   - **Note:** The stop hook independently verifies task counts before allowing exit. If the numbers don't add up, the hook will reject the completion and re-inject you.

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

### Swarm Mode (--swarm is true):

1. Create an Agent Team using the **TeamCreate** tool:
   - `team_name`: `"ralph-<name>"`
   - `description`: `"Swarm execution for: <goal>"`
   - **Immediately after TeamCreate succeeds**, update the state file: set `execution.teamCreated` to `true`. This MUST happen before any other swarm action (task creation, teammate spawning, etc.). If TeamCreate fails, do NOT set this field — report the error and stop.

2. Create tasks in the team's task list using **TaskCreate** for each task from tasks.md:
   - `subject`: task title
   - `description`: full task description including files, acceptance criteria, spec context, CLAUDE.md content
   - `activeForm`: present continuous form of the task title

3. Set up task dependencies using **TaskUpdate** with `addBlockedBy` where tasks.md specifies dependencies

4. Determine teammate count:
   - If `--teammates` is `"auto"`: compute parallel batches first (see swarm-coordinator skill), then use `min(largest_batch_size, 4)` but at least 2 (hard cap: 5 if user overrides)
   - If `--teammates` is a number: use that number, capped at 10

5. Spawn teammates using the **Task** tool with `team_name` parameter:
   - Each teammate should be a `swarm-executor` type (or `--agent-type` if specified)
   - Name them: `executor-1`, `executor-2`, etc.
   - Instruction for each: "You are a swarm executor. Check the TaskList for available tasks. Claim unassigned, unblocked tasks. Execute them. Mark completed. Check for more. When no tasks remain, go idle."

6. Assign initial tasks to teammates using **TaskUpdate** with `owner`

7. Monitor progress:
   - Periodically check **TaskList** for completed/failed/blocked tasks
   - Reassign failed tasks or unblock stuck teammates
   - When ALL tasks are completed:
     - If `--commit` is true, create a single commit: `feat(swarm): complete <name>`
     - Send `shutdown_request` to all teammates
     - Call **TeamDelete** to clean up
     - Verify that `execution.completedTasks` + `execution.failedTasks` accounts for all `execution.totalTasks`
     - Set `phase` to `"complete"` in the state file
     - Output exactly: `<promise>SWARM COMPLETE</promise>`

## Error Handling

- If any planning phase agent fails, update that phase status to `"failed"` in the state file, report the error, and stop. Do not proceed to the next phase.
- If a task execution fails in sequential mode, mark it as `"failed"`, increment `failedTasks`, and attempt the next eligible task. If all remaining tasks depend on failed tasks, update the state file (ensure completedTasks + failedTasks accounts for all tasks), set `phase` to `"complete"`, then output the completion promise with a failure summary.
- If the state file cannot be written, error immediately — the stop hook depends on it.
- Never silently swallow errors. Always report what went wrong and what the user can do about it.
