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

## Step 2: Create State File

Write `.ralph-swarm-state.json` in the project root with this exact structure:

```json
{
  "name": "<name>",
  "goal": "<goal>",
  "phase": "planning",
  "specPath": "./specs/<name>/",
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
    "taskIndex": 0,
    "totalTasks": 0,
    "completedTasks": 0,
    "failedTasks": 0,
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
- Update state: set `planning.research` to `"done"`

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
- Update state: set `planning.requirements` to `"done"`

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
- Update state: set `planning.design` to `"done"`

### Phase 4d: Task Breakdown

- Delegate to `swarm-task-planner` agent type if it exists, otherwise use a general-purpose agent
- Instruction: "Based on all specs in `<specPath>/`, break the work into discrete, actionable tasks for: `<goal>`. Save to `<specPath>/tasks.md`."
- The tasks.md must use this exact format:

```markdown
# Tasks: <name>

## Task 1: <title>
- **Status:** pending
- **Priority:** high | medium | low
- **Depends on:** [task numbers or "none"]
- **Files:** [list of files to create/modify]
- **Description:** [what to do, specific enough for an agent to execute without ambiguity]
- **Acceptance criteria:**
  - [ ] [testable criterion]
  - [ ] [testable criterion]

## Task 2: <title>
...
```

- Each task must be completable in a single agent session (if a task is too large, split it)
- Tasks must be ordered by dependency (tasks with no dependencies first)
- Include a final "verification" task that runs tests/linting
- Pass: goal, CLAUDE.md content, all prior spec files
- After completion: Read `<specPath>/tasks.md` to verify
- Update state: set `planning.tasks` to `"done"`, set `phase` to `"planning-complete"`

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
   - Increment `execution.completedTasks` (or `execution.failedTasks`)
   - Advance `execution.taskIndex`
5. If `--commit` is true, commit the changes with message: `feat(swarm): <task title> [<name>]`
6. The **stop hook** will re-inject you with a prompt to continue to the next task
7. When ALL tasks are completed, output exactly: `<promise>SWARM COMPLETE</promise>`

### Swarm Mode (--swarm is true):

1. Create an Agent Team using the **TeamCreate** tool:
   - `team_name`: `"ralph-<name>"`
   - `description`: `"Swarm execution for: <goal>"`

2. Create tasks in the team's task list using **TaskCreate** for each task from tasks.md:
   - `subject`: task title
   - `description`: full task description including files, acceptance criteria, spec context, CLAUDE.md content
   - `activeForm`: present continuous form of the task title

3. Set up task dependencies using **TaskUpdate** with `addBlockedBy` where tasks.md specifies dependencies

4. Determine teammate count:
   - If `--teammates` is `"auto"`: use `min(totalTasks, 5)` but at least 2
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
     - Output exactly: `<promise>SWARM COMPLETE</promise>`

## Error Handling

- If any planning phase agent fails, update that phase status to `"failed"` in the state file, report the error, and stop. Do not proceed to the next phase.
- If a task execution fails in sequential mode, mark it as `"failed"`, increment `failedTasks`, and attempt the next eligible task. If all remaining tasks depend on failed tasks, output the completion promise with a failure summary.
- If the state file cannot be written, error immediately — the stop hook depends on it.
- Never silently swallow errors. Always report what went wrong and what the user can do about it.
