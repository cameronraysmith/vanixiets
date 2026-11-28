Verification is by evaluation (`nix-stock eval`), by building the named check (`nix build`), by `just drv-diff <parent> <commit> <allow-list>` (about 16 minutes, run by the operator), by the reader measure (fresh agents), or by observation on a deployed host; each task says which.
Each step is one pull request of one commit; mutants run in a throwaway tree under `/tmp`, never in the working copy.
Code comments added by any task carry no design, task or assumption identifiers, dates, measurements, log paths or change history; those belong in this change's Markdown. `just comment-gate <rev>` runs on each commit before it is published.
Each step's pull request description names the open changes design D5 lists for its files, and whichever lands second is rebased.

## 1. Measure kit and misleading texts (design D1, D5 step 1)

- [ ] 1.1 Commit `docs/notes/development/reader-measure/` with the protocol (tree and commands arms), the twenty lookup questions and keys (Q1's naming the omnigent clan service route, `modules/clan/services/omnigent/flake-module.nix:20-23`), the ten hard tasks (PL1-PL5, E1-E3, I1-I2) with keys from the graded baseline, the baseline numbers with their sample sizes, and a grading script reporting counts of runs — verify: the grading script, run on the baseline transcripts, reproduces design D1's baseline column
- [ ] 1.2 Correct the texts behind four misleads: a header in `machines/nixos/cinnabar/matrix.nix` stating it serves tuwunel with no PostgreSQL (Q1); `fleet-observability.md:607` (Q6); stibnite's host comment pointing to `lib/host-users.nix` for the uid (Q19); and, if Open Question 12 is accepted, an `.ignore` entry for `openspec/changes/archive/` (Q17) — verify: `rg 'deployed to magnetite and cinnabar' packages/docs` finds nothing; `rg -l omnigent openspec` without `--no-ignore` lists no archived path; `just comment-gate <rev>` passes; **[operator]** `just drv-diff` against an empty allow-list exits 0

## 2. Host lists (design D2(d), D5 step 2)

- [ ] 2.1 Add `tags` and `description` to the host record in `modules/lib/hosts.nix`, move each host's values there, and compute `flake.clan.inventory.machines` from the registry — verify: `nix-stock eval --json .#clan.inventory.machines` equals the parent's value
- [ ] 2.2 Delete the assert at `checks/machines.nix:78-79` comparing `machineSystems` names with the inventory's, now equal by construction — verify: `rg -n 'machineSystems names must match' modules` finds nothing; the machine check drvPaths equal the parent's
- [ ] 2.3 Derive `machineAnchors` (`checks/sops-correspondence.nix`) from the registry's enrolled hosts — verify: the evaluated anchors equal the parent's; `nix build .#checks.x86_64-linux.sops-correspondence` succeeds
- [ ] 2.4 Derive the ssh `logins` from the host-users admin attachment, phones literal, if the evaluated attribute set equals today's for every host; otherwise keep the literal and add a key check against the registry — verify: `nix-stock eval` of the crs58 and cameron homes' `programs.ssh.matchBlocks` equals the parent's
- [ ] 2.5 Add fleet checks comparing `lib/cloud-machines.nix`'s keys with the registry's cloud hosts and `observabilityHostsFor`'s keys with the registry's hosts, each with a phantom entry written as `checks/validation.nix:105-120` writes one — verify: both build; a mutant row for an unknown name fails naming it
- [ ] 2.6 Add the phantom entry to `structure-fleet` (O12) — verify: the check builds; a mutant that makes the comparison ignore kinds makes the phantom's actual differ from its expected value and fails
- [ ] 2.7 Write the host-onboarding guide's section: the host lists by treatment, the two left by hand (`ztRecords`, the justfile's list), and the ordered generated steps (key and vars, bridge re-encryption, `fleet-deployers` link, topology) each with its check — verify: a throwaway tree adding enabled host `basalt` with key and vars but no `fleet-deployers` link fails `sops-correspondence` naming basalt, and the guide names that step and check
- [ ] 2.8 Write the step's allow-list (the added checks; `fleet-alert` if it renders `testSizes`) — verify: **[operator]** `just drv-diff <parent> <commit> openspec/changes/shape-the-repository-for-its-readers/drv-delta-host-lists.txt` exits 0 with no host or home listed

## 3. Composition command and route judge (design D2(g), D5 step 3)

