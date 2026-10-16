Each task lands as one commit on the change's linear chain (bookmark `cam-77-share-ghq-reference-tree`), in the order listed.
Groups 1–8 change source only and are verified by `nix eval` or `nix build` against the task's own commit (`git+file://$PWD?rev=<commit>`), so concurrent edits in the shared working copy cannot affect the evidence; nothing is activated on a host before group 9.
`B` below is the baseline revision, the proposal commit; `T` is the task's own commit.
A host's `toplevel.drvPath` changes with every commit because some of its inputs copy the flake source, so "unchanged" below means its *sharing projection* is identical at `B` and `T`: account names, group members, tmpfiles rules, socket units and `ghq*` services (NixOS) or known users and launchd daemons (darwin), and for each Home Manager user its git settings, package names and activation step names, hashed from `nix eval --json --apply`.
Tasks marked *gated* wait for the named approval.

## 1. Participation and the Linux writer

- [x] 1.1 Add `modules/system/shared-reference-tree.nix` exporting `flake.modules.{nixos,darwin}.shared-reference-tree-options` (`services.shared-reference-tree`: `enable`, `participants`, `writer` defaulting to `ghq` on NixOS and `_ghq` on darwin, `root` defaulting to `/var/lib/ghq` or `/Users/Shared/ghq`, `allowedProtocols` defaulting to `[ "https" ]`), adapter aspects `flake.modules.{nixos,darwin}.shared-reference-tree` importing them, and participation in the magnetite, pyrite and stibnite machine modules — verify: `nix eval --json "$T#nixosConfigurations.magnetite.config.services.shared-reference-tree.participants"` and the pyrite equivalent print `["cameron","omnigent-cameron","omnigent-janettesmith"]`, the stibnite darwin equivalent prints `["crs58","omnigent-cameron"]`; the sharing projection of every sharing and non-sharing host is identical at `B` and `T`.
- [x] 1.2 In `flake.lib.omnigentFleetObligations` (`modules/lib/omnigent-fleet-obligations.nix:64-97`), admit exactly the writer's group for a worker its host declares as participating, still rejecting every other group (D6) — verify: `failures "magnetite"` evaluated over magnetite extended with `users.groups.ghq.members = [ "omnigent-cameron" ]` plus participation returns `[]`, and over magnetite extended with `users.groups.users.members = [ "omnigent-cameron" ]` returns a list containing `accounts`.
- [x] 1.3 Declare the NixOS writer: system account `ghq` with group `ghq`, home at the root, `nologin` shell, locked password, no keys, no extra groups; group `ghq` members equal the declared participants — verify: `nix eval --json "$T#nixosConfigurations.magnetite.config.users.groups.ghq.members"` prints the three participants; the writer's `isSystemUser`, `hashedPassword` and `extraGroups` evaluate to `true`, `"!"` and `[]`; `nix eval --raw "$T#checks.x86_64-linux.nixos-magnetite.drvPath"` and the pyrite equivalent succeed, forcing assertions and fleet obligations.

## 2. Linux shared root

- [x] 2.1 Provision `/var/lib/ghq` with a tmpfiles rule `d <root> 0750 ghq ghq -` — verify: the magnetite and pyrite `systemd.tmpfiles.rules` filtered for `/var/lib/ghq` evaluate to exactly that rule; cinnabar's sharing projection is identical at `B` and `T`.

## 3. Root, link and trust in each participating account

- [x] 3.1 Add `programs.ghq-shared.root` (null default), declared in one module imported by `homeManager.ghq` and `homeManager.ghq-sync`; when set it adds `ghq.root`, one `safe.directory = <root>/*`, an activation step that links `~/ghq` to the root only when `~/ghq` is absent or already a link, and an assertion that `programs.git.enable` is true — verify: every host's sharing projection is identical at `B` and `T`.
- [x] 3.2 Set `programs.ghq-shared.root` from the NixOS adapter for every participant's `home-manager.users` entry — verify: `nix eval --json "$T#nixosConfigurations.magnetite.config.home-manager.users.<u>.programs.git.settings"` shows `ghq.root = "/var/lib/ghq"` and `safe.directory` containing `/var/lib/ghq/*` for `cameron`, `omnigent-cameron` and `omnigent-janettesmith`, and likewise on pyrite.

## 4. Delegated acquisition

