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
    By default, runs only the research phase and pauses for review.
    Use --full to run all 4 planning phases at once (legacy behavior).
    Use --yolo for --full + skip review + execute immediately.

    Examples:
      /ralph-swarm:start "add user authentication with JWT"
      /ralph-swarm:start "refactor database layer" --full --swarm
      /ralph-swarm:start "fix pagination bug" --yolo
      /ralph-swarm:start "migrate to new API" --full --swarm --yolo --no-commit

  /ralph-swarm:requirements
    Run the requirements planning phase. Takes research output and
    produces detailed requirements. Only works after research is complete.

    Example:
      /ralph-swarm:requirements

  /ralph-swarm:design
    Run the architecture/design planning phase. Takes research and
    requirements output and produces an architecture document. Only
    works after requirements are complete.

    Example:
      /ralph-swarm:design

  /ralph-swarm:tasks
    Run the task breakdown planning phase. Takes all prior spec files
    and produces vertical feature slice tasks. Only works after design
    is complete. Transitions to planning-review when done.

    Example:
      /ralph-swarm:tasks

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
    Cancel the active swarm, shut down teammates, remove state file,
    and clean up orphaned worktrees. Spec files and code changes are
    preserved.

    Example:
      /ralph-swarm:cancel

  /ralph-swarm:rollback
    Roll back ALL execution changes to the pre-execution snapshot
    commit. This is DESTRUCTIVE — all code from task execution is
    lost. Spec files are preserved only if they were committed before
    execution. Requires user confirmation.

    Example:
      /ralph-swarm:rollback

  /ralph-swarm:help
    Show this help text.

FLAGS (for /ralph-swarm:start)

  --full               Run all 4 planning phases (research, requirements,
                       design, tasks) in one shot without pausing between
                       phases. Without this flag, /start only runs research
                       and pauses for review.
                       Default: false

  --swarm              Enable parallel execution with Agent Teams.
                       Default: false (sequential mode)

  --yolo               Skip the planning review pause and go straight
                       to execution. Implies --full. Commit behavior is
                       unchanged (--commit remains true by default).
                       Default: false

  --teammates <N>      Number of parallel agents in swarm mode.
                       Only effective with --swarm.
                       Default: "auto" (min of largest batch size and 4, at least 2)
                       Max: 10

  --agent-type <TYPE>  Agent type for executor teammates.
                       Only effective with --swarm.
                       Default: "auto" (uses swarm-executor)

  --max-iterations <N> Maximum stop-hook re-injection cycles before
                       the swarm auto-terminates.
                       Default: 30

  --commit             Commit changes after each task (sequential) or
                       after all tasks (swarm). Default: true

  --no-commit          Do not commit changes. Overrides --commit.

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

  Incremental (default):

  /ralph-swarm:start "goal"
         |
         v
  +------------------+
  |  Parse Arguments |
  +------------------+
         |
         v
  +------------------+
  |    Research       |  <-- pauses here (pausedAfter: "research")
  |  (swarm-researcher)
  +------------------+
         |  /ralph-swarm:requirements
         v
  +------------------+
  |   Requirements   |  <-- pauses here (pausedAfter: "requirements")
  | (swarm-requirements)
  +------------------+
         |  /ralph-swarm:design
         v
  +------------------+
  |     Design       |  <-- pauses here (pausedAfter: "design")
  |  (swarm-architect)
  +------------------+
         |  /ralph-swarm:tasks
         v
  +------------------+
  |   Task Planner   |  <-- pauses here (planning-review)
  | (swarm-task-planner)
  +------------------+
         |  /ralph-swarm:go
         v
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

  Full (--full or --yolo):

  /ralph-swarm:start "goal" --full
         |
         v
  All 4 phases run in sequence (no pauses)
         |
         v
  Planning Review (or --yolo skips to execution)
         |
         v
  Execution (same as above)

STATE FILE

  .ralph-swarm-state.json in the project root tracks all swarm state.
  The stop hook (swarm-watcher.sh) reads this file to decide whether
  to re-inject the lead agent or allow the session to exit.

  Phases: planning (with pauses) -> planning-review -> execution -> (complete/removed)

SPEC FILES

  ./specs/<name>/research.md       - Codebase and external research
  ./specs/<name>/requirements.md   - Functional and non-functional requirements
  ./specs/<name>/design.md         - Architecture and implementation design
  ./specs/<name>/tasks.md          - Ordered, dependency-aware task breakdown

  These files are never deleted by /ralph-swarm:cancel. They persist for
  reuse or reference.

REQUIREMENTS

  - Claude Code with plugin support
  - For swarm mode: Agent Teams support (TeamCreate tool must be available).
    The /ralph-swarm:start command validates this automatically when --swarm
    is used.
  - The following agent types should be available:
    - swarm-researcher (required, included with plugin)
    - swarm-requirements (optional, falls back to general-purpose)
    - swarm-architect (optional, falls back to general-purpose)
    - swarm-task-planner (optional, falls back to general-purpose)
    - swarm-executor (optional, falls back to general-purpose)

TIPS

  - By default, /start only runs research and pauses. Review research.md
    before proceeding to /requirements. This catches bad research early.
  - Use --full if you trust the goal is well-defined and want speed.
  - Start without --swarm first to validate the approach, then re-run
    with --swarm for speed on larger tasks.
  - Review and edit spec files at each pause point. Each phase uses
    prior phases as input — fixing early saves cascading errors.
  - Re-running a phase (e.g., /requirements when already complete)
    will reset and delete all downstream phases.
  - Use /ralph-swarm:status frequently during long executions to monitor
    progress.
  - If a swarm gets stuck, /ralph-swarm:cancel is safe — it preserves
    all code changes and spec files.
  - The --max-iterations flag prevents runaway loops. Increase it for
    very large task lists (default 30 is usually enough for 10-15 tasks).
===============================================================================
```
