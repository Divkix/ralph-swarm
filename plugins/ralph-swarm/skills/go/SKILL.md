---
description: Resume execution after reviewing the generated plan
argument-hint: ""
allowed-tools: "*"
disable-model-invocation: true
---

# ralph-swarm:go

Resume swarm execution after the planning-review pause. This command picks up where `/ralph-swarm:start` left off.

## Step 0: Read Project Context

1. Check if `CLAUDE.md` exists in the project root. If it does, read it with the Read tool. Every agent you delegate to must receive the CLAUDE.md content.

## Step 1: Load and Validate State

1. Read `.ralph-swarm-state.json` from the project root using the Read tool.
2. If the file does not exist, output this error and stop:
   ```
   Error: No active swarm found. No .ralph-swarm-state.json in project root.
   Run /ralph-swarm:start "your goal" to begin.
   ```
3. Parse the JSON. Extract `phase`, `name`, `goal`, `specPath`, `flags`, and `execution` fields.
4. Verify that `phase` is exactly `"planning-review"` or `"planning-complete"`. If it is anything else, output this error and stop:
   ```
   Error: No plan awaiting review. Current phase is "<phase>".
   - If phase is "planning": planning is still in progress.
   - If phase is "execution": execution is already running. Use /ralph-swarm:status to check progress.
   - If phase is missing: state file may be corrupted. Run /ralph-swarm:cancel and start over.
   ```

## Step 2: Read Tasks

1. Read the tasks file at `<specPath>/tasks.md` using the Read tool.
2. If the file does not exist or is empty, output this error and stop:
   ```
   Error: Tasks file not found at <specPath>/tasks.md. The planning phase may have failed.
   Check the spec files at <specPath>/ and run /ralph-swarm:cancel to reset.
   ```
3. Parse the tasks file to extract all tasks. The format is defined in [../start/task-format.md](../start/task-format.md). Each task has:
   - **id**: TASK-NNN identifier (e.g., TASK-001, TASK-002)
   - **title**: the feature slice title
   - **complexity**: S, M, or L
   - **files**: list of files to CREATE or MODIFY (with operation type)
   - **dependencies**: list of TASK-IDs this task depends on (or "None")
   - **description**: end-to-end slice description
   - **context to read**: files and design sections the executor needs
   - **verification**: exact command to verify completion
4. Parse the **File Manifest** table at the bottom of tasks.md. This provides a quick-scan summary of which tasks touch which files.
5. Count the total number of tasks.

## Step 3: Update State for Execution

Update `.ralph-swarm-state.json` with these changes:

- Set `phase` to `"execution"`
- Set `pausedAfter` to `null`
- Set `execution.totalTasks` to the total task count
- Set `execution.taskIndex` to `0`
- Set `execution.completedTasks` to `[]`
- Set `execution.failedTasks` to `[]`
- Set `execution.iteration` to `0`
- Set `execution.swarm` to the value of `flags.swarm`
- Populate `execution.tasks` as an array of objects:
  ```json
  [
    {"id": 1, "title": "task title", "status": "pending", "dependsOn": []},
    {"id": 2, "title": "task title", "status": "pending", "dependsOn": [1]},
    ...
  ]
  ```

Write the updated state file.

## Step 4: Display Execution Start

Output to the user:

```
Starting execution for: <name>
Goal: <goal>
Mode: <sequential | swarm (parallel)>
Tasks: <totalTasks> total
Max iterations: <maxIterations>
Commit after tasks: <yes | no>
```

## Step 5: Begin Execution

See [../start/execution-protocol.md](../start/execution-protocol.md) for the full execution protocol covering both sequential and swarm modes.

## Error Handling

- If the state file is malformed JSON, report the parse error and suggest running `/ralph-swarm:cancel` to reset.
- If tasks.md is malformed (cannot parse task structure), report what went wrong and suggest the user edit the file manually then re-run `/ralph-swarm:go`.
- If a teammate fails to start in swarm mode, reduce the teammate count and continue with available agents.
- Never silently swallow errors. Always report and update the state file.
