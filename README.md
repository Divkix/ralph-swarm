# ralph-swarm

A Claude Code plugin that chains spec-driven planning with persistent execution. Supports sequential task execution out of the box and parallel execution via Agent Teams when you need multiple agents working simultaneously.

One command. Full spec. Then build.

## What It Does

ralph-swarm splits development into two distinct phases:

1. **Planning Phase** -- Researches the codebase, gathers requirements, produces an architectural design, and breaks the work into discrete tasks with dependencies. The output is a structured spec, not code.
2. **Execution Phase** -- Takes the spec and builds it. Either sequentially (one task at a time, default) or in parallel via Agent Teams (multiple agents working concurrently on independent tasks).

The planning phase is deterministic and thorough. The execution phase is where the actual file changes happen. By default, you review the spec before execution begins. Pass `--yolo` to skip the review and go straight to building.

## Installation

Install as a Claude Code plugin:

```bash
claude plugin add github:Divkix/ralph-swarm
```

Or clone and install locally:

```bash
git clone https://github.com/Divkix/ralph-swarm.git
claude plugin add /path/to/ralph-swarm
```

## Quick Start

### Sequential execution with review

```
/ralph-swarm:start "Build an authentication system with JWT tokens and refresh flow"
```

Plans the work, shows you the spec, waits for approval, then executes tasks one at a time.

### Parallel execution with Agent Teams

```
/ralph-swarm:start "Build an authentication system with JWT tokens and refresh flow" --swarm
```

Same planning phase, but execution spawns an Agent Teams swarm. Independent tasks run in parallel across multiple agents. Dependent tasks wait for their blockers to complete.

### Full autopilot

```
/ralph-swarm:start "Build an authentication system with JWT tokens and refresh flow" --swarm --yolo
```

Plans, skips the review step, and immediately begins parallel execution. No human in the loop until it finishes or hits a blocker it cannot resolve.

## Commands

| Command | Description |
|---|---|
| `start` | Begin a new planning + execution session. Takes a task description and optional flags. |
| `go` | Resume execution after reviewing a spec. Use this after `start` produces a plan and you approve it. |
| `status` | Show current session state: planning progress, task completion, agent activity. |
| `cancel` | Abort the current session. Shuts down any running agents and cleans up the task list. |
| `help` | Print usage information and available flags. |

## Flags

| Flag | Default | Description |
|---|---|---|
| `--swarm` | `false` | Enable parallel execution via Agent Teams. Without this flag, tasks execute sequentially. |
| `--yolo` | `false` | Skip the spec review step. Planning completes and execution begins immediately. |
| `--teammates N` | `3` | Number of teammate agents to spawn in swarm mode. Ignored without `--swarm`. |
| `--agent-type TYPE` | `code` | Agent type for spawned teammates. Determines tool access (e.g., `code`, `read-only`). Ignored without `--swarm`. |
| `--max-iterations N` | `50` | Maximum task iterations before the session auto-stops. Safety limit to prevent runaway execution. |
| `--commit` | `true` | Create git commits after completing each task (or group of tasks in swarm mode). |
| `--no-commit` | `false` | Disable automatic git commits. Changes are left unstaged. |

## How It Works

### Planning Phase

The planning phase runs four sub-phases in sequence:

1. **Research** -- Reads the codebase structure, existing patterns, dependencies, and conventions. Builds a context map of what exists and what the task description implies.
2. **Requirements** -- Extracts explicit and implicit requirements from the task description. Identifies constraints, edge cases, and acceptance criteria.
3. **Design** -- Produces an architectural design: which files to create or modify, data flow, API contracts, error handling strategy. References existing codebase patterns.
4. **Tasks** -- Breaks the design into discrete, ordered tasks with dependency declarations. Each task has a clear scope, input, output, and definition of done.

The output is a structured spec document. In default mode, execution pauses here for your review.

### Execution Phase

**Sequential mode (default):**
Tasks execute one at a time in dependency order. Each task completes fully before the next begins. Straightforward and predictable.

**Swarm mode (`--swarm`):**
A team is created via Agent Teams. Tasks are loaded into a shared task list. The lead agent assigns independent tasks to teammates. Tasks with unmet dependencies remain blocked until their prerequisites complete. Teammates work in parallel, report back, and pick up the next available task.

### Flow Diagram

```
  User runs /ralph-swarm:start "task description" [flags]
                          |
                          v
                  +---------------+
                  |   PLANNING    |
                  +---------------+
                  | 1. Research   |
                  | 2. Require    |
                  | 3. Design     |
                  | 4. Tasks      |
                  +-------+-------+
                          |
                          v
                  +---------------+
                  |  --yolo set?  |
                  +-------+-------+
                    |           |
                   yes          no
                    |           |
                    |           v
                    |   +---------------+
                    |   | REVIEW SPEC   |
                    |   | (user views   |
                    |   |  and approves)|
                    |   +-------+-------+
                    |           |
                    |    /ralph-swarm:go
                    |           |
                    +-----+-----+
                          |
                          v
                  +---------------+
                  | --swarm set?  |
                  +-------+-------+
                    |           |
                   yes          no
                    |           |
                    v           v
            +-----------+  +-----------+
            |  PARALLEL |  |SEQUENTIAL |
            | EXECUTION |  | EXECUTION |
            +-----------+  +-----------+
            | TeamCreate |  | For each  |
            | TaskCreate |  | task in   |
            | Spawn N    |  | order:    |
            | teammates  |  |  execute  |
            | Assign &   |  |  commit   |
            | coordinate |  |  next     |
            +-----------+  +-----------+
                    |           |
                    +-----+-----+
                          |
                          v
                  +---------------+
                  |   COMPLETE    |
                  | Summary +     |
                  | final commit  |
                  +---------------+
```

## Requirements

- **Claude Code 1.0.34+** -- Plugin system support.
- **CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1** -- Required environment variable for `--swarm` mode. Agent Teams is an experimental feature. Set this in your shell before launching Claude Code:
  ```bash
  export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  ```
  Without this variable, `--swarm` will fail with an error. Sequential mode works without it.
- **No external plugin dependencies.** ralph-swarm uses only built-in Claude Code tools (TaskCreate, TaskUpdate, TaskList, TeamCreate, SendMessage, etc.). Nothing to install beyond the plugin itself.

## License

MIT. See [LICENSE](LICENSE).
