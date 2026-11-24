## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: First-party skills conform to the Agent Skills specification

Every first-party skill's `SKILL.md` frontmatter SHALL parse as YAML, its `name` SHALL equal the skill's directory name, and the skill SHALL otherwise pass the Agent Skills specification's structure rules.
Frontmatter fields beyond the specification MAY be present, and files MAY sit at the skill's root.

#### Scenario: A skill's name differs from its directory

- **WHEN** a commit gives a first-party skill a frontmatter `name` other than its directory name
- **THEN** the commit is refused before it reaches the main branch

#### Scenario: A skill's frontmatter does not parse

- **WHEN** a commit leaves a first-party skill's frontmatter unparseable as YAML
- **THEN** the commit is refused before it reaches the main branch
