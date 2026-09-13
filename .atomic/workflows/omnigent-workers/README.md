# Omnigent worker migration workflow

This workflow implements the approved dedicated-worker design on the existing `omnigent-magnetite` chain.
It does not reuse the old deployment workflow's historical S0–S11 replay or infrastructure provisioning.
The shared server stays on magnetite; Cameron receives workers on magnetite, pyrite and stibnite, and Janette (`janettesmith`, GitHub `janetteasmith`) receives workers on both Linux hosts.
The identity phase replaces only Raquel's two experimental workers; both human profiles remain.

## Run and stop boundaries

After independent review and routing this tooling as a new chain-tip commit, the controlling session can reload `omnigent-workers`.
Run from `/Users/crs58/projects/vanixiets` with `openai-codex/gpt-6-astra` available in the Atomic model catalog; the session may select a different model.

| Input | Default | Meaning |
|---|---|---|
| `start_at` | `0` | First phase index from the table below. |
| `deploy` | `false` | Permit host migrations after their individual operator confirmations. False still permits implementation and local jj routing; it is not a read-only plan mode. |
| `max_repairs` | `2` | Additional implementation attempts per slice; contract defects stop immediately. |
| `build_timeout_minutes` | `90` | Positive deadline per gate/operation batch, forwarded through cancellation signals. |

| Index | Phase |
|---|---|
| 0 | capabilities |
| 1 | linux |
| 2 | darwin |
| 3 | inventory |
| 4 | identity |
| 5 | credentials |
| 6 | magnetite |
| 7 | pyrite |
| 8 | stibnite |
| 9 | closure |

The graph is:

```text
preflight
  → capabilities child → Linux child → Darwin child → inventory child
  → identity child → credentials child
  → magnetite migration → pyrite migration → stibnite migration
  → documentation/evidence child
```

Each implementation child runs `paired immutable baselines / owned-byte capture → implement → pre-route context check → attributed chain route → paired immutable preservation and chain gates → fresh review / provenance readback`.
A repair adds new suffixed nodes downstream; it never reopens an ancestor.
Each migration runs `observe integrated join → prepare disabled accounts → verify provisioned credentials/identities → complete missing browser/OAuth enrollment → enablement child → integrated gates → activate → runtime probes → human acceptance`.
An already-enabled host skips account preparation, verifies its current configuration and rechecks enrollment.

`implementation-ready` means the six implementation phases passed, including a credentials receipt, with no host migration requested.
Phases 0–3 retain the historical Raquel preparation matrix; identity establishes the Janette matrix, and credentials keeps all five workers disabled.
Magnetite preparation gates credentials; pyrite and stibnite preparation gate the preceding host phase.
`human-attested` means this run gathered all three host acceptance records; it is not a claim of independently automated end-to-end isolation.
`partial-resume` deliberately withholds a fleet-completion claim when starting after earlier hosts.
A blocked exit retains available slice/host receipts and its evidence directory.
It never restores execution under a privileged human account automatically.

## Evidence and trust boundaries

`contract.ts` owns slice objectives, scopes and the exact named checks the implementation must introduce alongside behavior.
`gates.ts` executes those checks at immutable source URLs, checks the current five-worker enable map and rejects root/human/admin/trusted-user assignments.
The first extraction compares an independently captured human package/artifact projection, canonicalizing only self-root sops and home-file inputs by content while retaining original relative-path/content witnesses; each slice separately compares the shared server unit derivation.
Home-file source canonicalization and source witnesses follow Home Manager's `enable` boundary, including files forwarded from XDG; disabled entries may legitimately have no source.
The projection retains every entry's enable flag and file properties, enabled text/source artifacts, and the complete generation and activation DAG, including activation-owned mutable settings.
Disabled, undelivered source/text definitions are not compared as artifacts; enabling an undefined source still fails evaluation.
Reviews must inspect the actual checks, their negative controls and realized artifacts, not infer coverage from a check name or successful exit.
A successful model review cannot override a failed tool gate.
Structured review decisions are persisted separately from prose, because Atomic's schema-output artifact may contain no prose.

Chain source C0/C1 and integrated source J0/J1 have separate roles.
The default source and squash destination remain the `omnigent-magnetite` authoring tip; the shared filesystem is the integrated context, not an isolated-chain baseline.
One read-only jj observation captures the working-copy change, join and direct parent change/commit pairs; pinned Git objects supply trees and parent commits, and repeat observations reject drift.
The initial owned bytes must match both the stored join and the isolated chain before writing: matching two versions already contaminated by foreign contributions does not authorize a whole-file squash.
Both baseline projections stay fixed through forward repairs, with private projection/expression files, digests, source roles, controller digest and exact evaluation commands.
The capabilities phase requires matched C0/C1 and J0/J1 human equality; every slice also requires matched server equality.
Later account/enablement phases do not require whole-home equality because they intentionally change homes.
Writer and reviewer reads name both contexts; pre-existing integrated Niri behavior is protected even though it is absent from the isolated chain.
Neither cross-context equality nor replacing the chain URL with the filesystem URL is a valid local pre-edit check.

