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
- The tasks.md must follow the format defined in [task-format.md](./task-format.md).
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

See [execution-protocol.md](./execution-protocol.md) for the full execution protocol covering both sequential and swarm modes.

## Error Handling

- If any planning phase agent fails, update that phase status to `"failed"` in the state file, report the error, and stop. Do not proceed to the next phase.
- If a task execution fails in sequential mode, mark it as `"failed"`, increment `failedTasks`, and attempt the next eligible task. If all remaining tasks depend on failed tasks, update the state file (ensure completedTasks + failedTasks accounts for all tasks), set `phase` to `"complete"`, then output the completion promise with a failure summary.
- If the state file cannot be written, error immediately — the stop hook depends on it.
- Never silently swallow errors. Always report what went wrong and what the user can do about it.
