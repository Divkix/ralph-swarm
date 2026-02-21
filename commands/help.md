---
description: Show ralph-swarm plugin help and available commands
argument-hint: ""
allowed-tools: []
---

# ralph-swarm:help

Display the following help text exactly as written (adjusting formatting for readability):

```
===============================================================================
                          ralph-swarm Plugin Help
===============================================================================

DESCRIPTION
  ralph-swarm orchestrates multi-phase planning and execution of development
  tasks. It breaks a goal into research, requirements, design, and tasks,
  then executes them either sequentially or in parallel using Agent Teams.

COMMANDS

  /ralph-swarm:start <"goal"> [flags]
    The main entry point. Provide a goal in quotes and optional flags.
    Planning runs automatically. Execution starts after review (or
    immediately with --yolo).

    Examples:
      /ralph-swarm:start "add user authentication with JWT"
      /ralph-swarm:start "refactor database layer" --swarm --teammates 4
      /ralph-swarm:start "fix pagination bug" --yolo
      /ralph-swarm:start "migrate to new API" --swarm --yolo --no-commit

  /ralph-swarm:go
    Resume execution after reviewing the generated plan. Only works when
    phase is "planning-review". Edit spec files before running this if
    you want to adjust the plan.

    Example:
      /ralph-swarm:go

  /ralph-swarm:status
    Show current swarm progress including planning phases, task completion,
    iteration count, and teammate status (in swarm mode).

    Example:
      /ralph-swarm:status

  /ralph-swarm:cancel
    Cancel the active swarm, shut down teammates, and remove state file.
    Spec files and any code changes are preserved.

    Example:
      /ralph-swarm:cancel

  /ralph-swarm:help
    Show this help text.

FLAGS (for /ralph-swarm:start)

  --swarm              Enable parallel execution with Agent Teams.
                       Default: false (sequential mode)

  --yolo               Skip the planning review pause and go straight
                       to execution. Also sets --no-commit by default.
                       Default: false

  --teammates <N>      Number of parallel agents in swarm mode.
                       Default: "auto" (min of task count and 5, at least 2)
                       Max: 10

  --agent-type <TYPE>  Agent type for executor teammates.
                       Default: "auto" (uses swarm-executor)

  --max-iterations <N> Maximum stop-hook re-injection cycles before
                       the swarm auto-terminates.
                       Default: 30

  --commit             Commit changes after each task (sequential) or
                       after all tasks (swarm). Default: true

  --no-commit          Do not commit changes. Overrides --commit.
                       Default when --yolo is set.

EXECUTION MODES

  Sequential (default):
    Tasks are executed one at a time in dependency order. The lead agent
    delegates each task to a swarm-executor agent, waits for completion,
    then moves to the next. The stop hook re-injects the lead after each
    task to continue the loop.

  Swarm (--swarm):
    Tasks are executed in parallel using Claude Code Agent Teams. The lead
    creates a team, spawns executor teammates, distributes tasks respecting
    dependencies, and monitors progress. Multiple tasks run simultaneously
    when their dependencies are satisfied.

FLOW DIAGRAM

  /ralph-swarm:start "goal"
         |
         v
  +------------------+
  |  Parse Arguments |
  +------------------+
         |
         v
  +------------------+     +------------------+
  |    Research       | --> |   Requirements   |
  |  (swarm-researcher)    | (swarm-requirements)
  +------------------+     +------------------+
         |                        |
         v                        v
  +------------------+     +------------------+
  |     Design       | <-- |                  |
  |  (swarm-architect)     |                  |
  +------------------+     +------------------+
         |
         v
  +------------------+
  |   Task Planner   |
  | (swarm-task-planner)
  +------------------+
         |
         v
  +------------------+
  | Planning Review  |  <-- user reviews spec files
  +------------------+
         |
         v  (/ralph-swarm:go or --yolo)
         |
    +----+----+
    |         |
    v         v
  Sequential  Swarm
  (one agent) (team of agents)
    |         |
    v         v
  +------------------+
  |  Tasks Execute   |
  |  (stop hook loop)|
  +------------------+
         |
         v
  <promise>SWARM COMPLETE</promise>

STATE FILE

  .ralph-swarm-state.json in the project root tracks all swarm state.
  The stop hook (swarm-watcher.sh) reads this file to decide whether
  to re-inject the lead agent or allow the session to exit.

  Phases: planning -> planning-review -> execution -> (complete/removed)

SPEC FILES

  ./specs/<name>/research.md       - Codebase and external research
  ./specs/<name>/requirements.md   - Functional and non-functional requirements
  ./specs/<name>/design.md         - Architecture and implementation design
  ./specs/<name>/tasks.md          - Ordered, dependency-aware task breakdown

  These files are never deleted by /ralph-swarm:cancel. They persist for
  reuse or reference.

REQUIREMENTS

  - Claude Code with plugin support
  - For swarm mode: Agent Teams support (CLAUDE_AGENT_TEAMS=1 if required
    by your Claude Code version)
  - The following agent types should be available:
    - swarm-researcher (required, included with plugin)
    - swarm-requirements (optional, falls back to general-purpose)
    - swarm-architect (optional, falls back to general-purpose)
    - swarm-task-planner (optional, falls back to general-purpose)
    - swarm-executor (optional, falls back to general-purpose)

TIPS

  - Start without --swarm first to validate the approach, then re-run
    with --swarm for speed on larger tasks.
  - Review and edit spec files during the planning-review pause. The
    execution phase uses them as the source of truth.
  - Use /ralph-swarm:status frequently during long executions to monitor
    progress.
  - If a swarm gets stuck, /ralph-swarm:cancel is safe — it preserves
    all code changes and spec files.
  - The --max-iterations flag prevents runaway loops. Increase it for
    very large task lists (default 30 is usually enough for 10-15 tasks).
===============================================================================
```
