---
execution_mode: HIL
linear_story_id: "611390e3-ea60-4171-8c43-893070437f21"
linear_story_identifier: CAM-57
linear_story_title: Deploy Omnigent on magnetite
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-57/deploy-omnigent-on-magnetite
linear_story_state: Todo
linear_team: CAM
linear_project: omnigent-magnetite
last_synced_state: Todo
last_synced_at: "2026-09-07T21:45:11Z"
review_round: 0
attempt_log:
  - at: "2026-09-07T21:45:11Z"
    transition: Backlog->Todo
    outcome: posted
    note: Created the requested project and story, seeded the business description, confirmed Todo by API readback, and posted the binding comment.
---

## Why

Omnigent needs a reproducible deployment on magnetite so the operator can use the existing Kanidm identity from a laptop and Android app and run an Atomic session on an always-on runner.
The existing research and deployment plan establish the approach, but the host environment, admission policy, and operational access instructions need the S0 corrections before packaging and deployment.

## What Changes

- S0, amend-plan: reconcile the deployment plan and Kanidm access runbook with the supplied corrections and bind this change to one CAM story in the new omnigent-magnetite project.
- S1, package: package the released Omnigent 0.12.0 wheel for Nix and verify the Linux CLI.
- S2, server: configure the server, shared PostgreSQL 16 database, confidential Kanidm sign-in, secret delivery, and HTTPS ingress while retaining existing services.
- S3, host-clan: configure one foreground runner and bind both server and host roles to magnetite through clan, with Atomic available beside Pi.
- S4, deploy and accept: after the controller's gates and operator confirmations, generate the two secrets, apply only the intended DNS addition, activate the pinned source, and collect live observations and human acceptance responses.

The endpoint is `https://omni.scientistexperience.net`.
Kanidm group `omnigent_users` gates admission; `OMNIGENT_OIDC_ALLOWED_DOMAINS` stays unset and the administrator roster names `cameron.ray.smith@gmail.com`.
The laptop and shipped mobile WebView clients use the same confidential client through the server's login flow.

## Capabilities

### New Capabilities

- `omnigent-deployment-interface` [interface]: the deployed package, configuration, authentication endpoints, foreground runner environment, pinned activation, and distinction between tool observations and human acceptance.

The trust boundary includes Nix evaluation and builds, the activated service configuration, HTTP responses, and recorded operator responses.
It does not establish the truth of a person's email independently of Kanidm administration, prove browser or passkey platform behavior, or provide an end-to-end isolation guarantee.
Native sessions initially run as `cameron` without sandbox enforcement; adding `/nix/store` to sandbox `read_paths` also weakens isolation.

### Modified Capabilities

None.

## Impact

S0 owns `docs/notes/development/omnigent/`, `packages/docs/src/content/docs/development/operations/identity/kanidm.md`, this change directory, and the additive project entry in `openspec/linear.yaml`.
S1 owns `pkgs/by-name/omnigent/`.
S2 owns `modules/nixos/omnigent.nix`, `modules/nixos/kanidm.nix`, and `modules/terranix/cloudflare.nix`.
S3 owns `modules/nixos/omnigent-host.nix`, `modules/clan/services/omnigent/`, and `modules/clan/inventory/services/omnigent.nix`.
S4 is controller-owned and additionally produces the two generator directories under `vars/per-machine/magnetite/`, DNS state, activation observations, and private operator state.
No new flake input, additional runner rollout, dedicated-user migration, backup system, monitoring system, or Buzz replacement is included.

## Contract and readiness

The current S0–S3 contracts are `slice-0.json` through `slice-3.json` under `.atomic/workflows/runs/deploy-omnigent/omnigent-magnetite/d0064db1-3756-4e49-ae30-e03f23ca0bd7/`.
This run reuses the existing CAM-57 binding recorded above; its timestamp records the earlier binding operation, not a fresh remote readback.
Those acceptance lists and deterministic gates remain unchanged; `tasks.md` is the HIL task ledger, not a replacement gate implementation.
The current S1–S3 gates use `__OMNIGENT_SOURCE__` instead of the previous run's working-copy source; the controller supplies that source, and this writer neither substitutes a guessed revision nor edits those gates.
S4 has no slice JSON in the supplied evidence.
Its sequence is recorded from the `input.deploy` branch in `.atomic/workflows/deploy-omnigent.ts`, the deployment helpers, and the `checklist` in `.atomic/workflows/omnigent/types.ts`.

The plan at commit `46be61b3e`, dated 2026-09-06, predates the supplied S0 corrections: its fork citations, unresolved admission values, and old inventory filename must not override the explicit slice contract.
The later research also examines development revisions rather than only the packaged release; release compatibility remains an implementation obligation, not a claim established by these tracking files.

This stage creates planning and tracking records only.
All tasks remain unchecked until the controller accepts their evidence; no implementation, remote operation, or deployment is authorized by file existence.
The selected schema is `superpowers-bridge-wrspm`.
Full fast-forward readiness additionally requires its brainstorm, design, and implementation-plan artifacts; this binding stage does not fabricate a raw brainstorming capture or human approval.

## Dedicated-worker amendment, 2026-09-10

