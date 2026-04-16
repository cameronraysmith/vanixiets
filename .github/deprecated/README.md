# Deprecated CI/CD artifacts

Archived CI/CD artifacts from successive pipeline consolidation phases.
Files here are predecessors of currently-active workflows or scripts, preserved for quick restore and diff comparison.
Named by what replaced them, following the ironstar convention.

## Archived files

### Phase 1: categorized matrix to nix-fast-build (PR #1803)

- `ci-pre-nix-check.yaml` -- snapshot of `ci.yaml` prior to the nix-check restructure, replaced by a single `nix-check` job that orchestrates `nix-fast-build` over `.#checks.${system}`.
- `scripts/` -- scripts superseded by nix-fast-build's check execution in CI.

### Phase 2: nix-fast-build to buildbot-nix delegation

- `ci-nix-fast-build.yaml` -- snapshot of `ci.yaml` with the nix-fast-build `nix-check` job, replaced by buildbot-nix evaluation and build on magnetite. The workflow was renamed to `cd.yaml` after this job was removed.

## Restoration

To restore any file, move it back to its original location:

- `ci-pre-nix-check.yaml` to `.github/workflows/ci.yaml`
- `ci-nix-fast-build.yaml` to `.github/workflows/ci.yaml`
- `scripts/*.sh` to `scripts/ci/`
