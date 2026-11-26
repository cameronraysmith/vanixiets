## Context

The den-ready-fleet project refactors how the fleet's hosts, users, relations and checks are composed so that a later migration to den is near-mechanical.
Almost every refactor in it is meant to leave every built output unchanged; a few declare a small change in advance (the darwin activation order, the darwin cache list, the runtime-test package set).
This change gives them the instrument that decides "unchanged", a protocol for the cost claims some of them make, and planning documents that describe the repository as it is.

Current state, re-read on 2026-11-26:
- `just eval-identity` (`justfile:435-452`) compares stock Nix and iets at **one** commit, through `apps/nix-eval-jobs-identity` (checks) and `apps/nix-classic-identity` (configurations). `modules/README.md:88` names the first "the drvPath-identity oracle".
- The cross-revision procedure exists only as prose in the `preferences-nix-checks-architecture` skill, `references/evaluation-cost.md:90-121`, covering `checks` and configuration toplevels.
- Runtime tests are the flake output `vmTests.<system>` (`modules/vm-tests/default.nix:1`), outside `checks`.
- `homeConfigurations` has 20 names of the form `<user>@<system>` (`modules/checks/structure/flake-shape.nix:50-71`); `clan/machines.nix:3-44` registers 6 NixOS and 4 darwin machines.
- The 2026-11-26 cost measurements (`logs/cross-host-eval-cost-*-20261126-*`, gitignored) are single runs on a dirty tree with no evaluator or command recorded.
- `docs/notes/development/architectural-principles.md` plans through "beads epics" (`:7,348-453,475`), lists five resolved or answered opportunities, and has no principle for three audit findings.
- ADR-0018 (`:12,39,215,188`), ADR-0019 (`:12,70-74`) and ADR-0020 (`:88-95,116-121,143-149`) describe 8 machines and 5 users, a `nixpkgs.hostPlatform` in `clan.machines`, `flakeModulesHome."users/crs58"`, and a clan-inventory `ssh-known-hosts` service over `modules.common`. Now each host module sets `nixpkgs.hostPlatform` (for example `machines/nixos/magnetite/default.nix:143`, `darwin/laptop.nix:69`), users export `flake.users.<u>.modules`, and known hosts come from `modules/system/ssh-known-hosts.nix`.

Stakeholders: the operator, who accepts each refactor and decides principle revisions (`architectural-principles.md:468-469`); the agents applying the other six changes of the project, which run the oracle.

## Goals / Non-Goals

**Goals:**
- One command that, given two commits and an optional allow-list, says which deployed systems, home configurations, checks and runtime tests changed derivation, and fails on anything undeclared.
- One command that measures an attribute's evaluation cost at two commits with interleaved runs and records every run with its conditions.
- Committed baselines for the cost points the project's later changes cite.
- Planning and architecture documents that a later change can start from without correction.

**Non-Goals:**
- Any change to a deployed system, check or runtime test.
- Changing `just eval-identity` or the iets oracles.
- Editing the `preferences-nix-checks-architecture` skill. Its procedure stays the reference; the recipe implements it.
- Building anything. Both tools instantiate derivations only.
- Deciding the candidate fifth principle or the `controller` tag rename.

## Decisions

### D1: A separate cross-revision oracle; `eval-identity` stays as is
- **Choice**: new `just drv-diff before after [allow] [systems] [vm-systems]`, backed by a flake app `drv-diff` (`modules/apps/drv-diff.{nix,sh}`), the pattern of `apps/nix-eval-jobs-identity`. `modules/README.md:88` gains one sentence saying `eval-identity` is single-revision and pointing to `drv-diff`.
- **Rationale**: the two oracles vary different things (evaluator vs revision). Folding them into one recipe would make each run pay for both.
- **Alternatives considered**: inline bash in the justfile like `check-ifd` (`justfile:405-433`). Rejected: an app pins `jq`, `git`, `diffutils` and the stock Nix through `runtimeInputs`/`runtimeEnv`, so the result does not depend on the caller's PATH, where `nix` may be iets' classic mode.

