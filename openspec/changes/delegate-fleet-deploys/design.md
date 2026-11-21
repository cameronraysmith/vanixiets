## Context

Only stibnite can deploy the fleet today: it holds the one age key that reads every machine key (`age1vn8f…tmv8`, listed as both `sops/users/cameron` and `sops/users/crs58`) and the SSH identities the targets accept.
Agent forwarding is off fleet-wide (`modules/home/core/ssh.nix:122`) and asserted off for omnigent workers (`modules/home/ai/omnigent/worker.nix:171-189`), so a session on magnetite, pyrite or a future agent host cannot deploy.

clan-core `d718bcf` shapes what a deployer needs:
- `clan machines update` becomes root on the target, then always uploads the machine key `sops/secrets/<machine>-age.key` as `/var/lib/sops-nix/key.txt` plus any var marked `neededFor = "activation"`. The upload wipes and rewrites that directory every time, and no flag skips it.
- Every other secret travels encrypted in the closure and is decrypted on the target. Reading a machine's key is therefore reading all of that machine's secrets.
- The update first runs the generators of every machine in the clan.
- clan has no deploy lock, queue, audit or pull mode (brainstorm F1-F9).

clan-infra and Mic92's dotfiles deploy by hand with personal keys. Nothing there delegates a clan deploy. The reusable pieces are nixbot's default-branch-only effects and OIDC tokens (F17, F18) and a jump-only SSH account (F19).

Already in place and reused:
- the deploy record `/var/log/deploy-record.jsonl`, written at every activation on all ten machines (`modules/system/deploy-record.nix`);
- `ntfy-send` to `ntfy.zt` with the `alerter` token for `fleet-*` topics, verified against caddy's root since CAM-87; ntfy's `alerter:fleet-*:rw` already admits a `fleet-deploy` topic (`modules/machines/nixos/cinnabar/ntfy.nix:61-64`);
- omnigent worker credentials delivered as shared clan vars (`modules/home/ai/omnigent/credentials.nix`);
- the host registry `flake.lib.hosts` (CAM-109) and the terranix machine sets, which say which cloud machines exist (`enabled`);
- the machine checks' fleet obligations (`modules/checks/machines.nix`) and the `secret-custody` correspondence check.

cinnabar is a Hetzner CX43 (8 vCPU, 16 GB). It runs caddy, ntfy, fleet-alert's dead-man and the ZeroTier controller, and no untrusted or session code.

The operator decided Q1-Q8 and, after Gate 1 was approved (Q33), Q30-Q32 on 2026-11-18 (`brainstorm.md`, "Operator decisions"). Stakeholders:
- the operator, who approves scope and holds the recovery path;
- cameron's and janettesmith's agent sessions, the requesters;
- christophersmith, argentum's primary user, whose laptop is a deploy target.

## Goals / Non-Goals

**Goals:**
- A session that holds its user's request credential can deploy one host it may reach, at a commit on `main`, unattended. It receives the log and one outcome covering both the deploy and its health check.
- Only the deployer can read the machine keys it uploads, and only those of deploy targets. No session, agent host or request credential can read any machine key.
- Every request is attributed to a requester, recorded on the deployer and announced, whether it is refused, fails or succeeds.
- Deploys of the same host never overlap. A sleeping host fails fast. A host that stops answering after activation returns to its previous system by itself.
- Requests cannot widen what the merge gates admitted: no unmerged commit, no flake reference chosen by the requester, no host outside the requester's reach, no disabled or excluded host.

**Non-Goals:**
- Pull-based activation (O6) and deploy-on-merge from a nixbot effect (O7). The request interface leaves room for O7 as a second requester.
- Deploying stibnite or blackphos, or deploying unmerged work. Both stay with the operator's workstation.
- Moving the deployer to cinnabar's successor (part of CAM-112), and key permissions on other hosts (the separate hardening change, Q8).
- Changing clan-core, sops-nix, nixbot or gitea-mq.

## Decisions

