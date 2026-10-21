# Stibnite activation and migration runbook

This is the record of the 2026-10-17 run with the migration tool of that day; the commands and outputs below describe that version, not the administrator-only tool of design D10 that replaced it.

This runbook covers task 9.3 on stibnite, the darwin workstation that also runs the orchestrating sessions.
The user runs the activation; the agent runs the read-only checks, the dry runs and the smoke, and runs `--apply` only after the user's explicit yes.

## Facts it rests on

The tree is `/Users/crs58/ghq`, owned by `crs58:staff`, about 195 GiB (209,425,690,624 bytes), 557 repositories by `ghq list`, 2,216,934 filesystem entries.
`/Users/omnigent-cameron/ghq` and `/var/lib/ghq` do not exist.
`stat -f %d` reports 16777234 for both `/Users/crs58/ghq` and `/var/lib`, so the move is a rename on one APFS volume.

The activation pin is `72872bd755c491406a4eb103facc80f69a26e7af`, the chain tip after the 2026-10-17 rebase onto main `a521e573` (which includes the greptimedb S1 work), taken just before this paragraph was written.
A self-referential pin is not possible, because recording the pin changes the commit that records it; the pinned commit differs from the commit holding this paragraph only in this file, so their stibnite closures differ only in the flake `source`.
There, `darwinConfigurations.stibnite.config.system.build.toplevel.drvPath` and `checks.aarch64-darwin.darwin-stibnite.drvPath` are both `/nix/store/yhqs4ikz177r9qnyvxbmrv3q4fnr65x9-darwin-system-26.11.4cff07d.drv`, whose output is `/nix/store/8ly0ph8w2b2x0x1ivwgi7j07i1wbyrpr-darwin-system-26.11.4cff07d`.
`nix store diff-closures` from the running system to that output adds only `ghq-shared`, `ghq-writer.json` and `org.vanixiets.ghq-writer.plist`, with `ghq` and the flake `source` changing; against the earlier pins `39321af4` (output `84kfrxp5…`) and `75d4324f` (output `nkhnfgfa…`) only `source` differs, so main's additions, greptimedb and otel-collector included, do not reach stibnite.

## Why the existing `~/ghq` does not abort activation

crs58's link is the Home Manager activation step `home.activation.ghqSharedLink` (`modules/home/development/repository-acquisition.nix`), not a `home.file` entry.
It links `~/ghq` only when the path is absent or already a symlink; otherwise it calls `warnEcho` (home-manager `lib/bash/home-manager.sh:43`) and exits zero.
Home Manager's `checkLinkTargets` (`modules/files.nix:177`) inspects only `home.file` targets, so it never examines `~/ghq`.
nix-darwin runs each user's Home Manager activation inside `postActivation` (home-manager `nix-darwin/default.nix:19-40`) under `set -e` (nix-darwin `modules/system/activation-scripts.nix:88`), so a failing step there would stop activation before `/run/current-system` is updated; the warn-and-skip step cannot cause that.
The root provisioning, which runs earlier at the start of the launchd phase, aborts only on a symlink, a non-directory, or a non-empty directory not owned by `_ghq` at `/var/lib/ghq`.
Rolling back leaves `_ghq` in place, because nix-darwin deletes only `knownUsers` that are no longer declared (`modules/users/default.nix:26`).

## Order

Activate, then migrate at once; no second activation is needed, because `ghq-shared-migrate --apply` creates the `~/ghq` symlink itself and later activations accept a symlink.
Renaming `~/ghq` aside before activation is rejected: nothing blocks, and the tool reads only `~/ghq`.
Between activation and `--apply`, crs58's `ghq` and `ghq-sync` already use the empty shared root, so avoid fetching reference repositories in that window.

## Steps

0. Pre-activation dry run, read-only, as root:
   `sudo -n env GHQ_SHARED_WRITER=nobody /nix/store/k4pfbiq55rrvnc2phbhp7f02r3z96wqr-ghq-shared-0.1.0/bin/ghq-shared-migrate crs58 omnigent-cameron`
   The writer account is used only by `--apply`; the plan touches nothing.
