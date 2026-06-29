## 1. Phase 1 — De-risk spike

- [ ] 1.1 Create one throwaway first-party package `modules/home/ai/plugins/apm-spike/` with a brand-new skill name (no `src/core` collision)
- [ ] 1.2 Add a nix compose derivation that generates a root consumer `apm.yml` listing the spike package + `${pkgs.agent-plugins-superpowers}` as local-path deps and runs `apm install --root $out -t agent-skills,claude` offline (HOME and `APM_CACHE_DIR` isolated, `APM_E2E_TESTS=1`, strip `apm.lock` `generated_at`)
- [ ] 1.3 Gitignore `apm_modules/` and `build/`
- [ ] 1.4 `nix build` and inspect `$out`; confirm it contains flat `.claude/skills/<spike-skill>/SKILL.md` AND superpowers' skills, the build is offline + deterministic, and live `~/.claude` is untouched (optional isolated `CLAUDE_CONFIG_DIR` live-load)

## 2. Phase 2 — Taxonomy + bulk restructure

- [ ] 2.1 Define the package grouping for the ~104 skills
- [ ] 2.2 Run `apm marketplace init`
- [ ] 2.3 For each package, run `apm plugin init <pkg>` and `apm marketplace package add ... --subdir modules/home/ai/plugins/<pkg>`
- [ ] 2.4 Move skills into `.apm/skills/`
- [ ] 2.5 Commit the producer root `apm.yml`
- [ ] 2.6 Confirm `apm marketplace check` passes and `apm pack` is clean

## 3. Phase 3 — nix compose + typed HM module

- [ ] 3.1 Generalize the Phase-1 derivation over all packages
- [ ] 3.2 Add a typed home-manager module (options: which packages, which upstream deps, which targets)
- [ ] 3.3 Rewrite `modules/home/ai/skills/default.nix` to consume `$out` per harness, preserving the codex real-file-copy
- [ ] 3.4 Confirm nix eval/build slices pass, all six harness skill paths are populated, and `agents-md.nix` `@`-refs still resolve (flat)

## 4. Phase 4 — Upstream deps + bridge fork

- [ ] 4.1 `fetchFromGitHub`-pin superpowers (reuse `pkgs.agent-plugins-superpowers`)
- [ ] 4.2 Fork `openspec-schemas-superpowers-bridge` and add a packaging signal (`SKILL.md`/`apm.yml`)
- [ ] 4.3 Declare an `agentic-planning-development-workflow` package depending on superpowers + the bridge fork
- [ ] 4.4 Confirm apm resolves the dep graph offline and `apm.lock` records the upstream `resolved_commit` + per-file hashes

## 5. Phase 5 — Integrate + deploy

- [ ] 5.1 `darwin-rebuild switch` on stibnite
- [ ] 5.2 Confirm flat skills + merged superpowers content across harnesses
- [ ] 5.3 Confirm `apm.lock` present and store-symlink immutability intact
- [ ] 5.4 Confirm activation succeeded and all harnesses see the skills