### D1: The deployer is a dedicated account on cinnabar, reached only through a forced command
- **Choice**: the NixOS module `fleet-deployer` (`modules/nixos/fleet-deployer.nix`), imported by cinnabar.
  - It creates the system account `fleet-deployer` (home `/var/lib/fleet-deployer`, mode `0700`). Its `authorized_keys` hold only requester keys, each with `restrict`, `from=` the mesh ranges (the tincr /64, ZeroTier's /64 and IPv4 /24) and `command="/run/current-system/sw/bin/fleet-deploy-request <requester>"`. The path is absolute because sshd runs a forced command through a non-login shell.
  - `fleet-deploy-request` (`pkgs/by-name/fleet-deploy-request`, Python) reads `SSH_ORIGINAL_COMMAND` and parses exactly `deploy <machine> [<commit>] [--session <id>]`, refusing anything else.
- **Rationale**: SSH needs no new listener, token store or TLS path. It carries requester identity in the key and streams output back over the connection the session opened (Q2; brainstorm O4).
- **Alternatives considered**: an HTTP API on the mesh with bearer tokens (a new listener, plus a token store); clan-infra's jump account (it forwards to targets, which would put root reach in the requester's hands).

### D2: The deployer's age and SSH keys are generated on cinnabar and never leave it
- **Choice**:
  - `fleet-deployer-keys`, a oneshot running as the account with `UMask=0277`, creates `/var/lib/fleet-deployer/keys/{age.key,id_ed25519}` when they are absent. The files are `0400` in a `0700` directory.
  - The public halves are committed as `flake.lib.fleetDeployer.keys = { age; ssh; }` and `sops/users/fleet-deployer/key.json`. Until then `keys` is `null`. No host accepts a deployer key and no secret names the group, which the obligation and the correspondence check hold (provisioning conditional, removed in task 7.1).
  - `fleet-deployer-keycheck`, at start and daily, fails when the modes, owner or public halves differ from the flake.
- **Rationale**: a clan var would be encrypted to the current admin as well (clan-core `secrets.py:221-222`), so the private key would sit in the repository, readable by the operator's key. Generated in place, it exists only on cinnabar. The move to the successor mints new keys and re-encrypts, which is the rotation that move deserves (Q8 lesson).
- **Boundary**: source-versus-delivered. The repository carries only public keys. The keycheck compares them with the private keys on cinnabar, which the source cannot see.
- **Alternatives considered**: a clan vars generator for cinnabar (the private key readable from the repository by the admin key); a key in Bitwarden (a human retrieval step on every rebuild).

### D3: Targets are derived from enabled state, and read access is scoped per machine by one sops group
- **Choice**:
  - `flake.lib.fleetDeployer.targets` is every NixOS or darwin inventory machine that is enabled, minus stibnite and blackphos (Q30). A machine is enabled when its `flake.lib.cloudMachines` entry says `enabled = true`, or when it has no cloud entry. The terranix sets moved into `modules/lib/cloud-machines.nix` unchanged; the terraform JSON is byte-identical (sha256 `3cea80f0…98ec` before and after).
  - Today the targets are argentum, cinnabar, magnetite, pyrite and rosegold. electrum, galena and scheelite are disabled. Re-enabling one in terranix makes it a target with no other edit.
  - The sops group `fleet-deployers` (only `fleet-deployer`) reads exactly what `clan machines update` decrypts on the deployer for each target. That is the machine key, plus every secret var with `neededFor = "activation"`; clan's sops `populate_dir` decrypts these for the update phases activation, users and services (clan-core `d718bcf`, `clan_lib/vars/secret_modules/sops.py:243-290`, `clan_lib/vars/upload.py:21`). Partitioning vars are decrypted only by `clan machines install`; users and services vars travel encrypted.
  - The group is added per file with clan's own commands: `clan secrets groups add-secret fleet-deployers <m>-age.key`, and a `groups/fleet-deployers` link on each activation var followed by `clan vars fix <m> -g <generator>`. Today that is the five machine keys plus `initrd-ssh/id_ed25519` on cinnabar, magnetite and pyrite; the darwin targets have no activation var.
  - `flake.lib.fleetDeployer.failures` derives the same set from each target's evaluated `clan.core.vars.generators`. Any such file without the group link fails that target's machine check, so a future activation var fails CI rather than a deploy.
