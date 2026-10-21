---
title: Satisfaction argument
description: Discharge status for every requirement in the OpenSpec corpus
generated: 2026-10-21
---

This file is a projection over `openspec/specs/`, regenerated wholesale at archive time and never patched.
It enumerates every current requirement from the post-sync corpus; it does not use the previous projection as input.
Discharge annotations come from the owning verification artifacts cited below, not from an agreement between configuration files.
The `W ∧ S ⇒ R` obligation is separate from implementation refinement and from an archive-ready behavioral verdict.
Nothing here is an end-to-end guarantee; OpenSpec structure checks are not behavioral validation.

## Status

The post-sync corpus has **196 requirements across 22 capabilities**: 172 requirement-side rows and 24 world-assumption rows.
**79 requirement-side rows are discharged — 3 at narrow CAM-41 interface boundaries, 36 from CAM-68's telemetry store slice, 26 from CAM-70's fleet alerting slice and 14 from CAM-77's shared reference tree; 93 remain undischarged**, each with a follow-up reference.
Of those undischarged rows, 8 name world assumptions but no named specification-side discharge; 85 name neither.
The 24 world rows remain self-attested, not independently discharged; their monitoring/scenario truth is not re-proved by this projection.
A13 has real incident evidence, including CAM-59, but no new world-assumption audit is claimed here.
A29–A33 carry CAM-68's first-activation and runtime monitoring evidence, A33 and A37–A42 carry CAM-70's cutover and runtime observations, and A34 and A35 carry CAM-77's VM and post-deploy observations, cited per row; that evidence monitors them and does not discharge them.

**CAM-63 qualifications are load-bearing:** GNOME reachability is amended to exclude live-niri display-manager restart (**CAM-66**, unrepaired); **8.2 no-history is a source-read-only method limitation**, not discharged by evaluation; **8.3/8.4/8.5 are evaluation, not observation; 8.6 is declined under CAM-59; 8.7 is physical testing with same-boot positive/negative controls and whole-boot totals 1 requested / 1 entry**.
Task 8.1 would have caught the strand; the post-deploy checklist ordering itself caused the lockout inside niri.
These behavioral dispositions do not manufacture named specification-side discharges.

## Evidence and follow-up conventions

- CAM-41 evidence: `openspec/changes/archive/2026-09-02-integrate-mergify-stacked-landing/verify.md:105–111,185–191`; qualifications W1–W6 at `:31–50`.
- CAM-62 evidence/follow-ups: `openspec/changes/archive/2026-09-09-pyrite-never-sleep/verify.md` §§7–8 and `retrospective.md` §6.
- CAM-63 evidence/follow-ups: `openspec/changes/archive/2026-09-10-pyrite-niri-second-session/verify.md` §§8,9.12 and `retrospective.md` §6.
- CAM-68 evidence/follow-ups: `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/verify.md` §§8b,9.4,9.5,10,11, `tasks.md` §10 and `retrospective.md` §6.
- CAM-70 evidence/follow-ups: `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/verify.md` §§8b,9,10,11, `tasks.md` §10, `review.md` and `retrospective.md` §6.
- CAM-77 evidence/follow-ups: `openspec/changes/archive/2026-10-20-share-ghq-reference-tree/verify.md` §§5,5a–5e,8b, `tasks.md` 9.4 and `retrospective.md` §6.
- `evidence annotation follow-up` means OpenSpec change `annotate-discharge-evidence` (active or subsequently archived), not implicit acceptance.
- `V-interface` means the CAM-63 retrospective §6 architecture decision: introduce named interface properties or explicitly decide the corpus discharge convention.
- `V-vocabulary` means the next sole designation-table owner grounds world/shared terms and relocates machine predicates; CAM-63 verify §8 is agent-executed/non-blocking and NEVER validation.
- Older capability strata remain inferred and not re-audited; CAM-41 declares its three additions interface, CAM-62/CAM-63 declare graphical-desktop-session behavioral; CAM-68 declares telemetry-store and host-metrics-collection behavioral and telemetry-store-interface interface; CAM-70 declares fleet-alerting behavioral and fleet-alerting-interface interface; CAM-77 declares shared-reference-tree behavioral and shared-reference-tree-interface interface.
- Every capability section cites the authoritative main-spec path; row order and titles are derived from that file.

## agentic-workflow-routing

Source: `openspec/specs/agentic-workflow-routing/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Unified seven-state Linear-canonical board | interface | — | — | undischarged — evidence annotation follow-up |
| In Review decomposes into two ordered human-steered sub-gates | interface | — | — | undischarged — evidence annotation follow-up |
| Shared re-queue with bounded-retries termination guarantee | interface | — | — | undischarged — evidence annotation follow-up |
| AFK, HIL, and Manual execution-mode fork at the Todo to In Progress boundary | interface | — | — | undischarged — evidence annotation follow-up |
| Compose by delegation, never re-implement | interface | — | — | undischarged — evidence annotation follow-up |
| HIL apply-phase jj and worktree isolation guidance | interface | — | — | undischarged — evidence annotation follow-up |

## apple-laptop-hardware-support

Source: `openspec/specs/apple-laptop-hardware-support/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| The pyrite host module imports the upstream model profile with its unwanted firmware pulls disabled | behavioral | — | — | undischarged — evidence annotation follow-up |
| The machine module states its firmware affirmations rather than inheriting them | behavioral | — | — | undischarged — evidence annotation follow-up |
| The stage-1 initrd force-loads the four SPI/SMC modules that make the unlock prompt answerable | behavioral | — | — | undischarged — evidence annotation follow-up |
| boot.initrd.kernelModules is never overridden with mkForce | behavioral | — | — | undischarged — evidence annotation follow-up |
| A USB-C keyboard and the clan-vars passphrase are prerequisites of the first boot, not recoveries improvised afterward | behavioral | — | — | undischarged — evidence annotation follow-up |
| The machine's configuration is never seeded from nixos-generate-config | behavioral | — | — | undischarged — evidence annotation follow-up |
| The sleep path is gated by three units the machine module defines itself | behavioral | — | — | undischarged — evidence annotation follow-up |
| Suspend is entered through the systemd-sleep path and resumes with the pool intact | behavioral | — | — | undischarged — evidence annotation follow-up; contradicted in part by CAM-59, see CAM-62 qualifications |
| A panic that outlives the disk is recorded through EFI pstore, because every other channel is unavailable on this machine | behavioral | — | — | undischarged — evidence annotation follow-up |

## bare-metal-install-path