### D2: The dumped output sets
- **Choice**: at each revision, maps from attribute name to drvPath for
  1. `nixosConfigurations.<h>.config.system.build.toplevel`;
  2. `darwinConfigurations.<h>.config.system.build.toplevel`;
  3. `homeConfigurations."<name>".activationPackage`;
  4. `checks.<s>` for `s` in `systems` (default `x86_64-linux aarch64-darwin`, nixbot's systems);
  5. `vmTests.<s>` for `s` in `vm-systems` (default `x86_64-linux aarch64-linux`).
  Attribute names are read from each revision, so an added or removed host, home or check is a key-set difference. With the default systems this is seven maps: three configuration maps, two `checks` maps and two `vmTests` maps.
- **Rationale**: these are what is deployed or gated. `vmTests` is included because register-fleet-obligations declares an intended difference in the runtime tests, which the oracle must see to confirm.
- **Alternatives considered**: every system the flake declares, as the skill suggests. Rejected for the default: `checks.aarch64-linux` is built by nothing and would double the run. It stays available through the parameter.

### D3: Per-attribute evaluation, nothing built
- **Choice**: sets 1–3 are evaluated one attribute per process, `$NIX_STOCK eval --raw '<ref>#<attr>.drvPath'`, with `--option eval-cache false`; sets 4–5 through `nix-eval-jobs` with `--workers` (default 2), `--max-memory-size` (default 4096), `--option allow-import-from-derivation false`, `--option eval-cache false`, the arguments `nix-eval-jobs-identity.sh:56-62` already uses. `--force-recurse` is passed for `checks` only, as there; `vmTests.<s>` values are derivations at the top level.
- **Rationale**: one process over all toplevels would keep every host in one heap (stibnite alone keeps 2.2 GB, `cross-host-eval-cost-b`); `nix-eval-jobs` isolates a failing attribute as an `error` line instead of aborting.
- **Boundary**: vendored-versus-first-party. `nix-eval-jobs` is vendored; the oracle depends only on its documented JSON lines (`attr`, `drvPath`, `error`), the fields the existing identity app projects.
- **Alternatives considered**: `nix eval --json --apply 'mapAttrs …'` per set, as the skill shows. Kept as the reference, rejected as the implementation for memory.

### D4: Stock evaluator, recorded
- **Choice**: `NIX_STOCK = lib.getExe (flake.lib.fleetNix pkgs)` as in `apps/nix-classic-identity.nix`; `nix-eval-jobs-stock` from PATH where present, else `nix-eval-jobs`. The dump header records both resolved paths (`readlink -f`) and versions.
- **Rationale**: the `nix` a person types on stibnite can be iets' classic mode, which falls back on `--apply`; the comparison must hold the evaluator fixed across both revisions. World assumption A313.
- **Alternatives considered**: accepting an evaluator argument. Deferred; nothing needs it yet.

### D5: Revisions by commit through `git+file`
- **Choice**: each side is `git+file://<repo>?rev=<commit>`, names resolved with `git rev-parse --verify <rev>^{commit}`. jj users pass `$(jj log -r <rev> --no-graph -T commit_id)`; the recipe's comment says so.
- **Rationale**: reads exactly the committed tree (A311); a dirty working copy or untracked file cannot leak into either side. Matches `nix-eval-jobs-identity.sh:53`.
- **Alternatives considered**: `after` defaulting to the working tree. Rejected: a path flake skips untracked files, so a new module would silently vanish from the candidate.

### D6: The allow-list
- **Choice**: a text file, one entry per line: `<set>.<attr> <expect>  # reason`, where `<set>` is `nixos`, `darwin`, `home`, `checks.<s>` or `vmTests.<s>`, and `<expect>` is `changed`, `added`, `removed` or `may-change`. Each entry names one exact attribute path. Blank and `#` lines are ignored. Each change keeps its file as `drv-delta.txt` in its change directory.
- **Outcome**: exit 0 when every difference is allowed and every `changed`/`added`/`removed` entry happened; exit 1 otherwise; exit 2 on a usage error or when a dump could not be produced. An entry naming an attribute absent at both revisions is a usage error.
- **Rationale**: a declared difference that does not happen means the change does not do what it says, which is as much a finding as an undeclared one. `may-change` is for effects the author cannot predict.
- **Alternatives considered**: glob patterns. Rejected: a glob over `checks.*` would hide exactly the undeclared differences the oracle exists to find.

### D7: Errors and evidence
- **Choice**: an attribute failing to evaluate at both revisions is listed and does not fail; failing at one revision is a difference. Dumps, the report and the header go to `logs/drv-diff-<before12>-<after12>-<UTC>/`; the report prints counts per set and every difference.
- **Rationale**: matches `nix-eval-jobs-identity`; the logs directory is where this repository keeps run evidence.

### D8: The cost protocol
- **Choice**: `just eval-cost attr before after [runs=2] [mode=drv]` (app `eval-cost`): one untimed warm-up evaluation per revision so the flake's store copy is not timed (base-flake's 113 s wall was copy, not evaluation), then `runs` rounds of before, after, each a fresh `$NIX_STOCK eval` with `NIX_SHOW_STATS=1`, `NIX_SHOW_STATS_PATH`, `--option eval-cache false`. `mode=drv` evaluates `.#.<attr>.drvPath`; `mode=keys` evaluates `.#.<attr>` with `--apply builtins.attrNames`. Each run records wall time, `cpuTime`, `gc.totalBytes`, `nrThunks`, `envs.number`; the header records the evaluator path and version, host, memory, and whether another `nix`/`nix-eval-jobs` process was running. Output: `logs/eval-cost-<label>-<UTC>.{log,jsonl}`.
- **Rationale**: the skill's A/B/A/B discipline (`evaluation-cost.md:77-88`). Thunks and allocation are reproducible for one expression and evaluator (A312: 24,376,302 thunks in both stibnite runs), so they separate on one round; CPU and wall need the interleaving.
- **Alternatives considered**: reusing the 2026-11-26 logs as the baseline. Rejected: no evaluator or command recorded.

