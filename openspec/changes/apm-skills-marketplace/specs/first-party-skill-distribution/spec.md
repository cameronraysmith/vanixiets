## ADDED Requirements

### Requirement: Build-time apm composition of first-party skills

First-party skills SHALL be authored as apm packages under `modules/home/ai/plugins/<pkg>/` (each with `apm.yml`, `plugin.json`, and `.apm/skills/<skill>/`), and a nix build derivation SHALL run apm at build time to compose them into per-harness flat skill trees that nix store-pins.
apm MUST NOT run at any time other than inside the nix derivation.

#### Scenario: deterministic offline build

- **WHEN** the compose derivation runs `apm install --root $out` with HOME and `APM_CACHE_DIR` isolated, `APM_E2E_TESTS=1` set, and all dependencies declared as local absolute paths at the root consumer manifest
- **THEN** the resolve and compose complete with no network access, and repeated builds produce byte-identical `$out` (the only nondeterministic value, `apm.lock`'s `generated_at`, is stripped or not harvested)

#### Scenario: per-harness flat deployment

- **WHEN** the build composes the targets `agent-skills,claude,codex,hermes`
- **THEN** `$out` contains a flat skill tree per harness (for example `$out/.claude/skills/<name>/SKILL.md`) with bare skill names and no `plugin:` prefix

---

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
