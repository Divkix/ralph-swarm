---
description: Rollback all execution changes to pre-execution state
argument-hint: ""
allowed-tools: Read, Bash
disable-model-invocation: true
---

# ralph-swarm:rollback

Roll back all changes made during execution to the pre-execution snapshot commit. This is a destructive operation — all code changes from task execution will be lost.

## Step 1: Load State

1. Read `.ralph-swarm-state.json` from the project root.
2. If the file does not exist, output: "No active swarm to rollback. Nothing to do." and stop.
3. Extract `execution.snapshotCommit` from the state file.
4. If `snapshotCommit` is empty or missing, output: "No snapshot commit found. Rollback is only available after execution has started." and stop.

## Step 2: Check for Uncommitted Spec Files

Before proceeding, check if spec files would be destroyed:

1. Read `specPath` from the state file.
2. Run `git status --porcelain <specPath>` to check for uncommitted spec files.
3. If uncommitted spec files exist, warn:
   ```
   WARNING: Uncommitted spec files detected at <specPath>.
   A git reset --hard will DESTROY these files.
   Options:
     1. Commit them first: git add <specPath> && git commit -m "chore: save spec files"
     2. Copy them elsewhere: cp -r <specPath> /tmp/specs-backup/
     3. Proceed anyway (files will be lost)
   ```
4. If the user chooses option 1 or 2, wait for them to act, then proceed.
5. If the user chooses option 3, proceed with explicit acknowledgment.

## Step 3: Confirm with User

Display a warning:

```
WARNING: This will reset the working tree to commit <snapshotCommit>.
All changes from task execution will be PERMANENTLY LOST.
This includes:
- All code written by executor agents
- All commits made during execution
```

Ask the user for confirmation before proceeding. Do NOT proceed without explicit approval.

## Step 4: Execute Rollback

1. Run: `git reset --hard <snapshotCommit>`
2. If the reset fails, report the error and stop.
3. Verify the rollback: `git rev-parse HEAD` should match `snapshotCommit`.

## Step 5: Clean Up

1. Delete `.ralph-swarm-state.json`:
   ```bash
   rm -f .ralph-swarm-state.json
   ```
2. Clean up any orphaned worktrees:
   ```bash
   git worktree prune
   ```

## Step 6: Report

Output:

```
Rollback complete.
HEAD is now at <snapshotCommit>.
State file removed.
Spec files are preserved at <specPath>.
```

## Important Rules

- **NEVER proceed without user confirmation.** This is a destructive operation.
- **Spec files are preserved.** They live in `specs/` and are not affected by `git reset --hard` if they were committed before execution.
- **This cannot be undone.** Make sure the user understands this.
