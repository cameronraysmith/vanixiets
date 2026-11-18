# Bound the fleet's garbage collection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. In this jj development join "commit" means routing the task's hunks into the change's chain with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`; never `jj edit`, rebase or push.

**Goal:** Every harmonia-gc run on every host ends within 2 hours, darwin keeps its output, laptops keep 7 days of generations and expire people's generations after 14 days, magnetite keeps a warm store, the laptops report their disks, and a stuck run is alerted.

**Architecture:** `modules/system/harmonia-gc.nix` stays the one home of the fleet's collection settings and gains `flake.lib.harmoniaGcObligations`, whose pure judge is asserted on every existing machine check and exercised over fixtures by one x86_64-linux check. Host-specific settings live in the host's file (magnetite), personal expiry in the home-manager nix module, reporting in the observability host table and the fleet-alert rules.

**Tech Stack:** Nix (flake-parts, import-tree), nix-darwin launchd, NixOS systemd, harmonia `8d717e07`, home-manager, the fleet-alert rule check.

**Spec:** `openspec/changes/bound-fleet-garbage-collection/` — `design.md` (D1-D11, Gate 1 table), `specs/store-garbage-collection/spec.md`, `specs/store-garbage-collection-interface/spec.md`, `specs/host-metrics-collection/spec.md`, `specs/world-assumptions/spec.md` (A148-A152), `tasks.md`.

## Global Constraints

- Bound: `"2h"` on every host; NixOS via `TimeoutStartSec`, darwin via `[ "${pkgs.coreutils}/bin/timeout" "2h" ] ++ config.services.harmonia-dev.gc.argv`.
- darwin log: `StandardOutPath = StandardErrorPath = "/var/log/harmonia-gc.log"`.
- `deleteOlderThan`: darwin `"7d"`, NixOS `"10d"`; `keepRecent = "1d"` everywhere.
- home-manager: `autoExpire = { enable = true; timestamp = "-14 days"; frequency = "daily"; store.cleanup = false; }`.
- magnetite: `ensureFree = "40%"`, `noVacuum = true`; min-free 30 GiB / max-free 80 GiB unchanged.
- Unchanged: darwin min-free/max-free 5/10 GiB; `nix.optimise.automatic = false` on darwin.
- Never copy upstream's `argv`; read it from `config.services.harmonia-dev.gc.argv`.
- Check key sets stay static: the new check's name is a literal under `lib.optionalAttrs (system == "x86_64-linux")`.

## Review Focus

