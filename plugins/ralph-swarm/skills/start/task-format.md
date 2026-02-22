# Task Format Specification

This is the canonical task format for `tasks.md`. Both `/ralph-swarm:start` and `/ralph-swarm:go` reference this specification.

## Template

```markdown
# Implementation Tasks: <name>

**Date:** [current date]
**Design Source:** design.md
**Total Tasks:** [count]
**Slicing Strategy:** vertical (each task = complete feature slice)

## TASK-001: [Feature Slice Title]

**Complexity:** S | M | L
**Files:**
- CREATE: `path/to/file`
- MODIFY: `path/to/file` — [what changes]
**Dependencies:** None
**Description:**
[End-to-end slice description, precise enough for an agent to execute without ambiguity]
**Context to Read:**
- design.md, section "[relevant section]"
- `[existing file path]` — [why to read it]
**Verification:**
```bash
[exact command to verify]
```

## TASK-002: [Feature Slice Title]
...

---

## File Manifest

| Task | Files Touched |
|------|---------------|
| TASK-001 | `file1`, `file2` |
| TASK-002 | ... |

## Risk Register

| Task | Risk | Mitigation |
|------|------|------------|
| TASK-xxx | [what could go wrong] | [how to handle it] |
```

## Format Rules

- Each task is a vertical slice delivering complete functionality end-to-end (not a horizontal layer)
- Each task must declare exact file lists (`Files: CREATE/MODIFY`) — this enables runtime parallelism computation
- Each task must be completable in a single agent session (1-5 files, if larger, split it)
- Tasks must be ordered by dependency (foundational slices first)
- Include a final "verification" task that runs the full test suite and linting
- The File Manifest at the bottom provides quick conflict scanning for the coordinator
- The task format is mode-independent — the same tasks.md works for both sequential and swarm execution
