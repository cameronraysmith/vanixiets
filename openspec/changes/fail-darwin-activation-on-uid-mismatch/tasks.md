## 1. Baselines and grounding

- [x] 1.1 Record the parent commit id and the drvPaths of `darwinConfigurations.{stibnite,blackphos,argentum,rosegold}.config.system.build.toplevel` at it — verify: a log under `logs/` with the commit id and four drvPaths
- [x] 1.2 Re-read A370-A374's cited lines at the locked nix-darwin and clan-core revisions and cite them in a sources log — verify: the log quotes `activation-scripts.nix:88-89,114-140`, `darwin-rebuild.sh:218-233`, `activate-system/default.nix:61-70`, `checks.nix:317-324`, `users/default.nix:197-198,285-288` and clan `update.py:713-725`, each matching the design's reading
- [x] 1.3 Confirm every attachment on the four darwin hosts is in that host's `users.knownUsers` — verify: `nix eval` of each host's `users.knownUsers` contains its attachment names

## 2. The comparison

- [x] 2.1 In the darwin branch of `modules/system/home-manager-integration.nix`, render one comparison per attachment (D3) into `home-manager-integration.uidPreflight` (internal, read-only, lines) and append it to `system.activationScripts.preActivation.text` at order 600 (`lib.mkOrder 600`, design D2) — verify: `nix eval --raw .#darwinConfigurations.blackphos.config.home-manager-integration.uidPreflight` shows crs58 502 and raquel 506 and the option path in the message
- [x] 2.2 Confirm the order inside the rendered `activate`: deploy-record's read, then the comparison, then nix-darwin's own `preActivation` text (`rm -rf /var/lib/linux-builder`) and its checks — verify: `grep -n` over `$(nix build --no-link --print-out-paths .#darwinConfigurations.stibnite.config.system.build.toplevel)/activate` (eval-only alternative: `config.system.build.activate` text, or `config.system.activationScripts.preActivation.text` for the first three) shows them in that order
  - Evidence (2026-11-27, verify): `preActivation.text` evaluated for stibnite, blackphos, argentum and rosegold renders the `/run/current-system` read at lines 2-3, `uidMismatches=()` at line 7 and `rm -rf /var/lib/linux-builder` at line 19 (stibnite) or 23 (the other three)
- [x] 2.3 Confirm NixOS hosts are unchanged — verify: `nix eval` of a NixOS host's `config.system.build.toplevel.drvPath` equals its parent value (and the full comparison in 4.1)

## 3. The mutant check

- [x] 3.1 Add `modules/checks/darwin-uid-preflight.nix`: literal attribute name, `x86_64-linux` gate, host list from `flake.fleet.hosts` darwin class read in the value, three cases per host with a stub `id` (D5); `testSizes.checks.darwin-uid-preflight = { class = "medium"; measured = false; }` — verify: `nix build .#checks.x86_64-linux.darwin-uid-preflight` succeeds
- [x] 3.2 Mutants in a throwaway tree under `/tmp` (never in `@`): (a) empty comparison, (b) comparison that ignores a mismatch, (c) comparison that fails an absent account — verify: the check fails on (a) and (b) in the mutant-uid case and on (c) in the absent case; each run builds only the case it must fail; log under `logs/`
- [x] 3.3 Write `drv-delta.txt` listing exactly the four darwin toplevels (changed), `checks.x86_64-linux.darwin-uid-preflight` (added), `checks.x86_64-linux.fleet-alert` (changed: renders every `testSizes.checks` entry), and any check that embeds the edited files outside the base allow-list — verify: the file exists and each entry carries its reason

## 4. Integration Verification

- [x] 4.1 `just drv-diff <parent> <commit> openspec/changes/fail-darwin-activation-on-uid-mismatch/drv-delta.txt` reports only declared differences (operator runs it; about 16 minutes) — verify: its log names no undeclared attribute
  - Evidence (2026-11-27): `just drv-diff 3fea6f9b152e 2d5daa389571 openspec/changes/fail-darwin-activation-on-uid-mismatch/drv-delta.txt` passes on the first judgement, exit 0, 991.5 s (`logs/drv-diff-3fea6f9b152e-2d5daa389571-20261127T185003Z`): the four darwin toplevels and their machine checks changed, `darwin-uid-preflight` added and `fleet-alert` changed, as declared; every NixOS toplevel, home and runtime test identical. The run covers the comparison at order 600
- [ ] 4.2 On each Mac, before its deploy, the operator runs `darwin-rebuild check --flake .#<host>` (`just darwin-test <host>`) — verify: `ok`, or a named mismatch fixed in `modules/lib/host-users.nix` before deploying
- [ ] 4.3 The operator deploys stibnite, blackphos, argentum and rosegold — verify: each deploy succeeds, no `unexpected uid` warning appears in its output, and every alert or notice posted since the deploy started is read from the alerting logs and recorded with its cause
- [ ] 4.4 Observe A374 on each Mac — verify: `id -u <account>` equals `dscl . -read /Users/<account> UniqueID` for each attachment
