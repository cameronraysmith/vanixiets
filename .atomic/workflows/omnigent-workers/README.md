# Omnigent worker migration workflow

This workflow implements the approved dedicated-worker design on the existing `omnigent-magnetite` chain.
It does not reuse the old deployment workflow's historical S0–S11 replay or infrastructure provisioning.
The shared server stays on magnetite; Cameron receives workers on magnetite, pyrite and stibnite, and Raquel receives workers on both Linux hosts.

## Run and stop boundaries

After independent review and routing this tooling as a new chain-tip commit, the controlling session can reload `omnigent-workers`.
Run from `/Users/crs58/projects/vanixiets` with `openai-codex/gpt-6-astra` selected.

| Input | Default | Meaning |
|---|---|---|
| `start_at` | `0` | Phase index: capabilities 0, Linux 1, Darwin 2, inventory 3, magnetite 4, pyrite 5, stibnite 6, closure 7. |
| `deploy` | `false` | Permit host migrations after their individual operator confirmations. False still permits implementation and local jj routing; it is not a read-only plan mode. |
| `max_repairs` | `2` | Additional implementation attempts per slice; contract defects stop immediately. |
| `build_timeout_minutes` | `90` | Positive deadline per gate/operation batch, forwarded through cancellation signals. |

The graph is:

```text
preflight
  → capabilities child → Linux child → Darwin child → inventory child
  → magnetite migration → pyrite migration → stibnite migration
  → documentation/evidence child
```

Each implementation child runs `baseline → implement → attributed route → immutable-source gates → fresh review`.
A repair adds new suffixed nodes downstream; it never reopens an ancestor.
Each migration runs `observe integrated join → prepare disabled accounts → enroll humans → enablement child → integrated gates → activate → runtime probes → human acceptance`.
An already-enabled host skips account preparation, verifies its current configuration and rechecks enrollment.

`implementation-ready` means the four implementation phases passed, with no host migration requested.
`human-attested` means this run gathered all three host acceptance records; it is not a claim of independently automated end-to-end isolation.
`partial-resume` deliberately withholds a fleet-completion claim when starting after earlier hosts.
A blocked exit retains available slice/host receipts and its evidence directory.
It never restores execution under a privileged human account automatically.

## Evidence and trust boundaries

`contract.ts` owns slice objectives, scopes and the exact named checks the implementation must introduce alongside behavior.
`gates.ts` executes those checks at immutable source URLs, checks the current five-worker enable map and rejects root/human/admin/trusted-user assignments.
The first extraction compares an independently captured human package/artifact projection, canonicalizing only self-root sops and home-file inputs by content while retaining original relative-path/content witnesses; each slice separately compares the shared server unit derivation.
Reviews must inspect the actual checks, their negative controls and realized artifacts, not infer coverage from a check name or successful exit.
A successful model review cannot override a failed tool gate.
Structured review decisions are persisted separately from prose, because Atomic's schema-output artifact may contain no prose.

`operations.ts` reuses the repository's process receipts, bounded logs and byte/mode snapshots.
It refuses pre-existing in-scope edits, detects foreign changes and routes only attributed paths using `jj new --no-edit`, path-scoped squash with `--keep-emptied`, and a chain bookmark advance.
The working-copy change ID and the development join's other chains must survive routing.
These checks detect observed drift; they do not lock concurrent writers.
An interrupted splice before bookmark advancement blocks for explicit topology reconciliation rather than creating another change blindly.

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
Each person logs into Omnigent, GitHub, Linear and selected model harnesses under the actual dedicated HOME.
Use owner-only local files with restrictive creation permissions; do not copy complete personal directories or refresh-state stores.
The implemented Linear probe targets the existing CLI API-key lane.
If a user selects MCP-only OAuth instead, stop for a deliberate probe-contract adjustment rather than pretend CLI authentication succeeded or create a bot.
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
The workflow checks the current model before stage creation and persists observed attempt metadata after each successful stage return.
The installed catalog's `currentModel` is the session model object, identified by its `provider` and `id`; declared string identities are also accepted.
Missing or malformed identity metadata blocks separately from a genuinely different selection.
An off-policy model/effort or missing successful high-effort metadata blocks further progress.
Missing effort metadata on unsuccessful attempts is preserved as unknown, not claimed verified.
These observations are not atomic session/model locks and cannot prevent an engine race or attest an attempt for which the SDK returns no result.
No Atomic patch or alternate model/provider is introduced.

## Validate the controller

```sh
node .atomic/workflows/omnigent-workers/check.mjs
```

For the offline model boundary alone, append `--model-only`.
The checker executes the installed catalog factory and successful-attempt metadata writer in isolation, without extension registration or model dispatch; controller fixtures reuse those values.

Controller fixtures use mocked VCS/model/host boundaries; the human-preservation lane additionally runs bounded offline Nix evaluations with IFD disabled and no builds.
These checks do not replace real-fleet or real-user acceptance.
