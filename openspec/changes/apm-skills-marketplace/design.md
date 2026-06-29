## Context

The fleet's first-party AI-agent skills (~104: 93 under `modules/home/ai/skills/src/core`, 11 under `src/claude`) are managed as a flat tree.
Nix builds that tree into the store and symlinks it into each harness: `~/.claude/skills`, `~/.factory/skills`, `~/.config/opencode/skill`, `~/.hermes/skills`, and `~/.agents/skills` for codex (a real-file copy, because codex skips symlinked `SKILL.md` leaves).
Third-party plugins are partially vendored as store-pinned Claude marketplaces in `pkgs/by-name/agent-plugins/`.
Harness-native plugin managers (Claude Code's marketplace) are not reproducible when they fetch unpinned github refs at runtime.

Two nix properties are load-bearing and non-negotiable: immutable store-symlinked skill files, and fully-declarative, always-succeeds activation (a `darwin-rebuild switch` must never fail on network or external schema churn).
The selected direction (captured in brainstorm.md) is to adopt apm (Agent Package Manager) as the package and marketplace format, run it only at nix build time, deploy skills flat, and let nix own the upstream version pins.

## Goals / Non-Goals

**Goals:**
- Make this repo a self-sovereign apm marketplace and author first-party skills as apm packages.
- Gain a lockable dependency graph where first-party packages can depend on upstream plugins with per-file content hashes.
- Preserve immutable store-symlinked skills and always-succeeds activation.
- Preserve flat skill names so the ~70 `@`-autoload references in `modules/home/tools/agents-md.nix` are unchanged.
- Forward-compatibility with the agentskills/agent-plugins/apm standards through one interface.

**Non-Goals:**
- Runtime `plugin:skill` namespacing (deferred to a separate Claude-only marketplace layer if ever wanted).
- Imperative `apm install` at activation time.
- droid/factory apm-targeting (apm's targets enum lacks it; handled via `~/.agents/skills` mapping or retained nix fan-out for `~/.factory/skills`).
- Hooks (unsupported at user scope for opencode/openclaw/hermes; they stay in agent-specific HM modules). This change is skills-only.

## Decisions

### D1: apm runs at nix build time, not at activation ("B1")

- **Choice**: apm runs only inside a nix derivation; nix store-pins the output and symlinks it; apm never runs at activation.
- **Rationale**: preserves immutability and always-succeeds activation while gaining apm's dependency graph, lock file, and multi-harness fan-out.
- **Alternatives considered**: `apm install` at activation (HM generates `~/.apm/{marketplaces.json,apm.yml,config.json}` + activation hook runs `apm install -g`). Rejected: `apm install --global` hard-errors when a skill destination is a symlink or resolves outside `$HOME` (`skill_integrator` `PathTraversalError`) — exactly our HM store-symlinks; an imperative install can fail on network/apm-schema churn, regressing always-succeeds activation; and it yields mutable copies, losing immutability.

### D2: flat skill namespacing (the `apm install` path)

- **Choice**: deploy skills FLAT/merged (bare names, no `plugin:` prefix) at `~/.claude/skills/<name>`.
- **Rationale**: requires NO rework of the ~70 absolute `@`-autoload references in `modules/home/tools/agents-md.nix`.
- **Alternatives considered**: a Claude `marketplace.json` + Claude's native loader yields runtime `plugin:skill` namespacing, but it is Claude-only and carries no apm dependency graph. Deferred.

### D3: nix owns upstream version pins

- **Choice**: nix owns upstream version pins via `fetchFromGitHub` rev+hash in `flake.lock`; `apm.lock` records per-file content hashes.
- **Rationale**: single nix-owned source of truth for upstream SHAs; deterministic, offline-resolvable compose.
- **Alternatives considered**: `apm.yml` carrying `#commit` pins resolved by a fixed-output derivation ("B2"). Rejected in favor of nix-owned pins.

### D4: source layout — apm packages plus a producer marketplace root

- **Choice**: first-party skills become apm packages under `modules/home/ai/plugins/<pkg>/`, each containing `apm.yml` + `plugin.json` + `.apm/skills/<skill>/SKILL.md` (+ `references/`). A committed ROOT `apm.yml` with a `marketplace:` block makes the repo a publishable apm marketplace (Monorepo-hybrid shape).
- **Rationale**: ecosystem-standard packaging that is both publishable (marketplace) and locally composable.
- **Authoring flow**: `apm marketplace init`; per package `apm plugin init <pkg>` (scaffolds `apm.yml` + `plugin.json` + `.apm/skills/`); `apm marketplace package add cameronraysmith/vanixiets --name <pkg> --subdir modules/home/ai/plugins/<pkg> --version '>=1.0.0'` (slug is the marketplace repo; `--name` required); `apm pack`.

### D5: hermetic consume — root consumer manifest composed offline (the key mechanism)

- **Choice**: a nix build derivation `fetchFromGitHub`-pins upstream deps and generates a ROOT *consumer* `apm.yml` (distinct from the producer marketplace `apm.yml`) whose `dependencies.apm` lists the first-party package dirs AND the upstream store paths as LOCAL absolute paths. The derivation runs `apm install --root $out -t agent-skills,claude,codex,hermes` with HOME isolated to a temp dir, `APM_CACHE_DIR` isolated, and `APM_E2E_TESTS=1` (suppresses a non-fatal github update probe). Nix store-pins `$out` and HM symlinks it per harness, preserving the codex real-file-copy.
- **Rationale**: local-path deps skip apm's git-fetch code path, so the whole resolve+compose is OFFLINE and deterministic (no git tag required). The only nondeterminism is `apm.lock`'s `generated_at` timestamp, which is stripped / not harvested.
- **Constraint (verified from apm source + Phase 1b build)**: a *remote* parent may not declare local-path deps (rejected); the root and any *local* parent may. The hermetic compose declares upstream local-path deps at the generated root consumer manifest; first-party local plugins may additionally declare their own local-path child deps (e.g. intra-monorepo siblings).

### D6: upstream "extension" is additive co-ship, not patch/override

- **Choice**: superpowers (`obra/superpowers`) is consumed as a direct dependency (auto-detected by apm as a `MARKETPLACE_PLUGIN` via its `.claude-plugin/`, NO fork needed). "Extending" it means co-shipping additive skills that deploy alongside it; same-name collisions resolve by precedence / `--force`.
- **Rationale**: apm has no patch/override mechanism, so declarative layering is unavailable; additive co-ship is the only composition primitive.
- **Bridge fork**: the `openspec-schemas-superpowers-bridge` fork is NOT apm-installable as-is (schema.yaml + templates/, no `SKILL.md`/`.claude-plugin/`/`apm.yml`); the fork must add ONE packaging signal (a `SKILL.md` or `apm.yml`). A first-party `agentic-planning-development-workflow` package then declares deps on superpowers + the bridge fork.

**Dual-manifest wiring (verified from apm source + Phase 1b build)**: each first-party plugin's own `apm.yml` declares upstream (superpowers, the bridge) under **`devDependencies.apm`** as remote refs, for publishability. Non-root `devDependencies` are NOT walked by the hermetic transitive resolver (it walks only each sub-package's regular `dependencies.apm`), so they impose no network during the nix build. The nix-generated ROOT consumer `apm.yml` declares the same upstream under `dependencies.apm` as LOCAL store-path deps, which supply the actual co-shipped content offline. A remote ref placed in a per-plugin *regular* `dependencies.apm` WOULD be transitively fetched and break the offline build, and there is no resolver-level override to remap it to a local path; a local store-path dep and a remote ref for the same upstream do not dedup (distinct unique keys), so declare each upstream exactly one way. The deployed flat skill name is the `.apm/skills/<subdir>` name (NOT the plugin name), so each skill subdir must keep its current flat name to preserve the ~70 `@`-autoload references.

### D7: lock semantics

- **Choice**: `apm.lock` is a flat list (transitive deps recorded via `discovered_via`); upstream deps lock `resolved_commit` + per-file content hashes; local deps lock content hashes only. `flake.lock` owns the upstream version pins.

## Risks / Trade-offs

- [Risk] apm hard-errors on symlinked/out-of-`$HOME` skill destinations → Mitigation: never run apm at activation; compose at build time into `$out`, then HM symlinks (D1).
- [Risk] non-determinism from `apm.lock` `generated_at` timestamp → Mitigation: strip / do not harvest the timestamp from the derivation output (D5).
- [Risk] remote parent local-path dep rejection → Mitigation: declare all local-path deps only at the ROOT consumer manifest (D5 constraint).
- [Risk] `apm install` of an upstream plugin that ships a `hooks/` dir (e.g. superpowers) integrates those hooks into a composed `.claude/settings.json` (plus `apm-hooks.json` and `hooks/`) → Mitigation: the Phase-3 consume step symlinks only the per-harness `skills/` subtree from `$out`, never the composed `settings.json`/`hooks/`; hooks remain owned by the agent-specific home-manager modules (this change stays skills-only).
- [Trade-off] no runtime `plugin:skill` namespacing → accepted: flat names avoid reworking ~70 `@`-autoload references; namespacing deferred (D2).
- [Trade-off] no patch/override of upstream plugins → accepted: extension is additive co-ship only (D6).
- [Trade-off] droid/factory is not an apm target → accepted: apm's generic agent-skills target writes `~/.agents/skills`, so either map droid to consume `~/.agents/skills` or keep nix fan-out for `~/.factory/skills`.
- [Trade-off] hooks unsupported at user scope for opencode/openclaw/hermes (supported for claude/codex/gemini) → accepted: hooks stay in the existing agent-specific HM modules; out of scope here.
- Housekeeping: gitignore `apm_modules/` and `build/`.

## Migration Plan

Phased and reversible; the current flat-nix system keeps working until the Phase 5 cutover.

1. De-risk spike: one throwaway package + a nix compose derivation proving the offline hermetic apm-install-in-nix compose; `nix build` and inspect `$out`; live `~/.claude` untouched.
2. Taxonomy + bulk restructure: define the package grouping for ~104 skills, scaffold packages, move skills into `.apm/skills/`, commit the producer root `apm.yml`.
3. nix compose + typed HM module: generalize the derivation over all packages; rewrite `modules/home/ai/skills/default.nix` to consume `$out` per harness (preserve codex real-file-copy).
4. Upstream deps + bridge fork: pin superpowers; fork the bridge and add a packaging signal; declare `agentic-planning-development-workflow`.
5. Integrate + deploy: `darwin-rebuild switch` on stibnite; confirm flat skills + merged superpowers content across harnesses; `apm.lock` present; immutability intact.

Rollback: the spike and restructure are additive; reverting to the prior `modules/home/ai/skills/default.nix` flat-tree consumption restores the current system at any point before cutover.

## Open Questions

- droid/factory mapping: consume `~/.agents/skills` directly, or retain nix fan-out for `~/.factory/skills`? (resolve during Phase 3).
- Final package grouping taxonomy for the ~104 skills (resolved during Phase 2).
