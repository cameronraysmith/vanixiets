# Implementation plan

One delivery commit: `feat(pyrite): add DankMaterialShell to niri`.
Author on the existing jj development join; route only the six owned Nix paths and this change directory into `pyrite-dms-prepared` after the niri tip.
No nested executor, worktree or publication is used under the operator's explicit instruction.

## Steps

1. Establish RED by asserting DMS is enabled against immutable slice-A base `1c31c2ab6e827758303b58875daddd8d10a704f7`.
2. Add a non-flake `dms-src` input in `flake.nix` and narrowly lock it in `flake.lock`; compare every pre-existing node and root edge to the base.
3. Add `modules/home/dms/default.nix` as a deferred HM aggregate importing the upstream module with native packages, declared bar/idle/lock settings and niri-only systemd service.
4. Compose the aggregate and native PAM service in `modules/machines/nixos/pyrite/default.nix`; extend typed binds in `modules/home/niri/default.nix` without changing existing actions.
5. Add concrete NixOS assertions in `modules/checks/pyrite-desktop.nix`; these read actual merged configuration rather than inventing probe options or a runner abstraction.
6. Format owned Nix files, route to the delivery change, export its immutable Git revision and evaluate the assertions and preservation settings.
7. Attempt the actual niri configuration and DMS builds using only the daemon's local builder; record unavailable Linux execution as NOT-RUN/blocker.
8. Validate OpenSpec structure, update the ledger, and return immutable refs for independent review.

Every Nix eval/build uses `--store daemon --builders '' --max-jobs 1 --cores 2 --option accept-flake-config false --no-write-lock-file --no-update-lock-file`.
Only the authorized new input lock operation may write the lock file; unrelated pins must not change.
Complete command output and exit status are retained in ignored `logs/pyrite-dms-*` files.
The oracle is literal required values or independent baseline configuration; mutation of service target, package identity or timeout must fail the corresponding assertion.

## Deferred acceptance

Physical rendering, keyboard/touchpad use, authentication, notification/polkit ownership, portal transactions, login/logout and performance have no equivalent evaluation-only test.
They remain unchecked in tasks 4.1–4.5; source generation does not authorize activation or close those gaps.
