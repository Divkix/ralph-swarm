# ralph-swarm

A Claude Code plugin for spec-driven development with optional parallel execution via Agent Teams.

## How It Works

```
Goal → Research → Requirements → Design → Tasks → Execution
                                             ↓
                                    Vertical Feature Slices
                                             ↓
                              ┌──────────────┴──────────────┐
                              │                             │
                        Sequential Mode              Swarm Mode
                        (one at a time)        (runtime parallelism)
                              │                             │
                              │                    File-conflict analysis
                              │                    → compute batches
                              │                    → assign to teammates
                              │                             │
                              └──────────────┬──────────────┘
                                             ↓
                                      Verified Output
```

## Key Concepts

### Who It's For

- Developers who want spec-first execution instead of jumping straight to code
- Larger tasks where reviewable planning artifacts improve outcomes
- Repos that can benefit from runtime parallelism via Agent Teams + worktrees
- Users who want incremental planning by default, with `--full` / `--yolo` when needed

### Not A Fit If

- You only want a fast one-shot code generation command
- The task is too small for planning overhead to pay off
- The codebase is tightly coupled and difficult to parallelize safely

### Vertical Slices

Tasks are decomposed as **vertical feature slices**, not horizontal layers. Each task delivers a complete piece of functionality end-to-end:

```
TASK: "Add user authentication"
  ├── migration.sql       (database layer)
  ├── auth_types.go       (domain layer)
  ├── auth_service.go     (service layer)
  ├── auth_handler.go     (handler layer)
  ├── auth_test.go        (tests)
  └── router.go           (wiring)
```

This means every completed task produces something testable. Sequential mode gets value after every single task.

### Runtime Parallelism (Swarm Mode)

Instead of manually grouping tasks into phases at planning time, parallelism is computed at runtime:

1. The task planner produces vertical slices with **exact file lists** for each task.
2. The swarm coordinator builds a **file-conflict graph** — tasks sharing files cannot run in parallel.
3. Non-conflicting tasks with satisfied dependencies are grouped into **batches**.
4. Batch 1 tasks run simultaneously. When Batch 1 completes, Batch 2 starts. And so on.

The same `tasks.md` works for both sequential and swarm execution. The format is mode-independent.

When `--swarm` is set, planning phases also leverage intra-phase parallelism (see [Swarm (`--swarm`)](#swarm---swarm) for details).

## Commands

| Command | Description |
|---------|-------------|
| `/ralph-swarm:start "goal" [flags]` | Plan and optionally execute a task |
| `/ralph-swarm:requirements` | Run the requirements planning phase |
| `/ralph-swarm:design` | Run the design planning phase |
| `/ralph-swarm:tasks` | Run the task breakdown planning phase |
| `/ralph-swarm:go` | Resume execution after reviewing the plan |
| `/ralph-swarm:status` | Show current progress |
| `/ralph-swarm:cancel` | Cancel and clean up |
| `/ralph-swarm:rollback` | Reset to pre-execution state (destructive) |
| `/ralph-swarm:help` | Show available commands |

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--full` | `false` | Run all 4 planning phases in one shot without pausing |
| `--swarm` | `false` | Enable parallel planning (intra-phase) and parallel execution (Agent Teams) |
| `--yolo` | `false` | Skip plan review, go straight to execution |
| `--teammates N` | `auto` | Number of parallel agents (swarm mode) |
| `--agent-type TYPE` | `auto` | Agent type for teammates (e.g., `golang-pro`) |
| `--commit` | `true` | Commit after each task |
| `--no-commit` | - | Disable auto-commit |
| `--max-iterations N` | `30` | Safety cap on execution loops |

## Execution Modes

### Sequential (default)

Tasks execute one at a time in dependency order. The lead agent delegates each task to an executor subagent, verifies the result, optionally commits, then moves to the next task.

Best for: small projects, quick tasks, when you want tight control.

### Swarm (`--swarm`)

The coordinator spawns multiple executor agents in isolated git worktrees. It computes parallel batches from the File Manifest in tasks.md and assigns non-conflicting tasks to teammates simultaneously.

When `--swarm` is set, planning phases also run in parallel: research spawns 3 focused agents (codebase structure, dependencies, testing patterns), requirements spawns 2 agents (functional, non-functional), and design spawns 2 agents (architecture, contracts). Each group runs concurrently within its phase, and outputs are merged into the canonical spec file. Cross-phase ordering remains strictly sequential.

Best for: larger projects with many independent feature slices, when you want speed.

## Task Format

```markdown
# Implementation Tasks: [Feature Name]

**Total Tasks:** [count]
**Slicing Strategy:** vertical (each task = complete feature slice)

## TASK-001: [Feature Slice Title]
**Complexity:** S | M | L
**Files:**
- CREATE: `path/to/file`
- MODIFY: `path/to/file` — [what changes]
**Dependencies:** None
**Description:** [end-to-end slice description]
**Verification:** [command]

---

## File Manifest
| Task | Files Touched |
|------|---------------|
| TASK-001 | `file1`, `file2` |
```

The File Manifest at the bottom enables the coordinator to quickly scan for file conflicts and compute parallel batches without re-parsing every task.

## Installation

```bash
claude plugin add /path/to/ralph-swarm/plugins/ralph-swarm
```

Or from GitHub:

```bash
claude plugin add https://github.com/Divkix/ralph-swarm
```

After installing, verify with `/ralph-swarm:help` — the `ralph-swarm` slash commands should appear in autocomplete (including `/ralph-swarm:start`, `/ralph-swarm:requirements`, `/ralph-swarm:go`, and `/ralph-swarm:help`).

Hook scripts require `jq` or `python3` to parse `.ralph-swarm-state.json` safely. If neither is installed, the SessionStart hook warns and the Stop hook blocks to avoid incorrect swarm state transitions.

## Architecture

| Component | Role |
|-----------|------|
| `skills/start/SKILL.md` | Entry point: parse args, run planning phases, begin execution |
| `skills/start/execution-protocol.md` | Shared execution protocol (sequential + swarm modes) |
| `skills/start/task-format.md` | Canonical task format specification |
| `skills/go/SKILL.md` | Resume execution after plan review |
| `skills/status/SKILL.md` | Display current swarm progress |
| `skills/cancel/SKILL.md` | Cancel and clean up swarm state |
| `skills/help/SKILL.md` | Show available commands and flags |
| `agents/swarm-task-planner.md` | Decompose design into vertical feature slices |
| `agents/swarm-executor.md` | Execute a single task autonomously |
| `agents/swarm-verifier.md` | Verify task completion |
| `agents/swarm-researcher.md` | Research codebase and external sources |
| `agents/swarm-requirements.md` | Generate requirements from research |
| `agents/swarm-architect.md` | Design architecture from requirements |
| `skills/swarm-coordinator/` | Coordinate Agent Teams: batch computation, task assignment, monitoring |
| `skills/team-composition/` | Determine optimal teammate count and agent types |
| `references/state-schema.md` | State file format documentation |
| `references/agent-team-patterns.md` | Best practices for Agent Teams coordination |

## Inspiration & Thanks

Inspired by:

- [smart-ralph](https://github.com/tzachbon/smart-ralph)
- [superpowers](https://github.com/obra/superpowers)

Thanks to the authors and maintainers for the ideas and groundwork.