Source: `openspec/specs/bare-metal-install-path/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| The install path is recorded in the repository, and is written to be re-runnable without being shown to be | behavioral | — | — | undischarged — evidence annotation follow-up |
| An install is accepted as evidence only if it exercised the create path | behavioral | — | — | undischarged — evidence annotation follow-up |
| The hardware report is committed as static data and never regenerated on the target | behavioral | — | — | undischarged — evidence annotation follow-up |
| The machine is registered across every hand-maintained list a new machine touches | behavioral | — | — | undischarged — evidence annotation follow-up |
| Network association is declarative, and the credentials are sops-encrypted clan vars | behavioral | — | — | undischarged — evidence annotation follow-up |
| ZeroTier admission requires redeploying the controller | behavioral | — | — | undischarged — evidence annotation follow-up |
| A FIDO2 token is verified present before each enrollment, and disko's own guard is never that verification | behavioral | — | — | undischarged — evidence annotation follow-up |

## encrypted-zfs-root

Source: `openspec/specs/encrypted-zfs-root/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| The root is a ZFS pool created with an explicit ashift matching the disk's 4096-byte sectors | behavioral | — | — | undischarged — evidence annotation follow-up |
| The ESP is typed EF00 and sized 1G | behavioral | — | — | undischarged — evidence annotation follow-up |
| A sibling partition carries the ZFS content that becomes the pool's vdev | behavioral | — | — | undischarged — evidence annotation follow-up |
| The pool device is named by a namespace-explicit by-id path | behavioral | — | — | undischarged — evidence annotation follow-up |
| The pool sits inside a LUKS2 container holding the clan-vars passphrase in slot 0 and a FIDO2 token in each of slots 1 and 2 | behavioral | — | — | undischarged — evidence annotation follow-up |
| The costs and the gains of the LUKS layer are both recorded rather than discovered later | behavioral | — | — | undischarged — evidence annotation follow-up |
| The LUKS header and the keyslot inventory are maintained artifacts, not install-time byproducts | behavioral | — | — | undischarged — evidence annotation follow-up |

## first-party-skill-distribution

Source: `openspec/specs/first-party-skill-distribution/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Build-time apm composition of first-party skills | interface | — | — | undischarged — CAM-41 verify W1/W2 canonical reconciliation follow-up |
| Immutable delivery and always-succeeds activation | interface | — | — | undischarged — evidence annotation follow-up |
| Flat skill name preservation | interface | — | — | undischarged — CAM-41 verify W3 canonical reconciliation follow-up |
| Distinct first-party policy and upstream mechanism skills | interface | `.#apm-skills-compose`; pinned-source byte comparison; first-party policy, ownership and VCS sections | — | discharged at two-target Nix composition interface; CAM-41 verify §9b |

## fleet-alerting-interface

Source: `openspec/specs/fleet-alerting-interface/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| The evaluator queries the fleet database as the regulators' store account | interface | R8.2 holder assertion with its mutant; fixture-server refusal leg; first run on magnetite (tasks 4.3, 4.8) | — | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §9.3 |
| Alert rules are rendered from one Nix source to the evaluator and to promtool | interface | `promtool` pass with the `malformedExpression` mutant; fixture legs on the rendered rules; a forced condition for each shipped rule (tasks 4.1, 4.5, 7.6, 10.10) | — | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §9.7 |
| Alert instance state is kept in one state file and posted once per transition | interface | fixture sequence with `noStateWrite` and `forZero`; property test against `model.py` (tasks 4.2, 4.6) | — | discharged at regulator interface; CAM-70 verify §8b |
| Store errors and silent hosts freeze instance state | interface | store-error and silent-host legs with `noStoreFreeze` and `noAbsenceFreeze`; thaw legs and property (tasks 4.2, 10.1) | — | discharged at regulator interface; CAM-70 verify §8b, §11.1 |
| Each rule's presence selector is watched | interface | both signal-gap legs; misspelt-selector control on magnetite (tasks 4.1, 7.2) | — | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §9.3 |
| An always-on host's silence is reported | interface | always-on-host leg with the `noHostsUpdate` mutant (task 10.2) | — | discharged at regulator interface by check only; CAM-70 verify §8b, §11.2; added by #3516 |
| Alerts are posted to fleet-alerts with a title and a severity priority | interface | fixture server's recorded posts, including the host-less titles; runtime titles and priorities (tasks 4.3, 10.7, 10.9) | — | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §9.7 |
| Each completed evaluator run posts a heartbeat | interface | heartbeat on the normal and store-error legs; heartbeats counted after C2 (tasks 4.3, 7.2) | — | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §9.3 |
| The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe | interface | dead-man legs with the probe mutant; R9.3; R9.4; cinnabar's dead-man assertions with their overrides (tasks 5.1, 7.3, 7.5, 10.8) | `world-assumptions` A42 | discharged at regulator, assertion and runtime interfaces; CAM-70 verify §8b, §9.4, §9.6, §11.3 |
| ntfy grants the fleet topics to alerter through declarative provisioning | interface | `ntfy-provisioning` with four mutants; R9.4; an anonymous host-topic publish accepted beside a refused `fleet-alerts` publish (tasks 3.3, 3.4, 5.2) | `world-assumptions` A37, A38 | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §9.2, §9.4 |
| ntfy counts each mesh client as its own visitor | interface | pre-C1 negative control; separate visitor counters after C1 (tasks 3.3, 7.1) | `world-assumptions` A40, A41 | discharged at runtime interface; CAM-70 verify §8b, §9.2; stibnite is counted by its IPv4 address (§9.9) |
| The alerter token travels only as a file | interface | `package-ntfy-send-test-token-transport` with its argv mutant; `unitsWithoutToken` assertion; an unknown token refused 401 at C1 (tasks 1.1, 1.2, 3.2, 4.7, 10.9) | `world-assumptions` A39 | discharged at package-test, assertion and runtime interfaces; CAM-70 verify §8b, §9.2, §11.3 |
| The alert budget is counted over the evaluator's state and the notifier's FAILED log | interface | budget and unreadable-log legs; `failed.log` rehearsal with the `drop-append` and `drop-mode` mutants; R9.1 at runtime (tasks 2.3, 4.2, 9.1, 10.5) | — | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §10.2 |
| The rule check runs promtool, fixture mutants and a property test | interface | each mutant rejected (tasks 4.5, 4.6) | — | discharged at regulator interface; CAM-70 verify §8b; evaluation cost §9.1 |
| The evaluator's memory ceiling and start timeout are asserted | interface | R9.5 mutant and control; the timing relation failing at `postDeadlineSec = 40` (tasks 4.4, 10.4) | — | discharged at evaluation-time assertion interface; CAM-70 verify §8b, §11.2; amended by #3516 |
| The weekly test rule is evaluated in one window each Monday | interface | window leg across the daylight-saving change; forced window on magnetite; the scheduled post on 2026-10-19 (tasks 4.1, 7.6, 7.7) | — | discharged at regulator and runtime interfaces; CAM-70 verify §8b, §9.8 |
| This capability states its own trust boundary | interface | the requirement's own statement; no regulator applies | — | discharged by statement; CAM-70 verify §8b |

## fleet-alerting

Source: `openspec/specs/fleet-alerting/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Each known failure class on a host reaches a person as an alert | behavioral | `The evaluator queries the fleet database as the regulators' store account`; `Alert rules are rendered from one Nix source to the evaluator and to promtool`; `Alerts are posted to fleet-alerts with a title and a severity priority`; `ntfy counts each mesh client as its own visitor` | `world-assumptions` A33, A40, A41 | discharged — CAM-70 verify §8b; every shipped rule fired and resolved §9.7; arrival on the phone composed in §10.1 |
| An alert instance reaches a person once when it fires and at most once when it resolves | behavioral | `Alert instance state is kept in one state file and posted once per transition`; `Alerts are posted to fleet-alerts with a title and a severity priority` | — | discharged — CAM-70 verify §8b, §9.7 |
| An unreachable telemetry store or a silent host freezes alerts | behavioral | `Store errors and silent hosts freeze instance state` | — | discharged — CAM-70 verify §8b after #3510; first runtime observation failed and was re-observed, verify §11.1 |
| A missing signal is itself reported | behavioral | `Each rule's presence selector is watched`; `An always-on host's silence is reported` | — | discharged — CAM-70 verify §8b; always-on-host clause by check only (tasks 10.2, verify §11.2) |
| A silent evaluator is reported from another host | behavioral | `Each completed evaluator run posts a heartbeat`; `The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe` | `world-assumptions` A33, A42 | discharged — CAM-70 verify §8b; R9.3 verify §9.6 |
| Only the alerting credential publishes alerts and heartbeats | behavioral | `ntfy grants the fleet topics to alerter through declarative provisioning`; `The alerter token travels only as a file` | `world-assumptions` A37, A38 | discharged — CAM-70 verify §8b; R9.4 verify §9.4 |
| Alert volume stays within the alert budget | behavioral | `The alert budget is counted over the evaluator's state and the notifier's FAILED log` | — | discharged — CAM-70 verify §8b; R9.1 against the captured messages verify §10.2 |
| The evaluator stays inside its envelope on magnetite | behavioral | `The evaluator's memory ceiling and start timeout are asserted` | `world-assumptions` A31 | discharged — CAM-70 verify §8b; tasks 10.4 |
| A weekly test alert proves the path to a person | behavioral | `The weekly test rule is evaluated in one window each Monday` | `world-assumptions` A33 | discharged — CAM-70 verify §8b; the first Monday message reached no phone, receipt shown by a later test post (verify §9.8) |

