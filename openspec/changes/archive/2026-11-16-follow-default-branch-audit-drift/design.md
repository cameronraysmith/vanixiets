## Context

The writer's request handler runs `ghq get -u`, which is `git pull --ff-only` on the checked-out branch. Lazy clones (`--depth 1`) fetch one branch. The writer has no credentials and only the actions `get`, `deepen`, `promote` and `hydrate`.

## Goals / Non-Goals

**Goals:** updates survive a default-branch rename; drift is visible to participants with the commands that resolve it; nothing the writer writes is open to others on any host.

**Non-Goals:** the writer deleting, renaming or relocating a clone; following a rename automatically.

## Decisions

### D28: follow the remote's default branch inside the update

Before `ghq get -u`, the handler runs `git ls-remote --symref origin HEAD` and reads the branch it names, checked with `git check-ref-format --branch`.
A clone whose fetch refspecs each name one branch is a single-branch clone: `remote set-branches origin <new>`, `fetch --no-tags --depth <current depth> origin <new>` (no depth for an unshallow one; the partial filter applies from the remote's configuration), then `checkout -B <new> origin/<new>`, which also sets its upstream for ghq's pull.
Any other clone is fetched with `remote.origin.followRemoteHEAD=always`, which moves `origin/HEAD`; it changes branch only when `HEAD` is on the previous `origin/HEAD` branch and `git status --porcelain` is empty, to an existing local branch of the new name as it is, or else to a new branch tracking `origin/<new>`.
A clone on another branch, with local changes, or on a detached `HEAD` stays where it is.
Each case prints one line, `default branch: <old> -> <new>; checked out <new>` or `…; kept <branch> (<reason>)`.
A remote that names no HEAD, or an ls-remote that fails, leaves the update as it was.

### D29: a read-only audit through the participant's own `gh`

`ghq-sync --audit [QUERY]` runs `gh api graphql` with fifty aliased `repository(owner:, name:)` fields per request over the github.com entries of `ghq list [QUERY]`, reading `nameWithOwner`, `isArchived` and `defaultBranchRef`.
`gh` is not a runtime input: the audit uses the account's own `gh` and stored token, and without one it says so and exits 0. `jq` is a runtime input.
Findings: `renamed:` (with the retire commands when the canonical path is already cloned, the relocate commands otherwise), `case:`, `missing:`, `archived:` and `default branch:`. Commands are printed shell-quoted, run as the writer the tree's root is owned by; the audit never runs them and writes nothing, zoxide included.

### D30: no writer-side deletion or relocation

Stated in the trust boundary. An administrator runs the printed commands as the writer.

### D32: the handler sets its own umask

launchd reports the job's `Umask` and does not apply it to the inetd-compatible instance started per connection; the cause is outside the handler, so the handler's `main()` sets `os.umask(0o027)` before anything else, on every host. The plist keeps `Umask` and the systemd unit keeps `UMask=0027`.
The handler test starts every handler with umask 022, as launchd does, and fails if anything under the test root has a permission for others or group write.
Entries already written are corrected after deployment by an operator script that only strips `o+rwx` and `g+w`, never follows a symbolic link, and stays under the root.

## Risks / Trade-offs

- One more network round trip (`ls-remote`) per update.
- The audit trusts what GitHub's API answers for the account's token; a private repository the token cannot see reads as `missing`.
- A full clone on a feature branch keeps it; its `origin/HEAD` moves.
