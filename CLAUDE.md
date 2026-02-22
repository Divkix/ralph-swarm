# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin — not compiled code. Every file is either markdown (prompts/docs), bash (hooks), or JSON (config). There is no build step, no test suite, no package manager. Validation is done via `bash -n` on shell scripts and manual cross-reference checks.

## Validation Commands

```bash
# Syntax check both hook scripts
bash -n plugins/ralph-swarm/hooks/scripts/swarm-watcher.sh
bash -n plugins/ralph-swarm/hooks/scripts/load-context.sh

# Verify file structure matches README diagram
find plugins/ralph-swarm/ -type f | sort

# Check for stale references to removed commands/ directory
grep -r "commands/" plugins/ralph-swarm/

# Verify swarm-verifier is referenced (not orphaned)
grep -r "swarm-verifier" plugins/ralph-swarm/ --include="*.md" --include="*.sh"

# Verify no unsafe git staging instructions
grep -r "git add -A\|git add \." plugins/ralph-swarm/

# Test promise tag regex tolerance
echo '<promise> SWARM COMPLETE </promise>' | grep -qiE '<promise>\s*SWARM\s+COMPLETE\s*</promise>' && echo "PASS"
```

## Architecture

### Two-Phase System

**Planning** (sequential cross-phase, no code written): By default, `/ralph-swarm:start` runs only the research phase and pauses. The remaining phases are run incrementally via `/ralph-swarm:requirements`, `/ralph-swarm:design`, and `/ralph-swarm:tasks`, each pausing for review. Use `--full` to run all 4 phases in one shot. Each phase delegates to a specialized agent (`swarm-researcher` → `swarm-requirements` → `swarm-architect` → `swarm-task-planner`) and writes to `specs/<name>/`. When `--swarm` is set, each planning phase (except tasks) spawns multiple agents in parallel within the phase — research spawns 3 agents (structure, dependencies, testing), requirements spawns 2 (functional, non-functional), design spawns 2 (architecture, contracts) — then the lead agent merges their outputs into the canonical spec file. Cross-phase ordering remains strictly sequential. User reviews before execution (unless `--yolo`).

**Execution** (code written): Either sequential (one task at a time, stop hook re-injects) or swarm (Agent Teams with parallel worktrees). Both modes follow `execution-protocol.md`.

### Stop Hook as Execution Loop

The stop hook (`swarm-watcher.sh`) is the engine that keeps execution running. When the session tries to exit during execution phase, the hook blocks it and re-injects a prompt. This creates a persistent loop without the agent needing to self-loop. The hook independently validates completion claims by checking task counts in the state file — it does not trust the agent's text output.

### Runtime Parallelism (Swarm Mode)

Parallelism is computed at runtime from the File Manifest in `tasks.md`, not declared manually. Two tasks conflict if they share ANY file. The coordinator builds a conflict graph and groups non-conflicting, dependency-satisfied tasks into batches using greedy coloring. Batch N must complete before Batch N+1 starts.

### State File

`.ralph-swarm-state.json` is the single source of truth. Schema documented in `references/state-schema.md`. Key fields:
- `phase`: planning → planning-complete → planning-review → execution → complete
- `execution.completedTasks` / `failedTasks`: arrays of task indices
- `execution.teamCreated`: enforced by stop hook in swarm mode
- `execution.snapshotCommit`: rollback point (git commit hash before first task)
- `specPath`: always absolute (worktree compatibility)

## Key Files

| File | Role |
|------|------|
| `hooks/hooks.json` | Wires `SessionStart` → `load-context.sh`, `Stop` → `swarm-watcher.sh` |
| `hooks/scripts/swarm-watcher.sh` | Stop hook: blocks exit, validates completion, re-injects prompts |
| `hooks/scripts/load-context.sh` | SessionStart hook: loads state, detects orphaned worktrees |
| `skills/start/SKILL.md` | Main entry point: parses args, runs planning, triggers execution |
| `skills/requirements/SKILL.md` | Standalone requirements phase (incremental planning) |
| `skills/design/SKILL.md` | Standalone design phase (incremental planning) |
| `skills/tasks/SKILL.md` | Standalone task breakdown phase (incremental planning) |
| `skills/start/execution-protocol.md` | Canonical execution protocol (sequential + swarm + merge) |
| `skills/start/task-format.md` | Canonical task format spec (single source of truth) |
| `references/state-schema.md` | Full `.ralph-swarm-state.json` schema documentation |
| `agents/swarm-verifier.md` | QA agent: runs verification, never modifies code |

## Conventions

- **Vertical slices only**: every task delivers end-to-end functionality (DB → types → service → handler → tests). Horizontal layering is explicitly forbidden.
- **Agent type fallback chain**: language-specific (e.g. `golang-pro`) → `swarm-executor` → `general-purpose`. Language-specific agents are third-party and may not be installed.
- **Explicit file staging**: `git add <file1> <file2>` only. `git add -A` and `git add .` are prohibited in all prompts.
- **Re-injection prompts**: always numbered step lists, never prose paragraphs. LLMs comply better with structured instructions.
- **State file locking**: `mkdir`-based spinlock in `swarm-watcher.sh` protects concurrent writes. Guard flag `_LOCK_HELD` prevents the exit trap from releasing an unacquired lock.
- **Version**: lives in `plugin.json` only (official docs: plugin.json always wins, avoid duplicating in marketplace.json).

## Cross-File Dependencies

Changes to these files require updating their counterparts:

| If you change... | Also update... |
|-------------------|----------------|
| State file fields | `references/state-schema.md`, `skills/start/SKILL.md` (template), `hooks/scripts/swarm-watcher.sh` (readers) |
| Task format | `skills/start/task-format.md` (canonical source) — do NOT duplicate in `agents/swarm-task-planner.md` |
| Execution protocol | `skills/start/execution-protocol.md` AND `skills/swarm-coordinator/SKILL.md` (mirrors key sections) |
| Commands | README.md Commands table AND `skills/help/SKILL.md` |
| Agent types / fallback | `skills/swarm-coordinator/SKILL.md` AND `skills/team-composition/SKILL.md` |
| Promise tag format | `swarm-watcher.sh` regex (line with `grep -qiE`) |
| Planning phase logic | Each phase skill (`skills/requirements/`, `skills/design/`, `skills/tasks/`) AND `skills/start/SKILL.md` `--full` path |
| Parallel planning (--swarm) | `skills/start/SKILL.md` (merge protocol + phase conditionals), `skills/requirements/SKILL.md`, `skills/design/SKILL.md` |
| `pausedAfter` field | `references/state-schema.md`, `hooks/scripts/swarm-watcher.sh`, `hooks/scripts/load-context.sh`, each phase skill, `skills/status/SKILL.md` |
