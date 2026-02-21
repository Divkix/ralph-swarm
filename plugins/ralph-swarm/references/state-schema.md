# State Schema Reference

The `.ralph-swarm-state.json` file is the single source of truth for a ralph-swarm session. It tracks the current phase, planning progress, execution state, and configuration flags. The file lives at the project root and is read/written by the coordinator throughout the session lifecycle.

## Full Schema

```json
{
  "name": "string",
  "goal": "string",
  "phase": "string",
  "mode": "string",
  "planning": {
    "research": "string",
    "requirements": "string",
    "design": "string",
    "tasks": "string"
  },
  "execution": {
    "swarm": "boolean",
    "teammates": "number",
    "agentType": "string",
    "taskIndex": "number",
    "totalTasks": "number",
    "completedTasks": "number[]",
    "failedTasks": "number[]",
    "iteration": "number",
    "maxIterations": "number"
  },
  "flags": {
    "yolo": "boolean",
    "commitSpec": "boolean"
  },
  "specPath": "string",
  "teamName": "string"
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
- **Type:** `string` (enum: `"planning"`, `"planning-review"`, `"execution"`, `"complete"`)
- **Default:** `"planning"`
- **Description:** The current high-level phase of the session.
  - `"planning"` — The coordinator is generating specs: research, requirements, design, and tasks.
  - `"planning-review"` — Planning is done, waiting for user review/approval before execution.
  - `"execution"` — Tasks are being executed (either sequentially or via swarm).
  - `"complete"` — All tasks finished and verified. Terminal state.
- **Updated:** Transitions forward as each phase completes. Never moves backward.

#### `mode`
- **Type:** `string` (enum: `"sequential"`, `"swarm"`)
- **Default:** `"sequential"`
- **Description:** Execution strategy.
  - `"sequential"` — The lead agent executes tasks one by one, no teammates.
  - `"swarm"` — Agent Teams is used; multiple teammates execute tasks in parallel.
- **Updated:** Set during planning based on user flags or auto-detection. Does not change once execution starts.

### `planning` Object

Tracks the progress of each planning sub-phase. All four sub-phases must reach `"complete"` before the session transitions to `"planning-review"`.

#### `planning.research`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`)
- **Default:** `"pending"`
- **Description:** Status of the research phase — analyzing the codebase, understanding existing architecture, identifying relevant files and patterns.
- **Updated:** Set to `"in-progress"` when research begins, `"complete"` when the research document is written to the spec directory.

#### `planning.requirements`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`)
- **Default:** `"pending"`
- **Description:** Status of requirements generation — translating the user's goal into concrete, testable requirements.
- **Updated:** Set to `"in-progress"` when requirements analysis begins, `"complete"` when the requirements document is finalized.

#### `planning.design`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`)
- **Default:** `"pending"`
- **Description:** Status of the design phase — architectural decisions, file-level plan, interface definitions.
- **Updated:** Set to `"in-progress"` when design work begins, `"complete"` when the design document is written.

#### `planning.tasks`
- **Type:** `string` (enum: `"pending"`, `"in-progress"`, `"complete"`)
- **Default:** `"pending"`
- **Description:** Status of task breakdown — converting the design into phased, assignable tasks in `tasks.md`.
- **Updated:** Set to `"in-progress"` when task breakdown begins, `"complete"` when `tasks.md` is finalized.

### `execution` Object

Tracks the state of task execution. Used by both sequential and swarm modes, though some fields are mode-specific.

#### `execution.swarm`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** Whether Agent Teams (swarm mode) is active. When `true`, the coordinator spawns teammates and delegates work. When `false`, the lead agent does everything itself.
- **Updated:** Set once when execution begins, based on `mode`.

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
- **Description:** The index of the current task being executed. **Sequential mode only.** In swarm mode, this field is not used (tasks are tracked via `completedTasks` and `failedTasks` instead).
- **Updated:** Incremented after each task completes (or fails and is skipped) in sequential mode.

#### `execution.totalTasks`
- **Type:** `number`
- **Default:** `0`
- **Description:** Total number of tasks across all phases in `tasks.md`.
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

#### `execution.iteration`
- **Type:** `number`
- **Default:** `0`
- **Description:** The current monitoring loop iteration. Incremented each time the coordinator runs a monitoring cycle (check TaskList, verify completions, assign new tasks).
- **Updated:** Incremented on each monitoring cycle. Used as a safety metric — if `iteration` exceeds `maxIterations`, the swarm is force-stopped.

#### `execution.maxIterations`
- **Type:** `number`
- **Default:** `100`
- **Description:** Safety cap on the number of monitoring iterations. Prevents runaway sessions that burn tokens indefinitely. If `iteration >= maxIterations`, the coordinator stops execution, marks remaining tasks as failed, and transitions to `phase: "complete"`.
- **Updated:** Set once during initialization. Can be overridden by user flags.

### `flags` Object

Boolean configuration flags that modify coordinator behavior.

#### `flags.yolo`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** When `true`, skip the `"planning-review"` phase entirely. Go directly from `"planning"` to `"execution"` without waiting for user approval. Useful for trusted, well-defined goals where human review is unnecessary.
- **Updated:** Set once from CLI flags during initialization.

#### `flags.commitSpec`
- **Type:** `boolean`
- **Default:** `false`
- **Description:** When `true`, the spec directory (research, requirements, design, tasks.md) is committed to git after planning completes. When `false`, specs are written but not committed.
- **Updated:** Set once from CLI flags during initialization.

### Additional Top-Level Fields

#### `specPath`
- **Type:** `string`
- **Default:** `"specs/"` (relative to project root)
- **Description:** Path to the directory where spec documents are stored. The actual spec files live in `<specPath>/<name>/` (e.g., `specs/add-user-auth/`).
- **Updated:** Set once during initialization. Can be overridden by user configuration.

#### `teamName`
- **Type:** `string`
- **Default:** Derived from `name` (e.g., `"ralph-add-user-auth"`).
- **Description:** The Agent Teams team name used with `TeamCreate`. Only relevant in swarm mode. In sequential mode, this field is empty or unused.
- **Updated:** Set once during team creation. Used throughout execution for `TaskCreate`, `TaskList`, `TaskUpdate`, and `SendMessage` calls.

## Lifecycle

```
Initialization:
  name, goal, phase="planning", mode, flags set

Planning:
  planning.* fields transition: pending -> in-progress -> complete
  phase transitions: "planning" -> "planning-review"

Review (skipped if flags.yolo):
  User approves/rejects
  phase transitions: "planning-review" -> "execution" (or back to "planning")

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
3. If `phase == "execution"`: compare `completedTasks` + `failedTasks` against `totalTasks` to find remaining work.
4. Re-create the team (if swarm mode) and assign remaining tasks.
5. Continue the monitoring loop from `iteration`.
