---
name: team-composition
description: This skill should be used when determining how many teammates to spawn and what agent types to use, based on tasks.md analysis.
user-invocable: false
---

# Team Composition

This skill determines the optimal number of teammates and the correct agent type for a swarm run. It is invoked during the planning phase, before team creation.

## Analysis Process

1. **Read `tasks.md`** from the spec directory.
2. **Parse the File Manifest** at the bottom of tasks.md (or the `Files:` section of each task).
3. **Compute parallel batches** by analyzing file conflicts:
   - Two tasks conflict if they share any file (CREATE or MODIFY).
   - Tasks with dependencies cannot be in the same batch as their prerequisites.
   - Group non-conflicting, dependency-free tasks into batches (same algorithm as the coordinator's Runtime Parallelism Computation).
4. **Find the largest batch.** That count is the maximum number of useful teammates — spawning more than that means idle agents burning tokens.
5. **Apply the hard cap of 5 teammates.** Beyond 5, coordination overhead and token costs grow faster than throughput. Diminishing returns hit hard.
6. **Recommended teammate count:** `min(largest_batch_size, 4)`. Using 4 instead of 5 gives a buffer for the coordinator to stay responsive.

### Examples

| Total Tasks | Largest Batch Size | Recommended teammates |
|-------------|--------------------|-----------------------|
| 6           | 2                  | 2                     |
| 10          | 6                  | 4 (capped)            |
| 3           | 1                  | 1                     |
| 8           | 3                  | 3                     |
| 12          | 10                 | 4 (capped)            |

## Agent Type Selection

### When `--agent-type` is explicitly provided
Use that type for all teammates. No analysis needed.

### When `--agent-type` is `auto` or not provided
Analyze the project to determine the dominant language/framework:

1. **Check for build system / config files** (most reliable signal):
   - `go.mod` --> Go project --> `golang-pro`
   - `package.json` with TypeScript dependencies or `tsconfig.json` --> `typescript-pro`
   - `package.json` without TypeScript --> `typescript-pro` (JS projects benefit from TS tooling awareness)
   - `Cargo.toml` --> Rust project --> `rust-pro`
   - `pyproject.toml`, `setup.py`, `setup.cfg`, `requirements.txt` --> `python-pro`
   - `mix.exs` --> Elixir project --> `elixir-expert`

2. **If no config files found**, check file extensions in the project root and `src/` directory:
   - Majority `.go` files --> `golang-pro`
   - Majority `.ts` / `.tsx` files --> `typescript-pro`
   - Majority `.js` / `.jsx` files --> `typescript-pro`
   - Majority `.py` files --> `python-pro`
   - Majority `.rs` files --> `rust-pro`
   - Majority `.ex` / `.exs` files --> `elixir-expert`
   - Majority `.sql` files --> `sql-pro`

3. **If tasks span multiple languages** (e.g., Go backend + TypeScript frontend), use `general-purpose`. Specialized agents struggle when they hit code outside their domain.

4. **If unclear or mixed**, default to `general-purpose`. It is the safest fallback.

### Agent Type Reference

| Agent Type        | Best For                                      |
|-------------------|-----------------------------------------------|
| `golang-pro`      | Go projects, CLI tools, servers                |
| `typescript-pro`  | TypeScript/JavaScript, React, Node.js, Next.js |
| `python-pro`      | Python, Django, Flask, FastAPI, data pipelines  |
| `rust-pro`        | Rust projects, systems programming              |
| `elixir-expert`   | Elixir/Phoenix projects                         |
| `sql-pro`         | Database-heavy work, migrations, query tuning   |
| `general-purpose` | Multi-language, mixed projects, unclear scope   |

## Cost Estimation

Provide a rough cost estimate so the user can make an informed decision before committing tokens.

### Per-Teammate Estimates
- Each teammate consumes approximately **$5-15/hour** in API tokens depending on task complexity and model usage.
- Simple tasks (file edits, config changes): lower end (~$5/hr).
- Complex tasks (architecture changes, debugging, multi-file refactors): upper end (~$15/hr).

### Total Estimate Formula
```
low  = teammates * hours * $5
high = teammates * hours * $15
```

### Examples

| Teammates | Estimated Duration | Low Estimate | High Estimate |
|-----------|--------------------|--------------|---------------|
| 2         | 1 hour             | $10          | $30           |
| 3         | 2 hours            | $30          | $90           |
| 4         | 3 hours            | $60          | $180          |
| 5         | 2 hours            | $50          | $150          |

Duration is estimated from the total number of tasks and their apparent complexity. A task with "implement X from scratch" is ~30-60 min. A task with "update config Y" is ~5-10 min.

## Output Format

When reporting team composition to the user or the coordinator, always use this format:

```
Team: <N> x <agent-type> in worktrees
Computed batches: <B> (largest batch: <L> tasks)
Estimated cost: $<low>-$<high>
```

### Example Output

```
Team: 3 x golang-pro in worktrees
Computed batches: 4 (largest batch: 3 tasks)
Estimated cost: $45-$135
```

If the user has not confirmed yet, present this and wait for approval before proceeding to team creation.
