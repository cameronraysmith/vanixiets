## Why

Shared reference clones drift from their upstreams in ways the writer cannot see or follow: a renamed default branch freezes or silently stales a clone, a renamed repository leaves a clone under the old name, and on darwin the writer's files are created open to every account because launchd does not apply the job's umask to the handler it starts per connection.

## What Changes

**Updates and the remote's default branch**
- From: an update pulls the branch the clone was made on, and fails when that branch is gone.
- To: an update follows the remote's default branch; a single-branch clone switches to it at its depth, and a full clone moves `origin/HEAD` and switches only when it was on the previous default with no local change.
- Reason: four clones failed every update and two followed a stale branch.
- Impact: non-breaking; one status line reports a switch.

**Auditing drift**
- From: nothing reports renames, transfers, deleted or archived upstreams.
- To: `ghq-sync --audit [QUERY]` reports them with the administrator commands that resolve them, changing nothing.
- Reason: git never shows a rename.
- Impact: non-breaking; a new read-only mode.

**Writer umask**
- From: the service manager sets the writer's umask.
- To: the handler sets umask `0027` itself; an operator script strips permissions the writer gave before.
- Reason: on darwin, launchd did not apply it.
- Impact: non-breaking.

**No deletion or relocation by the writer** (decided): stated in the trust boundary.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `shared-reference-tree-interface` (stratum: `interface`): an update follows the remote's default branch; the handler sets its own umask; a participating account audits the tree against GitHub without changing it; the trust boundary states that the writer never deletes, renames or relocates a repository. Trust boundary: the audit reports what GitHub's API answers for the account's token; the default-branch rule relies on the remote naming its HEAD.

The behavioral capability `shared-reference-tree` is unchanged: following the default branch is part of refreshing, and the audit only reads.

## Impact

- `pkgs/by-name/ghq-shared/ghq-writer-handler.py`, `test_handler.py`, `test-wrapper.nix`; `pkgs/by-name/ghq-sync/ghq-sync.sh`, `package.nix` (`jq`); `modules/vm-tests/shared-reference-tree.nix`; `modules/home/README.md`.
- A one-time operator script strips permissions for others and group write under stibnite's shared root after deployment.