`operations.ts` reuses the repository's process receipts, bounded logs and byte/mode snapshots.
It refuses pre-existing in-scope edits, detects foreign changes and routes only attributed paths using `jj new --no-edit`, path-scoped squash with `--keep-emptied`, and a chain bookmark advance.
Both routing child lookups use `${tip}+ & ancestors(@-)` to exclude off-join peers; an unfinished in-join splice still blocks for reconciliation.
The working-copy change ID and the development join's other chains must survive routing.
These checks detect observed drift; they do not lock concurrent writers.
An interrupted splice before bookmark advancement blocks for explicit topology reconciliation rather than creating another change blindly.

Before routing, the clean stored join is pinned again while attributed edits remain unlanded.
A changed integrated tree is compared once against the original integrated projection; relevant protected drift blocks for reconciliation, not automatic rebaselining.
Tree-identical parent metadata changes need no new content comparison.
Actual unsnapshotted foreign inputs are checked separately: a clean `@-` cannot stand for relevant dirty filesystem bytes.
The conservative relevance rule covers every Git-visible path except foreign working-note Markdown under `docs/notes/`; shipped module assets and non-Nix inputs remain covered.
That exception relies on the current protected human/server compositions not consuming working notes; the separate Pi environment check's note reference is not part of this projection or these named worker checks.
If a future composition consumes notes or ignored inputs, reconcile and revise this boundary before running; this is not a Nix dependency solver or a filesystem lock.
Routing rechecks stored owned bytes, observed writer output and immutable foreign-parent continuity, and binds the result to both C1 and J1.
Acceptance rechecks authoring identity, owned bytes and integrated context without relabelling J1 when a later unrelated join advances.
An old integrated preservation receipt never certifies a later deployment source: migration still observes, gates, builds and activates its fresh exact `@-` source with operator approval.

Every deployment builds and activates the exact gated integrated system; Darwin reconciles both the persistent system profile and active generation, completing only missing steps after interruption.
The source's join parents are recorded; the operator must still examine other chains' activation effects and coordinate deployers outside this workflow's Intercom group.
There is no Terraform, secret generation, package upgrade, PR publication or queue operation in this workflow.

`live.py` observes actual service UID, selected HOME/PATH, private home permissions, executable discovery, GitHub login and Linear CLI authentication success.
It does not print credential files, process environments, Linear credential errors or tokens.
Its temporary canaries contain public test data and exercise owner-positive/other-worker-negative Unix access checks.
These account-context probes do not substitute for actual agent, auxiliary API, terminal, project-hook and private-socket checks; those remain explicit human observations tied to real session references.
On stibnite, where only one worker is planned, the automated canary has only the owner-positive control; the human checklist requires a protected personal-account negative check.

## Human enrollment and recovery

The operator confirms account adoption and UID/GID/home compatibility before account activation.
Static signing, GitHub, Linear and optional native-Claude setup credentials require prior approved enrollment through declarative Clan vars and host-level delivery to selected worker-owned files with mode `0400`.
Record the approval and delivery evidence; absent evidence stops migration for the separately gated provisioning step.
Do not run `gh auth login` or `linear auth login` or overwrite managed files.
Humans complete only missing Omnigent browser tickets and selected model OAuth under the actual dedicated HOME and explicit tool auth directory.
Use restrictive creation permissions; never copy personal directories, age identities, bundles or tool-owned refresh stores.
Deployment must leave mutable OAuth state untouched, including after logout or deletion.

Verify the expected GitHub login, Linear person and explicit workspace, Omnigent `/v1/me` primary/SSO mail and owner/admin status, refresh readiness, and the signing key's public fingerprint.
Janette's primary/SSO mail is `janette.a.smith@gmail.com`; her Git/jj mail and `allowed_signers` principal are `125711642+janetteasmith@users.noreply.github.com`.
The Linear probe targets the existing CLI API-key lane; MCP-only OAuth requires a deliberate probe-contract adjustment, not a bot substitution.
Record only non-secret identity and evidence references; never print credential material or use token-output flags.