### D9: Baselines in a committed note
- **Choice**: `docs/notes/development/eval-cost-baselines.md`, one table row per measurement (date, commit, host, evaluator and version, attribute, mode, every run's figures), first filled with `darwinConfigurations.stibnite` and `nixosConfigurations.cinnabar` toplevels and the `checks.x86_64-linux` key set, measured with `just eval-cost` at the same commit on both sides; the 2026-11-26 cross-host figures follow in a separate "reference, not comparable" table. The principles document links to it.
- **Rationale**: `logs/` is gitignored (`.gitignore:59`).

### D10: Folding the audit into the principles document
- **Choice**:
  - remove O07, O08 and O13 (resolved, and O07/O08 landed with `migrate-mesh-to-tincr`'s registry readers more than one merge cycle ago); mark O14 and O16 resolved with the commits that resolved them, found with `git log -S`, for removal after the next merge per `:460-462`;
  - correct O06's severity note: an unimported module is never evaluated;
  - mark the `mkMachine{Darwin,NixOS}` cluster (`:111`) superseded by derivation from a typed host record plus aspects;
  - fold the open audit findings into the existing entries they extend (O01, O02, O04, O05, O09, O10, O15, O19, O20, O21, O22) and add the ones with no entry, each tagged with its principle or with "no principle" where P1–P4 do not derive it;
  - replace "Planned decomposition into beads epics and PRs" and "Status of preceding nix-0pd epic" with "Planned decomposition as OpenSpec changes": the project's seven changes and their order (see Migration Plan), each with the opportunities it closes; the nix-0pd history becomes one paragraph without the `bd` command;
  - replace the remaining tracker references (`:6-7`, `:417`, `:475`);
  - add "Candidate principle P5: composition is order-free and demand-driven; a module never reads another entity's evaluated config", with its evidence (cross-host evaluated-config reads, unkeyed dual-exported modules, deploy-record order resting on import order), marked as proposed and awaiting the operator, per `:466-469`.
- **Rationale**: the document is the planning entry point the other changes cite; the update protocol is the document's own.
- **Alternatives considered**: inserting P5 into "The four principles". Rejected: revision is the operator's call.

### D11: ADR amendments
- **Choice**: each of ADR-0018, -0019, -0020 gains a status line `- **Amended**: 2026-11-<dd>, see Amendment` and a closing `## Amendment (2026-11-<dd>)` section before References that states what changed and where it lives now; the original text stays.
- **Rationale**: an ADR records a decision as made; no ADR in the directory has an amendment yet, so this sets the convention.
- **Boundary**: source-versus-delivered. The ADRs' source is `packages/docs/src/content/docs/…`; the docs site is built from it, so the source is edited, never the built page.

### D12: README corrections
- **Choice**: `modules/README.md:88` adds that `eval-identity` compares evaluators at one commit and that a refactor across commits uses `just drv-diff`. `modules/home/README.md:32` reads that Den is `github:denful/den`, which drupol's infra uses.

### D13: A base allow-list for checks built from the whole flake source
- **Choice**: `modules/apps/drv-diff-base-allow.txt`, in the D6 format, holds one `may-change` entry per dumped check whose derivation takes the whole flake source as an input (`checks.<s>.gitleaks`, from `src = self` at `modules/checks/security.nix:25`, and any others task 1.4 finds, such as treefmt-nix's `checks.<s>.treefmt`, each with its file and line as the reason). The app reads it on every run and merges it with the `allow` argument; a change's entry that repeats a base entry is a usage error (exit 2). Per-change `drv-delta.txt` files never list these checks.
- **Rationale**: such a check's drvPath changes on every commit, whatever the commit touches, so every change would otherwise declare it, and seven changes would carry the same lines. Owning it once in the oracle keeps the declaration with the cause and keeps each change's file to the differences that change makes.
- **Boundary**: first-party-versus-vendored. treefmt-nix supplies `checks.treefmt` and its default project root; the base list depends only on the resulting attribute name, confirmed by task 3.5 rather than by reading the vendored module.
- **Alternatives considered**: filtering those checks' sources so their derivations depend only on the files they scan. Out of scope: it changes checks, which this change does not. `changed` entries instead of `may-change`: rejected, since 3.1's self-identity run compares a commit with itself, where nothing changes.

## Risks / Trade-offs

- [Risk] A full dump is slow: 30 configuration processes and two `nix-eval-jobs` runs per side, likely over 5 minutes per side. → Mitigation: the first run's duration is recorded in the baselines note; per the fleet's test-size policy a run expected over 5 minutes is announced with its duration, what it proves and what waits on it.
- [Risk] Darwin builds are unsandboxed by default, so the same derivation path does not guarantee the same darwin build. → Mitigation: stated in the interface trust boundary and A310; the oracle claims recipe identity only.
- [Risk] Outputs outside the seven maps change unseen (`flake.lib`, clan inventory data, terranix). → Mitigation: stated in the trust boundary; the structure pins cover inventory names and classes; a change touching those values adds its own check.
- [Risk] A whole-source check missing from the base allow-list makes every later change fail with an undeclared difference; an extra entry hides a real difference in a check that does not take the whole source. → Mitigation: task 3.5's whole-source mutant must report exactly the base list's attributes.
- [Risk] `vmTests.aarch64-linux` may fail to instantiate on a host with no aarch64-linux builder if any test uses import-from-derivation. → Mitigation: IFD is disallowed, so such a test reports an error at both revisions, which is listed and does not fail.
- [Trade-off] Per-attribute processes repeat the flake load (1.6 s CPU each). Accepted for bounded memory.
- [Trade-off] Adding the two apps changes `apps.<system>`, which no dumped map contains; the change's own oracle run is therefore expected to show only the base allow-list's whole-source checks.
- [Risk] An archive-time conflict on `world-assumptions`' grounded-vocabulary requirement, which this and several active changes each modify in full. → Mitigation: the delta copies the corpus requirement and only appends rows and adds `evaluator` to the three-sense list in the scenario. The `check` row is the same row declare-test-size-classes adds, word for word: whichever archives second keeps one row, not two. At archive, rows other changes added since (for example declare-test-size-classes' `run` sense, which moves the scenario's count from twenty-six to twenty-seven) are merged by hand before syncing, and later changes in the landing order rebase their copy onto this one's archived table.

## Migration Plan

N/A for deployment: no host's configuration changes.
Order within the project, by landing and by archive: establish-refactor-oracle, stop-reading-other-hosts-configs, type-the-fleet-host-registry, register-fleet-obligations, declare-host-user-relations-once (CAM-130), compose-hosts-from-cohesive-aspects, seam-secrets-away-from-clan-vars (CAM-129). declare-host-user-relations-once depends on stop-reading-other-hosts-configs: `modules/system/ssh-known-hosts.nix` is the last system module that takes `flake`, and stop-reading-other-hosts-configs removes that. Each change runs `just drv-diff` against its base with its own `drv-delta.txt` after rebasing onto its predecessor.
Rollback: revert the commits; nothing deployed depends on them.

## Open Questions

- **Stibnite's `controller` tag.** `controller` names both the deploy controller (stibnite) and the ZeroTier controller. Renaming stibnite's to `deployer-workstation` is recommended only if the operator's `clan machines update --tags controller` habits do not rely on it. Recorded for the operator; not decided here.
- **Candidate principle P5.** Accept, reject or reword. Until decided, the findings it would derive stay tagged "no principle".
- **Strictness of `may-change`.** Whether an undecidable expected difference should instead block until measured. Default here: allowed and reported.
