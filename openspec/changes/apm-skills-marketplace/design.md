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

**Clarification (targets, verified Phase 3 build)**: the hermetic compose runs `apm install -t agent-skills,claude`, the spike-proven native targets, superseding the earlier `agent-skills,claude,codex,hermes` form (codex is a GA target and may be added).
`hermes` is not a native apm-install target in apm 0.22; it is experimental and flag-gated (default off), so apm silently drops it unless `apm experimental enable hermes` runs first.
The hermes, droid (`.factory`), and opencode skill trees are therefore fanned out nix-side from the composed `$out` by `modules/home/ai/skills/default.nix`, not produced by apm `-t` targets.
Only the composed tree's `.claude/skills/` subtree is consumed; the `.claude/settings.json` superpowers-hooks side-effect is never consumed.

### D6: upstream "extension" is additive co-ship, not patch/override

- **Choice**: superpowers (`obra/superpowers`) is consumed as a direct dependency (auto-detected by apm as a `MARKETPLACE_PLUGIN` via its `.claude-plugin/`, NO fork needed). "Extending" it means co-shipping additive skills that deploy alongside it; same-name collisions resolve by precedence / `--force`.
- **Rationale**: apm has no patch/override mechanism, so declarative layering is unavailable; additive co-ship is the only composition primitive.
- **Bridge fork**: the `openspec-schemas-superpowers-bridge` fork is NOT apm-installable as-is (schema.yaml + templates/, no `SKILL.md`/`.claude-plugin/`/`apm.yml`); the fork must add ONE packaging signal (a `SKILL.md` or `apm.yml`). A first-party `agentic-planning-development-workflow` package then declares deps on superpowers + the bridge fork.

**Dual-manifest wiring (verified from apm source + Phase 1b build)**: each first-party plugin's own `apm.yml` declares upstream (superpowers, the bridge) under **`devDependencies.apm`** as remote refs, for publishability. Non-root `devDependencies` are NOT walked by the hermetic transitive resolver (it walks only each sub-package's regular `dependencies.apm`), so they impose no network during the nix build. The nix-generated ROOT consumer `apm.yml` declares the same upstream under `dependencies.apm` as LOCAL store-path deps, which supply the actual co-shipped content offline. A remote ref placed in a per-plugin *regular* `dependencies.apm` WOULD be transitively fetched and break the offline build, and there is no resolver-level override to remap it to a local path; a local store-path dep and a remote ref for the same upstream do not dedup (distinct unique keys), so declare each upstream exactly one way. The deployed flat skill name is the `.apm/skills/<subdir>` name (NOT the plugin name), so each skill subdir must keep its current flat name to preserve the ~70 `@`-autoload references.

**Correction (devDependency marketplace-refs, build-confirmed 2026-06-30)**: the earlier premise that a `NAME@MARKETPLACE` marketplace-ref under a per-package `devDependencies.apm` is install-safe — on the grounds that `apm pack` does not walk it — is false for `apm install`.
apm install validates every transitive `apm.yml` and fatally rejects the `@alias` shorthand (`Shorthand '@alias' is not supported; use object form with git:/path:/alias:`).
This went unobserved earlier because no spike composed the one package (`formal-specification-and-refinement`) that carried such an active entry.
A per-package intra-marketplace edge must therefore be an inert comment (as `planning-and-development/apm.yml` does) or use apm's object form — never an active `@alias` devDependency; `formal-specification-and-refinement`'s active edge was neutralized to a comment accordingly.

### D7: lock semantics

- **Choice**: `apm.lock` is a flat list (transitive deps recorded via `discovered_via`); upstream deps lock `resolved_commit` + per-file content hashes; local deps lock content hashes only. `flake.lock` owns the upstream version pins.

### D8: OpenSpec delivery=skills — drop the redundant `/opsx:*` commands

- **Context**: OpenSpec generates 11 `openspec-*` skills and 11 `/opsx:*` slash commands as 1:1 duplicate front-ends; harness command support varies (codex, opencode, droid, and hermes consume skills, not commands), so the command tree is redundant.
- **Choice**: set OpenSpec `delivery = "skills"` (a global config key; values `both` | `skills` | `commands`, default `both`); a single `openspec init` under `delivery=skills` emits only the 11 skills and creates no `commands/` tree (verified on OpenSpec 1.5.0).
- **Implementation**: set `programs.openspec.delivery = "skills"`; rework `modules/apps/openspec-refresh-vendored-artifacts.sh` to remove the command directory-existence check, the `cmd_count` assertion, and the command `rm`/`mkdir`/`cp`, keeping the exactly-11-skills assertion as the core-profile-fallback guard; remove the committed `modules/home/ai/openspec/assets/commands/` tree; remove the openspec module's `programs.claude-code.commandsDir` wiring.
- **Note**: OpenSpec 1.5.0 init also writes a per-project `openspec/config.yaml`, unrelated to `delivery`.

