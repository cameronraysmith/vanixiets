# Sparse checkout path patterns

Guidance for choosing paths with `git sparse-checkout set` after initializing `--cone` mode.
Cone mode operates at directory granularity — you include entire directories, not individual files.
Files in the repository root are always included.

## General heuristic

Start with the minimal set of directories needed for the task.
When build, eval, or test fails due to missing files, expand with `git sparse-checkout add <dir>`.
This iterative approach avoids over-including and preserves the benefit of sparse checkout.

## Nix flake repositories

Nix flake repos (like nixpkgs) typically need:

- Root is always included (covers `flake.nix`, `flake.lock`)
- Target package path, e.g. `pkgs/by-name/he/hello/`
- `lib/` — most packages reference nixpkgs lib functions
- `pkgs/stdenv/` — if the package uses stdenv internals
- `pkgs/build-support/` — for common builders (fetchurl, fetchFromGitHub, etc.)

Example for editing a package in nixpkgs:

```bash
git sparse-checkout set pkgs/by-name/he/hello lib pkgs/build-support
```

## Monorepos

For monorepos with a `packages/` or `services/` layout:

- Target package/service directory
- Shared dependency directories (`libs/`, `shared/`, `common/`)
- Build configuration root (if separate from repo root)
- CI/CD configuration if modifying pipeline (`.github/`, `.gitlab-ci/`)

Example:

```bash
git sparse-checkout set packages/auth libs/shared .github
```

## Deferred module composition (dendritic) nix repos

For repos using flake-parts with import-tree:

- Root (always included: `flake.nix`, `flake.lock`)
- Target module path, e.g. `modules/nixos/services/ntfy/`
- `parts/` or equivalent flake-parts directory
- Machine-specific config if testing on a machine, e.g. `machines/cinnabar/`
- `lib/` if custom library functions exist

Example:

```bash
git sparse-checkout set modules/nixos/services/ntfy parts machines/cinnabar
```

## Expanding after failures

When `nix build`, `nix eval`, or other commands fail with missing file errors:

```bash
git sparse-checkout add <missing-directory>
```

Repeat until the build succeeds.
The sparse-checkout set is persistent within the worktree so additions accumulate.
