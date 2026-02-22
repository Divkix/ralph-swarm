# State Schema Reference

The `.ralph-swarm-state.json` file is the single source of truth for a ralph-swarm session. It tracks the current phase, planning progress, execution state, and configuration flags. The file lives at the project root and is read/written by the coordinator throughout the session lifecycle.

> **Hook parser requirement:** The hook scripts require `jq` or `python3` to parse `.ralph-swarm-state.json` safely. If neither is available, `SessionStart` emits a warning message and `Stop` fails closed (blocks exit) to avoid incorrect swarm state transitions.

> **Leaf-key uniqueness:** Every field in the schema must have a unique leaf key name (the last segment after the final dot). If the grep fallback is ever reintroduced, it resolves nested paths by leaf key only and cannot distinguish fields that share one (e.g., `.flags.swarm` vs `.execution.swarm`). Leaf-key uniqueness is maintained as a defensive constraint.

## Full Schema

```json
{
  "name": "string",
  "goal": "string",
  "phase": "string",
  "mode": "string",
  "specPath": "string",
  "teamName": "string",
  "pausedAfter": "string | null",
  "flags": {
    "swarm": "boolean",
    "yolo": "boolean",
    "full": "boolean",
    "commit": "boolean",
    "teammates": "number | \"auto\"",
    "agentType": "string"
  },
  "planning": {
    "research": "string",
    "requirements": "string",
    "design": "string",
    "tasks": "string"
  },
  "execution": {
    "swarm": "boolean",
    "teamCreated": "boolean",
    "teammates": "number",
    "agentType": "string",
    "taskIndex": "number",
    "totalTasks": "number",
    "completedTasks": "number[]",
    "failedTasks": "number[]",
    "batches": "string[][]",
    "currentBatch": "number",
    "iteration": "number",
    "maxIterations": "number",
    "tasks": "object[]"
  },
  "createdAt": "string"
}
```

## Field Documentation

### Top-Level Fields

#### `name`
- **Type:** `string`
- **Default:** Derived from the user's goal, converted to kebab-case.
- **Description:** A short, kebab-case identifier for this spec/session. Used as the directory name under `specPath` and as part of the `teamName`.
- **Updated:** Set once during initialization, never changed.
- **Example:** `"add-user-auth"`, `"refactor-db-layer"`

#### `goal`
- **Type:** `string`
- **Default:** Empty string.
- **Description:** The original user goal, verbatim. Preserved for context if the session is resumed or reviewed later.
- **Updated:** Set once during initialization, never changed.
- **Example:** `"Add JWT authentication to the API endpoints"`

#### `phase`
- **Type:** `string` (enum: `"planning"`, `"planning-complete"`, `"planning-review"`, `"execution"`, `"complete"`)
- **Default:** `"planning"`
- **Description:** The current high-level phase of the session.
  - `"planning"` — The coordinator is generating specs: research, requirements, design, and tasks.
  - `"planning-complete"` — All four planning sub-phases are done. If `--yolo`, transitions directly to `"execution"`. Otherwise transitions to `"planning-review"`.
  - `"planning-review"` — Planning is done, waiting for user review/approval before execution.
  - `"execution"` — Tasks are being executed (either sequentially or via swarm).
  - `"complete"` — All tasks finished and verified. Terminal state.
- **Updated:** Transitions forward as each phase completes. Never moves backward.
- **Cancel behavior:** When `phase == "planning"` and cancel is invoked, the spec directory at `specPath` is deleted along with the state file.

#### `mode`
- **Type:** `string` (enum: `"sequential"`, `"swarm"`)
- **Default:** `"sequential"`
- **Description:** Execution strategy.
  - `"sequential"` — The lead agent executes tasks one by one, no teammates.
  - `"swarm"` — Agent Teams is used; multiple teammates execute tasks in parallel.
- **Updated:** Set during planning based on user flags or auto-detection. Does not change once execution starts.

#### `pausedAfter`
- **Type:** `string | null` (enum: `null`, `"research"`, `"requirements"`, `"design"`, `"tasks"`)
- **Default:** `null`
- **Description:** Indicates which planning phase just completed, causing the session to pause for user review. When set (non-null) and `phase == "planning"`, the stop hook allows the session to exit instead of blocking. This enables the incremental planning flow where each phase is a separate command.
  - `null` — Planning is actively running (not paused between phases).
  - `"research"` — Research phase completed. Next command: `/ralph-swarm:requirements`.
  - `"requirements"` — Requirements phase completed. Next command: `/ralph-swarm:design`.
  - `"design"` — Design phase completed. Next command: `/ralph-swarm:tasks`.
  - `"tasks"` — Task breakdown completed. Next command: `/ralph-swarm:go`.