- [ ] 3.1 Re-read A386's sources at the locked revisions — verify: `nix-stock eval --json .#nixosConfigurations.magnetite.graph --apply 'g: builtins.attrNames (builtins.head g)'` lists `disabled`, `file`, `imports`, `key`; the same for `darwinConfigurations.stibnite` and `homeConfigurations."crs58@aarch64-darwin"`
- [ ] 3.2 Add the route classifier to `flake.lib` and the `just composition <name>` recipe — verify: `just composition magnetite` prints the 80 names of the graded E1 key, each with one route kind; `just composition crs58` prints the systems `structure-home-configurations` pins
- [ ] 3.3 Measure one host's machine-check evaluation with and without the judge — verify: `just eval-cost` arms recorded in `logs/srr-3-eval-cost-<ts>.log`; return the measurement before registering if the fleet's machine checks would grow by more than five minutes
- [ ] 3.4 Pass each configuration's `graph` to judges that ask for it in `checks/machines.nix`, register `composition-routes` in `fleetObligations` and its key in `registeredObligations`, and add its fixture check with a named module under an unknown parent — verify: the machine checks build; the fixture check fails on a mutant fixture whose unknown parent is removed from the expected failures
- [ ] 3.5 Write the step's allow-list (the machine checks and the fixture check) — verify: **[operator]** `just drv-diff` against `drv-delta-composition.txt` exits 0 with no host or home listed

## 4. Placement rules (design D2(b), D5 step 4)

- [ ] 4.1 Rewrite `modules/README.md` as the map: kinds table, directory principle, placement table (host, person, fleet-wide setting, feature for some hosts, Mac application, server service, hand-entered secret, home tool, check), route kinds, where each order is written, the read-only commands — verify: each placement row cites one existing file that follows it
- [ ] 4.2 Add `modules/checks/README.md` with the ladder and its `checked = false` exception; align the `preferences-nix-checks-architecture` skill source under `modules/home/ai/plugins/` — verify: the three texts state the same rungs and exception; `nix build` of the plugin output that delivers the skill succeeds
- [ ] 4.3 State the hand-entered secret shape in `modules/system/secrets.nix`'s header and reword `darwin/darwin-workstation.nix:11-13` for Mac applications — verify: `just comment-gate <rev>` passes; **[operator]** `just drv-diff` against an empty allow-list exits 0

## 5. Priority, then order (design D2(f), D5 steps 5a and 5b)

- [ ] 5.1 Record the parent's drvPaths of the ten toplevels, the twenty standalone homes and their checks, and each Mac's `users.knownUsers`, `knownGroups`, uids and gids — verify: recorded in `logs/srr-5-baseline-<ts>.log`
- [ ] 5.2 For every enabled host, build its system path at the parent and list each path provided by two or more equal-priority members with differing file contents — verify: the list, with each path's winner and losers, recorded in `logs/srr-5-collisions-<ts>.log`; a member absent from the store is built, not skipped
- [ ] 5.3 Mark each listed winner with `lib.hiPrio` (or loser with `lib.lowPrio`) where it is added; commit as step 5a — verify: rebuilt system paths resolve every listed path to a file with the same content hash as at the parent; **[operator]** `just drv-diff` against `drv-delta-priority.txt` (the profiles containing a marked package) exits 0
- [ ] 5.4 Add the sort modules for `environment.systemPackages` (NixOS, darwin) and `home.packages` (`home-manager.sharedModules`, `flake.lib.mkHome`); remove the `lib.mkAfter` at `lib/host-users.nix:166` — verify: each host's and home's package list has the same members as at the parent, sorted
- [ ] 5.5 Key `programs.gh-dash.settings.keybindings.prs` by key, rendered `m`, `M`, `C` — verify: the rendered `gh-dash-config.yml` lists the three bindings in that order
- [ ] 5.6 Write the overlay order as one list in `nixpkgs/compose.nix`, equal to today's merge order — verify: every toplevel's drvPath is unchanged by this task alone
- [ ] 5.7 Give the four darwin launchd `mkBefore` snippets and stibnite's k8s certificate snippet slots in `activationOrder` keeping today's order — verify: each Mac's rendered activation script equals the parent's
- [ ] 5.8 Judge every changed toplevel and home with `openspec/changes/name-the-parts-of-base-and-ai/drv-order-trace.py` — verify: it exits 0 for each, accepting only `chosenOutputs` order and the gh-dash bindings' order
- [ ] 5.9 Build every system path and `home-manager-path` the trace reports at the parent and at the commit; compare, for each path, the content hash of the file it resolves to — verify: no path differs in content (recorded in `logs/srr-5-profiles-<ts>.log`); each Mac's accounts, groups and ids equal 5.1's
- [ ] 5.10 Write the allow-list (every toplevel, standalone home, machine and home check) and commit as step 5b — verify: **[operator]** `just drv-diff` against `drv-delta-order.txt` exits 0

