---
linear_story_id: CAM-133
linear_story_identifier: CAM-133
linear_story_title: "Build each fleet host without evaluating the other hosts"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-133/build-each-fleet-host-without-evaluating-the-other-hosts
linear_story_state: In Review
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: In Review
last_synced_at: "2026-11-27T04:00:29Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T23:02:05Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-133 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
  - { at: "2026-11-27T03:23:07Z", transition: "Todo->In Progress", outcome: "posted", note: "First tasks.md checkbox (1.1) ticked; state set by name and confirmed by read-only view; start comment posted" }
  - { at: "2026-11-27T04:00:29Z", transition: "In Progress->In Review", outcome: "posted", note: "verify.md written (PASS WITH WARNINGS); state set by name and confirmed by read-only view; review comment posted" }
---

## Why

Building any one host's configuration today also evaluates all six NixOS hosts' configurations, only to read six public key files already committed to the repository. stibnite also evaluates magnetite's configuration to read one more. Measured on stibnite on 2026-11-26, the host key reads cost about 0.98 s of CPU, 3.7M thunks and 423 MB on top of a 10.97 s, 24.38M-thunk, 3.15 GB toplevel. With the session key read (0.57 s alone), that is an upper bound of 9 to 12 %. The cross-host read also blocks moving each host into an independent declaration. Separately, the layout of the committed secret store is written out by hand in about fifteen places, so every reader has to know it.

## What Changes

**Host keys in known_hosts**
- From: `modules/system/ssh-known-hosts.nix` reads each NixOS host's key from `nixosConfigurations.<h>.config.clan.core.vars…value`.
- To: it reads `flake.lib.hostKeys`, built from the committed `vars/per-machine/<h>/openssh/ssh.id_ed25519.pub/value` and merged with `darwinHostKeys`. Each NixOS host asserts that its own generated public key equals its `hostKeys` entry.
- Impact: non-breaking; every `known_hosts` line keeps the same bytes.

**stibnite's session key**
- From: `stibnite/default.nix:173` reads magnetite's evaluated configuration.
- To: it reads magnetite's committed `stibnite-agent-session/key.pub/value`. `checks.nix-builders-wiring` still compares that key with magnetite's generated one.

**One accessor for the committed vars tree**
- Adds `flake.lib.vars` (`relPath`, `path`, `public`, `exists`, `isRecipient`) in `modules/lib/vars.nix`, built from the deployer's existing `varPath`.
- Migrates the ad-hoc readers, keeping at each site whether it reads by path or string and whether it trims.

**Magnetite's telemetry databases in tests**
- From: five vm-tests read `databases` from magnetite's evaluated configuration.
- To: they read `flake.lib.otelCollectorSchema.databases`, and each still asserts that magnetite declares exactly that map.

**Measured outcome**
- Every system and home drvPath is unchanged across the change. Among checks, only the new `host-key-obligations`, `fleet-alert` (which renders every check's size entry) and `eval-users-lib` (which embeds `home/users/lib.nix`'s source) change, and the seven vm-tests whose files are edited stay unchanged; `just drv-diff` with `drv-delta.txt` decides.
- The stibnite toplevel's CPU time, thunks and allocation are measured A/B afterwards and recorded against the baseline above.

**Non-goals**
- Removing the `_module.args.flake` setters. That belongs with the change that removes the ambient `flake` argument.
- Lifting omnigraph graphs, rendered collector settings or the users generator out of host reads in tests.
- Changing the host registry.
- Any change to the committed vars tree.

## Capabilities

### New Capabilities

- `host-configuration-independence` (stratum: behavioral): one host's configuration is built without another host's configuration; each host takes other hosts' host keys from the keys the fleet pins; a host whose configuration presents a host key other than the pinned one fails before it is deployed.
- `host-configuration-independence-interface` (stratum: interface): `flake.lib.vars` and its five functions; `flake.lib.hostKeys`; the own-host obligation and its judge check; the vm-test consumption assertions; drvPath identity across the change; the `NIX_SHOW_STATS` A/B record. Trust boundary: the obligation compares a NixOS host's own generated key with the committed file, and nothing compares a committed file with the key a running host presents. A darwin host's key is still a literal a person updates. The accessor guarantees one layout reading, not that clan still writes that layout.

### Modified Capabilities

- `world-assumptions` (stratum: world): adds A320 to A323:
  - A320: clan reads a public var's value as the committed file, untrimmed, at a path fixed by machine, generator and file name.
  - A321: the `openssh` generator that clan's sshd service declares is per-machine and public.
  - A322: reading a committed file through a path and through a source-tree string yields the same bytes and no store reference.
  - A323: the 2026-11-26 evaluation-cost baseline.
  The new behavioral requirements use only existing designations (host, configuration, host key, deploy), so the designation table does not change.

## Impact

- Code:
  - `modules/lib/vars.nix` (new).
  - `modules/system/ssh-known-hosts.nix`, `modules/lib/darwin-host-keys.nix` (header comment), and a new `modules/lib/host-keys.nix` holding `hostKeys` and the own-host obligation, with its judge in `modules/checks/host-key-obligations.nix`.
  - `modules/machines/darwin/stibnite/default.nix`.
  - The comments on six NixOS host modules.
  - The readers in `clan/inventory/services/tincr.nix`, `darwin/fleet-services-trust.nix`, `home/users/crs58/default.nix`, `nixos/workstation-ca-trust.nix`, `home/users/lib.nix`, `checks/otel-collector-{config,darwin}.nix`, `lib/fleet-deployer.nix`, `nixos/{postgresql-backup,r2-usage}.nix`, `lib/shared-vars-recipients.nix`, `lib/commit-signing.nix` and `darwin/otel-collector-agent.nix`.
  - Five vm-tests.
- Landing order: second, directly after the refactor-oracle change (`establish-refactor-oracle`), which supplies `just drv-diff` and the A/B measurement procedure, and before the host registry change (`type-the-fleet-host-registry`).
- Independent of: the host registry change. This change reads names from `hosts` exactly as today and keeps `nixosKeyHosts` a literal list of six; `type-the-fleet-host-registry`, landing after it, later derives that list from each host's class.
- Unblocks:
  - `declare-host-user-relations-once`, which depends on this change: removing the ambient `flake` argument needs `ssh-known-hosts` to stop reading `flake.nixosConfigurations`, and no system-level module reads it after this change.
  - `seam-secrets-away-from-clan-vars`, which builds on `flake.lib.vars`. The new `modules/lib/host-keys.nix` reads committed clan vars, and that change places it behind its seam.
- Deploys: none required. Unchanged drvPaths mean no host's closure changes.