The approved follow-on scope is five dedicated human workers: Cameron on magnetite, pyrite and stibnite, and Raquel on magnetite and pyrite.
It supersedes this proposal's earlier single-owner and excluded dedicated-user migration scope without rewriting the historical S0–S4 gates or ledger.
The Linux slice adds the shared typed worker interface and integrated Home Manager system-service adapter, with execution disabled until enrollment and legacy execution preserved until explicit migration.
Darwin's dedicated-UID daemon adapter and the five-account inventory are subsequent slices; the server remains unchanged.

The user explicitly accepted upstream `sandbox: none` initially, relying on dedicated non-admin Unix accounts and platform service restrictions.
This account boundary includes auxiliaries and project hooks but does not provide namespace or child confinement.
Normal Unix permissions govern Nix-store/profile visibility; there are no additional child-sandbox grants, and approved projects may expose their store inputs to other local users.
Additional child sandboxing requires future supported upstream policy delivery rather than an unused host option or shared-server change.
Account isolation, private state, no administrative/Nix-trusted/signing authority, ordered runtime/profile/extras PATH and activation-failure prevention remain required.

Private worker-local credentials and personal provider identities are accepted; provider permissions and application-admin grants retain their external authority.
`owner` records intended human association and must be checked against actual enrollment, not presented as module-enforced application authentication.
This `deploy=false` implementation performs no activation, credentials, OAuth, provisioning or administrative SSH.
The named Linux module check supplies build/evaluation evidence; actual-user identity, canary, selected-harness and lifecycle tests remain post-activation obligations.

## Identity amendment, 2026-09-13

Janette, canonical `janettesmith`, replaces only Raquel's experimental Linux workers on magnetite and pyrite.
Both human profiles remain; Cameron's three workers, stibnite, legacy execution and the shared server remain unchanged.
All five workers stay disabled through credential preparation, and the old Raquel activation candidate is superseded.
Earlier capabilities, Linux, Darwin and inventory evidence keeps its original Raquel preparation scope.

Typed `meta.gitEmail` defaults to the primary address and explicitly records Janette's verified GitHub noreply mail, separate from `janette.a.smith@gmail.com` for primary/SSO use.
Her human Git/jj mail and signer principal use that Git address, and her GitHub username follows `meta.githubUser` through the existing human Git convention.
Worker HM imports only her non-secret name and Git address through `extraHomeModules`.
The [deployment plan](../../../docs/notes/development/omnigent/deployment-plan.md#janette-identity-amendment-2026-09-13) records the B1 helper evidence, unchanged public-key/recipient association and the controller's fixed same-role preservation baselines.
The inventory check asserts the canonical identity and disabled matrix without source-role heuristics; controller gates retain the complete human/server/Cameron/stibnite comparisons.
No Kanidm provisioning, grant issuance, key copying, enrollment or activation belongs to this identity slice.

## Capability refinement, 2026-09-16

This amendment refines reusable Home Manager features within CAM-57, not the server, worker identity or credential authority.
The September 13 disabled-worker statements above describe preparation: inventory now enables all five workers and disables magnetite's legacy runner (magnetite: `21d66e12f4`, September 15; pyrite/stibnite: `adaa18f960`, September 15).
The controller reports the CLI delivery `c72b7d38` deployed on all three hosts; this source slice does not repeat live observations or close untested human acceptance gates.

The first slice exposes `homeManager.openspec` and `homeManager.mergify` independently, reusing their existing declarations with stable module identity.
Human `ai` retains OpenSpec's opt-in semantics, schema directory symlinks and global workflow configuration; human `development` retains Mergify's default-on behavior.
No worker imports change in this slice.

Later slices group repository acquisition (`ghq`, `ghq-sync`, `dependency-sources` and direct zoxide lookup), engineering utilities (`just`, `shellcheck`, `uncomment`, `ratchet`, `jc`, `jaq`, `yq`) and the existing Nix development tools as selectable capabilities.
Human aggregates retain their existing package membership through constituent exports, rather than each importing the union of a new group.
Workers opt in explicitly, without importing personal development/editor or AI aggregates.
Git's declared `git-xet` and Git/jj's declared `nvim` dependencies must be closed in their owning features later; editor configuration remains a separate decision, not permission to import the personal editor bundle.

Tools confer no authority: identity, credential adapters, signing, privileged services, sudo, container sockets and Nix trusted-user rights remain separate.
Mergify authentication requires credential-adapter review without new grants or ambient-token fallback; if `stack-land` is selected later, its `GH_BIN` route must preserve the worker's credential-aware wrapper.
Project devshell dependencies and approval of project hooks/direnv are a separate trust decision, not evidence of baseline closure.
Structured no-foreign-home, no-personal-secret and no-inherited-agent guards remain required.
Existing signed commits, logs, check results and PR records provide provenance; this work adds no telemetry, Den migration, Atomic defaults or publication authority.

Each slice compares actual before/after human package versions, relevant settings, generated files and activation effects without committed package goldens.
Evaluation and focused builds on Darwin and Linux establish source behavior only; generated supervisor PATH exercises and separately authorized live acceptance remain later gates.