1. Activation, run by the user, pinned to the tip:
   ```bash
   T=72872bd755c491406a4eb103facc80f69a26e7af
   o=$(nix build --no-link --print-out-paths "git+file:///Users/crs58/projects/vanixiets?rev=$T#darwinConfigurations.stibnite.config.system.build.toplevel")
   test "$o" = /nix/store/8ly0ph8w2b2x0x1ivwgi7j07i1wbyrpr-darwin-system-26.11.4cff07d \
     && sudo darwin-rebuild switch --flake "git+file:///Users/crs58/projects/vanixiets?rev=$T#stibnite" 2>&1 \
     | tee logs/ghq-stibnite-activate-$(date +%Y%m%d-%H%M%S).log
   ```
   Expect the Home Manager warning that `/Users/crs58/ghq` is a directory.
   Rollback: `sudo darwin-rebuild --rollback`.
2. Post-activation checks, read-only: `dscl . -read /Users/_ghq UniqueID PrimaryGroupID` shows 460/460; `dscl . -read /Groups/_ghq GroupMembership` lists `crs58 omnigent-cameron`; `stat -f '%Su:%Sg %Lp' /var/lib/ghq /var/run/ghq-writer.sock` shows `_ghq:_ghq 750` and `root:_ghq 660`; `sudo launchctl print system/org.vanixiets.ghq-writer` shows the job; `ghq root` and `git config --get-all safe.directory` as crs58 show `/var/lib/ghq` and `/var/lib/ghq/*`; `ls /var/lib/ghq` from an already-running crs58 shell succeeds (macOS resolving new membership for running processes is an inference to confirm here; if it fails, sessions need a fresh login).
3. Migration dry run as root, now with `_ghq` present; its dirty and local-only list goes to the user, and the agent stops for an explicit yes.
4. `--apply` after that yes: `sudo …/ghq-shared-migrate --apply crs58 omnigent-cameron`.
   The rename is O(1); the ownership pass touches all 2.2 million entries (metadata only) and records each original owner and mode in a root-only sidecar under `/var/lib/ghq-migration/crs58/`; then each `.git/config` is rewritten to the allow-list, non-sample hooks are removed with originals kept, and `~/ghq` becomes a symlink.
   Rollback: `sudo …/ghq-shared-migrate --rollback crs58 omnigent-cameron`, about as slow as the ownership pass.
5. Smoke as crs58 and omnigent-cameron, with `stat -f %Su` for the owner, plus the `_ghq` write control and the `nobody` socket probe.
6. Deleting `/var/lib/ghq-migration/crs58` is a separate, user-authorized step.

## Restarts during activation

`org.nixos.omnigent-host-cameron` changes (new worker start script and PATH), so nix-darwin reloads it and any session running inside the omnigent-cameron worker is interrupted.
crs58's Home Manager agent `org.nix-community.home.sops-nix` is reloaded and re-decrypts crs58's user secrets.
`org.vanixiets.ghq-writer` is new and starts only on the first request; `org.nixos.activate-system` changes with every generation.
Interactive crs58 sessions are not launchd jobs and should survive.

## Group membership in running sessions

Linux fixes supplementary groups at login, so on pyrite and magnetite cameron's sessions that predate activation need a fresh login or `newgrp ghq` before they can read `/var/lib/ghq`; the restarted Omnigent workers already carry the group.

## Step 0 result, 2026-10-17

The pre-activation dry run (`logs/ghq-stibnite-migrate-dryrun-pre-20261017-023400.log`, outside version control) took 83 s, exited 0 and changed nothing.
It planned `crs58: /Users/crs58/ghq (557 repositories; rename whole tree)` and `omnigent-cameron: nothing to move`.
It found no duplicates, no repository with a `.git` file, 4 repositories with uncommitted changes and 21 with commits on no remote (one has both), all of which move as they are and become read-only to crs58:

- uncommitted changes: `github.com/bastani-inc/atomic-crash-course`, `github.com/sciexp/flytezen`, `github.com/ulysseherbach/harissa-sandbox`, `gitlab.freedesktop.org/upower/upower`
- commits on no remote: `github.com/Mic92/nixbot`, `github.com/Mic92/sops-nix`, `github.com/cameronraysmith/atomic`, `github.com/cameronraysmith/bayesflow`, `github.com/cameronraysmith/dagster-university`, `github.com/cameronraysmith/docs`, `github.com/cameronraysmith/insdcio`, `github.com/cameronraysmith/northstar`, `github.com/cameronraysmith/omnigent`, `github.com/cameronraysmith/playwright-web-flake`, `github.com/nixos/nixpkgs`, `github.com/pinellolab/stormi`, `github.com/pyrovelocity/pyrovelocity`, `github.com/sciexp/flytezen`, `github.com/sciexp/ironstar`, `github.com/sciexp/omicslake`, `github.com/sciexp/omicsvortex`, `github.com/sciexp/python-nix-template`, `github.com/sciexp/sciops`, `github.com/sciexp/slidestar`, `github.com/theosysbio/FlowClass.jl`

