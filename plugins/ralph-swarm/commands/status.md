---
description: Show current swarm progress and status
argument-hint: ""
allowed-tools: ["Read", "Bash", "TaskList"]
---

# ralph-swarm:status

Display the current state of an active ralph-swarm session.

## Step 1: Load State

1. Read `.ralph-swarm-state.json` from the project root using the Read tool.
2. If the file does not exist, output this message and stop:
   ```
   No active swarm. Run /ralph-swarm:start "your goal" to begin.
   ```
3. Parse the JSON. If it is malformed, output:
   ```
   Error: .ralph-swarm-state.json exists but contains invalid JSON. Run /ralph-swarm:cancel to reset.
   ```

## Step 2: Display General Info

Output a formatted status report. Use this structure:

```
=== Ralph Swarm Status ===

Name:       <name>
Goal:       <goal>
Phase:      <phase>
Mode:       <sequential | swarm (parallel)>
Spec path:  <specPath>
Created:    <createdAt>
```

## Step 3: Display Planning Progress

```
--- Planning ---
Research:      <complete | pending | in-progress | failed>    <specPath>/research.md
Requirements:  <complete | pending | in-progress | failed>    <specPath>/requirements.md
Design:        <complete | pending | in-progress | failed>    <specPath>/design.md
Tasks:         <complete | pending | in-progress | failed>    <specPath>/tasks.md
```

For each phase that is `"complete"`, check if the corresponding file actually exists using the Read tool. If the file is missing despite the status being "complete", append `[FILE MISSING]` as a warning.

## Step 4: Display Execution Progress (if applicable)

Only display this section if `phase` is `"execution"` or there is execution data with `totalTasks > 0`.

```
--- Execution ---
Progress:   <completedTasks>/<totalTasks> completed, <failedTasks> failed
Iteration:  <iteration>/<maxIterations>
Commit:     <yes | no>
```

Then list each task from `execution.tasks`:

```
Tasks:
  [1] <completed|pending|in-progress|failed> - <title>
  [2] <completed|pending|in-progress|failed> - <title> (depends on: 1)
  [3] <pending> - <title> (blocked by: 2)
  ...
```

Use these indicators:
- `[x]` for completed
- `[ ]` for pending
- `[>]` for in-progress
- `[!]` for failed

## Step 5: Display Swarm Team Status (if applicable)

Only if `execution.swarm` is `true` and phase is `"execution"`:

1. Call the **TaskList** tool to get the team task list status.
2. Display teammate activity:

```
--- Swarm Team ---
```

Then display whatever the TaskList returns — task assignments, teammate statuses, blocked tasks.

If TaskList returns no results or errors (team may not be created yet), output:
```
Team not yet initialized or already cleaned up.
```

## Step 6: Display Available Actions

Based on the current phase, suggest what the user can do:

- If phase is `"planning"`: "Planning in progress. Wait for completion."
- If phase is `"planning-review"`: "Plan ready for review. Run `/ralph-swarm:go` to start execution or edit spec files first."
- If phase is `"planning-complete"`: "Planning complete. Run `/ralph-swarm:go` to start execution."
- If phase is `"execution"`: "Execution in progress. The swarm will continue automatically."
- For any phase: "Run `/ralph-swarm:cancel` to abort."
