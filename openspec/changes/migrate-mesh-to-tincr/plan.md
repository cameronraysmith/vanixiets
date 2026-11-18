# Migrate the fleet mesh to tincr (CAM-109) implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking; `tasks.md` is the authoritative ledger and each step names the item it serves.

**Goal:** every fleet member reaches every service and member by `<name>.vanixiets.internal` over a tincr mesh built from one registry, mirrored beside ZeroTier, adopted at one operator-approved cutover, after which ZeroTier is gone (Linear CAM-109).

**Architecture:** `flake.lib.fleet`, `flake.lib.mesh` and an extended `flake.lib.hosts` are the contract; every name and address is a pure function of a member's name.
A first-party `tincr` clan service, written with Qubasa/infra's as reference only, runs one instance `vanixiets` on six NixOS and four darwin machines with `StrictSubnets` and default crypto, pixel11 joins through tincapp (pixel7 best-effort); two dnsmasq name services generated from `flake.lib.meshRecords` answer the zone; firewall keys, SANs, ssh blocks and deploy targets are generated from the registry.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan-core `d718bcf9` (`clan.service`, vars, inventory); tincr `github:Mic92/tincr` (HEAD `fd92f216` on 2026-11-17; pin the reviewed revision at 3.2); nix-darwin; systemd-networkd; dnsmasq; caddy (`tls internal`); tuwunel; tincapp 0.48 on Android; nix-unit; clan and NixOS VM tests.

**Spec:** `openspec/changes/migrate-mesh-to-tincr/` — `design.md` (D1–D18, "The contract", "Task-group DAG", "Migration Plan"), `specs/`, `tasks.md`, `brainstorm.md`, `proposal.md`.

## Global constraints

- Repository `$REPO` is jj-colocated with a development join; `@` never moves; each task group is its own change off `main@origin` (group 1) or off group 1's change (groups 2–8), routed with `jj squash --into <change> --use-destination-message --keep-emptied <paths>`; after creating or renaming files run `jj st --no-pager >/dev/null` before any `nix` command.
- Parallel subagents each own the files listed under "File ownership" and nothing else; a needed edit outside one's files goes to the orchestrator.
- clan vars commands run in the join's working copy with `CLAN_NO_COMMIT=1`, which makes clan register the files it writes as intent-to-add instead of committing them; each names its generators, its files are routed into the owning change with `jj squash --into <change> --use-destination-message --keep-emptied <paths>`, and `git rev-parse HEAD` is recorded before and confirmed unchanged after.
- Deploys are run by the orchestrator only, after `nixbot-logs queue` prints `Queue is empty`, from the merged commit on `main`: NixOS `clan machines update <machine> --flake "git+file://$PWD?rev=<main commit>" 2>&1 | tee logs/<machine>-$(date +%Y%m%d-%H%M%S).log`; darwin `just activate` on the host with the operator present.
- Behaviour-neutral refactors (1.2, 2.1, 2.2 for the ZeroTier key) are verified by toplevel drvPath identity: `nix eval --raw .#nixosConfigurations.<m>.config.system.build.toplevel.drvPath` (and `darwinConfigurations.<m>.system.drvPath`) before and after, equal for every machine whose behaviour must not change.
- Every regulator is written first and seen failing; each mutant runs only the case it must fail.
- Evaluation cost per check as `tasks.md` states; machine checks' cost recorded before and after, rises put to the operator.
- Commit messages and PR titles say what changes in plain words, no decision or task codes; bodies end `Part of CAM-109.`
- Prose files keep one sentence per line.

## Interface contract

`design.md` "The contract" is authoritative; the names every group uses:

