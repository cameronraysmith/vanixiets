---
title: Satisfaction argument
description: Discharge status for every requirement in the OpenSpec corpus
generated: 2026-09-10
---

This file is a projection over `openspec/specs/`, regenerated wholesale at archive time and never patched.
It enumerates every current requirement from the post-sync corpus; it does not use the previous projection as input.
Discharge annotations come from the owning verification artifacts cited below, not from an agreement between configuration files.
The `W ∧ S ⇒ R` obligation is separate from implementation refinement and from an archive-ready behavioral verdict.
Nothing here is an end-to-end guarantee; OpenSpec structure checks are not behavioral validation.

## Status

The post-sync corpus has **105 requirements across 15 capabilities**: 95 requirement-side rows and 10 world-assumption rows.
**3 requirement-side rows are discharged at narrow interface boundaries; 92 remain undischarged**, each with a follow-up reference.
Of those undischarged rows, 8 name world assumptions but no named specification-side discharge; 84 name neither.
The 10 world rows remain self-attested, not independently discharged; their monitoring/scenario truth is not re-proved by this projection.
A13 has real incident evidence, including CAM-59, but no new world-assumption audit is claimed here.

**CAM-63 qualifications are load-bearing:** GNOME reachability is amended to exclude live-niri display-manager restart (**CAM-66**, unrepaired); **8.2 no-history is a source-read-only method limitation**, not discharged by evaluation; **8.3/8.4/8.5 are evaluation, not observation; 8.6 is declined under CAM-59; 8.7 is physical testing with same-boot positive/negative controls and whole-boot totals 1 requested / 1 entry**.
Task 8.1 would have caught the strand; the post-deploy checklist ordering itself caused the lockout inside niri.
These behavioral dispositions do not manufacture named specification-side discharges.

## Evidence and follow-up conventions

- CAM-41 evidence: `openspec/changes/archive/2026-09-02-integrate-mergify-stacked-landing/verify.md:105–111,185–191`; qualifications W1–W6 at `:31–50`.
- CAM-62 evidence/follow-ups: `openspec/changes/archive/2026-09-09-pyrite-never-sleep/verify.md` §§7–8 and `retrospective.md` §6.
- CAM-63 evidence/follow-ups: `openspec/changes/archive/2026-09-10-pyrite-niri-second-session/verify.md` §§8,9.12 and `retrospective.md` §6.
- `evidence annotation follow-up` means OpenSpec change `annotate-discharge-evidence` (active or subsequently archived), not implicit acceptance.
- `V-interface` means the CAM-63 retrospective §6 architecture decision: introduce named interface properties or explicitly decide the corpus discharge convention.
- `V-vocabulary` means the next sole designation-table owner grounds world/shared terms and relocates machine predicates; CAM-63 verify §8 is agent-executed/non-blocking and NEVER validation.
- Older capability strata remain inferred and not re-audited; CAM-41 declares its three additions interface, CAM-62/CAM-63 declare graphical-desktop-session behavioral.
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

## graphical-desktop-session

Source: `openspec/specs/graphical-desktop-session/spec.md`.

| Requirement | Stratum | Discharged by (S) | Under (W) | Status |
|---|---|---|---|---|
| The pyrite host provides a local GNOME desktop under GDM | behavioral | — | — | undischarged — V-interface / evidence annotation follow-up; no named S despite retained runtime evidence |
| The laptop does not suspend itself when nobody is using it | behavioral | — | `world-assumptions` A13 | undischarged — no named S; CAM-62 verify §8b / retrospective §6; see CAM-62 qualifications |
| A person at the panel can choose between two desktops, and the established one is what they get if they do not choose | behavioral | — | — | undischarged — V-interface; amended GNOME reachability excludes live-niri display-manager restart (CAM-66, unrepaired); 8.2 no-history METHOD LIMITATION, source-read only |
| A newly offered desktop does not suspend the host when nobody is using it | behavioral | — | `world-assumptions` A13 | undischarged — V-interface; 8.3/8.4/8.5 evaluation, 8.6 declined CAM-59, 8.7 physical controls; see CAM-63 qualifications |
| A desktop is not offered until the settings it will start with have been checked by the program that will start it | behavioral | — | — | undischarged — V-interface; actual positive/negative builds and binary equality do not name S; includes vacuous |

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
| Grounded vocabulary for behavioral requirements | world | Grounds behavioral vocabulary; not requirement-scoped | self-attested; monitoring follow-up: evidence annotation follow-up |
| A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine | world | The laptop does not suspend itself when nobody is using it; A newly offered desktop does not suspend the host when nobody is using it | self-attested; monitoring follow-up: evidence annotation follow-up; CAM-59 incident evidence, CAM-62 added eighth failure |

`A9` through `A12` remain absent from the current main corpus: they belong to the active `stand-up-nixbot-on-magnetite` delta, not this archive.
CAM-64 tracks full-content MODIFIED sync loss; CAM-63 contains no world-assumptions delta and did not edit this capability.

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

## Known limits

This projection contains no formal proof and no claim of end-to-end implementation verification.
The three inherited CAM-41 interface discharges establish machine-visible artifacts only: no harness selection, human compliance, authorization, forge correctness, activation or landing guarantee.
Pyrite file-db contents and runtime adoption are different evidence; user dconf overrides deliberately remain possible.
An archive-ready PASS WITH WARNINGS and an undischarged formal row are compatible claims at different boundaries, not a silent acceptance of missing evidence.