### D9: OpenSpec 1.4.1 → 1.5.0

- **Choice**: the `llm-agents` flake input was bumped to provide OpenSpec 1.5.0 (and apm 0.23.0); it landed at the diamond base commit.
- **Rationale**: the `delivery` config and the 11-skill/11-command machinery are byte-identical between v1.4.1 and v1.5.0; 1.5.0 adds only "stores (early beta)" store-selection guidance to the skill bodies plus config and YAML-parsing fixes.
- **Implementation**: the 11 vendored skills are regenerated at 1.5.0 (`generatedBy: 1.5.0`) under `delivery=skills`.

### D10: vendor the 11 `openspec-*` skills into the `planning-and-development` apm package

- **Context**: the 11 generated `openspec-*` skills currently reach the deployed tree via the openspec home-manager module's `aiSkills.extraSkillDirs` side-channel, unioned with the apm-composed tree only at the final sinks; they are NOT part of any apm package and do not ship to a non-nix apm consumer.
- **Choice**: move the 11 `openspec-*` skills INTO `modules/home/ai/plugins/planning-and-development/.apm/skills/` (the package grows from 3 hand-authored skills to 14) so they flow through `apm-skills-compose` and ship transitively to consumers; drop `aiSkills.extraSkillDirs` from the openspec module, which then retains only the schema bundle, `config.json`, and the CLI.
- **Cost**: generated (do-not-edit, `generatedBy` frontmatter) and hand-authored skills co-mingle in one package dir; the refresh app is retargeted from a wholesale `rm -rf assets/skills` to per-skill (`openspec-*`) targeting that preserves the 3 authored skills.

### D11: superpowers as a regular remote apm dependency resolved offline via git-cache pre-warm

- **Context**: to make `planning-and-development` self-describing and give a downstream apm consumer supply-chain coverage over superpowers, superpowers must be a regular (walked) remote dependency; apm's audit, scan, and executable gate cover only walked regular deps, while transitive `devDependencies` are validated but never resolved or scanned. A published per-package manifest cannot carry a local-path dep (see D5).
- **Constraint**: apm dedups by path/URL not name, and a regular remote ref in a copied sub-package is walked and fetched, which would break the hermetic offline compose (see D6: declare each upstream exactly one way; no remote→local remap).
- **Choice**: declare superpowers ONCE as a regular remote dep pinned to the FULL 40-char SHA in `planning-and-development/apm.yml` (`obra/superpowers#f2cbfbefebbfef77321e4c9abc9e949826bea9d7`); keep the nix compose offline by PRE-SEEDING apm's git checkout cache from the flake-pinned `fetchFromGitHub` tree before `apm install`, so apm resolves the remote ref from cache with zero network and records a remote-style `resolved_commit` lock — identical for the fleet build and an external consumer.
- **Implementation**: drop the separate `superpowers-src` local co-ship (single declaration, honors D6); the flake-pinned package remains as the offline cache feed; the three SHA copies (the `apm.yml` pin, the feed package rev in `pkgs/by-name/agent-plugins/superpowers`, and the compose `superpowersRev`) must stay in sync, threaded from one nix source.

**Cache-warm recipe (proven on apm 0.23.0, the live compose version)**: seed `$APM_CACHE_DIR/git/checkouts_v1/8c6014a36ca90e3f/<full-sha>/full/` with the source tree (`cp -RL`, `chmod u+w`) plus a stub `.git/HEAD` containing the 40-hex SHA followed by a newline.
The FULL SHA is required; a short ref forces network.
A blackholed-network, no-token install resolved in sub-second with a Cache HIT, `git/db_v1` empty (zero network), and `resolved_commit` equal to the full SHA.

**Pending**: a true linux no-network sandbox build (buildbot) as the final confirmation.

**Security-scan honesty**: the consumer-side value is real but shallow — the executable deny-by-default gate over superpowers' hooks plus the content-hash / `resolved_commit` pin; apm has no native CVE, malware, or signature scanning (only an optional, experimental external SARIF / SkillSpector seam).

