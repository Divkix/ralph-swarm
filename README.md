# ralph-swarm

### Spec-driven planning with parallel execution via Agent Teams

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Built%20for-Claude%20Code-blueviolet)](https://claude.ai/code)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

**One command. Full spec. Then build — sequentially or in parallel.**

> By default, each planning phase pauses for review. Use `--full` to run all phases at once.
>
> `Goal → Research → (pause) → Requirements → (pause) → Design → (pause) → Tasks → Execution`

---

## What Is This?

ralph-swarm is a Claude Code plugin that takes a development goal, breaks it into a structured spec (research, requirements, design, tasks), then executes each task — either one-at-a-time or in parallel using Agent Teams.

```text
You: "Add user authentication with JWT"
ralph-swarm: *researches codebase, writes requirements, designs architecture, breaks into tasks*
ralph-swarm: *executes each task with specialized agents*
ralph-swarm: SWARM COMPLETE
```

Two phases:

1. **Planning** — Four sequential sub-phases produce a full spec. No code is written.
2. **Execution** — Tasks from the spec are executed by specialized agents. Code is written here.

## Who It's For

- Teams or solo developers who want a repeatable planning workflow before coding
- Medium/large tasks where a written spec improves execution quality
- Repos with enough parallelizable work to benefit from Agent Teams + worktrees
- People who want a safer default (`review first`) with an opt-in autopilot path (`--yolo`)

## Not A Fit If

- You want a lightweight one-shot coding shortcut with minimal process
- The task is tiny (1-2 quick edits) and planning overhead will dominate
- The repo is highly coupled, making parallel execution mostly ineffective
- You do not want hook-driven state persistence / resumption behavior

---

## Installation

```bash
# Add the marketplace
/plugin marketplace add Divkix/ralph-swarm

# Install the plugin
/plugin install ralph-swarm@ralph-swarm

# Restart Claude Code
```

Note: ralph-swarm hook scripts require `jq` or `python3` to parse `.ralph-swarm-state.json` safely.

<details>
<summary>Alternative: local development</summary>

```bash
git clone https://github.com/Divkix/ralph-swarm.git
claude --plugin-dir ./ralph-swarm/plugins/ralph-swarm
```

</details>

---

## Quick Start

### Sequential with review (default)

```
/ralph-swarm:start "Build an authentication system with JWT tokens"
```

Runs the research phase and pauses. Continue with `/ralph-swarm:requirements`, `/ralph-swarm:design`, and `/ralph-swarm:tasks` (or use `--full` to run all phases at once), then review and execute.

### Parallel with review

```
/ralph-swarm:start "Build an authentication system with JWT tokens" --swarm
```

Same incremental planning flow (research first, then review/pause commands), but execution uses multiple agents working in parallel after `/ralph-swarm:go`.

### Full autopilot

```
/ralph-swarm:start "Build an authentication system with JWT tokens" --swarm --yolo
```

Plans, skips review, immediately fires up a team of agents. No human in the loop until it finishes.

---

## Commands

| Command | Description |
|---|---|
| `/ralph-swarm:start <"goal"> [flags]` | Begin planning + execution |
| `/ralph-swarm:requirements` | Run the requirements planning phase |
| `/ralph-swarm:design` | Run the design planning phase |
| `/ralph-swarm:tasks` | Run the task breakdown planning phase |
| `/ralph-swarm:go` | Resume execution after reviewing the spec |
| `/ralph-swarm:status` | Show current progress |
| `/ralph-swarm:cancel` | Abort the session, clean up state |
| `/ralph-swarm:rollback` | Reset to pre-execution state (destructive) |
| `/ralph-swarm:help` | Print usage and flags |

---

## Flags

| Flag | Default | Description |
|---|---|---|
| `--full` | `false` | Run all 4 planning phases in one shot without pausing |
| `--swarm` | `false` | Enable parallel planning (intra-phase) and parallel execution (Agent Teams) |
| `--yolo` | `false` | Skip spec review, go straight to execution |
| `--teammates N` | `auto` | Number of parallel agents (max 10). Auto = `min(task_count, 5)` |
| `--agent-type TYPE` | `auto` | Agent type for executors (e.g., `typescript-pro`, `golang-pro`) |
| `--max-iterations N` | `30` | Safety cap on execution loop iterations |
| `--commit` | `true` | Commit after each task (sequential) or after all tasks (swarm) |
| `--no-commit` | — | Disable auto-commits |

---

## How It Works

### Planning Phase

Planning consists of four sub-phases that run in strict order. Each delegates to a specialized agent:

| Phase | Agent | Output |
|---|---|---|
| Research | `swarm-researcher` | `specs/<name>/research.md` |
| Requirements | `swarm-requirements` | `specs/<name>/requirements.md` |
| Design | `swarm-architect` | `specs/<name>/design.md` |
| Tasks | `swarm-task-planner` | `specs/<name>/tasks.md` |

In the default incremental flow, `/ralph-swarm:start` runs **Research** and pauses; you continue with `/ralph-swarm:requirements`, `/ralph-swarm:design`, and `/ralph-swarm:tasks`. After all planning phases complete, you review the spec files (unless `--yolo` is set).

When `--swarm` is set, planning phases leverage intra-phase parallelism (see [Swarm (Parallel)](#swarm-parallel) for details).

### Execution Phase

**Sequential mode (default):**
Tasks execute one at a time in dependency order. The stop hook re-injects the lead agent after each task to continue the loop.

**Swarm mode (`--swarm`):**
An Agent Team is created. Independent tasks run in parallel across multiple agents in isolated worktrees. Dependent tasks wait for their blockers to complete.

When `--swarm` is set, planning phases also run in parallel: research spawns 3 focused agents (codebase structure, dependencies, testing patterns), requirements spawns 2 agents (functional, non-functional), and design spawns 2 agents (architecture, contracts). Each group runs concurrently within its phase, and the lead agent merges their outputs into the canonical spec file. Cross-phase ordering remains strictly sequential.

### Flow

```text
/ralph-swarm:start "goal" [flags]
       |
       v
  --full or --yolo?
   /            \
 no              yes
 |               |
 v               v
Research      Research -> Requirements -> Design -> Tasks
(pause)                |
  | /requirements      | --yolo set?
  v                    /          \
Requirements (pause) yes           no
  | /design           |             |
  v                   |     +-------v--------+
Design (pause)        |     |  REVIEW SPEC   |
  | /tasks            |     |  (edit files,  |
  v                   |     |  then /go)     |
Tasks (planning-review) |    +-------+--------+
  | /go               |             |
  +-------------------+------+------+
                             |
                        --swarm set?
                        /          \
                      yes           no
                       |             |
                       v             v
                   +---------+  +-----------+
                   | PARALLEL |  | SEQUENTIAL |
                   | N agents |  | 1 agent    |
                   | worktrees|  | in order   |
                   +---------+  +-----------+
                       |             |
                       +------+------+
                              |
                              v
                       SWARM COMPLETE
```

---

## Execution Modes In Detail

### Sequential

- Tasks run one at a time in dependency order.
- Each task is delegated to a `swarm-executor` agent.
- The stop hook (`swarm-watcher.sh`) blocks session exit and re-prompts the lead agent to pick up the next task.
- When all tasks finish, the lead outputs `<promise>SWARM COMPLETE</promise>` and the hook allows exit.

### Swarm (Parallel)

- A team is created via Agent Teams (`TeamCreate`).
- Tasks are loaded into a shared task list with dependency tracking.
- Teammates are spawned in isolated git worktrees (`isolation: "worktree"`).
- Independent tasks run simultaneously. Dependent tasks wait.
- The lead monitors, reassigns failed tasks, and merges completed work.
- 3-strike rule: if a task fails 3 times, it's marked failed and skipped.

### Key Patterns

| Pattern | Rule |
|---|---|
| Worktree Isolation | Teammates always get isolated worktrees |
| Task Granularity | 1-5 files per task, clear done criteria |
| Phase Dependencies | Phase N must complete before Phase N+1 starts |
| Verification Gates | Tests run after each task AND each phase |
| 3-Strike Failure | 3 retries per task, then mark failed |
| Cost Control | Prefer 3-4 teammates over many idle agents |
| Merge Strategy | Lead merges after verification, not teammates |

---

## State Management

### State File

`.ralph-swarm-state.json` in the project root tracks all session state:

- Current phase (`planning` → `planning-complete` → `planning-review` → `execution` → `complete`)
- Planning progress (which sub-phases are done)
- Execution progress (completed/failed tasks, iteration count)
- Configuration flags

The stop hook reads this file to decide whether to re-inject the agent or allow exit.

### Spec Files

Generated during planning at `./specs/<name>/`:

```text
./specs/<name>/
├── research.md       # Codebase patterns, dependencies, risks
├── requirements.md   # User stories, acceptance criteria, scope
├── design.md         # Architecture, data flow, API contracts
└── tasks.md          # Ordered tasks with dependencies
```

These files persist even after `/ralph-swarm:cancel`. They are the source of truth for execution.

See `skills/start/task-format.md` for the full task format specification.

### Hooks

| Hook | Script | Purpose |
|---|---|---|
| `SessionStart` | `load-context.sh` | Loads persisted state into the session on startup |
| `Stop` | `swarm-watcher.sh` | Blocks exit during execution, re-prompts the agent |

---

## Troubleshooting

**"A swarm is already active"**
A previous session left behind `.ralph-swarm-state.json`. Run `/ralph-swarm:cancel` to clean up, then start fresh.

**Task keeps failing after 3 retries**
The task is marked as failed and skipped. Check the spec files and the task description for ambiguity. Fix the spec, then re-run.

**Session exits during execution**
The stop hook should prevent this. Make sure `jq` or `python3` is installed so the hooks can parse `.ralph-swarm-state.json` safely. Check that `.ralph-swarm-state.json` exists and has `"phase": "execution"`.

**Swarm mode errors**
Agent Teams requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`:

```bash
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
```

Without this, `--swarm` will fail. Sequential mode works without it.

**Want to edit the plan before execution?**
That's the default. After planning completes, spec files are at `./specs/<name>/`. Edit them, then run `/ralph-swarm:go`.

**Resume after crash?**
The state file supports resumption. Just start a new session — the `SessionStart` hook loads the persisted state and shows you where things left off.

---

## Project Structure

```text
ralph-swarm/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/ralph-swarm/
    ├── .claude-plugin/plugin.json
    ├── agents/
    │   ├── swarm-researcher.md
    │   ├── swarm-requirements.md
    │   ├── swarm-architect.md
    │   ├── swarm-task-planner.md
    │   ├── swarm-executor.md
    │   └── swarm-verifier.md
    ├── hooks/
    │   ├── hooks.json
    │   └── scripts/
    │       ├── load-context.sh
    │       └── swarm-watcher.sh
    ├── references/
    │   ├── agent-team-patterns.md
    │   └── state-schema.md
    └── skills/
        ├── start/               ← /ralph-swarm:start
        │   ├── SKILL.md
        │   ├── execution-protocol.md
        │   └── task-format.md
        ├── requirements/SKILL.md ← /ralph-swarm:requirements
        ├── design/SKILL.md      ← /ralph-swarm:design
        ├── tasks/SKILL.md       ← /ralph-swarm:tasks
        ├── go/SKILL.md          ← /ralph-swarm:go
        ├── status/SKILL.md      ← /ralph-swarm:status
        ├── cancel/SKILL.md      ← /ralph-swarm:cancel
        ├── help/SKILL.md        ← /ralph-swarm:help
        ├── rollback/SKILL.md    ← /ralph-swarm:rollback
        ├── swarm-coordinator/SKILL.md  (internal)
        └── team-composition/SKILL.md   (internal)
```

---

## Requirements

- **Claude Code 1.0.34+** with plugin support
- **`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`** for `--swarm` mode (sequential works without it)
- Hook scripts require **`jq` or `python3`** for safe state parsing (SessionStart warns and Stop blocks if neither is available)

---

## License

MIT. See [LICENSE](plugins/ralph-swarm/LICENSE).

---

## Inspiration & Thanks

This plugin takes inspiration from:

- [smart-ralph](https://github.com/tzachbon/smart-ralph) by `tzachbon`
- [superpowers](https://github.com/obra/superpowers) by `obra`

Thanks for the ideas and prior work that helped shape this plugin.
