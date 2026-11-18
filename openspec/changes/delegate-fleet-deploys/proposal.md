---
linear_story_id: CAM-115
linear_story_identifier: CAM-115
linear_story_title: "Delegate fleet deploys to agent sessions through a scoped deployer"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-115/delegate-fleet-deploys-to-agent-sessions-through-a-scoped-deployer
linear_story_state: Todo
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: Todo
last_synced_at: "2026-11-18T21:34:28Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-18T21:34:28Z", transition: "Backlog->Todo", outcome: "posted", note: "Created in Backlog with the seeded description, related to CAM-112 and CAM-109, moved to Todo, bind comment posted" }
---

## Why

Only stibnite can deploy the fleet. It holds the one clan admin age key that unlocks machine keys, and the SSH identities the targets accept. Agent forwarding is off fleet-wide, and copying personal keys is ruled out. So an agent session on any other host cannot redeploy or reactivate a host without the operator at stibnite, and work stalls whenever stibnite sleeps.
Sessions are now multi-user (cameron, later janettesmith), and CAM-112 is planning the agent host and cinnabar's successor, so where deploy power lives has to be settled now.
The goal is that sessions can deploy what the merge gates already admitted, unattended and with feedback. No session or agent host should ever hold the admin key or root on a target.

## What Changes

The approach is pending the operator's answers to Q1–Q7 in `brainstorm.md`. Below is the recommended option, O4 (deploys as a service), as it would land if Q1 is accepted.

**A deployer that deploys on request**
- From: a deploy is `clan machines update` or `just activate`, run by the operator on stibnite with the operator's admin key.
- To: a requester asks one deployer to deploy one machine at one commit that is already on `main`. The deployer checks that the requester may deploy that machine, holds a per-machine lock, uploads the machine's vars, activates the machine, waits a settle period, and checks the host's health. It returns the log and a single outcome to the requester.
- Reason: deploy power sits in one place that runs no untrusted or session code. A requester's credential can only redeploy what CI and the merge queue already admitted.
- Impact: non-breaking. The operator can still deploy unmerged work from a workstation.

**Requesters and their credentials**
- Each user's sessions get a deploy-request credential delivered the same way as the other omnigent worker credentials, plus a per-user allowlist of machines (default deny).
- Every request is recorded with requester, machine, commit, closure and outcome, and announced through the fleet's ntfy path. Refusals and failed verifications are included.

**A scoped deployer key**
- The deployer gets its own age identity, generated on the deployer, which never leaves it. It reads the machine keys and activation-phase vars of in-scope machines only. With clan's sops backend, the narrowest possible scope is one machine.
- The deployer's SSH key is accepted only from the deployer's mesh address, without agent forwarding, port forwarding or a PTY. Targets are resolved from the host registry and passed explicitly, so clan's network selection (F36) is never consulted.

**Out of scope**
- Pull-based self-activation (O6) and deploy-on-merge from a nixbot effect (O7). O7 can later be added as a second requester without changing the deployer.
- Key-file permissions on other hosts (brainstorm F12, Q8: fixed on magnetite outside this change; rotating the key is the operator's decision). This change applies the lesson only to the deployer's own keys.

## Capabilities

### New Capabilities
- `fleet-deploy-delegation` (behavioral): a requester other than the operator can have a fleet host redeployed at a merged commit, and gets back the outcome of the deploy and of its health check. Every request is authorized per requester and machine, recorded, and announced. Deploys of the same host never overlap. A host that is asleep or unreachable is reported as such, and no deploy is attempted.
- `fleet-deploy-delegation-interface` (interface): the request channel and its forced command, the commit gate against `main` and CI status, the per-machine lock, the deployer's target SSH restrictions, and the audit and notification records. Trust boundary: the property ends at the deployer's account and its age identity. Root on the deployer host, or a compromised merge gate, defeats it, and no guarantee is claimed past the activation the target performs.

### Modified Capabilities
- `secret-custody` (behavioral): the deployer becomes a named automated reader of the machine keys and activation-phase vars of in-scope machines, and of nothing else. Operator credentials stay readable by the operator alone.
- `secret-custody-interface` (interface): the correspondence check accounts for the deployer's key and the group that scopes it.
- `world-assumptions` (world): four assumptions. With the sops backend, a machine key unlocks all of that machine's secrets. clan's update always uploads vars and offers no skip. darwin laptops and pyrite sleep or travel. CI builds darwin closures only best-effort.

## Impact

- New: a deployer service and its account, on the host Q2 chooses (recommended: cinnabar, moving with its CAM-112 successor). A `deployer` sops user and group, listed in `defaultGroups` of in-scope machines. Per-user deploy-request credentials among the omnigent worker credentials.
- Changed: `authorized_keys` for root on in-scope NixOS hosts and for the primary user on in-scope darwin hosts. Recipients of in-scope `sops/secrets/<machine>-age.key` and activation-phase vars, re-encrypted with `clan vars fix`. The `secret-custody` correspondence check.
- Interacts with: CAM-109/tincr (target names and `deployUser` come from `flake.lib.hosts`), CAM-112 (where the deployer and agent hosts live), CAM-87's verifying `ntfy-send`, and ADR-005's deploy record as the host-side witness.
- Unchanged: nixbot, gitea-mq and the merge gates; stibnite's own `just activate`; how sops-nix decrypts on the target.
