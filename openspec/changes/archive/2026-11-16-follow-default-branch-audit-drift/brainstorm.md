# Brainstorm: follow default-branch changes, audit upstream drift, enforce the writer umask

This records the evidence behind the change: a read-only drift audit of stibnite's shared tree on 2026-11-16 (561 github.com clones, batched GraphQL) and a probe of the writer's umask the same day.

## Problem

- **Default branch changed upstream.** ghq's update is `git pull --ff-only`, and every lazy clone fetches one branch. Four clones whose old default was deleted (clap-rs/clap, cssnano/cssnano, rust-lang/futures-rs, BerriAI/litellm) failed every update with `couldn't find remote ref`; two whose old default still existed followed it silently. Full clones kept a stale `origin/HEAD`.
- **Renames and transfers.** GitHub's git endpoint answers an old name with the repository and no redirect, so neither git, ghq nor the writer can see a rename; 21 clones (3.7%) followed an old name, five of them beside a second clone under the new name. Three upstreams were gone (404), eight archived, and eleven clones differed from upstream only in letter case.
- **Writer umask on darwin.** 31 repositories and 105,754 entries carried permission for others; a clone requested through the writer on 2026-11-16 was created `0755`. `launchctl print` reports the job's `umask = 27`, yet launchd does not apply it to the inetd-style instance it starts per connection; its own `StandardErrorPath` file is `0644` too. NixOS (systemd `UMask=0027`) has no such entry on magnetite or pyrite.

A manual cleanup on 2026-11-16 retired or relocated the 21 renamed and 4 frozen clones; this change does not redo it.

## Options

- D28: on update, the writer reads the remote's default branch with `git ls-remote --symref origin HEAD` (no token) and follows it: a single-branch clone is pointed at the new branch, fetched at its depth and checked out on it; a full clone has `origin/HEAD` moved and changes branch only when it was on the previous default and has no local change.
- D29: a read-only `ghq-sync --audit [QUERY]`, run as a participant with that account's `gh` token, batching GraphQL `repository()` (which follows renames) over `ghq list`, printing findings and the administrator commands that resolve them.
- D30: a writer action that deletes or relocates clones. Rejected: any participant, agents included, could remove a repository another account is reading; the writer has no token and git cannot show a rename, so it would act on the caller's claim; and a deleted upstream's clone may be the only copy.
- D32: set the umask in the handler itself, since the cause is in launchd and outside the handler's control; correct existing entries by an operator script that only removes permissions.

## Outcome

D28, D29 and D32 are built; D30 is decided against and stated in the trust boundary (operator decision, 2026-11-16).