- **Updated:** Set after each planning phase completes (unless `--full` flag runs all phases at once). Reset to `null` when the next phase begins.
- **Lifecycle:** Created as `null` during initialization. Set to a phase name after that phase completes and the session should pause. The next phase skill resets it to `null` before starting work, then sets it to its own phase name on completion.

### `planning` Object

Tracks the progress of each planning sub-phase. All four sub-phases must reach `"complete"` before the session transitions to `"planning-review"`.

#### `planning.research`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`, `"failed"`)
- **Default:** `"pending"`
- **Description:** Status of the research phase — analyzing the codebase, understanding existing architecture, identifying relevant files and patterns.
- **Updated:** Set to `"in-progress"` when research begins, `"complete"` when the research document is written to the spec directory.
  - `"failed"` — The agent for this phase encountered an error. The session cannot proceed until the user intervenes (cancel and restart, or manually fix the spec file).

#### `planning.requirements`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`, `"failed"`)
- **Default:** `"pending"`
- **Description:** Status of requirements generation — translating the user's goal into concrete, testable requirements.
- **Updated:** Set to `"in-progress"` when requirements analysis begins, `"complete"` when the requirements document is finalized.
  - `"failed"` — The agent for this phase encountered an error. The session cannot proceed until the user intervenes (cancel and restart, or manually fix the spec file).

#### `planning.design`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`, `"failed"`)
- **Default:** `"pending"`
- **Description:** Status of the design phase — architectural decisions, file-level plan, interface definitions.
- **Updated:** Set to `"in-progress"` when design work begins, `"complete"` when the design document is written.
  - `"failed"` — The agent for this phase encountered an error. The session cannot proceed until the user intervenes (cancel and restart, or manually fix the spec file).

#### `planning.tasks`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`, `"failed"`)
- **Default:** `"pending"`
- **Description:** Status of task breakdown — converting the design into vertical feature slice tasks in `tasks.md`. Each task is a complete feature slice with an explicit file list for runtime parallelism computation.
- **Updated:** Set to `"in-progress"` when task breakdown begins, `"complete"` when `tasks.md` is finalized.
  - `"failed"` — The agent for this phase encountered an error. The session cannot proceed until the user intervenes (cancel and restart, or manually fix the spec file).

### `execution` Object

Tracks the state of task execution. Used by both sequential and swarm modes, though some fields are mode-specific.

#### `execution.snapshotCommit`
- **Type:** `string`
- **Default:** `""` (empty string)
- **Description:** The git commit hash (`git rev-parse HEAD`) recorded before the first task executes. This is the rollback point — if `/ralph-swarm:rollback` is used, all changes are reset to this commit. Enables safe recovery from execution gone wrong.
- **Updated:** Set once at the start of execution, before the first task runs. Never changed after that.

#### `execution.swarm`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** Whether Agent Teams (swarm mode) is active. When `true`, the coordinator spawns teammates and delegates work. When `false`, the lead agent does everything itself.
- **Updated:** Set once when execution begins, based on `mode`.

#### `execution.teamCreated`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** Whether TeamCreate was actually called to create an Agent Team. Set to `true` immediately after a successful `TeamCreate` call — before any other swarm action (task creation, teammate spawning, etc.). This field exists to prevent the AI from bypassing TeamCreate by using Task tool subagents with `run_in_background` instead.
- **Updated:** Set to `true` once after TeamCreate succeeds. Never set to `true` without actually calling TeamCreate.
- **Stop hook enforcement:** The stop hook (`swarm-watcher.sh`) checks this field when `execution.swarm` is `true`. If `teamCreated` is `false`, the hook blocks exit and demands the AI call TeamCreate. This is a hard enforcement — there is no workaround.

#### `execution.teammates`
- **Type:** `number`
- **Default:** `0`
- **Description:** Number of teammates spawned. Always `0` in sequential mode. In swarm mode, set to the computed teammate count (see team-composition skill).
- **Updated:** Set when teammates are spawned. Does not change mid-execution (teammates are not added or removed dynamically).

