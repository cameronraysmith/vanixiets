# Disabled packages

`modules/nixpkgs/per-system.nix:51` sets `pkgsDirectory = ../../pkgs/by-name`, the tree that `pkgs-by-name-for-flake-parts` auto-discovers into the package set.
This directory is not that tree, so nothing in it is auto-discovered: none of these derivations exist in `.#packages`, `.#checks`, or anywhere else the flake exposes packages, even though the files remain in the repository.

Most entries here are complete, working derivations moved out for a reason unrelated to breakage: a consumer was retired (`beads`, `beads-ui`, and `dolt`, moved out when Linear and OpenSpec took over issue tracking from beads and dolt, as of 2026-08-26), a binary name collided with another tool (`gastown`, whose `gt` collided with graphite-cli), or nixpkgs already ships an equivalent (`smithy-cli`, `golem`, deferring to a lighter `golem-cli`).
Do not assume that pattern holds for every entry without checking its own package file and move commit first.
`python-lancedb`'s own `package.nix` records that its pinned 0.36.0 currently fails to build on `x86_64-linux` (an LLVM ABI mismatch tracked upstream at nixpkgs#524570 and nixpkgs#544495) and that its only consumer dropped it, so this one is both broken and unused rather than merely held out.
`git-repo-manager`'s move landed in a commit titled `fix(pkgs): disable git-repo-manager` with no further explanation recorded, so its status is unverified rather than confirmed working.

Restore an entry with `mv pkgs/disabled/<name> pkgs/by-name/<name>`.
Check the entry's move commit first: several also need a commented-out or removed consumer reinstated elsewhere in `modules/` (for example `modules/home/development/tools.nix`), and restoring the package alone does not bring that consumer back.
