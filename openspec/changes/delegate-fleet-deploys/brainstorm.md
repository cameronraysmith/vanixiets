# Brainstorm: let an agent session on another host redeploy fleet hosts with clan, unattended

## Background

Today only stibnite can deploy, because only stibnite holds the clan admin age key and the SSH identities the targets accept.
An agent session (omnigent or another) on any other host cannot redeploy or reactivate a fleet host without the operator at stibnite.
The operator approved starting this thinking on 2026-11-18 (Q16); this file is the raw capture, and it stops before design approval.

The reader is the operator, deciding the open questions at the end, and the designer who writes `design.md` from it.
Citations are `vanixiets@82010ba4` (`main@origin` on 2026-11-18) unless prefixed: `cc@d718bcf` is clan-core, `ci@008b3ec` is clan-infra (github.com/clan-lol mirror), `mic@d5b5b06` is Mic92/dotfiles, `nb@171a8c7` is Mic92/nixbot.
The upstream clones were read as found under `~/ghq`, without fetching.

## Given (operator, 2026-11-18)

- G1 A deploy needs SSH to the target (root on NixOS, the darwin primary user with sudo) and a clan admin age key, because `clan machines update` decrypts and uploads to `/var/lib/sops-nix`.
- G2 stibnite holds the admin age keys. pyrite has the operator's keys in a Bitwarden SSH agent, but no admin age key and no clan on `PATH`. magnetite holds no SSH identity.
- G3 Agent forwarding is off fleet-wide (`modules/home/core/ssh.nix:122`), and the omnigent worker asserts it (`modules/home/ai/omnigent/worker.nix:171-189`).
- G4 magnetite builds untrusted PR code (nixbot, Renovate) and runs effects with secrets, so the deployer does not live there.
- G5 The agent host is multi-user (cameron now, janettesmith later). CAM-112 plans a dedicated agent host and a successor to cinnabar.
- G6 F36: tincr's clan network export makes clan target darwin hosts as root over the mesh, which fails; `--target-host` works around it.
- G7 Options already weighed: O1 agent forwarding (fails unattended, too broad), O2 copying personal keys (no), O3 a per-host deploy identity, O4 deploys as a service (recommended going in), O5 the status quo.

## Found while preparing

### What a deploy actually decrypts

