# Deprecated CI/CD artifacts

Archived CI/CD artifacts from successive pipeline consolidation phases.
Files here are predecessors of currently-active workflows or scripts, preserved for quick restore and diff comparison.
Named by what replaced them, following the ironstar convention.

## Archived files

- `ci-pre-nix-check.yaml` -- snapshot of `ci.yaml` prior to the nix-check restructure, replaced by a single `nix-check` job that orchestrates `nix-fast-build` over `.#checks.${system}`.
- `scripts/` -- scripts superseded by nix-fast-build's check execution in CI. Kept for reference during the Phase 1/Phase 2 transition; can be removed after buildbot-nix adoption stabilizes.

## Restoration

To restore any file, move it back to its original location:

- `ci-pre-nix-check.yaml` to `.github/workflows/ci.yaml`
- `scripts/*.sh` to `scripts/ci/`
