---
description: Run the task breakdown planning phase
argument-hint: ""
allowed-tools: "*"
disable-model-invocation: true
---

# ralph-swarm:tasks

Run the task breakdown planning phase. This command takes all prior spec files and produces the vertical feature slice task list. It is the fourth and final step in the incremental planning flow.

## Step 1: Load & Validate State

1. Read `.ralph-swarm-state.json` from the project root using the Read tool.
2. If the file does not exist, output this error and stop:
   ```
   Error: No active swarm found. Run /ralph-swarm:start "your goal" first.
   ```
3. Parse the JSON. Extract `phase`, `pausedAfter`, `planning`, `specPath`, `goal`, `name`, and `flags`.
4. Validate prerequisites:
   - If `phase` is not `"planning"`, output this error and stop:
     ```
     Error: Cannot run tasks phase. Current phase is "<phase>".
     Tasks can only run during the planning phase.
     ```
   - If `planning.design` is not `"complete"`, output this error and stop:
     ```
     Error: Design phase must complete first. Run /ralph-swarm:design first.
     ```
   - If `pausedAfter` is set but `planning.design` is `"pending"`, this is a corrupt state. Output:
     ```
     Warning: State inconsistency detected (pausedAfter is set but design is pending). Run /ralph-swarm:cancel to reset.
     ```
     Then stop.

## Step 2: Handle Re-run

If `planning.tasks` is already `"complete"`:

1. Warn the user:
   ```
   Warning: Task breakdown phase already completed. Re-running will regenerate the task list.
   ```
2. Set `pausedAfter` to `null`.
3. Write the updated state file.

## Step 3: Read Context

1. Check if `CLAUDE.md` exists in the project root. If it does, read it with the Read tool.
2. Read `<specPath>/research.md` using the Read tool.
3. Read `<specPath>/requirements.md` using the Read tool.
4. Read `<specPath>/design.md` using the Read tool.
5. If any file does not exist or is empty, output an error identifying the missing file and stop.

## Step 4: Execute Task Breakdown Phase

1. Set `pausedAfter` to `null` in the state file (clear any previous pause).
2. Set `planning.tasks` to `"in-progress"` in the state file.
3. Write the updated state file.
4. Delegate to the `swarm-task-planner` agent type (subagent_type: `ralph-swarm:swarm-task-planner`) via the Task tool:
   - Instruction: "Based on all specs in `<specPath>/`, break the work into vertical feature slices for: `<goal>`. Save to `<specPath>/tasks.md`."
   - The tasks.md must follow the format defined in [../start/task-format.md](../start/task-format.md).
   - Pass: goal, CLAUDE.md content (if exists), all prior spec files (research.md, requirements.md, design.md)
5. After the agent completes, verify `<specPath>/tasks.md` exists by reading it.
6. If verification fails, set `planning.tasks` to `"failed"` and stop with an error.
7. Set `planning.tasks` to `"complete"` in the state file.

## Step 5: Commit Spec Files (if --commit)

If `flags.commit` is `true`:

1. Stage all spec files (use the absolute `specPath` from the state file):
   ```
   git add <specPath>/research.md <specPath>/requirements.md <specPath>/design.md <specPath>/tasks.md
   ```
2. Commit with message:
   ```
   chore(swarm): generate spec files for <name>
   ```
3. If the commit fails, warn but do not abort.

## Step 6: Transition to Planning Review

1. Set `phase` to `"planning-review"` in the state file.
2. Set `pausedAfter` to `"tasks"` in the state file.
3. Write the updated state file.
4. Display a summary to the user:
   - Print the total number of tasks from tasks.md
   - Print a brief one-line summary of each task (number + title)
   - Print the execution mode: "sequential" or "swarm (parallel)"
5. Tell the user:
   ```
   Task breakdown complete. All planning phases finished.
   Spec files are at: <specPath>/

   Review the plan, then run /ralph-swarm:go to start execution.
   Edit the spec files if needed before running /ralph-swarm:go.
   Run /ralph-swarm:cancel to abort.
   ```
6. **STOP HERE.** The stop hook will allow exit because `phase` is `"planning-review"`.

## Error Handling

- If the task planner agent fails, set `planning.tasks` to `"failed"` in the state file, report the error, and stop.
- If the state file cannot be written, error immediately.
- Never silently swallow errors.
