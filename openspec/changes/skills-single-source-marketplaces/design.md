## Context

### Current state

The skills library is 22 plugin groups under `modules/home/ai/plugins/<group>/`: 18 hold 126 first-party skills under `.apm/skills/`, and the four `agent-context-*` groups hold only `.apm/instructions/`.
Four groups declare remote apm dependencies that add 51 skills from 10 repositories, so the composed corpus is 177 skills, indexed in `pkgs/by-name/apm-skills-compose/skills.json`.
Each group carries a hand-written `apm.yml` and a root-level `plugin.json`; the root `apm.yml` lists the 22 packages again in its `marketplace:` block and lists 18 of them a third time as `#main` dependencies; a hand-run `apm pack` writes `.github/plugin/marketplace.json`.

### History

- Until 2026-06 the corpus was a flat tree under `modules/home/ai/skills/src/`, copied into the store by pure Nix and linked into each harness.
- The `apm-skills-marketplace` change (archived 2026-08-27) chose apm at build time (its D1): apm runs only inside a derivation, Nix pins the output, activation never runs apm. The reasons were apm's dependency graph and lock, its multi-harness deployment, and publishing the same packages as an apm marketplace.
- apm has since broken the build nine times, each found when an `llm-agents` bump moved apm:
  1. 2026-06-29 (da6263eb6): a formal-spec `@alias` dev dependency blocked `apm install`.
  2. 2026-06-30 (11b1f3c77): offline superpowers needed a faked git-cache pre-warm.
  3. 2026-09-02 (3443101f4): apm 0.29.0 deployed zero skills silently; the 18 root `plugin.json` files gained `"skills": ["./.apm/skills"]`.
  4. 2026-09-03 (0d5541887): a link-rewrite loop dropped a skill from the lock ledger.
  5. 2026-09-07 (855eba8a5, edc85b404): apm 0.29.1 rejected gh-stack's `SKILL_BUNDLE`; local patch, re-pin, relock for 0.30.0.
  6. 2026-09-17 (424410350): apm 0.31 changed its cache seeds.
  7. 2026-09-30 (83b45e2df, a89b5e81c): apm 0.32 `--update` kept stale literal pins.
  8. 2026-11-18 (d5208728e, 146c95918): apm 0.36 changed its cache layout and refused superpowers' hooks; the download was redesigned as one fixed-output derivation (`pin-apm-dependencies-in-apm-yml`).
  9. 2026-11-23: apm 0.38.0 changed the download hash (lockfile v4) and deployed mattpocock/skills whole into `.agents/plugins/`, so `tdd` vanished from the flat trees.
- An unmerged prototype branch, `claude-marketplace` (d68d40ed0, 2026-11-20), generated `.claude-plugin/marketplace.json` and 18 per-group `.claude-plugin/plugin.json` with a sync script and a drift check.

### Why apm stays in the build

