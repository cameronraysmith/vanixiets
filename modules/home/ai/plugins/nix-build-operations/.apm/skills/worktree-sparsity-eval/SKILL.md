---
name: worktree-sparsity-eval
description: >-
  Evaluate repository size metrics to determine whether worktrees should use sparse checkout.
  **Invoke only in git-native mode (no `.jj/` directory) when creating a `git worktree`, OR
  in jj mode when the user has explicitly requested workspace isolation by name and only to
  size a `jj workspace add` invocation.** `git worktree add` is hook-blocked in jj-managed
  repositories (see the no-worktree-in-jj-mode directive in the global CLAUDE.md); this
  skill does not apply to that case. In jj mode without an explicit workspace request,
  parallel work uses the diamond workflow's development join, not worktrees — see
  `~/.claude/skills/jj-version-control/tiered-ceremony.md`. Also invoke for periodic
  re-evaluation when a repo has grown significantly.
---

# Worktree sparsity evaluation

Collect repository metrics and determine whether worktrees should use sparse checkout.
Three conditions must all hold for sparse checkout to be recommended.

In jj mode, this skill applies ONLY to `jj workspace add` sizing when the user has explicitly requested workspace isolation by name.
`git worktree add` is hook-blocked in jj-managed repositories (no-worktree-in-jj-mode directive in the global CLAUDE.md); this skill does not apply to that case.
In jj mode without an explicit workspace request, parallel work uses the diamond workflow's development join in a single working copy — see `~/.claude/skills/jj-version-control/tiered-ceremony.md`.

## Thresholds

| Metric | Threshold | Rationale |
|---|---|---|
| File count | > 10,000 | Below this, checkout is fast enough |
| Working tree size | > 500 MB | Below this, disk cost of concurrent worktrees is negligible |
| Change locality | < 0.01 (1%) | Above this, sparse sets grow until approaching full checkout |

## Procedure

### 1. Collect metrics

Run the collection script from the repository root being evaluated:

```bash
bash <skill-dir>/scripts/collect_metrics.sh
```

The script is platform-aware (macOS/Linux) and outputs JSON with raw and formatted values:

```json
{
  "file_count": 98432,
  "tree_size_bytes": 2253211648,
  "tree_size_human": "2.1 GB",
  "change_locality": 0.000312,
  "change_locality_pct": "0.03%",
  "avg_files_per_commit": 30,
  "platform": "Darwin"
}
```

### 2. Update CLAUDE.md

Pipe the JSON into the update script, providing the path to CLAUDE.md:

```bash
bash <skill-dir>/scripts/collect_metrics.sh | bash <skill-dir>/scripts/update_claude_md.sh ./CLAUDE.md
```

The update script handles:
- Symlink resolution (CLAUDE.md is often a symlink into vanixiets)
- Existing metric comparison with 5% change threshold
- Sentinel-delimited section insertion or replacement
- Reporting which repository the commit targets

When existing metrics are found, the script compares and only rewrites if any value changed by more than 5% or the recommendation flipped.
It reports deltas (e.g., "File count: 98,432 -> 102,891 (+4.5%)").

### 3. Commit

The commit goes in the repository containing the *resolved* CLAUDE.md target, not necessarily the evaluated repository.
The update script prints the resolved target path and repository — use that for `git -C`.

Commit the updated metrics per git-preferences conventions.
The commit goes in `<target-repo>` against `<resolved-claude-md>`.

### 4. Worktree creation

When sparse checkout is recommended, use this command template instead of plain `git worktree add`:

Create a working branch per the working branch isolation conventions in git-preferences.
When sparse checkout is recommended, additionally configure sparse checkout with cone mode and set paths relevant to the task.

For guidance on choosing paths for sparse checkout, see `references/sparse-checkout-patterns.md`.

For guidance on choosing paths for `git sparse-checkout set`, see `references/sparse-checkout-patterns.md`.