- **Rationale**: per machine is the narrowest scope the sops backend offers (A155). Deriving targets from the enabled state means a disabled machine can never be in reach, which the policy judge and every machine check enforce.
- **Boundary**: vendored-versus-first-party. Recipient computation and re-encryption are clan's; we declare the group and its links.
- **Alternatives considered**:
  - a typed list of targets (rejected by Q30: it can drift from what exists);
  - clan's experimental age backend with per-host recipients (a fleet-wide backend migration);
  - (b) `clan.core.sops.defaultGroups = [ "fleet-deployers" ]` on targets followed by `clan vars fix`. This was rejected for diff size, not reach. By A155 the machine key already opens every var of the machine, so (b) grants nothing more. But it re-encrypts every per-machine var of every target in one change, which buries the few files that matter under dozens of unrelated rewrites in the operator's review. Until that `vars fix` lands, clan's recipient check also flags every existing var, which would make the deployer's `clan vars check` refuse every request.

### D4: Reach is a role policy over each machine's primary user
- **Choice**: `flake.lib.hosts.<name>.primaryUser` is a typed field: null, or one of the names under `flake.users` (aliases included). It is checked with `types.nullOr (types.enum …)`. The values are pyrite cameron, rosegold janettesmith, argentum christophersmith, stibnite crs58 and blackphos raquel; servers and phones are null. The policy (Q31), as data in `flake.lib.fleetDeployer`:
  - a shared server (no primary user) is reachable by every operator (`operators = [ cameron janettesmith ]`);
  - a personal machine is reachable by its primary user and by the admin (`admin = cameron`).
  - So cameron reaches argentum, cinnabar, magnetite, pyrite and rosegold, and janettesmith reaches cinnabar, magnetite and rosegold. christophersmith reaches argentum by the policy but holds no request credential.
  - The forced command refuses any machine outside its requester's reach.
  - The obligation requires each primary user to have an account on that machine.
- **Rationale**: one rule covers a new operator, a new laptop or a re-enabled server without per-person lists. Changes go through review and the merge gates.
- **Alternatives considered**: per-requester machine lists (superseded by Q31); a free-form inventory tag for the primary user (untyped).

### D5: Request credentials are one SSH key per user, delivered as an omnigent worker credential
- **Choice**: the credential kind `deployRequestKey` in the worker options and policy (`modules/system/omnigent-worker-options.nix`, `modules/home/ai/omnigent/credentials.nix`):
  - Its shared generator `<worker>-deploy-request` produces a private `key` (owner the worker, `0400`) and a public `key.pub` with `ssh-keygen`, without prompts.
  - The worker home gets an SSH alias `fleet-deployer` (`cinnabar.zt`, `IdentitiesOnly`, no agent) and a `fleet-deploy` command.
  - `flake.lib.fleetDeployer` reads each public key from `vars/shared/omnigent-<user>-deploy-request/key.pub/value`.
  - Every worker passes the kind through the flag `deployRequestEnrolled` (`modules/clan/inventory/services/omnigent.nix`). The flag stays false until the operator generates the vars, because a worker with a selected credential and no ciphertext fails its machine check (provisioning conditional, removed in task 7.1).
  - Keys are generated for cameron (magnetite, pyrite, stibnite) and janettesmith (magnetite, pyrite); she has agent-host accounts (Q31).
- **Accepted risk (Q31)**: a request key in an agent-run worker home lets that agent trigger deploys of merged `main` to its requester's hosts. That is bounded by the merged-only gate, the per-host lock, the health check, the rollback and the audit.
- **Boundary**: source-versus-delivered. The policy decides placement in the worker's home; delivery is observed on the host (task 3.3).

### D6: Only commits on `main` are deployed, from the deployer's own mirror
- **Choice**:
  - The deployer keeps a bare mirror (`/var/lib/fleet-deployer/mirror.git`) and fetches `main` from `https://github.com/cameronraysmith/vanixiets.git` at each request.
  - The requested commit (default: the fetched head) must be an ancestor of, or equal to, that head.
  - The deploy uses a detached worktree of that commit, never a path, ref or flake URI from the requester.
  - For a NixOS target, the evaluated toplevel must already be in `https://cache.scientistexperience.net` (`nix path-info --store`). For darwin a missing entry is allowed (A158).