## graphical-desktop-session

Source: `openspec/specs/graphical-desktop-session/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| The pyrite host provides a local GNOME desktop under GDM | behavioral | — | — | undischarged — V-interface / evidence annotation follow-up; no named S despite retained runtime evidence |
| The laptop does not suspend itself when nobody is using it | behavioral | — | `world-assumptions` A13 | undischarged — no named S; CAM-62 verify §8b / retrospective §6; see CAM-62 qualifications |
| A person at the panel can choose between two desktops, and the established one is what they get if they do not choose | behavioral | — | — | undischarged — V-interface; amended GNOME reachability excludes live-niri display-manager restart (CAM-66, unrepaired); 8.2 no-history METHOD LIMITATION, source-read only |
| A newly offered desktop does not suspend the host when nobody is using it | behavioral | — | `world-assumptions` A13 | undischarged — V-interface; 8.3/8.4/8.5 evaluation, 8.6 declined CAM-59, 8.7 physical controls; see CAM-63 qualifications |
| A desktop is not offered until the settings it will start with have been checked by the program that will start it | behavioral | — | — | undischarged — V-interface; actual positive/negative builds and binary equality do not name S; includes vacuous |

## host-metrics-collection

Source: `openspec/specs/host-metrics-collection/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| magnetite contributes its own signals to the telemetry store | behavioral | `Ingest is OTLP over HTTP with a database header`; `Scrape targets are reached on loopback`; `The collector's configuration bounds what it gathers` | — | discharged — CAM-68 verify §8b |
| Each stored series names its host | behavioral | `Ingest is OTLP over HTTP with a database header`; `Reads are PromQL and SQL over HTTP with a database header`; `Prometheus remote storage stays enabled for the PromQL query API` | — | discharged — CAM-68 verify §8b |
| Series cardinality stays bounded | behavioral | `The collector's configuration bounds what it gathers` | — | discharged — CAM-68 verify §8b; §8c alphabet finding repaired in #3501 |
| Collection survives a telemetry store restart without losing the queued interval | behavioral | `The collector's queue persists across a telemetry store restart` | — | discharged — CAM-68 verify §8b; verify §10.3 |
| Stored unit names carry no owner's name | behavioral | `Omnigent unit names are stored under aliases` | — | discharged — CAM-68 verify §8b |
| A failed collection or store job notifies a person | behavioral | `Failure notices are posted to one topic` | `world-assumptions` A33, A37 | discharged — CAM-68 verify §8b; verify §9.5, §11.1; CAM-70 verify §8b (posting with the credential) |

## openspec-linear-sync

Source: `openspec/specs/openspec-linear-sync/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Drive Linear exclusively through linear-cli | interface | — | — | undischarged — evidence annotation follow-up |
| Bind four forward transitions plus re-queue with invariants | interface | — | — | undischarged — evidence annotation follow-up |
| Local sync ledger as authoritative current-phase signal | interface | — | — | undischarged — evidence annotation follow-up |
| Single-location frontmatter binding that resolves against the registry | interface | — | — | undischarged — evidence annotation follow-up |
| Mirror the Linear issue description from proposal.md business content | interface | — | — | undischarged — evidence annotation follow-up |
| Archive-time document UPSERT with mirroring | interface | — | — | undischarged — evidence annotation follow-up |
| One-question setup, never-auto-select, best-effort non-blocking | interface | — | — | undischarged — evidence annotation follow-up |

## pi-agent-environment

Source: `openspec/specs/pi-agent-environment/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Nix-owned Pi resources | behavioral | — | — | undischarged — evidence annotation follow-up |
| Mutable settings seed | behavioral | — | — | undischarged — evidence annotation follow-up |
| Runtime state boundary | behavioral | — | — | undischarged — evidence annotation follow-up |
| Source-only extension package | behavioral | — | — | undischarged — evidence annotation follow-up |
| Selected extensions | behavioral | — | — | undischarged — evidence annotation follow-up |
| Nix-owned runtime executables | behavioral | — | — | undischarged — evidence annotation follow-up |
| Excluded extension resources | behavioral | — | — | undischarged — evidence annotation follow-up |
| Retained compaction extension | behavioral | — | — | undischarged — evidence annotation follow-up |
| Canonical skill sink | behavioral | — | — | undischarged — evidence annotation follow-up |
| Catppuccin source provenance | behavioral | — | — | undischarged — evidence annotation follow-up |
| Catppuccin theme delivery | behavioral | — | — | undischarged — evidence annotation follow-up |
| Permission-gate reuse | behavioral | — | `world-assumptions` A1 | undischarged — evidence annotation follow-up |
| Additional shell policy | behavioral | — | `world-assumptions` A2 | undischarged — evidence annotation follow-up |
| Non-Bash edit and write policy | behavioral | — | `world-assumptions` A1, A2, A3, A4, A5, A6, A7 | undischarged — evidence annotation follow-up |
| Git default-branch boundary | behavioral | — | `world-assumptions` A3, A5, A7, A8 | undischarged — evidence annotation follow-up |
| Jj diamond boundary | behavioral | — | `world-assumptions` A3, A5, A7, A8 | undischarged — evidence annotation follow-up |
| Fail-open policy | behavioral | — | `world-assumptions` A1, A2, A3, A4 | undischarged — evidence annotation follow-up |
| Secret-safe direnv | behavioral | — | — | undischarged — evidence annotation follow-up |
| Opt-in slow mode | behavioral | — | — | undischarged — evidence annotation follow-up |
| Consolidated custom regulators | behavioral | — | — | undischarged — evidence annotation follow-up |
| Offline aggregate smoke | behavioral | — | — | undischarged — evidence annotation follow-up |
| Rollback preservation | behavioral | — | — | undischarged — evidence annotation follow-up |
| Activation requires explicit permission | behavioral | — | — | undischarged — evidence annotation follow-up |
| Post-activation confirmation gate | behavioral | — | — | undischarged — evidence annotation follow-up |