The operator decided on 2026-11-23 (decision S1) to keep apm in the build and not to pin it apart from `llm-agents`.
The build is the only place where this repository installs its own packages the way an apm consumer does: every break above would otherwise have reached R2 users unseen, while it reached our build first.
A pure-Nix copy would reproduce the 126 first-party skills exactly, but it would need a hand-written resolver for the 51 remote skills (mattpocock's plugin list, unslop's whole root, apm's licence handling) and would stop telling us when apm's behaviour changes.
The cost is that each bump can need an adaptation; this change makes such a change fail loudly in the build (D7) instead of silently changing the delivered corpus.

### Requirements and the world they rest on

| Req | Statement | Rests on (observed, not promised) | Breaks if it fails | Check that shows it |
|---|---|---|---|---|
| R1 | Each host receives the composed corpus through home-manager from an offline build that runs apm | A213 (an `apm.yml` with `.apm/` deploys `.apm/skills` flat without a plugin manifest), A214 (a dependency with a Claude plugin manifest and a skill list deploys flat), A215 (apm requires `version` in a package manifest), A136-A140 restated for 0.38 | the build fails or emits a different tree | compose tree oracle (G1), mattpocock list rule (G2) |
| R2 | An apm consumer who registers `cameronraysmith/vanixiets` can install every group and gets flat skills | A216 (probe order and format tolerance of apm's marketplace client), A213 | installs fail, or deploy whole plugins instead of skills | offline consumer check (G5a), remote validate run (G5b) |
| R3 | A Claude user who adds `cameronraysmith/vanixiets` can install each of the 18 skill groups and gets all its first-party skills, following new commits | A217 (Claude Code installs a manifest-free entry whose skills sit in `./.apm/skills`), A218 (the desktop app does the same), A219 (no version means commit-hash versioning) | plugins install with zero skills, or never update | Claude install-and-count check (G4) for Claude Code; operator re-test for the desktop app |

A217-A219 rest on undocumented behaviour: Claude's documentation neither allows nor forbids a hidden directory in `skills`, and documents the manifest-free entry only for Claude Code.
They are recorded with the date and version of observation (Claude Code 2.1.330, the desktop app on 2026-11-23), not as promises.

### Stakeholders

The operator, who bumps `llm-agents` and reviews regenerated files; the fleet's hosts (R1); apm consumers (R2); Claude users (R3).

## Goals / Non-Goals

**Goals:**
- One authored source per fact about a group, with every vendor-specific file either deleted or generated under a check.
- Each group directory holds only `apm.yml` and its `.apm/` content.
- Both marketplace files generated from one source by one derivation, with a check that fails on drift.
- Standing regulators that fail on each known apm or Claude failure mode, each demonstrated by a mutant.
- Stages that land independently, the first being the 0.38 adaptation already in the workspace.

**Non-Goals:**
- Moving skills from `.apm/skills/` to `skills/` (D11).
- Delivering the 51 remote skills to Claude users (D12).
- Versions or release tags beyond commit hashes; the `path-scope-plugin-releases` change owns plugin tags.
- Relocking the root `apm.lock.yaml` to lockfile v4 (apm <= 0.36.1 refuses v4; relock when every machine runs >= 0.37).
- Delivering the composed `.claude/settings.json` hooks, or changing home-manager's skill delivery.

## Decisions

### D1: land the apm 0.38 adaptation first, unchanged in shape

- **Choice**: stage 1 is the `llm-agents` bump, mattpocock's explicit 25-name `skills:` list with the new `apmDepsHash`, and the `apm-marketplace-validate` fix that recognises an instructions group by the `.instructions.md` fragments apm stages under `apm_modules/`. No layout change rides along.
- **Rationale**: E4 showed all 177 skill directories byte-identical to `main`'s on both systems and all 32 apm-touching x86_64-linux checks passing. The validate fix passes 22/22 under apm 0.38.0 and 0.36.0. Boundary: vendored-versus-first-party (the list selects vendored skills; no first-party file changes).
- **Alternatives considered**: `skills: ["*"]`, which apm documents but 0.38.0 rejects ("Skill selection matched no available skills"); a per-dependency `targets:` without claude, which would drop mattpocock from `.claude/skills`.

### D2: each group holds `apm.yml` and `.apm/` only

- **Choice**: delete the 22 root `plugin.json` files.
- **Rationale**: apm types a group `apm_package` because its `apm.yml` is "eligible" (it has `.apm/`), and that rule precedes any plugin-manifest rule, so the file has no effect on install. Verified on 2026-11-23 with apm 0.38.0: compose from a scratch flake copy without the files, 177 skills per tree, `nix hash path` equal to `main`'s; the download rebuilt to the same hash; a third-party consumer got flat, byte-identical skills; `apm pack` wrote the same file. No code reads them. Boundary: source-versus-delivered (source files removed, delivered trees unchanged).
- **Alternatives considered**: keeping the files as Claude manifests. Claude reads only `.claude-plugin/plugin.json`; it did read the root file's version (undocumented), which is a reason to delete it, not to keep it.

### D3: versions live only where apm requires them

- **Choice**: each group `apm.yml` keeps `version: 0.0.0`; the root `marketplace.packages[].version` entries are deleted; the Claude marketplace file carries no version.
- **Rationale**: apm 0.38.0 refuses a dependency whose `apm.yml` lacks `version` (verified). `apm pack` inherits the group's version, and the generated file is byte-identical without the root entries (verified). Claude ranks plugin manifest, then entry, then commit hash; with none, a git marketplace installs at the commit hash and updates with it (observed `6832a512c2fe`); with `0.0.0` every install pins. Nothing of ours needs `0.0.0` beyond apm's required field.
- **Alternatives considered**: a real version per group; out of scope (Non-Goals) and, for Claude, it would freeze installs until bumped.

### D4: one authored source per fact

- **Choice**: the group `apm.yml` owns name, description and version; the directory tree owns each group's path and whether it carries skills (`.apm/skills/` present); the root `apm.yml` `marketplace:` block owns the marketplace's owner and the list of published groups (name and source). Group discovery is computed once, in pure Nix, and shared by the compose, the download, home-manager and the generator.
- **Rationale**: the published list stays apm's native authoring format, so `apm pack` and `apm marketplace check` work on it unchanged; the generator asserts that the list equals the set of group directories and that each group's `apm.yml` name equals its directory, so the one remaining duplicate cannot drift. Three copies of the discovery predicate (`package.nix`, `deps.nix`, `modules/home/ai/skills/compose.nix`) become one.
- **Alternatives considered**: deriving the published list from the tree and dropping it from `apm.yml`; rejected because `apm-marketplace-validate` and the two apps' identity guards read it, and a group present in the tree but not yet published is a legitimate state the check can allow explicitly.

### D5: one generator writes both marketplace files

- **Choice**: a derivation `skills-marketplace` takes the root `apm.yml` and the group `apm.yml` files (a fileset, no skill content), writes a private copy of the root manifest without `dependencies:` and `compilation:` and with `outputs: {claude, copilot}`, runs `apm pack --offline`, keeps the Copilot output as `.github/plugin/marketplace.json`, and passes the Claude output through one jq filter that keeps the skill-bearing groups, deletes `version`, adds `skills: ["./.apm/skills"]` and `strict: false`, and sets `metadata.description` from the root description. `just agents-marketplace` copies both into the tree; both are committed.
- **Rationale**: apm cannot emit the Claude file alone: its Claude mapper has a fixed field set, the package-entry schema refuses `skills` and `strict`, an output profile accepts only `path`, and dropping `version` would need a version-free group manifest that apm refuses (read in apm 0.38 `marketplace/output_mappers.py`, `yml_schema.py`, `output_profiles.py`). Running apm in the generator means an apm format change shows up as drift on the next bump, which is what apm consumers would see. Both files are read from git by their consumers, so they must be committed. Boundary: source-versus-delivered (generated files committed in source, kept equal by G3).
- **Alternatives considered**: (a) the prototype's sync script with 18 per-group `.claude-plugin/plugin.json`: 19 more generated copies, unnecessary since S2; (b) a pure jq/yq generator: re-implements apm's mappers and hides apm format changes; (c) packing the real root manifest: its `dependencies:` block makes `apm pack` build a bundle from `apm.lock.yaml`, which fails before an install, and no flag skips the bundle.

### D6: the apm-facing file becomes a real Copilot-profile file; the 18 self-dependencies stay

- **Choice** (operator decision S3, 2026-11-23): `.github/plugin/marketplace.json` is kept, generated, and switches from Claude-format to apm's real Copilot profile (22 groups). The root `dependencies:` block stays for `apm-skills-install`; only the generator strips it. The identity guards in `apm-skills-install.sh`, `apm-context-compile.sh` and `apm-marketplace-validate.sh` stop keying on `marketplace.output` (which goes away) and key on the manifest `name` and the presence of `marketplace.packages`.
- **Rationale**: apm probes `marketplace.json`, then `.github/plugin/`, then `.claude-plugin/`. A Copilot-profile file there registered 22 groups and installed skill and instructions groups under apm 0.38.0 and 0.36.0 (verified). The Claude file alone also works for apm, but carries only the 18 skill groups, so apm users would lose the four instructions groups.
- **Alternatives considered**: dropping `.github/plugin/marketplace.json` (rejected by the operator, S3); moving the self-dependencies to a separate manifest, which changes a working recipe for no gain.

### D7: regulators, each with the mutant it must fail on

| # | Regulator (placement) | What it asserts | Mutant that must fail it |
|---|---|---|---|
| G1 | Compose tree oracle, inside the `apm-skills-compose` build (both systems, as today) | names in both trees equal `skills.json`; each of the 126 first-party skills equals its `.apm/skills/<name>` source byte for byte (`diff -r`); each of the 51 remote skills has the `nix hash path` recorded for it in `skills.json`; `.claude/skills` equals `.agents/skills`. Replaces the 26 hand-picked path assertions. | edit one byte of a deployed remote skill (the 0.36 LICENSE-carrying class); remove a first-party file from the deployed tree (the link-rewrite class); deploy mattpocock whole (the 0.38 class, already caught by names) |
| G2 | mattpocock list rule, inside the `apm-deps` fixed-output build (network allowed; output unaffected), modelled on the superpowers rule | the `skills:` list equals the basenames of `skills[]` in `.claude-plugin/plugin.json` at the declared commit | delete one name from the list; bump the ref to a commit whose manifest adds a skill |
| G3 | Marketplace drift check `skills-marketplace-drift` (x86_64-linux only) | the committed `.claude-plugin/marketplace.json` and `.github/plugin/marketplace.json` equal the generator's output; the published list equals the group directories | change a group description without regenerating; add a group directory without listing it |
| G4 | Claude install check `claude-marketplace-install` (x86_64-linux only; offline, verified in the magnetite sandbox with Claude Code 2.1.330) | `claude plugin validate` passes; in an isolated config directory every entry installs and lists exactly its group's `.apm/skills` children | `skills: [".apm/skills"]` (validate fails); a `source` naming a missing directory (validate passes, install fails); an entry without `skills` (installs with zero skills) |
| G5a | Offline apm consumer check `apm-marketplace-consumer` (x86_64-linux only; verified in the sandbox) | a bare repository built from the source, reached through a `url.insteadOf` rewrite of an `https://` URL, registers 22 groups; the groups without remote dependencies and one instructions group install; first-party skills land flat and byte-identical | a marketplace `source` with a typo; a group manifest that makes apm deploy it whole (a `.claude-plugin/` without `.apm/`) |
| G5b | Network consumer run: `just agents-marketplace-remote`, which runs `nix run .#apm-marketplace-validate -- --remote` (registers `cameronraysmith/vanixiets` at `main` from GitHub). The app is already in the house style: a `writeShellApplication` in `modules/apps/apm-marketplace-validate.nix` whose `text` is the sidecar `apm-marketplace-validate.sh`, like `obs-query` and `langfuse-query`; only the recipe is new. Later home: a nixbot effect on `main` (S3) | the real GitHub route installs all 22 groups, remote dependencies included | not a check; a failing run is reported by its log |
| G6 | `--no-frozen` on the compose's `apm install` (one-off proof, no standing check) | a `CI=true` in the builder cannot switch apm to frozen mode | without the flag, exporting `CI=true` in the build script fails ("declared in apm.yml but missing from apm.lock.yaml", observed in E4); with it, the build passes |
| G7 | `$out` reproducibility: delete `.apm-local/installation` (one-off proof) | `nix build --rebuild` of the compose reports no difference | without the deletion, `--rebuild` reports "may not be deterministic" (observed in E4) |

- **Rationale**: G1 turns E4's one-off oracle into a standing one: first-party content needs no committed data because its source is in the same derivation, and only remote skills need committed hashes, which change only when a ref or apm's normalisation changes, exactly the events to review. G6 and G7 get one-off proofs because no build environment sets `CI` and G1 already covers the skill trees; a standing check for them could name no failure that nothing else catches. Each mutant demo runs only its own case.
- **Alternatives considered**: hashes for all 177 skills in `skills.json` (every first-party edit would need an index regeneration); a separate tree-oracle check derivation (a second compose build per evaluation).

### D8: evaluation cost

- **Choice**: G3, G4 and G5a exist only under `checks.x86_64-linux`, keyed by literal names; G1 and G2 live inside existing derivations; the generator is a package on every system so `just agents-marketplace` builds locally on darwin, but no check evaluates it on darwin.
- **Rationale**: the generated files, the Claude install and the consumer install are system-independent, so a second system buys no evidence. No key depends on an evaluated configuration or package `passthru`; the shared group discovery is `builtins.readDir` over a source path, with no import-from-derivation.

### D9: stages

| Stage | Content | Lands when |
|---|---|---|
| 1 | D1 (three commits already in the workspace) plus the world-assumption restatements | now; R1 and R2 unchanged |
| 2 | G1, G2, G6, G7; shared group discovery | after 1; regulators exist before any layout change |
| 3 | D2 (delete 22 `plugin.json`), prose updates | after 2; G1 proves the trees unchanged |
| 4 | D3, D5, D6, G3, G4; the Claude file goes public | after 3 |
| 5 | G5a, G5b recipe, Claude-user docs, prototype branch retired | after 4 |

Each stage leaves `main` building and every published route working; stages 2 and 3 change no published file.

### D10: the prototype branch retires

- **Choice** (operator decision S3): once stage 4 merges, the operator deletes `origin/claude-marketplace`; its sync script, per-group manifests and drift check are superseded by D5 and G3.

### D13: the desktop fixture for the undocumented Claude behaviours

- **Choice** (operator decision S3): the public repository `cameronraysmith/skills-marketplace-test` (commit 2542b08 and its `sync-probe` follow-up) is kept as the fixture for A218 (the desktop app installs a manifest-free entry whose skills sit in `./.apm/skills`) and A219 (a version-free plugin follows commits). The operator re-tests after each Claude desktop release he installs, or when Claude's plugin documentation changes:
  1. In the desktop app, Customize > Plugins > Add marketplace, enter `cameronraysmith/skills-marketplace-test` (remove and re-add it if already present).
  2. Install each of the three layout plugins and confirm each shows all its skills (five, plus `sync-probe` after the follow-up commit).
  3. Push a one-line edit to one skill without any version change, run "Check for updates", and confirm the edit arrives.
  4. Record the app version, date and result in A218's and A219's Evidence; a failure voids the assumption (its scenario) and triggers the fallback D11.
- **Rationale**: G4 covers Claude Code in the sandbox, but no automated route reaches the desktop app.

### D11: skills stay under `.apm/skills/`

- **Choice**: no move to `skills/`.
- **Rationale**: the desktop app installed the hidden path (S2), Claude Code too (E3, X3); a move touches 126 directories and changes apm's package typing (`skill_bundle`, or `marketplace_plugin` with a Claude manifest, which 0.38 deploys whole). It stays the fallback if A217 or A218 fails.

### D12: remote skills are not carried into Claude plugins

- **Choice**: Claude users get the 126 first-party skills; the plugins README tells them to install superpowers from `claude-plugins-official` and names the other upstream repositories.
- **Rationale**: a Claude plugin's `dependencies` name whole plugins in a marketplace, optionally another marketplace behind `allowCrossMarketplaceDependenciesOn`, with semver ranges resolved against git tags (Claude Code docs, `plugin-dependencies.md:31-52,85-110`); they cannot select 15 of superpowers' skills or a skill subdirectory of a repository that is not a Claude marketplace. apm 0.38's native-plugin route deploys into an apm consumer's project, not into a Claude marketplace. A `git-subdir` entry per remote skill directory would be possible (`marketplace-reference.md:140-145`) but re-publishes others' work under our marketplace.

## Duplication before and after

| Fact | Before (hand-kept unless noted) | After |
|---|---|---|
| group name | directory; group `apm.yml`; group `plugin.json`; root `packages[]`; root `dependencies` (18); `.github` file (hand-run `apm pack`); `apm.lock.yaml` (generated) | directory; group `apm.yml`; root `packages[]` (asserted equal by G3); root `dependencies` (18, unchanged); two generated files (G3); `apm.lock.yaml` |
| version `0.0.0` | group `apm.yml`; `plugin.json`; root `packages[]`; `.github` file | group `apm.yml` only (apm requires it); inherited into the `.github` file; absent from the Claude file |
| description | group `apm.yml`; `plugin.json`; `.github` file | group `apm.yml`; generated copies |
| source path | root `packages[]`; `.github` file | root `packages[]`; generated copies |
| skill container `./.apm/skills` | 18 `plugin.json` | one literal in the generator |
| skill-bearing group set | three `readDir` predicates | one shared predicate |
| Claude marketplace | prototype: sync script, 18 generated `.claude-plugin/plugin.json`, generated marketplace file, drift check | one generated file, G3, G4 |
| kept equal by | `apm-marketplace-validate` (manual) compares names only | G3 and G4 (flake checks), G1 |
| hand-kept vendor-specific files | 22 `apm.yml` + 22 `plugin.json` + root `apm.yml` + one hand-regenerated JSON = 46 | 22 `apm.yml` + root `apm.yml` = 23; two generated |

## Risks / Trade-offs

- [Risk] Claude stops honouring a hidden `skills` path or the manifest-free entry (A217, A218, undocumented) → Mitigation: G4 catches it for Claude Code on each `llm-agents` bump; the desktop app has no automatic check, so the operator re-tests with the fixture (D13) after app updates; fallback D11.
- [Risk] An apm bump changes the marketplace files' bytes → Mitigation: G3 fails; `just agents-marketplace` regenerates; the diff shows what apm consumers will see.
- [Risk] An apm bump changes a remote skill's bytes → Mitigation: G1 fails naming the skill; `just agents-skills-index` records the new hash after review.
- [Risk] G2 needs the manifest blob from a blob-less fetch; whether `git show` lazily fetches it inside the fixed-output sandbox is untested → Mitigation: fetch with blobs at depth 1 if the lazy fetch fails.
- [Trade-off] apm consumers see `version: 0.0.0` and Claude users see commit hashes → accepted until real versioning is in scope.
- [Trade-off] The Claude file omits the four instructions groups and the 51 remote skills → accepted (D12); the README says so.
- [Trade-off] `skills.json` changes shape (remote hashes) → one more regeneration on a remote ref bump, already part of the bump flow.

## Migration Plan

N/A for hosts: no stage changes a delivered skill tree (G1 proves it per stage), so activation picks each stage up as a no-op.
Publication order: stage 4's merge is the moment Claude users can add the marketplace; before it, the `.claude-plugin/` file does not exist on `main`.
Rollback: each stage is one revert; reverting stage 4 removes the Claude file (installed Claude plugins then fail to update, which is acceptable for a rollback).

## Operator decisions (S3, 2026-11-23)

- Stage 1 is approved to publish now, together with this proposal.
- `.github/plugin/marketplace.json` is kept, generated, in real Copilot format (D6).
- The networked marketplace test is `just agents-marketplace-remote` calling the existing flake app `apm-marketplace-validate` (G5b); a nixbot effect is its later home. No script outside the `modules/apps` pattern.
- `cameronraysmith/skills-marketplace-test` is kept as the desktop fixture (D13).
- The operator deletes `origin/claude-marketplace` after stage 4 (D10).

## Open Questions

- Q3. Keep the 18 `#main` self-dependencies (recommended; only `just agents-install` and `just agents-relock` use them) or retire `apm-skills-install` on hosts without home-manager?
