---
title: Deploy delegation
description: "How an agent session asks cinnabar's fleet deployer to redeploy a host at a merged commit, what the answer means, and how requesters, targets and the deployer itself are added, revoked or moved."
---

An agent session redeploys a fleet host by asking the fleet deployer on cinnabar, not by holding any key that reads the host's secrets.
The deployer deploys only commits already on `main`, only to hosts the requester may reach, one deploy per host at a time.
It answers with the log and one exit status that covers the deploy and a health check after it.
The design is the `delegate-fleet-deploys` change (CAM-115).

## Asking for a deploy

From an omnigent worker whose owner holds a request credential:

```bash
fleet-deploy <host>                      # at the head of main
fleet-deploy <host> <commit>             # at a merged commit
fleet-deploy <host> --session <id>       # the id is logged, not verified
```

`fleet-deploy` is `ssh fleet-deployer deploy …`. The SSH alias names `cinnabar.zt`, the account `fleet-deployer` and the worker's request key, with no agent.
Nothing else can be run through it: any other command is refused.

| Exit | Outcome | Meaning |
|---|---|---|
| 0 | deployed | the host runs the commit's configuration, answers, and reports no failed unit or job |
| 3 | refused | malformed request, host outside the requester's reach, commit not on `main`, NixOS closure not built by CI, or a failed `clan vars check`; nothing was contacted |
| 4 | busy | another deploy of the host held its lock for 10 minutes |
| 5 | unreachable | the host did not answer within 10 s (asleep or away); nothing was queued |
| 6 | failed | `clan machines update` failed; the host's watcher was stopped |
| 7 | unhealthy | deployed and answering, but a unit or job failed, or the deploy record names another closure; the host keeps the configuration |
| 8 | rolled back | the host stopped answering after activation, so it returns to its previous system within 5 minutes by itself |

Every request is appended to `/var/lib/fleet-deployer/requests.jsonl` on cinnabar and posted to the ntfy topic `fleet-deploy`, with refusals, unhealthy deploys and rollbacks at high priority.
The host's own deploy record (`/var/log/deploy-record.jsonl`) is the second witness.

## Who may deploy what

Targets are derived, never listed (`flake.lib.fleetDeployer.targets`): every NixOS or darwin machine that is enabled, except stibnite and blackphos.
A cloud machine is enabled by its `enabled` flag in `modules/lib/cloud-machines.nix`, which terranix provisions from; any other inventory machine is enabled.
Re-enabling a cloud machine makes it a target with no other change.

Reach follows each machine's `primaryUser`, which `modules/lib/hosts.nix` derives from the host's one attachment with `primary = true` (`modules/lib/host-users.nix`):

- a shared server (no primary user) is reachable by every operator (`operators` in `modules/lib/fleet-deployer.nix`);
- a personal machine is reachable by its primary user and by the admin.

`nix eval .#lib.fleetDeployer.requesters` prints each requester's reach.
The machine checks fail when a disabled or excluded machine would be in reach, or when any host other than a target accepts the deployer's key.

## Adding a requester

1. Make the person an operator in `modules/lib/fleet-deployer.nix`, or the primary user of their machine (`primary = true` on their attachment in `modules/lib/host-users.nix`). The requesters are the owners in `flake.fleet.workers` (`modules/lib/fleet-workers.nix`), so a person with an omnigent worker is a requester with nothing more to declare.
2. Enable `deployRequestKey` for their worker, generate its vars on stibnite with `clan vars generate <agent host> --generator omnigent-<user>-deploy-request`, and commit both together.
3. Deploy cinnabar, which picks up the new forced-command line, and the agent hosts, which deliver the key.

## Revoking

- **A requester:** remove their worker owner entry from `flake.fleet.workers` (which also removes their workers) and deploy cinnabar. Their key no longer opens the account.
- **A target's trust:** a machine that stops being a target loses the deployer's key at its next deploy. To withdraw all trust at once, set `flake.lib.fleetDeployer.keys = null` and deploy the targets from stibnite.
- **Read access:** remove the target from the targets, then run `clan secrets groups remove-secret fleet-deployers <host>-age.key` and delete the `groups/fleet-deployers` links of its activation vars, followed by `clan vars fix <host>`, on stibnite.

## Moving the deployer

The deployer's keys are generated on its host by `fleet-deployer-keys` and never leave it.
To move it, for example to cinnabar's successor:

1. Import `flake.modules.nixos.fleet-deployer` on the new host, set `deployerHost` in `modules/lib/fleet-deployer.nix`, and deploy the new host from stibnite.
2. Read the new public halves there with `age-keygen -y` and `ssh-keygen -y`, as `fleet-deployer`. Commit them to `flake.lib.fleetDeployer.keys` and `sops/users/fleet-deployer/key.json`.
3. Replace `sops/users/fleet-deployer/key.json` with the new age key (`clan secrets users add -f`), which re-encrypts every file the `fleet-deployers` group reads. Then deploy each target from stibnite so it trusts the new address and key.

The move rotates both keys.

The group reads exactly what `clan machines update` decrypts on the deployer: each target's machine key and its activation-phase vars.
When a target gains an activation-phase var, its machine check fails until the var has a `groups/fleet-deployers` link and `clan vars fix <host>` has re-encrypted it.
`fleet-deployer-keycheck` fails daily, and at start, while the keys' modes, owner or public halves differ from the flake.