- **Rationale**: the merge queue and the required checks stay the only route to a deployable commit (Q1). A cache check keys on the closure, so it holds for gitea-mq's merge commits.

### D7: Deploys go through `clan machines update` with the commit's own target, after a vars check
- **Choice**:
  - Per request, `fleet-deploy-request` evaluates the target at the commit being deployed: `clan.inventory.machines.<m>.deploy.targetHost` for NixOS, `darwinConfigurations.<m>.config.clan.core.networking.targetHost` for darwin.
  - It runs `clan vars check` for every machine; any failure refuses the request, so clan never generates on cinnabar.
  - It then runs `clan machines update <m> --flake <worktree> --target-host <target>`, with `SOPS_AGE_KEY_FILE` the deployer's key, `CLAN_NO_COMMIT=1`, no agent socket, and `~/.ssh/config` naming only the deployer's key.
- **Rationale**: the target follows the deployed commit, so CAM-109's switch of targets to the registry takes effect with the commit that makes it. Passing it explicitly keeps clan's network selection out, so F36 does not apply. clan keeps owning the upload and the darwin activation.
- **Boundary**: vendored-versus-first-party. Whether `vars check` needs any out-of-scope decryption is observed on cinnabar (task 4.2).
- **Alternatives considered**: `deployUser@fqdn` from the registry (wrong while targets are still `.zt`); `clan vars upload` plus `nixos-rebuild` (nix-darwin has no remote target).

### D8: Targets accept the deployer's SSH key from cinnabar only
- **Choice**: `fleet-deploy-target` (NixOS and darwin, imported by every base, acting only on targets) installs `fleet-deploy-watch`. Once `keys` is set, it adds `from="<cinnabar's tincr, ZeroTier IPv6 and IPv4 addresses>",restrict <key>` to the deploy account: root on NixOS, `flake.lib.hosts.<m>.deployUser` on darwin (`cameron`, `NOPASSWD`).
- **Rationale**: root reach only from the one host that holds the key, without forwarding or a PTY.

### D9: One deploy per host at a time; sleeping hosts fail fast; two slots bound memory
- **Choice**:
  - The target is probed (`ssh -o ConnectTimeout=10`, status 5 on failure, nothing queued, Q6) twice:
    - first at `flake.lib.hosts.<name>.targetHost`, before the worktree and any evaluation, so a sleeping host fails in seconds (F83);
    - again at the address resolved from the commit, after the slot is released. A host can drop off during evaluation, and the commit names the address the deploy uses.
  - Evaluation (resolve, cache check, vars check) holds one of two slot locks.
  - The second probe precedes `flock` on `/run/fleet-deployer/lock/<machine>` (status 4 after 600 s).
  - The deploy takes a slot again.

### D10: The target arms its own rollback before activation and the deployer confirms after verification
- **Choice**: `fleet-deploy-watch <id> 7200 300`, started by `systemd-run` on NixOS. On darwin, `sudo fleet-deploy-watch --arm <id> 7200 300` bootstraps the job the target's configuration declares (`vanixiets.fleetDeployWatch`, rendered to `/etc/fleet-deploy-watch`) into launchd's system domain. There is one job label per host, and a second arm while it is loaded fails. The watcher:
  - records `/run/current-system` and waits up to 2 h for it to change, then 300 s for `<run>/fleet-deploy/<id>.confirmed`; the confirmation ends it whenever it arrives, during the first wait too, so a deploy of the running closure does not keep it for 2 h (F90);
  - unless confirmed, sets a new system profile generation to the recorded system and activates it (`switch-to-configuration switch` or `activate`), which writes a deploy record.

  The deployer confirms as soon as SSH answers after the settle period, whatever the health result. It stops its watcher when the deploy command fails. When the confirm fails, it reads the target's `/run/current-system` until `confirmWindow + rollbackGrace` has passed, and reports rolled back only once the target runs the closure it ran before the deploy; otherwise the request is unconfirmed.