- F1 `clan machines update` becomes root on the target and runs `upload_secret_vars` before the build, with no flag to skip it (`cc@d718bcf:pkgs/clan-cli/clan_lib/machines/update.py:609-612`; flags at `clan_cli/machines/update.py:255-321`).
- F2 With the sops backend, the upload decrypts only `sops/secrets/<machine>-age.key` (sent as `key.txt`) and the vars marked `neededFor = "activation"`; every other var travels encrypted in the closure and is decrypted on the target by sops-nix with that `key.txt` (`cc@d718bcf:clan_lib/vars/secret_modules/sops.py:243-280`, `vars/secret/sops/generators-to-sops.nix:63`).
- F3 So the deployer's real secret scope is per machine, not per secret: whoever can read `<machine>-age.key` can read every secret of that machine. Narrowing below a machine is not possible with this backend `[INFERENCE from F2]`.
- F4 In this fleet one var is `neededFor = "activation"` (the initrd SSH host key, `modules/system/initrd-networking.nix:8`) and one is `neededFor = "partitioning"` (pyrite's ZFS key, `modules/machines/nixos/pyrite/disko.nix:40`).
- F5 Each upload wipes and rewrites the target directory; there is no "already present" check (`cc@d718bcf:clan_lib/ssh/upload.py:13-124`).
- F6 `clan machines update` runs the generators of every machine in the clan, not only the targets, and checks each one's health (`cc@d718bcf:clan_cli/machines/update.py:210`, `clan_lib/vars/generate.py:328-329`). A deployer scoped to some machines fails or tries to generate when another machine has a missing var `[INFERENCE]`. `clan vars upload <m>` followed by `nixos-rebuild`/`darwin-rebuild` is a documented alternative that avoids this (`cc@d718bcf:clan_cli/vars/upload.py:11-41`, `docs/src/guides/nixos-rebuild.md`).
- F7 Scoping works today: add the deployer's age key to a sops group, list that group in `clan.core.sops.defaultGroups` of the chosen machines only, and `clan vars fix` re-encrypts (`cc@d718bcf:nixosModules/clanCore/sops.nix:34-39`, `clan_lib/vars/secret_modules/sops.py:345-468`). clan's experimental age backend has explicit per-host recipients (`vars.settings.recipients.hosts.<machine>`, `cc@d718bcf:clan_lib/vars/secret_modules/age.py:211-252`).
- F8 clan-core has no deploy lock, queue, hook or audit log (`cc@d718bcf:clan_lib/git/__init__.py:76` is the only lock, for git commits), and no pull or auto-upgrade mode (`docs/src/guides/migrations/migrate-inventory-services.md:255`). A pull deploy, `dm-pull-deploy`, exists in clan-community (`cc@d718bcf:docs/src/releases/26-05.md:171`). It is not cloned here, so I have not read it.
- F9 A non-root target user is wrapped in `sudo -A` with a GUI or TTY askpass (`cc@d718bcf:clan_lib/ssh/remote.py:194-283`). darwin's primary user here has `NOPASSWD: ALL` (`modules/darwin/base.nix:11-12`), so `cameron@<darwin>` runs unattended. `requireExplicitUpdate` excludes a machine from a bare `clan machines update` (`cc@d718bcf:nixosModules/clanCore/networking.nix:91-99`).

### Who can decrypt today

- F10 Every `sops/secrets/<machine>-age.key` and every per-machine var has a single user recipient, `cameron` or `crs58` (`sops/secrets/*-age.key/users/`, `vars/per-machine/*/*/*/users/`).
- F11 `sops/users/cameron` and `sops/users/crs58` hold the same public key, `age1vn8f…tmv8`. christophersmith, janettesmith and raquel are users but read no machine key and no per-machine var. In practice the fleet has one admin key.
- F12 magnetite's `~cameron/.config/sops/age/keys.txt` is not an admin key. Its public key is `age1js02…w8cy`, the Kubernetes development key (`docs/notes/development/kubernetes/components/sops-secrets-operator.md:117`). On 2026-11-18 it was mode `0644` in a `0755` directory, so every account on magnetite could read it, the omnigent worker accounts and nixbot's builds included (read-only ssh). The orchestrator has since fixed it: the file is now `0600` in `0700` directories. No service reads the file, which was created by hand on 2026-04-22. A sweep of magnetite, cinnabar and pyrite found no other private key readable by group or world. Whether to rotate the key is the operator's decision, outside this change.

### Targets

- F13 NixOS targets are `root@<host>.zt` in the inventory (`modules/clan/inventory/machines.nix:25-85`); darwin targets are `clan.core.networking.targetHost = "<user>@<host>.zt"` (argentum, rosegold `cameron@`; blackphos, stibnite `crs58@`; `modules/machines/darwin/*/default.nix`).
- F14 CAM-109's design generates both from `flake.lib.hosts.<name>.{deployUser,fqdn}` and keeps `--target-host root@<public>` as the VPS break-glass (`openspec/changes/migrate-mesh-to-tincr/design.md:71`, `:149`, `:238-239`). With G6, a deployer that resolves targets from that registry and always passes an explicit `--target-host` is unaffected by clan's network selection.
- F15 Four darwin laptops (stibnite, blackphos, rosegold, argentum) and pyrite sleep or travel. clan-infra and Mic92 both mark such machines `requireExplicitUpdate` (`ci@008b3ec:machines/build02/configuration.nix:13-15`, `mic@d5b5b06:machines/bernie/configuration.nix:44`).

### CI and merge gates

- F16 nixbot on magnetite builds and evaluates `x86_64-linux` and `aarch64-darwin`, but darwin only best-effort, on whichever Mac magnetite can reach (`modules/nixos/nixbot.nix:130-142`). The six NixOS closures can therefore be required to come from CI. A darwin closure may have no CI build, so for darwin the gate is "on `main`", which still implies the flake evaluated in CI.
- F17 vanixiets already runs nixbot effects with per-repo secrets (`modules/effects/vanixiets/secrets.nix:114`, enabled on magnetite at `modules/machines/nixos/magnetite/default.nix:83`). nixbot reads its effects settings from the default branch, so a PR cannot enable effects for itself (`nb@171a8c7:nixbot/nixbot/effects.py:75-91`). It can also mint a 300 s OIDC token whose `sub` names repo and branch (`nb@171a8c7:docs/WORKLOAD_IDENTITY.md:12-81`).
- F18 Mic92 deploys with that token: an effect on `main` presents it to a relay (`flakelet-relay`) that maps the principal to allowed `host/service` targets (`mic@d5b5b06:nixosModules/flakelet-relay/default.nix:57-157`), or to OpenBao, which signs a 10-minute SSH certificate for a `deploy` user (`nb@171a8c7:docs/WORKLOAD_IDENTITY.md:17-52`). His clan machines, though, are still deployed by hand, as root, with his own age key. He has no bot age key (`mic@d5b5b06:sops/users/`).
- F19 clan-infra deploys every machine by hand, the same way. Its sops users are all humans, its machine keys are encrypted to `groups/admins`, and it has no `from=` restriction anywhere. Its one reusable piece is a jump-only `tunnel` account: nologin, no TTY, no agent forwarding (`ci@008b3ec:modules/web01/jumphost.nix:6-29`). Neither reference has a delegated clan deploy to copy.

### Existing receptacles this should reuse

- F20 Per-host evidence of a deploy already exists: every activation appends `{host, closure, previous_closure, ts}` to `/var/log/deploy-record.jsonl`, and the collected hosts ship it to `devloop` (ADR-005; `openspec/specs/world-assumptions/spec.md:261-262`).
- F21 Alerts and notices go through `ntfy-send` to `ntfy.zt` with the shared `alerter` token (`modules/nixos/fleet-alert.nix`); CAM-87 made clients verify caddy's root.
- F22 Per-user agent credentials are already delivered as clan vars shared to the agent hosts and gated by the worker's credential policy (`modules/home/ai/omnigent/credentials.nix`; `vars/shared/omnigent-<user>-*`, machines magnetite, pyrite, stibnite). A per-user deploy-request credential fits this receptacle; a parallel credential path would duplicate it.
- F23 `secret-custody` already admits "automated runners that use a file" as readers (`openspec/specs/secret-custody/spec.md:21-27`), and its correspondence check compares each file's recipients with its rule (`openspec/specs/secret-custody-interface/spec.md:94`). A deployer key is a new reader that check must account for.

## Volatility (lowy lens)

What changes independently, and so wants its own boundary:

| Axis | What changes | Likelihood × effect |
|---|---|---|
| Requester | who asks: cameron's sessions now, janettesmith's later, the operator by hand, possibly a nixbot effect on merge (F17) | high: a second user is planned (G5) |
| Authorization | which requester may deploy which machines | high, changes with each user and host |
| Target transport | `.zt` to `.vanixiets.internal`, darwin user vs root, F36, break-glass addresses (F14) | certain: CAM-109 is in flight |
| Secret backend | sops today, clan's age backend later (F7) | plausible; clan encapsulates it behind `clan vars upload` |
| Health verification | what "healthy after deploy" means per platform | moderate |

The deployer is the manager of the sequence: authorize, check that the commit is gated, lock the target, upload vars, activate, settle, verify, report.
Target resolution and health verification are its two engines.
A requester never sees the target transport or the age key; it sees one verb, "deploy machine M at commit C", and a result.

## Options

O1, O2 and O5 are settled (G7). O6 and O7 are new; O3 and O4 are restated with what the survey adds.

| | Shape | Security | Usability | Verdict |
|---|---|---|---|---|
| O3 per-host deploy identity | each agent host gets its own SSH key (root on targets, `from=` that host) and its own clan admin recipient | the admin key lives on every agent host. Agent hosts are multi-user and run session code, so each one can read every in-scope machine's `key.txt` (F3). Revoking a host means re-encrypting. No requester identity below the host. | direct: a session runs `clan machines update` itself and sees the output | rejected: the key's blast radius grows with each agent host, and no layer separates "a session asked" from "a session did it" |
| O4 deploys as a service | sessions ask one deployer to deploy a commit already on `main`. Only the deployer holds a scoped admin recipient (F7) and root/sudo SSH to targets (`from=` the deployer). Requests carry a per-user credential (F22) and are audited and announced. Unmerged experiments still deploy from a workstation. | one place holds deploy power. Requesters can only name a machine and a commit that is already on `main`. Their credential, if stolen, can only redeploy what merge gates already admitted. | one verb, synchronous result, works when stibnite sleeps. Experiments stay on stibnite. | **recommended** |
| O6 pull-based self-activation | each host fetches `main` (or a CI-built toplevel) and activates itself. The secrets it needs are already decrypted on the host with its own `key.txt` (F2) | no central key or root path. `main` itself becomes the deploy authority. The admin key is still needed for activation-phase vars (F4) and machine-key rotation. clan-core has none of this (F8). | no per-request feedback or requester identity. Each darwin laptop evaluates the flake itself (F16), though it does pull after waking up. | rejected as the primary path. A candidate later for the darwin laptops only. |
| O7 deploy on merge from a nixbot effect | an effect on `main` deploys the changed hosts | effects run on magnetite (G4). Holding the key there is excluded. Mic92's relay pattern (F18) keeps the key off magnetite: the effect only presents an OIDC token to the deployer. | automatic. Sessions cannot pick a host or a time, and darwin laptops are rarely awake. | rejected as the mechanism. Kept as a second requester O4 can admit later through F18's token, without changing the deployer. |

### O4 in more detail (the recommendation, for the operator to correct)

- **Request channel.** SSH to a `deploy` account on the deployer, with a forced command (`command=`, `restrict`): `fleet-deploy <machine> [<commit>]`, where the commit defaults to the current `main`. Each requester gets its own SSH key, delivered like the existing worker credentials (F22) and generated per user (`omnigent-<user>-deploy-request`). The forced command logs the key's owner as the requester. My call: SSH rather than HTTP, because it needs no new listener, token store or TLS path, it carries requester identity in the key, and it streams output back over the same connection. A per-session identity (finer than per user) is open (Q3).
- **Authorization.** A per-requester allowlist of machines, declared in nix next to the deployer and evaluated into the forced command. Default deny.
- **Commit gate.** The deployer fetches `main` itself and refuses any commit that is not an ancestor of it. It never takes a flake path or arbitrary ref from the requester. For NixOS targets it also requires nixbot's success status on that commit, or a toplevel present in niks3. For darwin, being on `main` is the whole gate (F16).
- **Secret scope.** The deployer gets its own age key, generated on the deployer, which never leaves it. It is registered as `sops/users/deployer` in a group listed in `defaultGroups` of in-scope machines only (F7). The recipients of `<machine>-age.key` and the activation vars change for those machines only. Which machines are in scope is Q4. The deployer cannot read operator credentials or shared vars it does not upload (F2).
- **Activation path.** `clan vars upload` plus `nixos-rebuild`/`darwin-rebuild --target-host` with the target resolved from the host registry (F14, G6), rather than `clan machines update`, to avoid F6. This is a designer's call to confirm in `design.md`.
- **Target SSH.** The deployer's SSH key is in root's `authorized_keys` on NixOS and in the primary user's on darwin (F9), restricted to the deployer's mesh address with `from=`, and to `no-agent-forwarding,no-port-forwarding,no-pty` (`no-X11-forwarding` is implied).
- **Concurrency.** One `flock` per target machine on the deployer. A second request for the same machine waits up to a bound and then fails with `busy`. Requests for different machines run in parallel, capped to protect the deployer's memory for evaluation.
- **Sleeping darwin targets.** Reachability is probed before anything is uploaded. An unreachable target returns `unreachable` immediately, and nothing is queued. Whether to queue and retry on wake is Q6.
- **Feedback.** The forced command streams the log. After activation it waits a settle period (my call: 60 s), then checks health: failed systemd units on NixOS, the launchd daemons the host declares on darwin, SSH reachability, and the new deploy record with its closure (F20). It exits 0 only if all of these pass. The requesting session therefore gets one exit code and a log covering the deploy and its verification.
- **Audit and notification.** The deployer appends `{requester, machine, commit, closure, outcome, ts}` to its own journal. Every request, refused ones included, is posted through `ntfy-send` to a fleet topic. Refusals and failed verifications go out at higher priority. The host's own deploy record (F20) is the second, independent witness.
- **Rollback.** Proposed: if the target stops answering after activation, it rolls itself back (a deploy-rs-style confirm timer that the deployer cancels once verification passes). A failed health check that leaves the target reachable is reported, not rolled back automatically. This is Q5.
- **Where it lives.** Not magnetite (G4), and not the multi-user agent host. On a shared host, root on that host would hold the deploy key, and so would anything that escapes a worker. That leaves cinnabar now, cinnabar's successor or a small dedicated host (CAM-112), or stibnite. stibnite sleeps, and keeping it as the deployer means nothing changes. This is Q2.

## Questions for the operator

Most important first. Each has my recommendation.

- **Q1 Approach.** O4, deploys as a service, with O7's CI requester left as a later extension and O6 kept for possible later use on darwin laptops? Recommendation: yes.
- **Q2 Where does the deployer live?** (a) on cinnabar now, moving with cinnabar's successor (CAM-112). (b) a small dedicated host, which costs money and needs your approval. (c) a separate account on the planned agent host. Recommendation: (a). cinnabar is always on, holds no untrusted code, and already serves `ntfy.zt`. (c) puts the key one root escalation away from every session.
- **Q3 Requester granularity.** One deploy credential per user (cameron, janettesmith), or one per session? Recommendation: per user now, matching how other worker credentials are issued (F22). The journal records the session id the request passes, but nothing verifies it.
- **Q4 Machine scope of the deployer's key.** Which machines may the deployer redeploy? Recommendation: the six NixOS hosts, plus rosegold and argentum if you want family laptops covered. Keep stibnite and blackphos (the `crs58` workstation and raquel's laptop) out, so a compromised deployer cannot read the controller's key or change it. Per F3, the scope can only be drawn per machine.
- **Q5 Rollback.** Should a target that becomes unreachable after activation roll itself back automatically, while other health failures are only reported? Recommendation: yes. A fully automatic rollback on any failed check would hide real breakage from the requesting session.
- **Q6 Sleeping darwin targets.** Fail immediately with `unreachable` (the session retries later), or queue the request and deploy when the host returns? Recommendation: fail immediately. A queued deploy runs at a time nobody watches, which defeats the synchronous feedback.
- **Q7 Authorization for janettesmith.** When her sessions arrive, which machines may they deploy? Recommendation: rosegold (her laptop) only, and nothing until she has an agent host account.
- **Q8 (settled, kept as a lesson) Keys on shared or agent hosts.** F12 was fixed outside this change, but it shows the risk this design has to avoid. A key on a multi-user host that runs agent or untrusted code is one permission slip away from every account there. The deployer's age identity and SSH key therefore live only on the deployer (Q2 excludes the agent host and magnetite). The design should also keep them unreadable to anyone but the deployer's account, and add a check that fails if they are readable more widely.

## Status

Brainstorm captured on 2026-11-18. The approaches are laid out with a recommendation; nothing is decided until the operator answers Q1–Q7. `design.md` is not written and the design is not approved.