## Step 1–3 results, 2026-10-17

The user activated with `just activate`, which builds from the working copy rather than the pinned revision, giving `/nix/store/h8d9qql1z64g4y94m6wzi9sgaq20ayyn-darwin-system-26.11.4cff07d` (previously `ip2nmsbc…`); `readlink /run/current-system` confirms it.
Its closure diff against the previous system matches the pin's (`ghq-shared`, `ghq-writer.json` and `org.vanixiets.ghq-writer.plist` added, `ghq` and the flake `source` changed), so it differs from the pinned output `8ly0ph8w…` only in `source`; no other session's work reached stibnite.

Post-activation checks passed: `_ghq` is UID/GID 460 with shell `/usr/bin/false` and members `crs58 omnigent-cameron`; `/var/lib/ghq` is `_ghq:_ghq 750`; `/var/run/ghq-writer.sock` is `root:_ghq 660` and `org.vanixiets.ghq-writer` is loaded, socket-activated and idle; crs58's `ghq.root` is `/var/lib/ghq` and `safe.directory` is `/var/lib/ghq/*`; the omnigent-cameron worker generation carries the same and the `ghq-shared` wrapper; its daemon is running.
`ls /var/lib/ghq` succeeds from a crs58 shell started before activation even though that shell's `id -Gn` does not list `_ghq`, so macOS resolves the new membership for running processes and no fresh login is needed.
`ghq root` prints `/private/var/lib/ghq`, because ghq resolves symbolic links in its root (A35) and `/var` is a link to `/private/var` on darwin.
The repository's development shell puts nixpkgs `ghq` ahead of the profile on `PATH` inside this checkout, so there `ghq` is the unwrapped binary; a login shell resolves the `ghq-shared` wrapper.

The step 3 dry run (`logs/ghq-stibnite-migrate-dryrun-20261017-122533.log`) took 83 s, exited 0, changed nothing, planned the same whole-tree rename of 557 repositories, and flagged exactly the same 24 lines as step 0.

## Step 4–5 results, 2026-10-17

The user ran `ghq-shared-migrate --apply crs58 omnigent-cameron`; it moved 557 repositories into `/var/lib/ghq` by rename and left `/Users/crs58/ghq.pre-shared-20261017` empty, since a whole-tree rename sets nothing aside.
Stibnite was then activated at `/nix/store/bzn91p7imi8rk9i6h40n9dj3g9svlmcy-darwin-system-26.11.4cff07d`, which carries the writer-log fix (`/var/log/ghq-writer/`, `_ghq:_ghq 0750`), the root-conditional wrapper and path-target resolution.

The smoke (`logs/ghq-stibnite-smoke-*.log`) passed for crs58 and omnigent-cameron: the shared root by `realpath` (`/private/var/lib/ghq`), `ghq.root`, the `~/ghq` link and `safe.directory = /var/lib/ghq/*`; a delegated clone of octocat/Hello-World owned by `_ghq`, listed by `ghq list -p` and zoxide; `git log` and `git status`; `ghq-sync -u .` from a subdirectory of github.com/Mic92/nixbot; the negative control, where `GIT_CONFIG_GLOBAL=/dev/null git status` reports dubious ownership; and refusal of creating files, writing or appending `.git/config`, `git fetch`, `ghq get -- -x` and `ghq create`.
The controls passed: `_ghq` can write; `nobody` can neither list the root nor connect to `/var/run/ghq-writer.sock`; and each request appended to `/var/log/ghq-writer/writer.log`.
The two owner checks first reported failures because the profile puts GNU `stat` ahead of `/usr/bin/stat` in login shells, so `stat -f %Su` printed filesystem data; `/usr/bin/stat -f %Su` reports `_ghq` for both accounts.
The stopgap `/var/log/ghq-writer.log` from the first run is no longer written and is left for the user to remove.