- **Rationale**: only a host that stops answering rolls back (Q5). Watching `/run/current-system`, not the profile, covers every activation, specialisations included.
- **F84 (2026-11-19)**: the darwin watcher was first started with `sudo sh -c 'launchctl submit …'` over SSH. `submit` is a legacy subcommand that acts on the caller's bootstrap namespace, which sudo does not change, so the job ran as the deploy user in `gui/502` (`logs/cam115-e2e3-20261119T1852Z-6.3-rolledback-diag.log`). It could not create `/var/run/fleet-deploy`, so the confirm failed, and it could not roll back. The deployer then reported rolled back after sleeping without reading the host, and every Mac deploy exited 8. `launchctl bootstrap system <plist>` names its domain and requires root. `asuser 0` is documented only as running as close as possible to the user's context. A nix-darwin daemon was rejected, because activation reloads a daemon whose plist changed, which would end the watcher in the middle of the deploy it watches. The obligation in `flake.lib.fleetDeployer.failures` requires every darwin target's job to be in the system domain, run as root, not kept alive and run `fleet-deploy-watch --run`.

### D11: Feedback is the streamed log, a settle period and a health verdict
- **Choice**: after the update, 60 s of settling, then:
  - SSH answers, and the confirm is sent;
  - the newest deploy record names the deployed closure;
  - `systemctl --failed` is empty (NixOS), or every `org.nixos.*` job's last exit is 0 (darwin).

  Exit statuses: 0 deployed, 3 refused, 4 busy, 5 unreachable, 6 failed, 7 unhealthy, 8 rolled back, 9 unconfirmed (not confirmed and not read back on its previous closure, F84).

### D12: Every request is recorded and announced, with the token kept root-only
- **Choice**: `fleet-deploy-request` appends `{ts, id, requester, command, session, machine, target, commit, closure, previous, outcome, reason, finished}` to `/var/lib/fleet-deployer/requests.jsonl` (`0600`) for every request. `previous` is the target's running system read before the deploy. The path unit `fleet-deploy-notify` (root, the alerter token through `NTFY_TOKEN_FILE`) posts each new line to the topic `fleet-deploy` (Q32), with `Priority: high` for refused, unhealthy, rolled-back and unconfirmed. ntfy's existing `alerter:fleet-*:rw` admits the topic, so no ACL edit is needed.
- **Rationale**: the request process never holds the alerter token.

### D13: The deployer itself is deployed like any other target
- **Choice**: cinnabar is a target. The request process is a child of `sshd`, not a unit activation restarts, and D10's watcher covers a switch that cuts SSH.

### D14: A darwin host's deploy depends on the darwin machine-key guard
- **Choice**: no change. The existing guard refuses darwin activation without the host's machine key, and the upload delivers that key before activation; task 6.3 exercises it on rosegold.

### D15: Regulators sit in the machine checks and in fixture checks
- **Choice**:
  - `flake.lib.fleetDeployer.failures` is asserted in `withFleetObligations` on every `nixos-<host>` and `darwin-<host>` check, at no added evaluation. It requires:
    - the primary user's account;
    - no deployer key on a non-target, nor on a second account;
    - exactly the restricted line on a target's deploy account;
    - on the deployer host only, the account's keys equal to the requesters' lines, the key directory `0700` and `UMask=0277`.
  - `flake.lib.fleetDeployer.problems`, asserted by the machine checks module, judges the real policy: no disabled, excluded or non-system target, and no reach outside the role rule.
  - `checks.x86_64-linux.fleet-deployer-obligations` runs both judges over fixtures with mutants; `checks.x86_64-linux.fleet-deploy-request` runs the parser; `sops-correspondence` covers the deployer's reach.
  - `vmTests.x86_64-linux.fleet-deployer` (on-demand, KVM on pyrite) runs the request path end to end with a local forge, cache and stubbed clan.

## Risks / Trade-offs

