---
name: worktree-sparsity-eval
description: >-
  Evaluate repository size metrics to determine whether a separate working copy should use
  sparse checkout. **Invoke when a separate working copy is already warranted — a
  `git worktree` or a `jj workspace add` — and only to size that invocation.** It does
  not decide whether to create one. In jj mode the
  diamond workflow's development join remains the default for parallel chains and needs no
  sparsity evaluation; see the `jj-version-control` skill's `tiered-ceremony.md` for the
  triggers and `jj-version-control` §"Worktree interop" for the
  discipline. Also invoke for periodic re-evaluation when a repo has grown significantly.
---

# Worktree sparsity evaluation

Collect repository metrics and determine whether worktrees should use sparse checkout.
Three conditions must all hold for sparse checkout to be recommended.

This skill sizes a separate working copy that is already warranted; it does not decide whether to create one.
That decision belongs to the `jj-version-control` skill's `tiered-ceremony.md`, whose default in jj mode is the diamond workflow's development join in a single working copy — which needs no sparsity evaluation.
In a flake repository the separate working copy is a git worktree or a colocated jj workspace (jj 0.46.0 or later), never a non-colocated jj workspace; the `git sparse-checkout` recipes below apply to a git worktree, and a jj workspace narrows its checkout with `jj sparse set` instead.
Before creating a worktree in a jj-colocated repository, read `jj-version-control` §"Worktree interop" for the branch-ownership and return-by-ref discipline.

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

Create a working branch per the working branch isolation conventions in git-preferences.
When sparse checkout is recommended, additionally configure sparse checkout with cone mode and set paths relevant to the task.

In a jj-colocated repository the branch the worktree checks out must be one the jj primary does not hold: never a bookmark on or under the primary's `@`, and never one a live development join includes.
Point the worktree at a stable base or at nothing.

For guidance on choosing paths for `git sparse-checkout set`, see `references/sparse-checkout-patterns.md`.