| Name | Owner | Used by |
|---|---|---|
| `flake.lib.fleet.{label,domain}` | 1.1 | R, T, A, M, S, F |
| `flake.lib.mesh.{instance,prefixOf,addressOf,port,crypto,resolvers,interface}` | 1.1 | R, T, A, S |
| `flake.lib.hosts.<name>.{class,fqdn,address,endpoints,deployUser,services,zerotier}` | 1.2 | all |
| `flake.lib.meshRecords` | 1.2 | R (zone), A (phone DNS) |
| `flake.lib.meshInterfaces config` | 1.3 | R, S, Z |
| clan service `tincr`, instance `vanixiets`, generator `tincr-vanixiets`, interface `tinc-vanixiets` / `utun10` | T | R (networkd match), S, V |
| package `tincapp-network-<phone>` | A | V |
| `flake.lib.matrixServerName` | M | M (tuwunel, hermes-agent, openclaw) |
| `flake.lib.tuwunelServerNameGuard pkgs { serverName }` | M | M (tuwunel `ExecStartPre`, check `matrix-server-name-reset`) |

## DAG and dispatch

```text
wave 0: C (1.1–1.5)                                   one agent, serial
wave 1: R (2.x) | T (3.x) | A (4.2) | K (5.x) | M (6.1) | B (7.2 config, 7.3) | S (8.1–8.4)   seven agents in parallel
wave 2: integration: merge stack C → R → T → S → M (A, B docs ride with R)
wave 3: V (9.x, 4.3, 6.2, 7.1, 7.2 proof; 4.4 optional, never gating)   orchestrator + operator, runtime
gate:   X (10.1)                                        operator
wave 4: F (11.x) → soak (11.3) → Z (12.x) → E (13.x, 14.1)
```

S is authored in wave 1 against the contract's names; it merges after T because its sites listen on `tinc-vanixiets` addresses that only exist once T deploys, and its certificate reissue (8.2, 8.3) runs at wave 2 end.

## File ownership