#### `execution.agentType`
- **Type:** `string`
- **Default:** `"auto"`
- **Description:** The agent type used for teammates. Either an explicit type (e.g., `"golang-pro"`, `"typescript-pro"`) or `"auto"` if auto-detected.
- **Updated:** Set once during team composition analysis. After teammates are spawned, this reflects the resolved type, not `"auto"`.

#### `execution.taskIndex`
- **Type:** `number`
- **Default:** `0`
- **Description:** The index of the current task being executed. **Sequential mode only.** In swarm mode, this field is not used (tasks are tracked via `completedTasks`, `failedTasks`, and `batches` instead).
- **Updated:** Incremented after each task completes (or fails and is skipped) in sequential mode.

#### `execution.totalTasks`
- **Type:** `number`
- **Default:** `0`
- **Description:** Total number of tasks in `tasks.md`.
- **Updated:** Set once after parsing `tasks.md`. If fix tasks are created during execution, this count is incremented.

#### `execution.completedTasks`
- **Type:** `number[]` (array of task indices)
- **Default:** `[]`
- **Description:** Indices of tasks that have been completed and verified. Used in both sequential and swarm modes.
- **Updated:** A task index is appended after the task passes verification.

#### `execution.failedTasks`
- **Type:** `number[]` (array of task indices)
- **Default:** `[]`
- **Description:** Indices of tasks that failed after exhausting retries (3 attempts in swarm mode). These tasks are skipped.
- **Updated:** A task index is appended when a task hits the retry limit and is abandoned.

#### `execution.batches`
- **Type:** `string[][]` (array of arrays of TASK-IDs)
- **Default:** `[]`
- **Description:** Computed parallel execution batches. **Swarm mode only.** Each inner array contains TASK-IDs that can run simultaneously (no file conflicts, all dependencies satisfied). Computed at runtime by the coordinator from the File Manifest in tasks.md using the file-conflict graph algorithm.
- **Updated:** Set once when execution begins, after the coordinator parses `tasks.md` and computes the conflict graph.
- **Example:** `[["TASK-001"], ["TASK-002", "TASK-003"], ["TASK-004"], ["TASK-005"]]`

#### `execution.currentBatch`
- **Type:** `number`
- **Default:** `0`
- **Description:** Index into the `batches` array indicating which batch is currently being executed. **Swarm mode only.** Batch 0 is the first batch.
- **Updated:** Incremented when all tasks in the current batch are completed or failed, and the coordinator advances to the next batch.

#### `execution.iteration`
- **Type:** `number`
- **Default:** `0`
- **Description:** The current monitoring loop iteration. Incremented each time the coordinator runs a monitoring cycle (check TaskList, verify completions, assign new tasks).
- **Updated:** Incremented on each monitoring cycle. Used as a safety metric — if `iteration` exceeds `maxIterations`, the swarm is force-stopped.

#### `execution.maxIterations`
- **Type:** `number`
- **Default:** `30`
- **Description:** Safety cap on the number of monitoring iterations. Prevents runaway sessions that burn tokens indefinitely. If `iteration >= maxIterations`, the coordinator stops execution, marks remaining tasks as failed, and transitions to `phase: "complete"`.
- **Updated:** Set once during initialization. Can be overridden by `--max-iterations` flag.

#### `execution.tasks`
- **Type:** `object[]` (array of task objects)
- **Default:** `[]`
- **Description:** Parsed task list from `tasks.md`. Each object represents a task with its current execution status. Populated when the session transitions to the `"execution"` phase.
- **Object shape:**
  ```json
  {"id": 1, "title": "Task title", "status": "pending", "dependsOn": []}
  ```
  - `id` (`number`): Task number (1-based, derived from TASK-NNN identifiers).
  - `title` (`string`): The feature slice title from tasks.md.
  - `status` (`string`, enum: `"pending"`, `"in-progress"`, `"completed"`, `"failed"`): Current execution status.
  - `dependsOn` (`number[]`): Array of task IDs that must complete before this task can start.
- **Updated:** Populated once when execution begins. Individual task `status` fields are updated as tasks complete or fail.

### `flags` Object

Configuration flags parsed from CLI arguments that modify coordinator behavior.

#### `flags.swarm`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** When `true`, enables parallelism in both planning (multiple focused agents per phase) and execution (Agent Teams with parallel worktrees). When `false`, all planning and execution is single-agent sequential.
- **Updated:** Set once from CLI flags during initialization.