## project-management-hub

Source: `openspec/specs/project-management-hub/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Linear Method ontology spine | interface | — | — | undischarged — evidence annotation follow-up |
| Four flat one-level reference areas | interface | — | — | undischarged — evidence annotation follow-up |
| Linear workspace safety gate keyed on confirmed credentials | interface | — | — | undischarged — evidence annotation follow-up |

## requirements-stratification

Source: `openspec/specs/requirements-stratification/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Stratum assignment for any requirement-like statement | behavioral | — | — | undischarged — evidence annotation follow-up |
| Grounding of terms used in requirements | behavioral | — | — | undischarged — evidence annotation follow-up / V-vocabulary; CAM-62 and CAM-63 unresolved nouns |
| Separation of what is assumed from what is wanted | behavioral | — | — | undischarged — evidence annotation follow-up |
| Discharge of a requirement is stated, not implied | behavioral | — | — | undischarged — evidence annotation follow-up |
| Obstacle analysis produces the boundary and open questions | behavioral | — | — | undischarged — evidence annotation follow-up |

## satisfaction-argument-audit

Source: `openspec/specs/satisfaction-argument-audit/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Specification is checked against intent independently | behavioral | — | — | undischarged — evidence annotation follow-up |
| Everything the argument depends on unverified is enumerated | behavioral | — | — | undischarged — evidence annotation follow-up |
| Agreement between two artifacts is not treated as confirmation | behavioral | — | — | undischarged — evidence annotation follow-up |
| External claims are bounded by what was actually established | behavioral | — | — | undischarged — evidence annotation follow-up |
| The audit runs at a boundary, not continuously | behavioral | — | — | undischarged — evidence annotation follow-up |

## shared-reference-tree-interface

Source: `openspec/specs/shared-reference-tree-interface/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Sharing hosts are declared, and only they change | interface | NixOS and darwin module assertions on the three machine checks, each failing under a mutation; non-sharing projection unchanged against main (task 10.2) | — | discharged at evaluation interface; CAM-77 verify §5 |
| The shared root is owned by the writer and closed to everyone else | interface | tmpfiles and darwin provisioning assertions; VM test with `group-writable` mutation; post-deploy ownership audit with no orphaned owner | — | discharged at evaluation, VM and runtime interfaces; CAM-77 verify §5 |
| Each participating account resolves the shared root | interface | participant `programs.ghq-shared.root` assertion; VM `ghq root` per reader; post-deploy `ghq root` per account | `world-assumptions` A35 | discharged at evaluation, VM and runtime interfaces; CAM-77 verify §5 |
| Readers trust the writer's tree and nothing broader | interface | `safe.directory` exactness and enclosing-entry assertions and `safe.bareRepository` assertions, each failing under mutations; VM ownership and bare-repository refusals; post-deploy settings per account | `world-assumptions` A34 | discharged at evaluation, VM and runtime interfaces; CAM-77 verify §5, §5a, §5b |
| Acquisition is delegated to the writer through a socket-activated entry point | interface | VM delegation, deepen, promote, update and tags subtests; handler and wrapper package tests; post-deploy `ghq-sync -u .` and tags per account | — | discharged at package-test, VM and runtime interfaces; CAM-77 verify §5 |
| The writer accepts only constrained requests | interface | handler package test refusal classes; VM malformed requests refused through the client | — | discharged at package-test and VM interfaces; CAM-77 verify §5a |
| Migration moves only administrators' trees in place, sets other trees aside, and can be rolled back | interface | VM migration subtest (administrator move and rollback, refusals, set-aside with reacquisition, mid-apply probe, resumed rollback, earlier-format records), failing with each earlier tool; ACL and writer-stop package test | — | discharged at VM and package-test interfaces; CAM-77 verify §5, §5c–5e; darwin refusal through its probe only |
| Each property is backed by evidence that can fail | interface | VM `group-writable` and `broken-control` mutations fail at their subtests; assertion mutations fail evaluation | — | discharged — CAM-77 verify §5 |
| This capability states its own trust boundary | interface | — | — | undischarged — boundary statement, not a property; follow-up: CAM-77 qualifications |

## shared-reference-tree

Source: `openspec/specs/shared-reference-tree/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Every participating account reads one reference tree per host | behavioral | `Sharing hosts are declared, and only they change`; `Each participating account resolves the shared root` | `world-assumptions` A35 | discharged — CAM-77 verify §8b; post-deploy §5 |
| Only the writer changes the reference tree | behavioral | `The shared root is owned by the writer and closed to everyone else`; `Readers trust the writer's tree and nothing broader`; `Acquisition is delegated to the writer through a socket-activated entry point` | `world-assumptions` A34 | discharged — CAM-77 verify §8b; VM threat demonstration and post-deploy refusals §5 |
| A missing reference repository can be requested without a person | behavioral | `Acquisition is delegated to the writer through a socket-activated entry point`; `The writer accepts only constrained requests` | — | discharged — CAM-77 verify §8b |
| Only participating accounts can read the reference tree | behavioral | `The shared root is owned by the writer and closed to everyone else` | — | discharged — CAM-77 verify §8b; `nobody` refused at root and socket §5 |
| Sharing the reference tree leaves every private home private | behavioral | `Sharing hosts are declared, and only they change`; existing Omnigent worker obligations (private `0700` homes, admitted groups) | — | discharged — CAM-77 verify §8b |
| Moving per-account copies into the reference tree loses nothing and is reversible | behavioral | `Migration moves only administrators' trees in place, sets other trees aside, and can be rolled back` | `world-assumptions` A36 | discharged — CAM-77 verify §8b, §5c–5e; stibnite migrated by the earlier tool, whose records still roll back |

## skill-corpus-interface

