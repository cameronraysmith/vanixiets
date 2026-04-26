# cd.yaml to herculesCI effects migration — final-state notes

This document was originally drafted on 2026-04-21 as an ADR (commit `d629aa7e3`), then revised on 2026-04-22 to incorporate discovery resolutions.
On reflection it was misclassified: the work it describes is concrete and bounded, not an architecture-level decision worth ADR ceremony.
What follows is the final state of the migration on branch `cd-via-effects` as of 2026-04-26, retained as a working note for value extraction — patterns and rationale worth preserving — rather than as an ADR.
The file may be deleted before the PR merges to main; the final state remains in branch git history.

## What was migrated

Two effect modules already existed prior to this session and now own the CD jobs they correspond to:

- `modules/effects/vanixiets/herculesCI/deploy-docs.nix` — supersedes the GHA jobs `preview-docs-deploy` and `production-docs-deploy`.
- `modules/effects/vanixiets/herculesCI/release-packages.nix` — supersedes `preview-release-version` and `production-release-packages`.

This session removed the four corresponding GHA jobs from `.github/workflows/cd.yaml` and trimmed the workflow's surrounding scaffolding to match what's left.

## What was decided not to migrate, and why

`bootstrap-verification` stays in `cd.yaml` on `ubuntu-latest`.
Its semantic property is "clean-host nix bootstrap works" — it tests the bootstrapping path that *makes* nix usable.
A bwrap-isolated effect on magnetite already has nix, with `/nix/store` ro-bound and no root or systemd; running the bootstrap there would be a structurally different and less faithful test of the same property name.
Keeping it on a fresh GHA runner preserves the test's meaning.

`test-cluster` stays in `cd.yaml`.
It needs a Docker daemon plus worktree access in ways that don't fit bwrap.
Even if `/var/run/docker.sock` were exposed into the bwrap sandbox, containers spawned by `docker run` execute in the host's mount and network namespaces and don't see bwrap-isolated paths anyway.
The cache-locality argument that motivates effects (warm `/nix/store`, niks3 push) doesn't apply because test-cluster's outputs are pass/fail signals, not store paths.
Two future-work options exist if migration becomes worthwhile — wrap as a NixOS VM `nixosTest`, or run as a buildbot-nix worker step outside bwrap — but neither was pursued in this session.

## cd.yaml refactor outcome

Branch `cd-via-effects` shows the final shape.
The four migrated jobs were deleted: `preview-release-version`, `preview-docs-deploy`, `production-release-packages`, `production-docs-deploy`.

`set-variables` was slimmed.
Only `debug` (consumed by `test-cluster`) and `force-ci` (consumed by `bootstrap-verification`) outputs remain.
Package-discovery steps and dead push/pull_request shell branches were removed.

Triggers reduced to `workflow_dispatch:` only — no `push`, no `pull_request`, no `workflow_call`.
Manual dispatch is `gh workflow run cd.yaml --ref <branch> [-f job=<job>]`.

Permissions narrowed from `contents: read` + `deployments: write` to `contents: read` only.

`concurrency.group` simplified to `ci-${{ github.ref }}`.

Vestigial `github.event_name != 'workflow_dispatch'` clauses dropped from the retained jobs' `if:` expressions.

Net diff: cd.yaml went from 407 lines to 145 lines.

## Snapshot rollback pattern

Before any edits, the original cd.yaml was copied to `.github/deprecated/cd.yaml` as a frozen 407-line snapshot.
Rollback if effects misbehave is a single step: `cp .github/deprecated/cd.yaml .github/workflows/cd.yaml`.
The deprecated copy stays frozen — it does not track `cd.yaml`'s evolution, it preserves the pre-migration state.

This supersedes the original draft's "archive cd.yaml at end of Phase 6" framing.
The snapshot was taken at the *start* of editing rather than the end, which means the rollback target is the GHA-only state, not a hybrid intermediate.

## Cleanup commits in release.sh and release-packages.nix

These are independent of the GHA removals but landed alongside them on the same branch.

In `modules/apps/release/release.sh`:

- Dropped unused `SOPS_AGE_KEY` env-var passthrough (no consumer).
- Dropped transitional `GIT_USER_NAME` / `GIT_USER_EMAIL` aliases (no external caller after GHA retirement).
- Updated stale GHA reference in the repo-root resolution comment.

In `modules/effects/vanixiets/herculesCI/release-packages.nix`:

- Dropped unused `dryRunFlag` binding (never threaded into dispatch).
- Extracted `mkReleasePackagesEffect { dryRun ? false }` helper to factor out shared logic between production and rehearsal use.

Net: release.sh 250 to 240 lines; release-packages.nix 183 to 237 lines (growth from helper structure plus comments).

## Rehearsal toggle pattern

This is the load-bearing operational knowledge from the session.

`mkReleasePackagesEffect` takes a `dryRun` parameter.
Production: `effects.release-packages = mkReleasePackagesEffect { dryRun = false; }`.

To rehearse a release without remote mutations: flip `dryRun` to `true` on a feature branch, push to magnetite, run

```
buildbot-effects run --branch main --rev <head> ... release-packages
```

on magnetite, observe semantic-release's full plugin chain run with `--dry-run`, then revert `dryRun` to `false` and commit.
The two transient commits in branch history capture the rehearsal cycle.

Under `dryRun = true` the dispatch always calls `RELEASE -- --dry-run` (full production plugin set, suppressed mutations); the stale-rev guard is bypassed (so rehearsal can run against any rev while declaring `--branch main`); distinct log markers (`RELEASE-PACKAGES-ACTION: rehearsal`, `RELEASE-PACKAGE-DRY-RUN-DISPATCH:`) make it visually unambiguous in logs.