- [x] 4.1 Add `pkgs/by-name/ghq-shared/` with the wrapper `bin/ghq`, the client and the writer handler (D5 request validation, peer identity, no shell, protocol allow-list), with `passthru.tests.handler` feeding the handler each refused request class and one accepted request over a socket pair against an in-sandbox fixture, and declare that test in `modules/checks/package-tests.nix` — verify: `nix build "$T#checks.x86_64-linux.package-ghq-shared-test-handler"` and `"$T#checks.aarch64-darwin.package-ghq-shared-test-handler"` succeed; the same build with the leading-`-` rejection removed fails.
- [x] 4.2 Add a `delegate` argument to `pkgs/by-name/ghq-sync/` that sends `--deepen` and in-place `--full` work to the delegate, and a `GHQ_SYNC_NO_ZOXIDE` switch for the writer — verify: `nix build "$T#ghq-sync"` and `"$T#ghq-sync".override { delegate = …; }` succeed (shellcheck runs in `writeShellApplication`); `nix build "$T#checks.x86_64-linux.package-ghq-sync"` succeeds.
- [x] 4.3 When `programs.ghq-shared.root` is set, install `pkgs.ghq-shared` instead of `pkgs.ghq` and `pkgs.ghq-sync` overridden with the wrapper and the delegate instead of `pkgs.ghq-sync` — verify: magnetite `cameron`'s evaluated `home.packages` names contain `ghq-shared` and a `ghq-sync` whose `ghq` input is `ghq-shared`, and not nixpkgs `ghq`; `nix build "$T#checks.x86_64-linux.omnigent-worker-capabilities" --no-link` succeeds, so `modules/checks/omnigent-workers.nix:171-181` needs no change.
- [x] 4.4 Add the NixOS transport: `ghq-writer.socket` (`/run/ghq-writer.sock`, `SocketGroup=ghq`, `SocketMode=0660`, `Accept=yes`) and `ghq-writer@.service` (`User=ghq`, `Group=ghq`, `UMask=0027`, socket on standard input and output, handler with a generated configuration) — verify: the magnetite `systemd.sockets.ghq-writer.socketConfig` and `systemd.services."ghq-writer@".serviceConfig` evaluate to those values; `nix eval --raw "$T#checks.x86_64-linux.nixos-magnetite.drvPath"` succeeds.

## 5. Linux checks

- [ ] 5.1 Add the D7 module assertions to the NixOS adapter — verify: magnetite's check drvPath evaluates, and each of four `extendModules` mutations (`safe.directory = [ "*" ]` on `cameron`; an extra member of group `ghq`; writer `extraGroups = [ "wheel" ]`; a participant's `programs.ghq-shared.root = null`) fails evaluation with its assertion's message.
- [ ] 5.2 Add `vmTests.x86_64-linux.shared-reference-tree` in `modules/vm-tests/` per D8 — verify: `nix build "$T#vmTests.x86_64-linux.shared-reference-tree"` succeeds on pyrite's KVM builder; with the tmpfiles mode changed to `0770` and the writer umask to `0007`, the reader write-refusal assertions fail; with the writer-write control replaced by a constant failure, the control assertion fails.
- [ ] 5.3 Build the magnetite and pyrite machine checks in full — verify: `nix build "$T#checks.x86_64-linux.nixos-magnetite" "$T#checks.x86_64-linux.nixos-pyrite" --no-link` succeeds.

## 6. Migration tool

- [ ] 6.1 Add `ghq-shared-migrate` to `pkgs/by-name/ghq-shared/` per D10 (dry run by default, `--apply`, `--rollback`, same-volume rename, cross-volume reflink copy, per-repository merge keeping the deeper clone, chown and chmod, configuration and hook sanitisation with a sidecar, dirty and local-only listing, manifest), and extend the NixOS test with a migration and rollback scenario — verify: `nix build "$T#vmTests.x86_64-linux.shared-reference-tree"` succeeds on pyrite's builder, asserting that a seeded tree with `core.fsmonitor`, a non-sample hook, an uncommitted change and a local-only commit is listed, moved, owned by `ghq`, sanitised with originals in the sidecar, and fully restored by `--rollback`; a dry run on stibnite as `crs58` over its own tree prints its plan and leaves `~/ghq` unchanged (`find ~/ghq -newer <stamp> -print -quit` prints nothing).

## 7. Documentation

- [ ] 7.1 Update `modules/home/ai/plugins/version-control-and-forge/.apm/skills/dependency-source-acquisition/SKILL.md`: replace line 40's claim, state that on sharing hosts `$(ghq root)` is the shared root and `ghq list -p` prints the resolved shared path, that acquisition, update, deepen and promotion are delegated, and that readers cannot fetch, gc or promote in place — verify: `nix build "$T#apm-skills-compose" --no-link --print-out-paths` succeeds and the composed `dependency-source-acquisition/SKILL.md` contains the new text and not `This fleet configures`.
- [ ] 7.2 Update `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/30-reference-repositories.instructions.md` for the shared root — verify: `nix eval --raw "$T#darwinConfigurations.stibnite.config.home-manager.users.crs58.programs.agents-md.settings.body"` contains the new sentence.
- [ ] 7.3 Update `modules/home/README.md` (`programs.ghq-shared.root` and the package swap) and `modules/clan/services/omnigent/README.md` (the writer-group exception for participating workers) — verify: both files name `programs.ghq-shared.root` or the writer group respectively, and the names match the evaluated options from 1.1 and 3.1.

## 8. Darwin

