## 1. Phase 1 — De-risk spike

- [x] 1.1 Create one throwaway first-party package `modules/home/ai/plugins/apm-spike/` with a brand-new skill name (no `src/core` collision)
- [x] 1.2 Add a nix compose derivation that generates a root consumer `apm.yml` listing the spike package + `${pkgs.agent-plugins-superpowers}` as local-path deps and runs `apm install --root $out -t agent-skills,claude` offline (HOME and `APM_CACHE_DIR` isolated, `APM_E2E_TESTS=1`, strip `apm.lock` `generated_at`)
- [x] 1.3 Gitignore `apm_modules/` and `build/`
- [x] 1.4 `nix build` and inspect `$out`; confirm it contains flat `.claude/skills/<spike-skill>/SKILL.md` AND superpowers' skills, the build is offline + deterministic, and live `~/.claude` is untouched (optional isolated `CLAUDE_CONFIG_DIR` live-load)

## 1b. Phase 1b — Canonical-shape de-risk

- [x] 1b.1 Author a throwaway canonical-shape fixture under `modules/home/ai/plugins/apm-spike-canonical/`: a marketplace root (`apm.yml` with a `marketplace:` block + `packages[].source: ./plugins/<pkg>`) and one canonical plugin (`plugin.json` + `apm.yml` + `.apm/skills/<skill>/SKILL.md`), with a deliberately-nonexistent plugin `devDependencies` ref as the non-root-devDep-skip probe
- [x] 1b.2 Add a two-path compose derivation `pkgs/by-name/apm-spike-canonical-compose/`: producer (`apm pack` → assert `.claude-plugin/marketplace.json` carries `plugins:`) and consumer (`apm install --root $out -t agent-skills,claude` → flat `.apm/skills` promotion + offline superpowers co-ship)
- [x] 1b.3 `nix build` + inspect: confirm `plugin.json` → MARKETPLACE_PLUGIN classification deploys `.apm/skills/<skill>` flat to `.claude/skills/<skill>` and `.agents/skills/<skill>`; superpowers co-ships; producer `marketplace.json` is valid; the bogus non-root `devDependency` is never resolved (offline build proves the skip); `nix build --rebuild` is deterministic

## 2. Phase 2 — Taxonomy + bulk restructure

- [x] 2.1 Define the package grouping for the ~104 skills
- [x] 2.2 Hand-author the repo-root marketplace manifests — the root `apm.yml` `marketplace:` block plus `.claude-plugin/marketplace.json` — equivalent to what `apm marketplace init` produces
- [x] 2.3 For each package, hand-author the per-package `plugin.json` + `apm.yml` and the matching root marketplace package entry (pointing at `--subdir modules/home/ai/plugins/<pkg>`), equivalent to running `apm plugin init <pkg>` and `apm marketplace package add` for each
- [x] 2.4 Move skills into `.apm/skills/`
- [x] 2.5 Commit the producer root `apm.yml`
- [x] 2.6 Confirm `apm marketplace check` passes and `apm pack` is clean

## 3. Phase 3 — nix compose + typed HM module

- [x] 3.1 Generalize the Phase-1 derivation over all packages
- [x] 3.2 Add a typed home-manager module (options: which packages, which upstream deps, which targets)
- [x] 3.3 Rewrite `modules/home/ai/skills/default.nix` to consume `$out` per harness, preserving the codex real-file-copy
- [x] 3.4 Confirm nix eval/build slices pass, all six harness skill paths are populated, and `agents-md.nix` `@`-refs still resolve (flat) — darwin confirmed: `claude-code.skills` 116→130, all five sinks populated via a green `nix build .#checks.aarch64-darwin.home-manager-crs58`, all 58 `agents-md` `@`-refs resolve flat; linux/x86_64-linux confirmation deferred to buildbot CI at integration

## 4. Phase 4 — delivery=skills, openspec-into-package, superpowers cache-warm, command-drop

Supersedes the original "Upstream deps + bridge fork" Phase 4 (fork the bridge + add an apm packaging signal), now superseded per design.md decision D13.

- [ ] 4.1 `delivery=skills`: set `programs.openspec.delivery = "skills"`; rework the refresh sidecar (remove the command path, keep the exactly-11-skills assertion); remove the `assets/commands/` tree; remove the `commandsDir` wiring; update the affected doc-comments
- [ ] 4.2 OpenSpec 1.5.0:
  - [x] bump `llm-agents` to OpenSpec 1.5.0 + apm 0.23.0 (landed at the diamond base)
  - [ ] regenerate the 11 `openspec-*` skills at 1.5.0 under `delivery=skills`
- [ ] 4.3 Vendor openspec skills into the package: move the 11 `openspec-*/` dirs into `planning-and-development/.apm/skills/`; drop `aiSkills.extraSkillDirs`; retarget the refresh app per-skill, preserving the 3 authored skills
- [ ] 4.4 superpowers cache-warm: add the regular full-SHA dep to `planning-and-development/apm.yml`; in `apm-skills-compose/package.nix` add `superpowersSrc`/`superpowersRev` + the cache pre-warm, drop `superpowers-src` from `upstreamDeps`, and add a superpowers skill to the assertion list; in `compose.nix` default `upstreamDeps` to `[]` and thread the args; thread the SHA from one nix source
- [ ] 4.5 Command-drop ripple: rewrite `agentic-planning-development-workflow/SKILL.md` + `references/{collaborators,delegation,execution-modes,hil-isolation}.md` + `openspec-linear-sync/SKILL.md` to skill-form; set `openspec/config.yaml` default schema to `superpowers-bridge`; rewrite the bridge `README.md` + `templates/adopters/CLAUDE.md.fragment.md` to skill-form (`schema.yaml` unchanged)
- [ ] 4.6 Verify: `nix build .#checks.aarch64-darwin.home-manager-crs58` → exit 0; inspect `$out/apm.lock.yaml` for the superpowers `resolved_commit` entry; confirm the flat skill set + the openspec skills now arriving via apm + no `/opsx:*` commands; (deferred) a linux x86_64 no-network sandbox build confirms the cache-warm at buildbot

## 5. Phase 5 — Integrate + deploy

- [ ] 5.1 `darwin-rebuild switch` on stibnite
- [ ] 5.2 Confirm flat skills + merged superpowers content across harnesses
- [ ] 5.3 Confirm `apm.lock` present and store-symlink immutability intact
- [ ] 5.4 Confirm activation succeeded and all harnesses see the skills

A consumer-path validation flake-app (an external, non-nix apm consumer resolving `planning-and-development` and its superpowers dep offline) is a follow-on, out of scope for this change.