## 6. Parts lists resumed, then moves (design D2(c), D2(e), D5 step 6)

- [ ] 6.1 Apply `name-the-parts-of-base-and-ai` tasks 3.1-3.2 (darwin `base`) and 4.1-4.2 (`ai`) on top of group 5, names unchanged — verify: that change's task 1.1 inventory lists only the list files; `nix build .#checks.x86_64-linux.structure-aspect-parts` succeeds
- [ ] 6.2 Split the files assigning into two aggregates (`development/gh-dash.nix`, `tools/omnigraph.nix`, `shell/session-path.nix`, `system/cli-tools/host-inspection.nix`) into named parts of one concern — verify: each module's definitions come from one file
- [ ] 6.3 Move `nixos/ntfy-alerter.nix` and `nixos/hm-sops-bridge.nix` to `system/` — verify: `rg -l 'flake.modules.darwin|darwin\.' modules/nixos` lists no file defining a darwin module
- [ ] 6.4 Confirm no derivation changed — verify: **[operator]** `just drv-diff` against `drv-delta-parts.txt` (structure check only) exits 0

## 7. People's literals (design D5 step 7)

- [ ] 7.1 Default `meta.username` to the attribute key and drop the five literals (O11); default the aggregate list and drop the four identical literals (O22) — verify: each user's evaluated `meta.username` and aggregate names equal the parent's
- [ ] 7.2 Add a per-user content constructor and rewrite the five user `default.nix` files with it (O03, O17) — verify: every home's drvPath equals the parent's
- [ ] 7.3 Add a clan user-instance constructor and rewrite `clan/inventory/services/users/{cameron,crs58,tara}.nix` (O04); read ssh keys from the people registry at the four O09 sites — verify: `nix-stock eval .#clan.inventory.instances` and every toplevel drvPath equal the parent's
- [ ] 7.4 Confirm no derivation changed — verify: **[operator]** `just drv-diff` against an empty allow-list exits 0

## 8. Deploy (design Migration Plan)

- [ ] 8.1 **[operator]** Name the standalone `crs58@*` and `cameron@*` homes activated today, and where — verify: recorded in design.md Resolved Questions with the date
- [ ] 8.2 **[operator]** Deploy cinnabar, magnetite and pyrite — verify: each deploy succeeds; `readlink /run/current-system` equals the evaluated toplevel's `outPath` at the deployed commit; every alert or notice posted since the deploy started is read from the alerting logs and recorded with its cause
- [ ] 8.3 **[operator]** Deploy stibnite, argentum and rosegold — verify: each succeeds with no `deleting user` or `deleting group` line; `readlink /run/current-system` equals the evaluated toplevel; every alert or notice since the deploy started is read and recorded with its cause
- [ ] 8.4 **[operator]** Activate each home named in 8.1 — verify: the activated generation is the evaluated `activationPackage`; every alert or notice since is read and recorded with its cause
- [ ] 8.5 Record that electrum, galena and scheelite (disabled) and blackphos (no machine) were not deployed and take the new derivations when next provisioned — verify: the record in design.md Resolved Questions names each

## 9. Close-out

- [ ] 9.1 List every one-shot branch this change added (none planned; the `lib.mkAfter` removed in 5.4 is the only retired conditional) and remove any left — verify: `rg -n 'mkAfter' modules/lib/host-users.nix` finds none
- [ ] 9.2 Update `docs/notes/development/architectural-principles.md`: O03, O04, O09, O11, O12, O17, O22 and L5 resolved with their commits — verify: each entry carries its resolving commit

## 10. Integration Verification

- [ ] 10.1 Re-run both reader sets, both arms, three runs each, same model and effort, on the last commit — verify: the grading script reports, per target of design D1, the count of runs meeting it beside the baseline; a miss is recorded with the next step design D3 names for it
- [ ] 10.2 A new server joins every host list it must — verify: a throwaway tree adding `basalt` by the guide passes the structure, correspondence and machine checks after editing the 9 hand-written lists and running the guide's generated steps
- [ ] 10.3 Every named module of every checked host arrives by a known route — verify: the machine checks with `composition-routes` succeed on the last commit
- [ ] 10.4 Every host and home changed only in declared priority and order — verify: the drv-diff reports of groups 1-7 pass and their combined changed set equals the allow-lists of 5.3 and 5.10 plus the added checks