- [ ] 8.1 *Gated on the user's approval of the `_ghq` UID/GID, presented with live `dscl` collision evidence from stibnite.* Declare `_ghq` and group `_ghq` with the approved IDs in `users.knownUsers` and `users.knownGroups`, members `crs58` and `omnigent-cameron`, and change the darwin worker credential delivery group from `lib.head (groupsFor worker)` to the worker's own group — verify: stibnite's `users.users._ghq.uid` evaluates to the approved UID; the delivery group for `cameron` evaluates to `omnigent-cameron`; `nix eval --raw "$T#checks.aarch64-darwin.darwin-stibnite.drvPath"` succeeds.
- [ ] 8.2 *Gated on 8.1.* Provision `/Users/Shared/ghq` in `system.activationScripts.postActivation` with mode `0750`, owner and group `_ghq` — verify: the evaluated `postActivation.text` contains the `install -d -m 0750 -o _ghq -g _ghq` line for `/Users/Shared/ghq`.
- [ ] 8.3 *Gated on 8.1.* Set `programs.ghq-shared.root` for `crs58` and, through the darwin worker-home builder, for `omnigent-cameron` — verify: on stibnite, `crs58`'s evaluated `programs.git.settings` and the `omnigent-cameron` worker home's name `/Users/Shared/ghq` as `ghq.root` and `/Users/Shared/ghq/*` as `safe.directory`.
- [ ] 8.4 *Gated on 8.1.* Add the launchd transport: daemon `org.vanixiets.ghq-writer`, `Sockets` listener at `/var/run/ghq-writer.sock` (mode `0660`, group `_ghq`), `inetdCompatibility.Wait = false`, `UserName = "_ghq"`, `Umask = 23` — verify: the evaluated `launchd.daemons.ghq-writer.serviceConfig` carries those values.
- [ ] 8.5 *Gated on 8.1.* Add the D7 assertions to the darwin adapter and build stibnite — verify: `nix build "$T#checks.aarch64-darwin.darwin-stibnite" --no-link` succeeds on stibnite, and the `safe.directory = [ "*" ]` mutation on `crs58` fails evaluation with its message.

## 9. Activation and migration on hosts

Each task in this group is a human-gated operation; the agent prepares and records, the operator authorizes each activation, each `--apply`, and each deletion.

- [ ] 9.1 Pyrite: activate; run `ghq-shared-migrate` as a dry run and present its dirty and local-only list; run it with `--apply`; run the smoke below as `cameron`, `omnigent-cameron` and `omnigent-janettesmith` — verify: post-activation inspection on pyrite, every smoke line producing its stated result, recorded in `verify.md`.
- [ ] 9.2 Magnetite: the same — verify: post-activation inspection on magnetite, recorded in `verify.md`.
- [ ] 9.3 *Gated on group 8.* Stibnite: the same for `crs58` and `omnigent-cameron`, with `R=/Users/Shared/ghq`, `stat -f %Su` in place of `stat -c %U`, and the same-volume check `stat -f %d /Users/crs58 /Users/Shared` printing one value twice before `--apply` — verify: post-activation inspection on stibnite, recorded in `verify.md`; this is the only darwin runtime evidence.
- [ ] 9.4 Delete each `~/ghq.pre-shared-<date>`, `~/ghq.set-aside-<date>` and sidecar only after the operator explicitly authorizes that account on that host — verify: the authorization is recorded in `verify.md` before the deletion, and the path is absent afterwards.

Smoke, run as each participating account (`sudo -u <account> -i`), with `R=/var/lib/ghq` and `P=$R/github.com/octocat/Hello-World`:

```bash
ghq root                                  # prints $R
git config --get-all ghq.root | tail -n1  # prints $R
readlink -f ~/ghq                         # prints $R (darwin: realpath ~/ghq)
git config --get-all safe.directory       # includes "$R/*" and never "*"
ghq-sync https://github.com/octocat/Hello-World; echo $?   # 0
stat -c %U "$P"                           # ghq (darwin: _ghq)
ghq list -p octocat/Hello-World           # prints $P
zoxide query Hello-World                  # prints $P
git -C "$P" log -1 --oneline; echo $?     # 0
git -C "$P" status >/dev/null; echo $?    # 0
touch "$P/probe"; echo $?                 # non-zero, Permission denied
mkdir "$R/probe"; echo $?                 # non-zero, Permission denied
git -C "$P" config core.fsmonitor /bin/false; echo $?   # non-zero, could not lock config file
git -C "$P" fetch; echo $?                # non-zero
ghq get -- -x; echo $?                    # non-zero, refused by the writer
```

Control, as the operator: `sudo -u ghq touch "$P/.probe" && sudo -u ghq rm "$P/.probe"` succeeds; `sudo -u nobody ls "$R"` fails with Permission denied.

## 10. Integration Verification

- [ ] 10.1 Verify the reference tree is shared and single-writer on every sharing host with `vmTests.x86_64-linux.shared-reference-tree` passing on pyrite's builder and the group 9 smoke passing for every participating account on pyrite, magnetite and stibnite, recorded in `verify.md` with the commands and outputs.
- [ ] 10.2 Verify non-sharing hosts are untouched with the sharing projection of cinnabar, electrum, galena, scheelite, argentum, blackphos and rosegold identical at `B` and at the chain tip.
