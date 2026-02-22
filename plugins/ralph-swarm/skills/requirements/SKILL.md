---
description: Run the requirements planning phase
argument-hint: ""
allowed-tools: "*"
---

# ralph-swarm:requirements

Run the requirements planning phase. This command takes the research output and produces detailed requirements. It is the second step in the incremental planning flow.

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
     Error: Cannot run requirements phase. Current phase is "<phase>".
     Requirements can only run during the planning phase.
     ```
   - If `planning.research` is not `"complete"`, output this error and stop:
     ```
     Error: Research phase must complete first. Run /ralph-swarm:start "your goal" to begin.
     ```
   - If `pausedAfter` is set but `planning.research` is `"pending"`, this is a corrupt state. Output:
     ```
     Warning: State inconsistency detected (pausedAfter is set but research is pending). Run /ralph-swarm:cancel to reset.
     ```
     Then stop.

## Step 2: Handle Re-run

If `planning.requirements` is already `"complete"`:

1. Warn the user:
   ```
   Warning: Requirements phase already completed. Re-running will invalidate downstream phases.
   ```
2. Reset downstream phases:
   - Set `planning.design` to `"pending"`
   - Set `planning.tasks` to `"pending"`
3. Delete downstream files if they exist:
   - Delete `<specPath>/design.md` if it exists
   - Delete `<specPath>/tasks.md` if it exists
4. Set `pausedAfter` to `null`.
5. Write the updated state file.

## Step 3: Read Context

1. Check if `CLAUDE.md` exists in the project root. If it does, read it with the Read tool.
2. Read `<specPath>/research.md` using the Read tool.
3. If research.md does not exist or is empty, output this error and stop:
   ```
   Error: Research file not found at <specPath>/research.md. The research phase may have failed.
   Run /ralph-swarm:cancel to reset and start over.
   ```

## Step 4: Execute Requirements Phase

1. Set `pausedAfter` to `null` in the state file (clear any previous pause).
2. Set `planning.requirements` to `"in-progress"` in the state file.
3. Write the updated state file.
4. Delegate to the `swarm-requirements` agent type (subagent_type: `ralph-swarm:swarm-requirements`) via the Task tool:
   - Instruction: "Based on the research at `<specPath>/research.md`, produce detailed requirements for: `<goal>`. Save to `<specPath>/requirements.md`."
   - The requirements.md must include:
     - Functional requirements (numbered, testable)
     - Non-functional requirements (performance, security, compatibility)
     - Acceptance criteria for each requirement
     - Out-of-scope items (explicit exclusions)
     - Dependencies on external systems or libraries
   - Pass: goal, CLAUDE.md content (if exists), research.md content
5. After the agent completes, verify `<specPath>/requirements.md` exists by reading it.
6. If verification fails, set `planning.requirements` to `"failed"` and stop with an error.
7. Set `planning.requirements` to `"complete"` in the state file.

## Step 5: Pause

1. Set `pausedAfter` to `"requirements"` in the state file.
2. Write the updated state file.
3. Display to the user:
   ```
   Requirements phase complete.
   Review the output at: <specPath>/requirements.md

   Next: Run /ralph-swarm:design to continue planning.
   Or edit the requirements file first, then run /ralph-swarm:design.
   ```
4. **STOP HERE.** The stop hook will allow exit because `pausedAfter` is set.

## Error Handling

- If the requirements agent fails, set `planning.requirements` to `"failed"` in the state file, report the error, and stop.
- If the state file cannot be written, error immediately.
- Never silently swallow errors.