- [Risk] cinnabar compromise yields the targets' machine keys and root on them → Mitigation: no session or untrusted code runs there; the keys belong to one account at `0400`; every use is announced; stibnite and blackphos are out of reach; the move to the CAM-112 successor rotates both keys.
- [Risk] `clan vars check` or the update's health pass needs to decrypt an out-of-scope file → Mitigation: task 4.2 tests it on cinnabar before any target trusts the key. If it fails, D7 changes before rollout.
- [Risk] A request key in a worker home is used by the agent there (accepted, Q31) → Mitigation: bounded by D4, D6, D9, D10, D11 and D12.
- [Risk] The darwin watcher does not survive `darwin-rebuild`, or launchd restarts it → Mitigation: the watcher removes its own job on every path; task 5.4 confirms it on a no-op deploy (A159).
- [Risk] Evaluation of two deploys exhausts cinnabar's memory beside ntfy and caddy → Mitigation: two slots; magnetite's memory-budget pattern is available if observed peaks warrant it.
- [Risk] A request can redeploy an older merged commit → Mitigation: allowed by design, recorded and announced; refusing downgrades would need the deployed commit, which the deploy record does not carry.
- [Trade-off] darwin targets are gated on `main` only → accepted (A158).
- [Trade-off] session ids are not verified → accepted (Q3).
- [Trade-off] Two provisioning conditionals (`keys = null`, `deployRequestEnrolled = false`) live until the host steps → removed by task 7.1.
- [Known limit, F72] A darwin deploy can fail inside a person's home-manager activation: argentum, 2026-11-18, `Activating sops-nix` → `Bootstrap failed: 5: Input/output error`, because launchd cannot load a per-user agent without that person's console session. It leaves `/etc` and the system profile on the new generation and the running system on the old one.
  - **What the code does today:** `fleet-deploy-request` treats any non-zero exit of `clan machines update` as `failed` (status 6, "the deploy command failed"). It stops the rollback watcher, records the request and posts it at normal priority. This case is therefore never reported as success, provided clan exits non-zero, which it did here.
  - **Gap, closed (Q66, 2026-11-19):** the health check now begins by comparing `readlink -f /run/current-system` on the target with the deployed closure, on both NixOS and darwin. A mismatch ends the request as `unhealthy` (7), with a reason naming both paths, so an activation that exits 0 without switching is never reported as deployed. The deploy record alone is not evidence, because activation writes it before the switch.
  - **Remaining limit:** a darwin target needs its users logged in with a console session for a deploy that changes their agents. Physical presence is not needed: the operator's `clan machines update argentum` at 04:23Z on 2026-11-19 completed remotely (generation 30), with both users holding console sessions. Statuses 6 and 7 send the operator to the machine.
- [Fixed, F83] A request to a sleeping host used to end `unreachable` (5) only after the resolve, the cache check and the vars check: argentum, 2026-11-19 18:36Z, took 133 s against task 6.3's one minute. The deployer now probes `flake.lib.hosts.<name>.targetHost` before evaluating (D9). That address is the single source of every deploy address:
  - darwin machine modules set `clan.core.networking.targetHost` from it;
  - NixOS inventory `deploy.targetHost` reads it;
  - no darwin machine has an inventory `deploy.targetHost`, so manual `clan machines update` keeps its network-peer path (F36).
  - `flake.lib.networkTargetObligations` holds this on every machine check.

## Migration Plan