### D12: drop the `/opsx:*` command references; route bridge schema selection through `openspec-new-change`

- **Context**: because `delivery=skills` removes the `/opsx:*` commands, the hand-authored router (`agentic-planning-development-workflow/SKILL.md` + its `references/`) and `openspec-linear-sync` are rewritten from `/opsx:*` invocation to the `openspec-*` skill forms.
- **Constraint**: there is no `ff` CLI command, and `--schema` is honored only by `openspec new change`; the schema is sticky (written once to the change's `.openspec.yaml` at creation and auto-detected downstream), so bridge schema selection routes through the `openspec-new-change` skill.
- **Choice**: set `openspec/config.yaml` project default schema to `superpowers-bridge` (the router's stated spec-first default) so the `openspec-ff-change` skill works one-shot without a per-invocation flag (tradeoff: non-bridge changes then need an explicit `--schema spec-driven`).
- **Implementation**: the bridge `schema.yaml` needs no edit; its hand-maintained `README.md` and `templates/adopters/CLAUDE.md.fragment.md` are rewritten to skill-form.
- **Note**: the upstream-generated `openspec-*` skill bodies still embed `/opsx:` prose (regenerates regardless of `delivery`) — an accepted upstream wart, out of scope.

### D13: supersession — the original Phase 4 (bridge fork + apm packaging signal)

- **Choice**: the originally-planned Phase 4 — `fetchFromGitHub`-fork the `openspec-schemas-superpowers-bridge` and add a packaging signal so the bridge becomes apm-installable (the D6 "Bridge fork" bullet) — is SUPERSEDED.
- **Rationale**: the `superpowers-bridge` stays an OpenSpec *schema* delivered via its own home-manager module (`schemaDir` → `~/.local/share/openspec/schemas/`); it is not forked and not given an apm packaging signal, because it is a schema (consumed by the OpenSpec CLI), not a skill, and forcing it through the apm skills marketplace is an impedance mismatch.

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
4. Phase 4 — delivery=skills, vendor the 11 `openspec-*` skills into the `planning-and-development` apm package, superpowers as a regular remote dep resolved offline via git-cache pre-warm, and the `/opsx:*` command-drop ripple (see decisions D8–D13).
5. Integrate + deploy: `darwin-rebuild switch` on stibnite; confirm flat skills + merged superpowers content across harnesses; `apm.lock` present; immutability intact.

Rollback: the spike and restructure are additive; reverting to the prior `modules/home/ai/skills/default.nix` flat-tree consumption restores the current system at any point before cutover.

## Open Questions

- droid/factory mapping: consume `~/.agents/skills` directly, or retain nix fan-out for `~/.factory/skills`? (resolve during Phase 3).
- Final package grouping taxonomy for the ~104 skills (resolved during Phase 2; see "Phase 2 taxonomy" below).

## Phase 2 taxonomy

This section records the resolved Phase-2 partition of the 104 first-party skills into 17 apm packages.
The partition is exhaustive (104 skills) and disjoint (each skill belongs to exactly one package).
No skill leaf is renamed: each skill `X` moved from `src/{core,claude}/X/` to `modules/home/ai/plugins/<package>/.apm/skills/X/` with `X` byte-identical, so the package name never appears in the deployed path and the ~70 `@`-autoload references stay valid.

### Naming convention

Package names are semantic and verbose (for example `preferences-functional-programming-theory`, `agent-orchestration-and-meta-tooling`), describing the cluster's domain rather than its mechanism.
No package carries an `apm-pkg-` or similar prefix; the marketplace structure is conveyed by the `modules/home/ai/plugins/<package>/` location, not by a name decoration.

### Key decisions

The historical `src/core` versus `src/claude` split is dissolved: every package is all-agent and deploys to every harness, so no package is Claude-only.
The agentic-planning Manual execution mode retires together with beads; the beads issue tracker and the session-workflow skills are grouped into a single toggle-off `beads-issue-tracking-and-session-workflow` package, and the planning workflow's coupling to it is a soft (comment-only) annotation rather than a hard dependency.
`nucleus-platform` is grouped with `refinement-driven-development` in the `formal-specification-and-refinement` package, reflecting their shared spec-anchored, approximately-verifiable axis.
The `preferences-*` skills are sub-clustered into 9 thematic packages (functional-programming theory, programming languages, nix and secrets, domain-driven architecture, event-driven systems, web platform and deployment, operations and reliability, code and collaboration conventions, data and scientific computing) rather than a single monolithic preferences package.

### Roster (17 packages, 104 skills, all all-agent)

The nine `preferences-*` packages (48 skills, stable tier):

| Package | Skills |
|---|---|
| preferences-functional-programming-theory (6) | preferences-theoretical-foundations, preferences-algebraic-data-types, preferences-algebraic-laws, preferences-functional-reactive-programming, preferences-railway-oriented-programming, preferences-computational-system-taxonomy |
| preferences-programming-languages (4) | preferences-python-development, preferences-haskell-development, preferences-rust-development, preferences-typescript-nodejs-development |
| preferences-nix-and-secrets (4) | preferences-nix-development, preferences-nix-checks-architecture, preferences-nix-ci-cd-integration, preferences-secrets |
| preferences-domain-driven-architecture (7) | preferences-domain-modeling, preferences-bounded-context-design, preferences-strategic-domain-analysis, preferences-collaborative-modeling, preferences-discovery-process, preferences-architectural-patterns, preferences-architecture-diagramming |
| preferences-event-driven-systems (5) | preferences-event-modeling, preferences-event-sourcing, preferences-event-catalog-tooling, preferences-event-catalog-qlerify, preferences-schema-versioning |
| preferences-web-platform-and-deployment (6) | preferences-web-platform-foundations, preferences-hypermedia-development, preferences-hypermedia-documents, preferences-react-tanstack-ui-development, preferences-web-application-deployment, preferences-cloudflare-wrangler-reference |
| preferences-operations-and-reliability (6) | preferences-observability-engineering, preferences-production-readiness, preferences-distributed-systems, preferences-validation-assurance, preferences-compositional-continuous-verification, preferences-adaptive-planning |
| preferences-code-and-collaboration-conventions (5) | preferences-style-and-conventions, preferences-documentation, preferences-git-version-control, preferences-git-history-cleanup, preferences-change-management |
| preferences-data-and-scientific-computing (5) | preferences-data-modeling, preferences-json-querying, preferences-scalable-probabilistic-modeling-workflow, preferences-scientific-inquiry-methodology, preferences-workflow-orchestration-algebra |

The eight non-`preferences` packages (56 skills):

| Package | Tier | Skills |
|---|---|---|
| beads-issue-tracking-and-session-workflow (14) | toggle-off | issues-beads, issues-beads-audit, issues-beads-checkpoint, issues-beads-evolve, issues-beads-init, issues-beads-orient, issues-beads-prime, issues-beads-seed, session-advisor, session-orient, session-plan, session-review, session-checkpoint, stigmergic-convention |
| formal-specification-and-refinement (2) | fresh-retain | nucleus-platform, refinement-driven-development |
| planning-and-development (3) | fresh-retain | agentic-planning-development-workflow, openspec-linear-sync, project-management |
| agent-orchestration-and-meta-tooling (15) | stable | meta-agent-teams, meta-list-all-agents, meta-list-all-tools, meta-load-cc-docs, meta-orchestrate-dispatch, meta-orchestrator-checkpoint, meta-orchestrator-initiate, meta-search-sessions, meta-session-resume, meta-skill-creator, meta-create-workspace-agents-md, meta-generate-context-test, meta-generate-handoff-prompt, meta-load-prompting-docs, meta-optimize-prompt |
| version-control-and-forge (8) | stable | jj-git-interactive-rebase-to-jj, jj-history-cleanup, jj-summary, jj-version-control, jj-workflow, gitbutler-but-cli, git-commit-prompt, github-browse |
| document-authoring-and-visualization (6) | stable | doc-to-md, doc-to-md-cmd, web-to-markdown, knowledge-graph, scientific-visualization, text-to-visual-iteration |
| event-modeling-workflow (4) | stable | event-modeling-brownfield, event-modeling-greenfield, event-modeling-qlerify-session, event-modeling-to-eventcatalog |
| nix-build-operations (4) | stable | nix-flake-pr-cycle, nixpkgs-broken-package, process-compose-init, worktree-sparsity-eval |

Counts reconcile as preferences 6+4+4+7+5+6+6+5+5 = 48 and non-preferences 14+2+3+15+8+6+4+4 = 56, totaling 104 (93 formerly under `src/core`, 11 under `src/claude`).
