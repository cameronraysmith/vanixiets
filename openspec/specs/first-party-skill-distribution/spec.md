# first-party-skill-distribution Specification

## Purpose
TBD - created by archiving change apm-skills-marketplace. Update Purpose after archive.

## Requirements

### Requirement: Build-time apm composition of first-party skills

First-party skills SHALL be authored as apm packages under `modules/home/ai/plugins/<pkg>/`, each holding `apm.yml` and `.apm/skills/` or `.apm/instructions/` and no other manifest, and a nix derivation SHALL run apm at build time to compose them into flat per-harness skill trees that nix store-pins.
apm MUST NOT run at any time other than inside the nix derivation.
The derivation SHALL fail when a composed skill differs from its source or from its recorded hash.

**Relies on**: A213.

#### Scenario: deterministic offline build

- **WHEN** the compose derivation runs `apm install --root $out --no-frozen` with HOME and `APM_CACHE_DIR` isolated, `APM_E2E_TESTS=1` set, and all dependencies declared as local paths at the root consumer manifest
- **THEN** the resolve and compose complete with no network access, and repeated builds produce byte-identical `$out` (the lock's `generated_at` and `apm_version` are stripped and `.apm-local/installation` is removed)

#### Scenario: per-harness flat deployment

- **WHEN** the build composes the targets `agent-skills,claude`
- **THEN** `$out` contains a flat skill tree per target (for example `$out/.claude/skills/<name>/SKILL.md`) with bare skill names and no `plugin:` prefix, and the two trees are identical

#### Scenario: an apm release changes the composed trees

- **WHEN** an apm release deploys a first-party skill differently from its source, or changes a remote skill's content
- **THEN** the build fails naming the skill, before any host receives the changed tree

### Requirement: Immutable delivery and always-succeeds activation

The composed `$out` SHALL be symlinked into each harness as immutable store paths, and activation (`darwin-rebuild switch`) MUST NOT run apm or depend on any network or external schema, so activation always succeeds.

#### Scenario: immutable store symlinks retained

- **WHEN** home-manager links the composed trees into `~/.claude/skills`, `~/.config/opencode/skill`, `~/.hermes/skills`, and (via the real-file copy) the codex `~/.agents/skills`
- **THEN** the delivered skill files are read-only nix store paths and the codex real-file-copy workaround is preserved

#### Scenario: always-succeeds activation with no apm at switch

- **WHEN** `darwin-rebuild switch` runs with no network connectivity or an upstream apm schema change
- **THEN** activation succeeds because apm is never invoked at activation time

---

### Requirement: Flat skill name preservation

The composition SHALL preserve flat skill names so that existing absolute `@`-autoload skill references in `modules/home/tools/agents-md.nix` continue to resolve unchanged.

#### Scenario: agents-md.nix references unchanged

- **WHEN** the ~104 first-party skills are restructured into apm packages and composed flat
- **THEN** the ~70 absolute `@`-autoload references in `modules/home/tools/agents-md.nix` resolve to the same flat skill paths without modification

---

### Requirement: Distinct first-party policy and upstream mechanism skills

The composed corpus SHALL expose `git-stacked-pr-integration` and `mergify-stack` as distinct flat skill names.
The first-party skill SHALL retain the fleet's policy, role contracts, VCS routing, and base landing evidence while referring to the upstream skill for Mergify mechanism detail.
Adding `mergify-stack` MUST NOT retire, rename, replace, or overwrite `git-stacked-pr-integration`.

This interface establishes that both named skill documents are present and separately addressable in the composed output.
It does not establish which skill a harness selects or whether a consumer follows either document correctly.

#### Scenario: Both stacked-landing skills are composed

- **WHEN** the version-control-and-forge package and its pinned Mergify dependency are composed for the `agent-skills` and `claude` targets
- **THEN** the output contains independently resolvable `git-stacked-pr-integration` and `mergify-stack` skill documents under both target trees

#### Scenario: Evidence and routing text retain distinct provenance

- **WHEN** `git-stacked-pr-integration` is revised to refer to the upstream Mergify mechanism
- **THEN** its base statement recording the landing of PRs 2738, 2739, and 2740 remains present verbatim
- **AND** adjacent prose limits that evidence to the observed fast-forward landing and GitHub reachability rather than Mergify authoring or publication
- **AND** the transcript-prescribed soft routing statement between Git-native and `.jj/` repositories is added verbatim by this change rather than described as pre-existing text

#### Scenario: Upstream skill is added

- **WHEN** `mergify-stack` becomes available in the composed corpus
- **THEN** `git-stacked-pr-integration` remains available under its existing flat name rather than being removed or aliased to the upstream name

### Requirement: First-party skills conform to the Agent Skills specification

Every first-party skill's `SKILL.md` frontmatter SHALL parse as YAML, its `name` SHALL equal the skill's directory name, and the skill SHALL otherwise pass the Agent Skills specification's structure rules.
Frontmatter fields beyond the specification MAY be present, and files MAY sit at the skill's root.

#### Scenario: A skill's name differs from its directory

- **WHEN** a commit gives a first-party skill a frontmatter `name` other than its directory name
- **THEN** the commit is refused before it reaches the main branch

#### Scenario: A skill's frontmatter does not parse

- **WHEN** a commit leaves a first-party skill's frontmatter unparseable as YAML
- **THEN** the commit is refused before it reaches the main branch