#### `flags.yolo`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** When `true`, skip the `"planning-review"` phase entirely. Go directly from `"planning"` to `"execution"` without waiting for user approval. Useful for trusted, well-defined goals where human review is unnecessary. Implies `--full`.
- **Updated:** Set once from CLI flags during initialization.

#### `flags.full`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** When `true`, run all four planning phases (research, requirements, design, tasks) in a single `/ralph-swarm:start` invocation without pausing between phases. This is the legacy behavior. When `false` (default), `/ralph-swarm:start` runs only the research phase and pauses, requiring separate commands (`/ralph-swarm:requirements`, `/ralph-swarm:design`, `/ralph-swarm:tasks`) for each subsequent phase. `--yolo` implies `--full`.
- **Updated:** Set once from CLI flags during initialization.

#### `flags.commit`
- **Type:** `boolean`
- **Default:** `true`
- **Description:** When `true`, commit spec files after planning and commit each completed task during execution. When `false`, changes are written but not committed. Overridden by `--no-commit`.
- **Updated:** Set once from CLI flags during initialization.

#### `flags.teammates`
- **Type:** `number | "auto"`
- **Default:** `"auto"`
- **Description:** Number of teammates to spawn in swarm mode. When `"auto"`, the coordinator computes the optimal count from the largest parallel batch (capped at 4, minimum 2). When a number, that exact count is used (capped at 10).
- **Updated:** Set once from CLI flags during initialization.

#### `flags.agentType`
- **Type:** `string`
- **Default:** `"auto"`
- **Description:** Agent type to use for swarm teammates. When `"auto"`, the coordinator auto-detects from the project's dominant language (see team-composition skill). When an explicit type (e.g., `"golang-pro"`), all teammates use that type.
- **Updated:** Set once from CLI flags during initialization.

### Additional Top-Level Fields

#### `specPath`
- **Type:** `string`
- **Default:** Resolved as absolute path: `"$(pwd)/specs/<name>/"` at initialization time.
- **Description:** Absolute path to the directory where spec documents are stored. Always stored as an absolute path for worktree compatibility — teammates in isolated worktrees cannot resolve relative paths back to the main working tree.
- **Updated:** Set once during initialization. Can be overridden by user configuration.

#### `teamName`
- **Type:** `string`
- **Default:** Derived from `name` (e.g., `"ralph-add-user-auth"`).
- **Description:** The Agent Teams team name used with `TeamCreate`. Only relevant in swarm mode. In sequential mode, this field is empty or unused.
- **Updated:** Set once during team creation. Used throughout execution for `TaskCreate`, `TaskList`, `TaskUpdate`, and `SendMessage` calls.

## Lifecycle

```
Initialization:
  name, goal, phase="planning", pausedAfter=null, mode, flags set

Planning (incremental, default):
  /start: research runs -> pausedAfter="research" -> session exits
  /requirements: requirements runs -> pausedAfter="requirements" -> session exits
  /design: design runs -> pausedAfter="design" -> session exits
  /tasks: tasks runs -> phase="planning-review", pausedAfter="tasks" -> session exits

Planning (--full or --yolo):
  All four planning.* fields transition: pending -> in-progress -> complete
  pausedAfter="tasks" after all complete
  phase transitions: "planning" -> "planning-complete"

Note: The incremental path skips "planning-complete" because /ralph-swarm:tasks
(the final phase skill) transitions directly to "planning-review". The "planning-complete"
intermediate state only exists in the --full path, where start/SKILL.md needs a brief
state between finishing all planning and deciding the next step (review vs execution).

Review (skipped if flags.yolo):
  If --yolo: phase transitions: "planning-complete" -> "execution"
  If not --yolo: "planning-complete" -> "planning-review"
  User approves/rejects
  phase transitions: "planning-review" -> "execution"

Execution:
  execution.* fields updated continuously
  completedTasks/failedTasks arrays grow
  iteration increments

Completion:
  phase transitions: "execution" -> "complete"
  Final state written to disk
```

## Resumability

If a session crashes or is interrupted, the state file allows the coordinator to resume:

1. Read `.ralph-swarm-state.json`.
2. Check `phase` to determine where we left off.
3. If `phase == "execution"`: compare `completedTasks` + `failedTasks` against `totalTasks` to find remaining work. In swarm mode, check `currentBatch` to determine which batch to resume from.
4. Re-create the team (if swarm mode) and assign remaining tasks from the current batch onward.
5. Continue the monitoring loop from `iteration`.
