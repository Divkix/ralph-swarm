---
description: Run the design planning phase
argument-hint: ""
allowed-tools: "*"
disable-model-invocation: true
---

# ralph-swarm:design

Run the architecture/design planning phase. This command takes the research and requirements output and produces an architecture/design document. It is the third step in the incremental planning flow.

## Step 1: Load & Validate State

1. Read `.ralph-swarm-state.json` from the project root using the Read tool.
2. If the file does not exist, output this error and stop:
   ```
   Error: No active swarm found. Run /ralph-swarm:start "your goal" first.
   ```
3. Parse the JSON. Extract `phase`, `pausedAfter`, `planning`, `specPath`, `goal`, and `name`.
4. Validate prerequisites:
   - If `phase` is not `"planning"`, output this error and stop:
     ```
     Error: Cannot run design phase. Current phase is "<phase>".
     Design can only run during the planning phase.
     ```
   - If `planning.requirements` is not `"complete"`, output this error and stop:
     ```
     Error: Requirements phase must complete first. Run /ralph-swarm:requirements first.
     ```
   - If `pausedAfter` is set but `planning.requirements` is `"pending"`, this is a corrupt state. Output:
     ```
     Warning: State inconsistency detected (pausedAfter is set but requirements is pending). Run /ralph-swarm:cancel to reset.
     ```
     Then stop.

## Step 2: Handle Re-run

If `planning.design` is already `"complete"`:

1. Warn the user:
   ```
   Warning: Design phase already completed. Re-running will invalidate the task breakdown.
   ```
2. Reset downstream phases:
   - Set `planning.tasks` to `"pending"`
3. Delete downstream files if they exist:
   - Delete `<specPath>/tasks.md` if it exists
4. Set `pausedAfter` to `null`.
5. Write the updated state file.

## Step 3: Read Context

1. Check if `CLAUDE.md` exists in the project root. If it does, read it with the Read tool.
2. Read `<specPath>/research.md` using the Read tool.
3. Read `<specPath>/requirements.md` using the Read tool.
4. Read `flags.swarm` from the state file (parsed in Step 1).
5. If either spec file does not exist or is empty, output an error identifying the missing file and stop.

## Step 4: Execute Design Phase

1. Set `pausedAfter` to `null` in the state file (clear any previous pause).
2. Set `planning.design` to `"in-progress"` in the state file.
3. Write the updated state file.

**Pre-merge check (if `flags.swarm` is true):** Before spawning parallel agents, check `<specPath>` for partial files from a prior interrupted attempt:
- If **all expected partial files** (`design-architecture.md`, `design-contracts.md`) exist AND `design.md` does NOT exist: skip agent delegation, proceed directly to merge. Read `skills/start/SKILL.md` and follow the [Merge Protocol](../start/SKILL.md#merge-protocol) section.
- If **only one** partial file exists: delete the stale partial (incomplete prior run), then proceed with agent delegation.
- If **no partial files** exist: proceed normally.

**If `flags.swarm` is true:** Spawn 2 parallel Task calls using `swarm-architect` agent type:

| Agent | Focus | Output File |
|-------|-------|-------------|
| A | **Architecture & data**: component design, data models, migrations, data flow, parallelization analysis | `<specPath>/design-architecture.md` |
| B | **Contracts & strategy**: API contracts, interfaces, error handling strategy, testing strategy, design decisions | `<specPath>/design-contracts.md` |

- Launch both as parallel Task calls (in a single message with 2 tool uses).
- Each agent's instruction: "Based on the research at `<specPath>/research.md` and requirements at `<specPath>/requirements.md`, produce a design document for: `<goal>`. Focus specifically on **<focus area>**. Save to `<output file>`."
- Pass to each: goal, CLAUDE.md content (if exists), research.md content, requirements.md content
- After both complete: Read `skills/start/SKILL.md` and follow the [Merge Protocol](../start/SKILL.md#merge-protocol) section to combine partial files into `<specPath>/design.md`. Partial files: `design-architecture.md`, `design-contracts.md`.
- Error handling: Both agents must succeed. If one fails, set `planning.design` to `"failed"` and stop.

**If `flags.swarm` is false (default):** Single-agent delegation:

4. Delegate to the `swarm-architect` agent type (subagent_type: `ralph-swarm:swarm-architect`) via the Task tool:
   - Instruction: "Based on the research at `<specPath>/research.md` and requirements at `<specPath>/requirements.md`, produce an architecture/design document for: `<goal>`. Save to `<specPath>/design.md`."
   - Pass: goal, CLAUDE.md content (if exists), research.md content, requirements.md content

**Regardless of path**, the design.md must include:
   - High-level architecture (components, data flow)
   - File-by-file change plan (which files to create/modify, what changes)
   - Interface contracts (function signatures, types, API shapes)
   - Error handling strategy
   - Testing strategy (what to test, how)
   - Migration/rollback plan if applicable

**After delegation (both paths):**
5. Verify `<specPath>/design.md` exists by reading it.
6. If verification fails, set `planning.design` to `"failed"` and stop with an error.
7. Set `planning.design` to `"complete"` in the state file.

## Step 5: Pause

1. Set `pausedAfter` to `"design"` in the state file.
2. Write the updated state file.
3. Display to the user:
   ```
   Design phase complete.
   Review the output at: <specPath>/design.md

   Next: Run /ralph-swarm:tasks to continue planning.
   Or edit the design file first, then run /ralph-swarm:tasks.
   ```
4. **STOP HERE.** The stop hook will allow exit because `pausedAfter` is set.

## Error Handling

- If the design agent fails, set `planning.design` to `"failed"` in the state file, report the error, and stop.
- If the state file cannot be written, error immediately.
- Never silently swallow errors.