A *persistent* second effect attribute (e.g., `release-packages-dry-run` exposed alongside `release-packages`) was rejected.
buildbot-nix triggers every attribute under `onPush.default.outputs.effects` on every qualifying push, so a persistent rehearsal attribute would auto-fire on every commit to main, producing a no-signal rehearsal run alongside the real one.
The transient toggle pattern keeps the production-effect surface at exactly one attribute.

### release.sh's existing `--` passthrough

The argument parser in `release.sh` already routes `--` followed by additional args into `extra_args`, which is passed verbatim to semantic-release.
So `"$RELEASE" "$pkg_path" -- --dry-run` works without any release.sh changes — this is what the rehearsal dispatch uses.
No `EFFECT_DRY_RUN` env var or other plumbing was needed.

### Stale-rev guard

For the production attribute (`dryRun = false`), the effect aborts before semantic-release runs if local HEAD differs from origin/main HEAD.
This means a manual `buildbot-effects run --branch main` against any non-main rev safely aborts with `RELEASE-CLONE-STALE`.
The actual release fires only after fast-forward of main from `cd-via-effects`.

## Stage 3b verification result

On 2026-04-26 the production code path was verified end-to-end via the rehearsal toggle.

`[@semantic-release/github] - Verify GitHub authentication` returned `Allowed to push to the Git repository`.
This confirms the fine-grained PAT in the `vanixiets-effects-secrets` clan-vars generator has Contents: Read+Write on `cameronraysmith/vanixiets` and authenticates correctly.

The production plugin chain loaded fully: changelog, github (publish + addChannel), commit-analyzer, release-notes-generator, semantic-release-major-tag.

semantic-release-monorepo correctly filtered 76 commits to the 2 touching `packages/docs/`, recognized `fix(docs):` as patch-tier, and computed next version `0.5.1`.

All `Skip ... in dry-run mode` markers fired at correct step boundaries (prepare, publish, success).
Effect exited 0.

## PAT identity transition (parity gap with old GHA path)

The old path used the GHA implicit `GITHUB_TOKEN`: identity `github-actions[bot]`, ephemeral 1-hour token, scope determined by job-level `permissions:` block.

The new path uses a fine-grained PAT from the `vanixiets-effects-secrets` clan-vars generator: identity is the PAT owner (`cameronraysmith`), long-lived (rotation manual), with permissions scoped by what was selected at PAT creation time rather than by per-job `permissions:`.

Releases will appear under the PAT-owner identity rather than the bot.

Branch-protection risk is low because the active plugin list does **not** include `@semantic-release/git` (no commit-back to main).
Only tag pushes occur, and tags aren't protected by default branch rules.
`@semantic-release/git`'s presence in `devDependencies` only is intentional and not cruft — it remains available if commit-back behavior is ever wanted, but isn't loaded by the active plugin chain.

## Verification staircase

Four stages, each exercising strictly more of the production code path:

1. `nix run .#preview-version` from a laptop — preview-version mechanics in isolation.
2. `buildbot-effects run --branch refs/pull/N/merge ... release-packages` on magnetite — the bwrap surface plus the PR-clone preamble; dispatches preview-version per the PR-arm logic.
3. `buildbot-effects run --branch main ... release-packages` with the rehearsal toggle active — the full production code path with `--dry-run`. This is the load-bearing test; Stage 3b above documents its outcome.
4. Actual merge — the only stage that exercises buildbot's onPush trigger plumbing end-to-end. Pending at time of writing.

## Conflicts with the original draft

The original draft proposed a `just ci-dispatch <effect>` recipe wrapping the SSH+CLI invocation.
This was never built; manual dispatch in the final state is the raw `ssh magnetite.zt buildbot-effects run ...` command.
The wrapper recipe could still be added, but is not present.

The original draft listed seven jobs and described a phased migration with parity windows.
The final state migrated four (the docs and release pairs) and explicitly excluded `bootstrap-verification` and `test-cluster` for the structural reasons described above.
`set-variables` was retained in trimmed form rather than removed.
Phase 5 ("per-job parity validation") was not run as a separate observational period; verification happened via the rehearsal toggle (Stage 3b) prior to merge rather than via dual-running both paths in production.

The original draft's exit-criteria block named "Fully-migrated" / "Hybrid-stable" / "Discovery-blocks" outcomes.
The final state corresponds to "Hybrid-stable" with two jobs explicitly held back on architectural grounds rather than for coordination cost.

## References

Final-state files on branch `cd-via-effects`:

- `.github/workflows/cd.yaml` (145 lines, workflow_dispatch only)
- `.github/deprecated/cd.yaml` (407-line frozen snapshot for rollback)
- `modules/effects/vanixiets/herculesCI/release-packages.nix`
- `modules/effects/vanixiets/herculesCI/deploy-docs.nix`
- `modules/apps/release/release.sh`
- `modules/apps/release/release.nix`
- `modules/apps/release/preview-version.sh`

Original draft commit: `d629aa7e3 docs(notes): draft ADR-001 cd.yaml to buildbot migration (v0)`.

Research reports from the original ADR draft (still useful for buildbot-nix mechanics; do not represent the final migration scope):

- `.factory/research/adr-001-validation/01-hercules-effects-buildbot-nix-mechanics.md`
- `.factory/research/adr-001-validation/02-magnetite-state-and-web01-pattern.md`
- `.factory/research/adr-001-validation/03-cd-yaml-inventory.md`
- `.factory/research/adr-001-validation/04-fork-pr-security.md`
- `.factory/research/adr-001-validation/05-ops-triggers-observability-rollback.md`