- A later module that `mkForce`s `ProgramArguments` or drops `TimeoutStartSec`: the obligation judges the merged value, so it must fail (pinned by task 1's machine-check red step and task 6.4).
- A harmonia bump that adds an argument: the wrapper must still end with exactly `argv` (pinned by the "wrapper around a different argument list" mutant).
- `timeout` sending SIGTERM to a process blocked in `flock`: it must exit (pinned by task 2's stibnite probe).
- `ensureFree = "40%"` against a pool-sized `df`: stop and ask (pinned by task 4 step 1).
- An 8 GiB laptop gaining the collector: read memory before and after (pinned by task 5's argentum step).

---

### Task 1: The obligation and its fixture check (tasks.md 1.1-1.3)

**Files:**
- Modify: `modules/system/harmonia-gc.nix`
- Create: `modules/checks/harmonia-gc-obligations.nix`
- Modify: `modules/checks/machines.nix` (`withFleetObligations`)

**Interfaces:**
- Produces: `self.lib.harmoniaGcObligations = { bound :: str; logPath :: str; problems :: { platform :: "nixos" | "darwin"; service :: attrs; argv ? list; timeoutBin ? str } -> [str]; failures :: name -> hostConfig -> [str]; }`.
  `failures` reads `hostConfig.systemd.services.harmonia-gc.serviceConfig` on NixOS, and `hostConfig.launchd.daemons.harmonia-gc.serviceConfig` with `hostConfig.services.harmonia-dev.gc.argv` on darwin; the platform comes from `self.lib.machineSystems.${name}`, as `meshHostsObligations` does.

- [ ] **Step 1:** Write `modules/checks/harmonia-gc-obligations.nix` on the pattern of `modules/checks/mesh-hosts-obligations.nix`: fixtures `nixosOk = { TimeoutStartSec = "2h"; Type = "oneshot"; }`, `darwinOk = { ProgramArguments = [ "/x/bin/timeout" "2h" "/h/bin/harmonia-gc" "--delete-older-than" "7d" ]; StandardOutPath = logPath; StandardErrorPath = logPath; }` with `argv = [ "/h/bin/harmonia-gc" "--delete-older-than" "7d" ]`, and the seven mutants each expecting 1 problem.
- [ ] **Step 2:** Run `nix build .#checks.x86_64-linux.harmonia-gc-obligations`; expected: evaluation error, `harmoniaGcObligations` undefined.
- [ ] **Step 3:** Implement `harmoniaGcObligations` in `modules/system/harmonia-gc.nix`; the darwin judge checks `lib.take 2 ProgramArguments` is `[ <path ending /bin/timeout> bound ]` and `lib.drop 2 ProgramArguments == argv`.
- [ ] **Step 4:** Run the build again; expected: success. Set one mutant's `problems` to 0; expected: failure naming that case; restore.
- [ ] **Step 5:** Add `unmetHarmoniaGc = harmoniaGcObligations.failures name machineConfig;` to `withFleetObligations` and to its condition and message.
- [ ] **Step 6:** Run `nix eval .#checks.x86_64-linux.nixos-cinnabar.drvPath` and `nix eval .#checks.aarch64-darwin.darwin-stibnite.drvPath`; expected: both fail naming `harmoniaGcObligations` (red). Record the messages in `verify.md`.
- [ ] **Step 7:** Commit (route the three files into the chain).

### Task 2: The bound and the darwin log (tasks.md 2.1-2.4)

**Files:**
- Modify: `modules/system/harmonia-gc.nix`
- Modify: `modules/darwin/nix-settings.nix:59-60`

**Interfaces:**
- Consumes: `harmoniaGcObligations.bound`, `.logPath`.

- [ ] **Step 1:** NixOS branch: `systemd.services.harmonia-gc.serviceConfig.TimeoutStartSec = bound;`.
- [ ] **Step 2:** darwin branch: make it a function of `{ config, pkgs, lib, ... }` and set `launchd.daemons.harmonia-gc.serviceConfig = { ProgramArguments = lib.mkForce ([ "${pkgs.coreutils}/bin/timeout" bound ] ++ config.services.harmonia-dev.gc.argv); StandardOutPath = logPath; StandardErrorPath = logPath; };`.
- [ ] **Step 3:** Run Task 1 step 6's evaluations plus `nixos-magnetite`, `nixos-pyrite`, `darwin-rosegold`, `darwin-argentum`, `darwin-blackphos`; expected: all evaluate.
- [ ] **Step 4:** On stibnite, read the evaluated `ProgramArguments`, replace `2h` with `60s`, hold the lock (`sudo flock /nix/var/nix/gc.lock sleep 600` from a flock available on darwin), run the list with `sudo`; expected: exit 124 after about 60 s, lock holder unaffected. Then `nix-store --verify`. Record in `verify.md`.
- [ ] **Step 5:** Rewrite the comment; `rg -n "15% free" modules/` finds nothing.
- [ ] **Step 6:** Commit.

### Task 3: Rollback window and personal expiry (tasks.md 3.1-3.3)

**Files:**
- Modify: `modules/system/harmonia-gc.nix` (darwin `deleteOlderThan = "7d"`)
- Modify: `modules/home/tools/nix.nix`

- [ ] **Step 1:** The window is a plain value with no logic of ours to judge, so it is verified by evaluation, not by a new check (placement ladder). Run `nix eval --json .#darwinConfigurations.stibnite.config.services.harmonia-dev.gc.argv`; expected before the change: `10d`.
- [ ] **Step 2:** Set darwin `deleteOlderThan = "7d"`; re-run; expected: `7d`; cinnabar still `10d`.
- [ ] **Step 3:** Confirm `services.home-manager.autoExpire` and `store.cleanup` exist in the locked home-manager and support darwin; record the declaration path.
- [ ] **Step 4:** Set the autoExpire block; evaluate it for one user on stibnite and one on pyrite; build the launchd agent and read that it runs `expire-generations` only.
- [ ] **Step 5:** Commit.

### Task 4: magnetite's warm store (tasks.md 4.1-4.2)

**Files:**
- Modify: `modules/machines/nixos/magnetite/default.nix` (beside `min-free`, line ~375)

- [ ] **Step 1:** On magnetite: `df -B1 /nix`; `zfs get -p quota,available,used <store dataset>`. If `df`'s size is not the quota, stop and ask the operator.
- [ ] **Step 2:** Set `services.harmonia-dev.gc = { ensureFree = "40%"; noVacuum = true; };`.
- [ ] **Step 3:** `nix eval --json .#nixosConfigurations.magnetite.config.services.harmonia-dev.gc.argv`; expected: contains `40%` and the no-vacuum flag.
- [ ] **Step 4:** Commit.

### Task 5: Reporting (tasks.md 5.1-5.9)

**Files:**
- Modify: `modules/lib/observability-hosts.nix`
- Modify: `modules/nixos/fleet-alert/rules.nix`
- Modify: `modules/checks/fleet-alert.nix`

**Interfaces:**
- Produces: rule `GarbageCollectionOverrun` (severity warning, `for: 60m`).

- [ ] **Step 1:** Add the three host entries with `collect = false` (blackphos commented as having no machine); evaluate the otel-collector and fleet-alert checks.
- [ ] **Step 2:** Write the overrun cases in `modules/checks/fleet-alert.nix` (70 minutes fires once, 50 minutes none); build; expected: fail, rule missing.
- [ ] **Step 3:** Add the rule; build; expected: pass. Change `for` to `120m`; expected: the 70-minute case fails; restore.
- [ ] **Step 4:** Commit; then confirm the state label values (tasks.md 5.2) during manual runs on cinnabar and stibnite.
- [ ] **Step 5:** Deploy magnetite and cinnabar, then stibnite, then (after capturing tasks.md 5.6's evidence) rosegold and argentum, each watched, each recording every alert posted since its deploy started.
- [ ] **Step 6:** Set `collect = true` for rosegold in its own commit; deploy magnetite and rosegold; watch. Then argentum, with memory before and after.

### Task 6: Integration verification (tasks.md 6.1-6.4)

- [ ] **Step 1:** The pyrite end-to-end hold, in an operator-chosen window.
- [ ] **Step 2:** `nix-store --verify` on pyrite and stibnite.
- [ ] **Step 3:** One week later, read every host's run durations; set D7's threshold from them.
- [ ] **Step 4:** Scratch-remove `TimeoutStartSec` and `StandardErrorPath`; the machine checks fail; revert.
