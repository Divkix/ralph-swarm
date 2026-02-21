---
description: Resume execution after reviewing the generated plan
argument-hint: ""
allowed-tools: "*"
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
3. Parse the tasks file to extract all tasks. Each task has:
   - **id**: sequential number (Task 1, Task 2, etc.)
   - **title**: the task title
   - **status**: should be "pending" at this point
   - **dependsOn**: list of task IDs this task depends on (or "none")
   - **files**: list of files to create/modify
   - **description**: what to do
   - **acceptance criteria**: testable criteria list
4. Count the total number of tasks.

## Step 3: Update State for Execution

Update `.ralph-swarm-state.json` with these changes:

- Set `phase` to `"execution"`
- Set `execution.totalTasks` to the total task count
- Set `execution.taskIndex` to `0`
- Set `execution.completedTasks` to `0`
- Set `execution.failedTasks` to `0`
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

### If Sequential Mode (flags.swarm is false):

1. Read the tasks list from the state file.
2. Find the first task with `status` of `"pending"` whose `dependsOn` tasks are all `"completed"`.
3. If no eligible task exists:
   - If there are still `"pending"` tasks but all are blocked by `"failed"` tasks, report the deadlock and output: `<promise>SWARM COMPLETE</promise>` with a summary of what succeeded and what failed.
   - If all tasks are `"completed"`, output: `<promise>SWARM COMPLETE</promise>`
4. Delegate the eligible task to a `swarm-executor` agent (or general-purpose agent) using the Task tool:
   - Pass the full task description, acceptance criteria, relevant files list
   - Pass the content of the relevant spec files (research.md, requirements.md, design.md)
   - Pass CLAUDE.md content
   - Instruction: "Execute this task completely. Follow the acceptance criteria. Report what files you created or modified and whether all criteria are met."
5. After the agent completes:
   - Read the agent's output to determine success or failure
   - Update the task status in `.ralph-swarm-state.json` to `"completed"` or `"failed"`
   - Increment `execution.completedTasks` or `execution.failedTasks`
   - Advance `execution.taskIndex`
6. If `flags.commit` is true and the task succeeded:
   - Stage changed files: `git add -A` (or preferably stage specific files the agent reported changing)
   - Commit: `feat(swarm): <task title> [<name>]`
7. The **stop hook** (`swarm-watcher.sh`) will detect the active execution phase and re-inject you with a prompt to continue the next task. You do not need to loop manually — just complete the current task and let the hook handle continuation.

### If Swarm Mode (flags.swarm is true):

1. Create an Agent Team using the **TeamCreate** tool:
   - `team_name`: `"ralph-<name>"`
   - `description`: `"Swarm execution for: <goal>"`

2. Create tasks in the team's task list using **TaskCreate** for each task from the parsed tasks.md:
   - `subject`: task title
   - `description`: full task description including file list, acceptance criteria, all relevant spec file contents, and CLAUDE.md content
   - `activeForm`: present continuous form of the task (e.g., "Implementing user auth" for "Implement user auth")

3. Set up dependencies using **TaskUpdate** with `addBlockedBy` based on each task's `dependsOn` field.

4. Determine teammate count:
   - If `flags.teammates` is `"auto"`: use `min(totalTasks, 5)` but at least 2
   - If `flags.teammates` is a number: use that exact number, capped at 10

5. Spawn teammates using the **Task** tool with `team_name` and `name` parameters:
   - Agent type: `flags.agentType` if not `"auto"`, otherwise `"swarm-executor"` (fall back to default if agent type does not exist)
   - Names: `executor-1`, `executor-2`, ..., `executor-N`
   - Instruction for each: "You are a swarm executor on team `ralph-<name>`. Check the TaskList for available tasks (pending, no owner, not blocked). Claim one by setting yourself as owner via TaskUpdate. Execute it fully. Mark it completed via TaskUpdate. Then check TaskList again for more work. When no tasks remain, go idle."

6. Assign initial unblocked tasks to teammates using **TaskUpdate** with `owner` field.

7. You are the **coordinator**. Your loop:
   - Check **TaskList** to monitor progress
   - When a teammate completes a task, check if new tasks are unblocked and assign them
   - If a teammate reports a failure, decide whether to retry (assign to a different teammate) or mark as failed
   - Keep the execution state file in sync: update `execution.completedTasks`, `execution.failedTasks`, and individual task statuses
   - When ALL tasks are done:
     - If `flags.commit` is true: stage and commit all changes with `feat(swarm): complete <name>`
     - Send `shutdown_request` to all teammates via **SendMessage**
     - Wait briefly for shutdown responses
     - Call **TeamDelete** to clean up the team
     - Output exactly: `<promise>SWARM COMPLETE</promise>`

## Error Handling

- If the state file is malformed JSON, report the parse error and suggest running `/ralph-swarm:cancel` to reset.
- If tasks.md is malformed (cannot parse task structure), report what went wrong and suggest the user edit the file manually then re-run `/ralph-swarm:go`.
- If a teammate fails to start in swarm mode, reduce the teammate count and continue with available agents.
- Never silently swallow errors. Always report and update the state file.