| Group | Files |
|---|---|
| C | `modules/lib/fleet.nix`, `modules/lib/mesh.nix`, `modules/lib/mesh.test.nix`, `modules/lib/mesh-interfaces.nix`, `modules/lib/hosts.nix`, the seven `magnetite.zt` consumer lines of 1.2, `docs/notes/development/architectural-principles.md` |
| R | the 15 literal-address files except `modules/lib/hosts.nix`, the 8 firewall-opening files, `modules/lib/zerotier-interfaces.nix` (deleted), `modules/lib/nginx-metrics-location.nix`, `modules/nixos/mesh-dns.nix`, `modules/system/mesh-dns.nix`, `modules/home/core/ssh.nix`, `modules/system/ssh-known-hosts.nix`, `modules/system/stibnite-access.nix`, `modules/home/tools/hooks/gate-dangerous-commands.sh` |
| T | `flake.nix`, `flake.lock`, `modules/clan/services/tincr/**`, `modules/clan/inventory/services/tincr.nix`, `modules/vm-tests/tincr-mesh.nix`, `modules/terranix/gcp.nix`, `vars/per-machine/*/tincr-vanixiets/**` |
| A | `pkgs/by-name/tincapp-network/**` (or the repo's package location for generated configs) |
| K | `openspec/changes/bind-mesh-writes-to-their-host/**` on CAM-81's chain |
| M | `modules/machines/nixos/cinnabar/matrix.nix`, `modules/clan/inventory/services/hermes-agent.nix`, `modules/clan/inventory/services/openclaw.nix`, `modules/checks/matrix-server-name-reset.nix` |
| B | the operations runbook page, `modules/clan/inventory/services/p2p-ssh-iroh.nix` if 7.2 adds it |
| S | `modules/machines/nixos/cinnabar/caddy.nix`, `modules/darwin/zt-services-trust.nix` (renamed), `modules/clan/services/otel-collector/flake-module.nix` SAN lines, `modules/clan/services/nix-builders/flake-module.nix`, `modules/clan/inventory/services/nix-builders.nix`, `modules/clan/inventory/services/sshd.nix`, the nine checks of 8.4 |

R and C both touch the files holding `magnetite.zt` consumers: C changes only the attribute path on those lines, R everything else in them, and R rebases on C.

## Task 1: Contract (tasks.md 1.1–1.5)

- [ ] **Step 1 (1.1):** Write `modules/lib/mesh.test.nix` in the nix-unit style of `modules/home/users/lib.test.nix` with cases `prefixVanixiets` (`fd09:836d:82f8:3d7d::/64`), `addressCinnabar` and `addressPyrite` (vectors from `printf %s cinnabar | sha256sum` cut to four hextets, written in the test's comment with the command), and `hookFormulaMatches` (the hook's `${hash:0:4}:…` slicing reproduced in Nix over `pixel7`). Run it; expected: fails, `flake.lib.mesh` missing.
- [ ] **Step 2 (1.1):** Write `modules/lib/fleet.nix` and `modules/lib/mesh.nix` with `prefixOf`/`addressOf` implementing the formula stated in design "The contract" (written here, not copied from Qubasa/infra, which carries no licence) and the constants of the contract. Run the test; expected: pass. Mutant: swap two hextets in `addressOf`; expected: `addressCinnabar` fails; revert.
- [ ] **Step 3 (1.2):** Record toplevel drvPaths of all ten machines into `logs/cam109-evidence/1.2-drv-before-<ts>.log`.
- [ ] **Step 4 (1.2):** Rewrite `modules/lib/hosts.nix` into twelve entries; `zerotier.address` from today's literals (`zerotier.nix:17-22` for external members, `vars/shared/zerotier-ip-<m>-zerotier/ip/value` for clan peers), `memberId` from the same comments; derive `fqdn` and `address`; add `meshRecords`. Change the seven `hosts.magnetite.zt` reads to `hosts.magnetite.zerotier.address`.
- [ ] **Step 5 (1.2):** Re-record drvPaths; expected: identical for all ten. `nix eval --json .#lib.hosts | jq 'keys|length'` prints `12`.
- [ ] **Step 6 (1.3):** Add `modules/lib/mesh-interfaces.nix`; `nix eval` it against magnetite (iptables) and a configuration with `networking.firewall.backend = "nftables"`; expected: `[ "zt+" "tinc-vanixiets" ]` and `[ "zt*" "tinc-vanixiets" ]`.
- [ ] **Step 7 (1.4):** Edit O07/O08 and E1 in `architectural-principles.md`.
- [ ] **Step 8 (1.5):** `nix fmt`; route into the C change; open the PR "Add a transport-neutral host registry and mesh addressing"; record drvPath identity in the body.

## Task 2: Registry consumers (tasks.md 2.1–2.7)

- [ ] **Step 1 (2.1):** drvPaths before; replace each literal in the 15 files with a registry read (cinnabar's ZeroTier listen list moves into `cinnabar/zt-dns.nix` as a `let` binding read by caddy through an option or shared lib value); drvPaths after; expected identical.
- [ ] **Step 2 (2.2):** Replace the seven raw keys and two helper calls with `meshInterfaces`; this changes firewall rules (adds `tinc-vanixiets`), so verify by `nix eval` of `networking.firewall.interfaces` on magnetite, cinnabar, pyrite: each port under both keys.
- [ ] **Step 3 (2.3):** `modules/nixos/mesh-dns.nix`: `services.dnsmasq` cannot run two instances, so on cinnabar the module extends the existing dnsmasq's `listen-address` and `address` lists with the mesh records and cinnabar's mesh address, and on magnetite enables dnsmasq with only the mesh lists; build the rendered `dnsmasq.conf` for both and grep one record per `meshRecords` entry.
- [ ] **Step 4 (2.4):** NixOS: define `systemd.network.networks."40-tincr-${mesh.instance}"` with `matchConfig.Name = flake.lib.mesh.interface.nixos` (no `"tinc-vanixiets"` literal, so 2.2's search stays empty), `dns` (both resolvers) and `domains = [ "~vanixiets.internal" ]`, merging into the unit tincr's NixOS module writes with the interface's `Address=` (Mic92/tincr `nix/module.nix:478-480` at `fd92f216`; networkd applies only the first `.network` file matching an interface, so a separate unit would shadow tincr's address), with that coupling named in a comment; darwin `environment.etc."resolver/vanixiets.internal"`; `nix eval` each.
  Once T is in the stack (wave 2), an evaluation check that the merged unit on a peer carries both tincr's `Address` and these `DNS`/`Domains` and that no other `.network` unit matches the mesh interface.
- [ ] **Step 5 (2.5):** Generate ssh blocks with `lib.mapAttrs'` over `hosts` filtered to `class != "android"` plus pixel7's existing Termux block; known-hosts `extraHostNames` gains `fqdn`; `nix eval` stibnite's home `programs.ssh.matchBlocks` names.
- [ ] **Step 6 (2.6):** Extend the hook's `.zt` pattern to `(\.zt|\.vanixiets\.internal)`; run the hook with a fixture JSON for both destinations.
- [ ] **Step 7 (2.7):** `nix fmt`; costs; PR "Generate mesh names, resolvers and firewall keys from the host registry".

## Task 3: tincr clan service (tasks.md 3.1–3.7)

- [ ] **Step 1 (3.1):** Write `modules/clan/services/tincr/README.md` first with its provenance: written first-party, Qubasa/infra `a00b9b1` `services/tincr/default.nix` read as a design reference only, none of its code copied (no licence file); the operator asks Qubasa for a grant in parallel and the README records the request and any answer. The service is written from tincr's `nix/module.nix` and `nix/darwin-module.nix` options and clan-core's `clanServices/wireguard` service shape, not from Qubasa's text.
- [ ] **Step 2 (3.2):** Add the input; `nix flake lock --update-input tincr`; read `nix flake metadata --json` for the rev.
- [ ] **Step 3 (3.3):** Write `modules/vm-tests/tincr-mesh.nix` reading tincr's `nix/nixos-test-nat.nix` for the NAT topology; run `nix build .#vmTests.x86_64-linux.tincr-mesh` on magnetite; expected: evaluation failure for the missing service.
- [ ] **Step 4 (3.4):** Write the service: `default.nix` (manifest, `exports`, `roles.peer` interface and `perInstance` with `nixosModule` and `darwinModule`, `perMachine` importing `inputs.tincr.nixosModules.tincr` / `darwinModules.tincr`), the README with the trust boundary of `fleet-mesh-interface`; build the VM test; expected: pass. Overrides `addressCollision` (two peers forced to one address) and `pqWithDevice` evaluated; expected: assertion failures naming them.
- [ ] **Step 5 (3.5):** Inventory instance and terranix rule; `nix eval` the peer machine list and pyrite's/stibnite's `services.tincr.networks.vanixiets`.
- [ ] **Step 6 (3.6):** In the join's working copy with T's change in the join, record `git rev-parse HEAD`, then `for m in cinnabar electrum galena scheelite magnetite pyrite stibnite blackphos argentum rosegold; do CLAN_NO_COMMIT=1 clan vars generate $m --generator tincr-vanixiets; done`; `jj diff -r @ --stat` lists only `vars/per-machine/*/tincr-vanixiets/` paths; route those paths into T's change with `jj squash --into <T> --use-destination-message --keep-emptied <paths>`; `git rev-parse HEAD` unchanged.
- [ ] **Step 7 (3.7):** `nix fmt`; costs; PR "Run a tincr mesh beside ZeroTier on every NixOS and darwin machine".

## Task 4: Android (tasks.md 4.1–4.3)

- [ ] **Step 1 (4.1):** Operator reads pixel11's tincapp version; record.
- [ ] **Step 2 (4.2):** A `runCommand` package per phone writing `network.conf` and `tinc.conf` from `hosts.<phone>` and `mesh.resolvers`; `nix build` and `cat` both files.
- [ ] **Step 3 (4.3):** At wave 3, operator runs `tinc -n vanixiets invite pixel11` on cinnabar, joins in tincapp, reads the phone's public key from `/var/lib/tincr/vanixiets/hosts/pixel11` on cinnabar into `devices`; deploy all peers (D12); check `tinc dump reachable nodes`. pixel7 (4.4) follows the same steps only if the operator has it at hand.

## Task 5: CAM-81 rewrite (tasks.md 5.1–5.2)

- [ ] **Step 1 (5.1):** CAM-81 is holding Task 2 until C lands; confirm 2.x is still unstarted.
- [ ] **Step 2 (5.2):** On CAM-81's chain, edit `design.md` D7, `tasks.md` 2.1–2.2, `plan/task-2.md` and `plan.md`'s interface contract row `flake.lib.hosts.<host>.zt` → `flake.lib.hosts.<host>.zerotier.address` (then `.address`); add the retirement note to its D4; `openspec validate bind-mesh-writes-to-their-host --strict`.

## Task 6: Matrix (tasks.md 6.1–6.2)

- [ ] **Step 1 (6.1):** In `matrix.nix` set the new `server_name`; add a `systemd.services.tuwunel.preStart` guard that moves `/var/lib/tuwunel` aside once when a marker file names the old server; `nix eval` the setting.
- [ ] **Step 2 (6.2):** Operator re-registers, creates the room, invites hermes; edit `hermes-agent.nix` and `openclaw.nix`; deploy cinnabar; read the cron post.

## Task 7: Break-glass (tasks.md 7.1–7.3)

- [ ] **Step 1 (7.1):** Endpoints already in the registry from 1.2; at wave 3 run the public-address deploy for cinnabar and magnetite.
- [ ] **Step 2 (7.2):** In wave 1, add `modules/clan/inventory/services/p2p-ssh-iroh.nix` (server pyrite, client stibnite); at wave 3, with pyrite behind an address-translating router, run `systemctl stop tincr-vanixiets` on pyrite, then `clan ssh pyrite` over iroh, then start tincr again; if that fails, remove the instance and put an alternative to the operator.
- [ ] **Step 3 (7.3):** Write the Mac recovery steps in the operations docs.

## Task 8: Service mirroring (tasks.md 8.1–8.5)

- [ ] **Step 1 (8.1):** Add caddy sites by mapping `hosts.cinnabar.services`; `nix eval` virtual host names and listen addresses.
- [ ] **Step 2 (8.2):** SAN generators read the registry; in the join's working copy with S's change in the join, record `git rev-parse HEAD`, regenerate exactly `otel-cert` on magnetite and `nix-grpc-*` on each builder with `CLAN_NO_COMMIT=1` and `--generator` per generator, and route the regenerated vars paths into S's change; `git rev-parse HEAD` unchanged; `openssl` read; CA sha256 before and after equal.
- [ ] **Step 3 (8.3):** `searchDomains = [ "zt" "vanixiets.internal" ]`; regenerate the sshd certificate generators the same way, in the join's working copy with `CLAN_NO_COMMIT=1`, routed into S's change, `git rev-parse HEAD` unchanged; `ssh-keygen -L`.
- [ ] **Step 4 (8.4):** Re-point each check, run its existing mutants.
- [ ] **Step 5 (8.5):** PR "Serve every fleet service under its vanixiets.internal name".

## Tasks 9–14: runtime waves

These are runtime and operator steps; `tasks.md` 9.1–14.1 are their exact commands and evidence.
`cutover.md` is created at 9.4 with sections Reachability, NAT traversal, Deploys, A65, Break-glass and Decision, and every evidence log is linked from it.
At 12.1 the retirement is one pull request "Retire ZeroTier", followed by the certificate reissue and vars removal in the same stack.