Source: `openspec/specs/skill-corpus-interface/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| A named skill is resolvable in the delivered corpus | interface | — | — | undischarged — evidence annotation follow-up |
| A skill's trigger surface admits the situations it must fire on | interface | — | — | undischarged — evidence annotation follow-up |
| Stated ownership boundaries hold across the corpus | interface | — | — | undischarged — evidence annotation follow-up |
| Stacked landing guidance is conditioned by role and repository mode | interface | first-party role/requirement-map/routing sections; evaluated user-context text; integrated-main stack-land predicate/tests | — | discharged at composed/rendered guidance interface; CAM-41 verify §9b |

## stratified-change-authoring

Source: `openspec/specs/stratified-change-authoring/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Proposal artifact records a stratum tag per capability | interface | — | — | undischarged — evidence annotation follow-up |
| Specs artifact applies stratum-conditional vocabulary rules | interface | — | — | undischarged — evidence annotation follow-up |
| Verify artifact runs non-blocking stratum checks | interface | — | — | undischarged — evidence annotation follow-up |
| Archive step regenerates the satisfaction projection | interface | — | — | undischarged — evidence annotation follow-up |
| Tasks artifact records per-task verification | interface | — | — | undischarged — evidence annotation follow-up |
| The stratum layer states its own trust boundary | interface | — | — | undischarged — evidence annotation follow-up |

## telemetry-store-interface

Source: `openspec/specs/telemetry-store-interface/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| Listeners are bound to loopback only | interface | R7.1 in the `greptimedb-envelope` check | — | discharged at evaluation-time regulator interface; CAM-68 verify §8b |
| Prometheus remote storage stays enabled for the PromQL query API | interface | pipeline container test PromQL cases (task 2.1) | — | discharged at container runtime-test interface; CAM-68 verify §8b |
| Scrape targets are reached on loopback | interface | R3.1 (tasks 3.3, 3.7, 4.4) | — | discharged at evaluation-time regulator interface; CAM-68 verify §8b |
| Store accounts carry fixed permission modes | interface | users-file check; R8.2; container auth matrix (task 6.1) | — | discharged at regulator and runtime-test interfaces; CAM-68 verify §8b |
| Ingest is OTLP over HTTP with a database header | interface | R3.1, R1.2; container ingest case (task 6.1) | — | discharged at regulator and runtime-test interfaces; CAM-68 verify §8b |
| Reads are PromQL and SQL over HTTP with a database header | interface | container read-back case (task 6.1) | — | discharged at container runtime-test interface; CAM-68 verify §8b |
| Databases and their retention are set at the telemetry store | interface | schema oneshot (task 2.6); container retention cases (task 6.1) | — | discharged at runtime-test interface; CAM-68 verify §8b |
| Tables allowed a retention of their own are declared | interface | `flake.lib.greptimedbEnvelopeTables` table-TTL clause over `services.greptimedb.tableTtls`; container undeclared-`ttl` negative control (tasks 10.5, 10.10) | — | discharged at regulator and runtime-test interfaces; CAM-68 verify §11.2; added after §8b |
| The store and the collector name the same databases | interface | ingress-module assertion that the store's database names equal `flake.lib.otelCollectorSchema.databases` (task 10.4) | — | discharged at evaluation-time assertion interface; CAM-68 tasks 10.4, verify §11; added after §8b |
| Object data lives under one prefix of one bucket | interface | R6.4 storage clause; R6.3; container `sst_format` negative control (tasks 2.1, 2.5, 4.3, 5.1, 10.10) | `world-assumptions` A29 | discharged at regulator interface; CAM-68 verify §8b; verify §11.2 |
| Credentials exist only as activation-resolved files owned by non-worker users | interface | R8.2 with its mutants (CAM-68 tasks 2.4, 4.3); R8.2 admitting `fleet-alert` and rejecting a third holder (CAM-70 task 4.8) | — | discharged at evaluation-time regulator interface; CAM-68 verify §8b; CAM-70 verify §8b |
| The account file the telemetry store loaded is recorded | interface | `ExecStartPre` hash (task 2.2); R7.4 (task 5.1) | — | discharged at regulator interface; CAM-68 verify §8b; no `Discharges:` clause names it by title |
| The telemetry store and the collector run inside a declared envelope | interface | R7.1 with seven mutants; R7.2, R7.3; pyrite VM kill-order test (tasks 2.2, 4.1, 5.1, 6.2) | `world-assumptions` A31, A32 | discharged at regulator and runtime-test interfaces; CAM-68 verify §8b |
| Runtime regulators treat absent evidence as failure | interface | renamed-table mutant (tasks 5.1, 5.2) | — | discharged at runtime regulator interface; CAM-68 verify §8b |
| The telemetry store's release and usage reporting are fixed at evaluation | interface | R1.1 amended; R1.4 with mutants (task 4.2) | `world-assumptions` A30 | discharged at evaluation-time regulator interface; CAM-68 verify §8b |
| The collector's configuration bounds what it gathers | interface | R3.1 process and systemd clauses (tasks 3.2, 4.4) | — | discharged at evaluation-time regulator interface; CAM-68 verify §8b |
| Omnigent unit names are stored under aliases | interface | R3.1 alias clause (task 4.4); container alias read-back (task 6.1) | — | discharged at regulator and runtime-test interfaces; CAM-68 verify §8b |
| The collector's queue persists across a telemetry store restart | interface | R3.1 queue clause (tasks 3.2, 4.4); container restart case (task 6.1) | — | discharged at regulator and runtime-test interfaces; CAM-68 verify §8b; verify §10.3 |
| Failure notices are posted to one topic | interface | R3.1 failure-wiring clause and notifier rehearsal with their mutants; `package-ntfy-send-test-token-transport`; resolve-hook assertion; forced failure (CAM-68 tasks 3.4, 3.5, 4.4, 8.6; CAM-70 tasks 1.2, 2.2, 2.3, 4.7, 10.9) | — | discharged at regulator interface; CAM-68 verify §8b; CAM-70 verify §8b; delivery with `alerter` §9.4 |
| A failure episode ends at the unit's next successful start or exit | interface | R3.1 failure-wiring clause with its start-hook mutant and notifier crash-loop rehearsal (task 10.1) | — | discharged at regulator interface; CAM-68 tasks 10.1, live notifier verify §11.1; added after §8b |
| This capability states its own trust boundary | interface | the requirement's own statement; no regulator applies | — | discharged by statement; CAM-68 verify §8b; CAM-70 verify §8b; Purpose sentence edited at archive (CAM-70 task 8.4) |

## telemetry-store

Source: `openspec/specs/telemetry-store/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| A database keeps its series for its retention and no longer | behavioral | `Databases and their retention are set at the telemetry store`; `Object data lives under one prefix of one bucket` | `world-assumptions` A29 | discharged — CAM-68 verify §8b |
| Part of a database keeps the database's retention unless another is declared | behavioral | `Tables allowed a retention of their own are declared` | — | discharged — CAM-68 tasks 10.5, 10.10; verify §11.2; added after §8b, see CAM-68 qualifications |
| Only the collector writes and only named readers read | behavioral | `Store accounts carry fixed permission modes`; `Listeners are bound to loopback only`; `Credentials exist only as activation-resolved files owned by non-worker users` | — | discharged — CAM-68 verify §8b |
| A replaced store credential takes effect on the running telemetry store | behavioral | `Credentials exist only as activation-resolved files owned by non-worker users`; `The account file the telemetry store loaded is recorded` | — | discharged — CAM-68 verify §8b |
| The telemetry store stays inside a memory envelope that leaves build capacity to the build service | behavioral | `The telemetry store and the collector run inside a declared envelope` | `world-assumptions` A31, A32 | discharged — CAM-68 verify §8b; kill order by pyrite VM test (task 6.2) |
| The telemetry store stays inside a disk envelope of its own | behavioral | `The telemetry store and the collector run inside a declared envelope` | — | discharged — CAM-68 verify §8b |
| The telemetry store sends no usage report to its vendor | behavioral | `The telemetry store's release and usage reporting are fixed at evaluation` | — | discharged — CAM-68 verify §8b |
| The telemetry store runs a stable vendor release that serves its dashboard | behavioral | `The telemetry store's release and usage reporting are fixed at evaluation` | `world-assumptions` A30 | discharged — CAM-68 verify §8b; authenticated dashboard check verify §9.4 |
| The telemetry store's own failures reach a person | behavioral | `Failure notices are posted to one topic` | `world-assumptions` A33, A37 | discharged — CAM-68 verify §8b; verify §9.5, §11.1; CAM-70 verify §8b, §9.4 (delivery with the credential) |