1. Land the regulators red, then the deployer on cinnabar, the target module, the request credential kind (enrollment off) and the VM test. No host trusts a deployer key while `keys` is null (done in this change's code commit).
2. Deploy cinnabar from stibnite; `fleet-deployer-keys` generates the keys. Commit their public halves to `flake.lib.fleetDeployer.keys` and `sops/users/fleet-deployer`. Create the group and add it to the targets' machine keys and activation vars (D3). Verify that only those files changed (tasks 2.1-2.4).
3. On cinnabar, as the deployer, run the vars check and a target-unreachable dry pass (task 4.2).
4. Generate the request keys (`clan vars generate`) and flip `deployRequestEnrolled`; deploy magnetite, pyrite and stibnite (task 3.3).
5. Deploy each target from stibnite so it trusts the deployer, laptops when awake (task 5.2).
6. Run the integration verification (group 6).

Rollback: setting `keys = null` and redeploying withdraws every target's trust; `clan secrets groups remove-secret fleet-deployers <m>-age.key` and removing the activation vars' group links followed by `clan vars fix` withdraw read access. Each is one revertible commit.

## Open Questions

1. World-assumption numbers A155-A159 follow A154 (`diagram-fleet-topology`). A concurrent change claiming the same numbers is reconciled at archive.
2. The `world-assumptions` MODIFIED delta copies the designation table at `main@origin` `82010ba4`; other in-flight changes modify the same table, and their rows are merged at archive.
3. Answered on 2026-11-18: a failing `fleet-deployer-keycheck` raised no alert. #4042 adds it to cinnabar's `notifiedUnits`.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
The repository has no BDD runner and no `.feature` file, so no row routes to a Gherkin scenario. Each requirement is witnessed by one of:
- a build gate: `nix eval`, `nix build`, a fleet obligation on the machine checks, the fixture checks, or the correspondence check;
- the on-demand VM test;
- a smoke observation on a deployed host, recorded in `verify.md`.

The operator approved this table on 2026-11-18 (Q33). It was revised the same day for Q30-Q32 (derived targets, role policy, `fleet-deploy` topic) and for the implementation's check names; the revision changes witnesses, not modalities.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| A requester can have a host redeployed at a merged commit and learn the outcome | `fleet-deploy-delegation` | behavioral | VM test and smoke | tasks 4.3, 5.1, 6.1, 6.2, 6.3 |
| Only merged commits are deployed | `fleet-deploy-delegation` | behavioral | build gate (fixture check), VM test and smoke | tasks 1.2, 4.1, 4.3, 6.4 |
| A requester deploys only the hosts allowed to them | `fleet-deploy-delegation` | behavioral | build gate (fixture checks, policy judge) and smoke | tasks 1.1, 1.2, 3.1, 6.4 |
| Every deploy request is recorded and announced | `fleet-deploy-delegation` | behavioral | VM test and smoke | tasks 4.3, 4.4, 6.1, 6.4 |
| Two deploys of the same host never overlap | `fleet-deploy-delegation` | behavioral | VM test | task 4.3 |
| A sleeping or unreachable host is reported without a deploy | `fleet-deploy-delegation` | behavioral | VM test and smoke | tasks 4.3, 6.3 |
| A host that stops answering after a deploy returns to its previous configuration | `fleet-deploy-delegation` | behavioral | VM test and smoke | tasks 5.3, 5.4, 6.5; the darwin "cut connection" scenario is accepted from 5.4's exercise plus the VM test, because cutting a laptop's connection on purpose is not worth the disruption |
| stibnite and blackphos are never deployed by the deployer | `fleet-deploy-delegation` | behavioral | build gate (obligation, fixture checks, correspondence check) and smoke | tasks 1.1, 1.2, 1.3, 2.2, 6.4 |
| A disabled host is never deployed by the deployer | `fleet-deploy-delegation` | behavioral | build gate (policy judge, obligation, fixture check) | tasks 1.1, 5.1 |
| Each `fleet-deploy-delegation-interface` requirement | `fleet-deploy-delegation-interface` | interface | build gate and VM test | tasks 1.1-1.4, 2.1-2.4, 3.1-3.3, 4.1-4.4, 5.1-5.3 |
| The deployer reads only the machine keys of the hosts it deploys | `secret-custody` | behavioral | build gate (correspondence check) and smoke | tasks 1.3, 2.2 (the deployer's key fails on `stibnite-age.key`) |
| The operator identity can read every secret file (modified: admits the deployer's key for deploy targets' machine keys) | `secret-custody` | behavioral | build gate (correspondence check) | tasks 1.3, 2.2 |
| The correspondence check compares user anchors and clan user keys with login keys (modified) and compares the deployer's reach with the deploy targets | `secret-custody-interface` | interface | build gate (correspondence check, mutants) | tasks 1.3, 2.2 |
| A155-A159 | `world-assumptions` | world | monitoring (violation scenarios) | A155 by 2.2's decrypt test and review of clan-core's sops backend at each clan-core bump; A156 by 4.2 at each clan-core bump; A157 by 6.3 and the `unreachable` outcomes in `requests.jsonl`; A158 by review of `modules/nixos/nixbot.nix` when its darwin builds change; A159 by 5.3 (NixOS) and 5.4 (darwin) |
| Grounded vocabulary for behavioral requirements (modified: eleven rows, from `deployer` to `rollback`) | `world-assumptions` | world | designation lint (verify §8) | `verify.md` §8 |