Narrow file-backed signing-key delegation is approved through selected host-level Clan/SOPS vars files, not a personal secret bundle, age identity, SSH agent or `hm-sops-bridge` enrollment.
Acceptance requires each worker's signed commit to verify against its declared public key and canonical Git mail principal.
File-backed SOPS delivery is the current design; systemd `LoadCredential` is the designated follow-up, with `LoadCredentialEncrypted` optional only after hardware verification.
The accepted `sandbox:none`, shared-store visibility and same-UID/admin access limits remain explicit; file ownership does not remove external grant or administrator authority.
Use independent person/host grants by default and record renewal/revocation authority during provisioning.
Kanidm provisioning, real grant issuance and enrollment of real values remain separate human/deploy-gated steps.
Real external create/update operations require explicit human target approval and evidence references.
The workflow never performs those writes autonomously.

The operator identifies and stops the legacy service/agent and any manually launched duplicate hosts before enabled activation.
Old homes, credentials, registrations and sessions are preserved; a fresh host registration does not reroute old sessions.
Actual owner matching, sharing behavior, native/selected-ACP turns, approved devshell/cache use and laptop lifecycle behavior require separate acceptance answers.
`failed` and `not-tested` both stop completion.

For a new invocation after a block, reconcile the recorded working-copy/topology, account, home-generation, enrollment and running-generation state before selecting `start_at`.
Implementation resume verifies current-state checks rather than asserting obsolete historical SHAs.
An incomplete host migration can be selected again without repeating account preparation when already enabled; activation itself reconciles the current generation.
Existing in-scope unlanded edits or an unfinished splice require operator attribution/recovery before relaunch.
When earlier host attestations are not supplied to this invocation, completion remains `partial-resume`; retain the earlier evidence directories for final human reconciliation.
Atomic's completed child checkpoints can replay, but an incomplete child starts again; stable source state and readback, not assumed exactly-once callbacks, prevent duplicate activation.

## Model policy

All implementation, repair, review and coordination stages request `openai-codex/gpt-6-astra:high`, `thinkingLevel: high` and `fallbackModels: []`.
Atomic 0.9.18 implicitly appends the current model despite the empty list.
The compatibility thinking option applies high effort to that unsuffixed candidate; same-model retries are authorized.
Before stage creation, the workflow checks `ctx.models.listModels()` for the pinned `fullId` and, when exposed, requires `availableThinkingLevels` to include `high`.
The installed Atomic 0.9.18 catalog exposes `provider`, `id`, `fullId` and `model`, but not `availableThinkingLevels`; high-effort support is therefore not established by this preflight snapshot.
The session's `currentModel` does not determine whether the pinned model is available.
The workflow persists observed attempt metadata after each successful stage return.
An off-policy model/effort or missing successful high-effort metadata blocks further progress.
Missing effort metadata on unsuccessful attempts is preserved as unknown, not claimed verified.
These observations are not atomic session/model locks and cannot prevent an engine race or attest an attempt for which the SDK returns no result.
No Atomic patch or alternate model/provider is introduced.

## Validate the controller

```sh
node .atomic/workflows/omnigent-workers/check.mjs
```

`check.mjs` invokes the full `controller-checks.mjs` and `regression-checks.mjs` fixture functions, along with strict TypeScript, generated syntax and live-probe checks.
Running either helper module directly only imports its exports; it does not execute its fixtures.
For the offline model boundary alone, append `--model-only` to `check.mjs`.
The checker executes the installed catalog factory and successful-attempt metadata writer in isolation, without extension registration or model dispatch; controller fixtures reuse those values.

Controller fixtures use mocked VCS/model/host boundaries; the human-preservation lane additionally runs bounded offline Nix evaluations with IFD disabled and no builds.
The differentiated controller fixtures execute the actual projection/comparison and source/attribution/routing callbacks, while replacing model, command and filesystem boundaries where needed.
They cover integrated-only failure despite chain equality, fixed baselines through repairs, relevant foreign drift, owned overlap, byte/mode/symlink drift, tree-identical metadata changes, unrelated working notes and source-bound reviewer receipts.
Phase fixtures cover all six implementation children, implementation/closure resume indices, credentials-receipt readiness, per-host preparation gates, and join-scoped routing child selection with off-join peers and an unfinished-splice negative control.
For this repair's separately recorded immutable real-source probes, `--provenance-artifacts` reuses the private ignored C0/J0 and complete archive-movement outputs rather than evaluating the mutable fleet.
That optional lane retains real projection contents but uses explicitly synthetic routed commit labels; it does not create Git objects or route real changes.
The separate probe logs, immutable source URLs and projection hashes establish the real Nix semantics, not the controller mocks.

```sh
node .atomic/workflows/omnigent-workers/check.mjs --model-only
node .atomic/workflows/omnigent-workers/check.mjs --provenance-artifacts
```

Use a 5400-second deadline and `set -o pipefail` with `tee` into ignored `logs/` for each validation command.
These checks do not replace real-fleet or real-user acceptance.