## third-party-plugin-dependency

Source: `openspec/specs/third-party-plugin-dependency/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| First-party packages declare nix-pinned apm dependencies on upstream plugins | interface | — | — | undischarged — evidence annotation follow-up |
| Upstream plugins consumed without forking and extended additively | interface | — | — | undischarged — evidence annotation follow-up |
| Release-aligned offline Mergify skill dependency | interface | equal package-version evaluations; normal/negative structure builds; offline composition; generated-lock revision/hashes; byte comparison | Mergify tag `2026.8.31.1` → `727ce50b8fb3be8a9a24025807e159d644dbba80`, dated CAM-41 inspection | discharged at Nix build interface; repository-local frozen delivery pending CAM-41 W4 |

## world-assumptions

Source: `openspec/specs/world-assumptions/spec.md`.

| Requirement | Stratum | Discharges (R) | Status |
|---|---|---|---|
| A1 — No native permission system | world | Permission-gate reuse; Non-Bash edit and write policy; Fail-open policy | self-attested; monitoring follow-up: evidence annotation follow-up |
| A2 — Unanswerable dialog stalls a session with UI but no human present | world | Additional shell policy; Non-Bash edit and write policy; Fail-open policy | self-attested; monitoring follow-up: evidence annotation follow-up |
| A3 — Policy failure carries no safety evidence | world | Non-Bash edit and write policy; Git default-branch boundary; Jj diamond boundary; Fail-open policy | self-attested; monitoring follow-up: evidence annotation follow-up |
| A4 — Refusing on ambiguity has a real cost and prevents nothing | world | Non-Bash edit and write policy; Fail-open policy | self-attested; monitoring follow-up: evidence annotation follow-up |
| A5 — A tracked target is recoverable from repository history | world | Non-Bash edit and write policy; Git default-branch boundary; Jj diamond boundary | self-attested; monitoring follow-up: evidence annotation follow-up |
| A6 — Atomic inherits Pi's configuration root unconditionally | world | Non-Bash edit and write policy | self-attested; monitoring follow-up: evidence annotation follow-up |
| A7 — Pi's enumerated path forms are exhaustive | world | Non-Bash edit and write policy; Git default-branch boundary; Jj diamond boundary | self-attested; monitoring follow-up: evidence annotation follow-up |
| A8 — Jj's outside-repository diagnostic is stable | world | Git default-branch boundary; Jj diamond boundary | self-attested; monitoring follow-up: evidence annotation follow-up |
| Grounded vocabulary for behavioral requirements | world | Grounds behavioral vocabulary; not requirement-scoped | self-attested; monitoring follow-up: evidence annotation follow-up; CAM-68 verify §8a nouns grounded in #3501; CAM-70 verify §8a nouns open, retrospective §6 |
| A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine | world | The laptop does not suspend itself when nobody is using it; A newly offered desktop does not suspend the host when nobody is using it | self-attested; monitoring follow-up: evidence annotation follow-up; CAM-59 incident evidence, CAM-62 added eighth failure |
| A29 — Cloudflare R2 behaves as S3-compatible object storage for the telemetry store's client | world | A database keeps its series for its retention and no longer; Object data lives under one prefix of one bucket | self-attested; monitored by first activation (CAM-68 verify §9.4) and the R6.4 readiness probe |
| A30 — nixpkgs channels lag the telemetry store's vendor releases and omit its dashboard | world | The telemetry store runs a stable vendor release that serves its dashboard; The telemetry store's release and usage reporting are fixed at evaluation | self-attested; monitored by R1.1 accepting the channel's package once it declares the dashboard (CAM-68 verify §8b) |
| A31 — magnetite's memory is finite and shared with the build service's evaluation work | world | The telemetry store stays inside a memory envelope that leaves build capacity to the build service; The telemetry store and the collector run inside a declared envelope; The evaluator stays inside its envelope on magnetite | self-attested; monitored hourly by R7.2 (CAM-68 verify §8b) |
| A32 — magnetite has no /dev/kvm, and the kernel's kill order does not depend on the host it runs on | world | The telemetry store stays inside a memory envelope that leaves build capacity to the build service; The telemetry store and the collector run inside a declared envelope | self-attested; exercised by the pyrite kill-order VM test (CAM-68 task 6.2); kernel-equivalence not independently re-proved |
| A33 — The fleet's notification service on cinnabar is reachable over ZeroTier and is the single delivery path | world | The telemetry store's own failures reach a person; A failed collection or store job notifies a person; Each known failure class on a host reaches a person as an alert; A silent evaluator is reported from another host; A weekly test alert proves the path to a person | self-attested; monitored by forced-failure delivery (CAM-68 verify §9.5, §11.1) and the access matrix after C3 (CAM-70 verify §9.4); nothing in the fleet reports cinnabar or its notification service down (CAM-76) |
| A37 — ntfy provisions users, access entries and tokens from its declaration, and refuses to start on an undeclared user | world | Only the alerting credential publishes alerts and heartbeats; ntfy grants the fleet topics to alerter through declarative provisioning; A failed collection or store job notifies a person; The telemetry store's own failures reach a person | self-attested; observed by `alerter` and its token coming from server config at C1 (CAM-70 verify §9.2); `ntfy-provisioning` cites the pinned source |
| A38 — One ntfy access entry decides a request, a named user's before the anonymous one's | world | Only the alerting credential publishes alerts and heartbeats; ntfy grants the fleet topics to alerter through declarative provisioning | self-attested; observed by `alerter` accepted beside an anonymous `fleet-alerts` publish refused 403 (CAM-70 verify §9.4) |
| A39 — ntfy refuses a request whose token it does not know, even where anonymous access is allowed | world | The alerter token travels only as a file | self-attested; observed by an unknown token refused 401 on an open topic at C1 (CAM-70 verify §9.2) |
| A40 — ntfy rate-limits a client by its address masked to a prefix, taken from a trusted proxy's forwarding header | world | Each known failure class on a host reaches a person as an alert; ntfy counts each mesh client as its own visitor | self-attested; observed by separate visitor counters after C1 (CAM-70 verify §9.2); the IPv4 prefix stays at its default (§9.9) |
| A41 — caddy reaches ntfy from ::1 and forwards the mesh client's address | world | Each known failure class on a host reaches a person as an alert; ntfy counts each mesh client as its own visitor | self-attested; observed by the journal showing each client's own mesh address, never `::1` (CAM-70 verify §9.2) |
| A42 — ntfy keeps a topic's messages for 12 hours and returns a recent window to a poll | world | A silent evaluator is reported from another host; The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe | self-attested; observed by the dead-man's heartbeat counts and R9.3 (CAM-70 verify §9.4, §9.6) |
| A34 — Git runs repository-local programs as the invoking account, and refuses foreign-owned repositories unless trusted | world | Only the writer changes the reference tree; Readers trust the writer's tree and nothing broader | self-attested; observed by the VM threat demonstration (a writer-planted `core.fsmonitor` runs as a reader) and stibnite's dubious-ownership negative control (CAM-77 verify §5) |
| A35 — ghq resolves its root from the environment, then git configuration, then the home directory, through symlinks | world | Every participating account reads one reference tree per host; Each participating account resolves the shared root | self-attested; observed by `ghq root` resolving the shared root for every account on all three hosts (CAM-77 verify §5) |
| A36 — A host's administrator can act as any account on that host | world | Moving per-account copies into the reference tree loses nothing and is reversible | self-attested; monitoring follow-up: evidence annotation follow-up; administrator membership read with `getgrouplist` on each host (CAM-77 verify §5) |

`A9`–`A12` and `A14`–`A28` remain absent from the current main corpus: active deltas carry them (`stand-up-nixbot-on-magnetite` A9–A12, `k3s-nixos-vm-tests` A14–A16, `capi-hetzner-cluster` A17–A21, `stand-up-gitea-mq-on-magnetite` A22–A28), not this archive; `path-scope-plugin-releases` (A9, A10), `filter-check-sources-for-substitution` (A22, A23) and `k3s-nixos-vm-tests` (A13) reuse numbers already taken, unresolved here.
CAM-64 tracks full-content MODIFIED sync loss; CAM-68's MODIFIED `Grounded vocabulary for behavioral requirements` was synced as a whole-block replacement carrying its fourteen double-sense terms.
CAM-70's MODIFIED block was synced the same way, carrying fifteen double-sense terms (`evaluator` added) and every pre-sync row, with `credential` (notification service) rewritten under the same term and sense (CAM-70 verify §10.3).
CAM-77's MODIFIED block was rebuilt on CAM-70's synced block before it archived and synced the same way: every pre-sync row is kept, `person` and `writer` are each split into two senses (the earlier text kept under `service` and `database`), eleven rows are added, and eighteen double-sense terms are named (CAM-77 verify §3).

## CAM-41 qualifications

- W1/W2/W3: canonical four-direct-target provenance, build-only APM statement and absolute-autoload census conflict with the observed two-target/later-fan-out, producer installer and single-force-load arrangement; separate canonical reconciliation remains open.
- W4: the archived verification could not establish repository-local ignored `.agents/` delivery; post-main generated relock is required before that frozen-delivery claim. This projection does not assert current root-lock or ignored-tree contents.
- W5/W6: archived repository evidence did not establish absence of external activation/landing or publication; those historical boundaries are not new queries of present forge state.
- S1: placeholder Purpose maintenance remains separate from these discharges; no repo-wide structural success is claimed here.

## CAM-62 qualifications

- Battery inactivity and panel blank/lock were discharged by evaluation, not behavioral observation. Each residual costs an elapsed idle window and no redeploy; no new window is claimed by CAM-63.
- The inactivity requirement has no named S: the greeter/user dconf properties occur only in design/tasks. Its world A13 annotation alone does not discharge it; the table retains the undischarged row and retrospective §6 follow-up.
- `laptop`, `person`, and `network` designation gaps were recorded, not silently repaired; CAM-63 adds its own recorded vocabulary/interface gaps.
- CAM-59 remains an unexplained resume defect, historical cohort 8 failures against 30 successes across 14 boots after CAM-62 verification. The latest failure broke the prior first-suspend-of-boot success regularity; idle harm reduction is not a repair.
- No plan.md was authored in CAM-62; tasks carried the manual-check role. Publication and full behavioral coverage were not inferred from archive.

## CAM-63 qualifications

Primary disposition record: `openspec/changes/archive/2026-09-10-pyrite-niri-second-session/verify.md` §9.12; incident: `known-limitations.md`; follow-ups: `retrospective.md` §6.
- **Requirement amended after counterexample:** only unconditional GNOME reachability and recovery WHEN narrow for live-niri display-manager restart; GNOME registration/selectability/default-for-no-history, per-user persistence/no host overwrite and recovery THEN/AND remain outside that exception. Niri v26.04 lacks the leader-death bridge GNOME 50.1 has; no configuration of ours supplies that upstream behavior. This is not a fixable configuration defect hidden by bar-lowering. **[CAM-66](https://linear.app/cameronraysmith/issue/CAM-66)** remains the excluded, unrepaired upstream follow-up, not a discharge or a claimed upstream submission.
- **8.2 split:** remembered choice discharged by persisted Session=niri at operator login and subsequent logins; **no-history GNOME remains a METHOD LIMITATION, source-read only**, grounded in GDM 50.1 hardcoded fallback and explicit defaultSession=null/no rewrite, not observation and not discharged-by-evaluation. The operator declined destroying their real saved preference; a second disposable user with no session history is the safe future check.
- **6.6 runtime observation:** niri session 238 / compositor PID 158454, gsettings through its own environment: idle-delay uint32 1800, gsd power schema absent from XDG_DATA_DIRS. GNOME power settings are structurally inapplicable in that niri session, not merely unread by an absent daemon. Four delay-mode sleep inhibitors, no block handle-power-key inhibitor, independently corroborate niri 8.7; GNOME gsd-media-keys holds that block-mode inhibitor and bypasses logind.
- **8.3/8.4/8.5 evaluation, not observation. 8.6 declined** under CAM-59 physical-recovery risk. No untouched niri AC/battery or repeated GNOME/greeter interval, no deliberate niri suspend/guard/wake pass.
- **8.7 physical tests:** GNOME 176 press at 02:02:54.328864 UTC; niri 209 presses at 02:03:39.311662 and 02:03:41.429194, all on 2026-09-10. Same-boot pre-fix positive control: September 9 21:16:36.327747 press → media-keys request 21:16:36.392292 → PM entry 21:16:37.863260. Protected logged presses with no suspend/shutdown are negative controls. **Whole-boot totals 1 requested / 1 entry**, not zero or two; the extra grep hit was sudo audit text.
- **Task 8.1 was the test that would have caught the strand. The checklist ordering itself caused the lockout inside niri.** Correct order quits niri and verifies the affected user service inactive before any separately authorized display-manager restart; SSH/greeter location alone is insufficient.
- **Formal obligations remain undischarged:** no named S for any of the four CAM-63 delta requirements. V-interface/V-vocabulary are agent-executed/non-blocking findings, NEVER validation; a clean designation lint without grounding is vacuous.
- **Slice B residuals:** xwayland-satellite absent, xcursor-theme default warning, GNOME GlobalShortcutsProvider InvalidArgs warning, portal functional transactions untested, 8.2 no-history half, empty logind Desktop despite niri environment/desktop-entry metadata. Empty Desktop propagation remains unresolved rather than guessed.
- **Other follow-ups unchanged:** CAM-59 resume, CAM-60 unattended boot, CAM-61 Bluetooth/wlp2s0, CAM-64 MODIFIED content loss. The local C sd-login monitor was deliberately not carried; prototype preserved in logs/niri-session-strand-defect.md, not verified end-to-end.

## CAM-68 qualifications

Primary disposition record: `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/verify.md` §8b; deployment evidence §§9–10; review follow-ups §11 and `review.md`; follow-ups: `retrospective.md` §6.
- **Verdict PASS WITH WARNINGS:** the warnings were §8a (content nouns without a designation row) and §8c (two non-world phenomena in behavioral requirements); both were addressed in #3501 before archive, and the synced designation table and `Series cardinality stays bounded` carry those fixes.
- **Four requirements postdate §8b:** `Part of a database keeps the database's retention unless another is declared`, `Tables allowed a retention of their own are declared`, `The store and the collector name the same databases` and `A failure episode ends at the unit's next successful start or exit` came from review findings F1, F3 and F4 (#3497, #3498); their rows cite `tasks.md` 10.1, 10.4, 10.5 and 10.10 and verify §11, not the §8b table.
- **Interface discharges are regulator and runtime-test evidence:** evaluation-time checks with mutants, the hourly envelope regulator, the pipeline container test and the on-demand pyrite VM kill-order test, plus first-activation observations on magnetite. `The account file the telemetry store loaded is recorded` is named by no `Discharges:` clause by title; task 5.1 names it as R7.4.
- **Trust boundary is stated, not discharged:** R2 durability and token scope belong to Cloudflare (A29), any root process on magnetite can reach the loopback listener, ntfy access was ZeroTier membership until CAM-70 replaced it with ntfy's access entries, and cinnabar is the single delivery path (A33); nothing here guarantees a series reaches the store end to end.
- The roborev sub-gate was replaced at the operator's direction by the holistic review in `review.md` (twelve findings, all applied); verify §11 records the redeployments after #3497 and #3499.

## CAM-70 qualifications

Primary disposition record: `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/verify.md` §8b; deployment evidence §§9–10; review follow-ups §11 and `review.md`; follow-ups: `retrospective.md` §6.
- **Verdict PASS WITH WARNINGS:** the `LocalExporterDown` pair that tasks.md 9.1 asks to see on the phone was not observed there, because no phone was subscribed until 2026-10-20; its last link is composed from pyrite's capture of `fleet-alerts` and the 7.7 test post received on the phone over the same topic and server (verify §10.1); the §8a designation nouns remain open as a retrospective §6 promote item.
- **Review follow-ups changed requirements:** `An always-on host's silence is reported` was added, and `A missing signal is itself reported`, `The evaluator's memory ceiling and start timeout are asserted` and the title requirement were amended, by #3516; the always-on-host clause is discharged by check only, with no runtime observation.
- **Interface discharges are regulator, package-test, assertion and runtime evidence:** evaluation-time checks with mutants (`fleet-alert`, `ntfy-provisioning`, `otel-collector-config`, `package-ntfy-send-test-token-transport`), host assertions shown able to fail by overrides, and cutover observations on magnetite and cinnabar, some made by an agent and marked so in verify §8b.
- **Trust boundary is stated, not discharged:** ntfy enforces the access entries and rate limits (A37–A41); any root process on magnetite or cinnabar can read the `alerter` token; cinnabar is the single delivery path (A33), and nothing reports an ntfy outage until CAM-76, which now blocks CAM-72 (review F4); nothing here guarantees that an alert reaches a person.
- The roborev sub-gate was replaced at the operator's direction by the holistic review in `review.md` (twelve findings, none critical): F1–F3, F5–F9, F11 and F12 were applied in #3516 and #3519, F4 is documented, and F10 is deferred to S2; verify §11 records the redeployment after #3516, and #3519 was not deployed because it changed no alerting unit.

## CAM-77 qualifications

Primary disposition record: `openspec/changes/archive/2026-10-20-share-ghq-reference-tree/verify.md` §8b; runtime and deploy evidence §5; review rounds §5a–5e; follow-ups: `retrospective.md` §6 and task 9.4.
- **Verdict PASS WITH WARNINGS:** task 9.4, deleting stibnite's empty `~/ghq.pre-shared-20261017` and the migration records, waits for the operator; a deploy of main before the merge removed the writer from magnetite, recovered by redeploying with the same uid (verify §5).
- **Trust boundary decided by the user (2026-10-17):** only an administrator's tree moves in place, under A36, and only when no entry could have been written by another account; every other account's tree is set aside and reacquired through the writer; nothing a non-administrator wrote is in any shared tree.
- **Interface discharges are evaluation, package-test, VM and post-deploy evidence:** module assertions shown able to fail by mutations, the NixOS test with the `group-writable` and `broken-control` mutations, and post-deploy checks on pyrite, magnetite and stibnite; darwin runtime behaviour is observed by inspection on stibnite only, and the darwin migration refusal is tested through its probe, not an end-to-end apply.
- **Trust boundary is stated, not discharged:** the properties hold at the hosts' declared configuration and Unix permissions; they do not cover an account overriding its own git or ghq configuration, root or the writer acting against the tree, or upstream content.

## Known limits

This projection contains no formal proof and no claim of end-to-end implementation verification.
The three inherited CAM-41 interface discharges establish machine-visible artifacts only: no harness selection, human compliance, authorization, forge correctness, activation or landing guarantee.
The 36 CAM-68 discharges establish configuration, regulator and tested-pipeline behavior on magnetite only; they assert neither R2 durability, ntfy delivery when cinnabar is down, nor end-to-end arrival of every series.
The 26 CAM-70 discharges establish configuration, regulator and observed cutover behavior on magnetite and cinnabar only; they assert neither delivery while cinnabar or its notification service is down, nor that a person reads an alert.
The 14 CAM-77 discharges establish configuration, VM-test and post-deploy behavior on pyrite, magnetite and stibnite only; they assert nothing about upstream content or an account that overrides its own git or ghq configuration.
Pyrite file-db contents and runtime adoption are different evidence; user dconf overrides deliberately remain possible.
An archive-ready PASS WITH WARNINGS and an undischarged formal row are compatible claims at different boundaries, not a silent acceptance of missing evidence.
