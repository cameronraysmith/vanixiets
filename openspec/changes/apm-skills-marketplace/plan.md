# apm-skills-marketplace Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Refactor the ~104 first-party AI-agent skills into apm packages composed by nix at build time, making this repo a self-sovereign apm marketplace, without surrendering immutable store-symlinked skills or always-succeeds activation.

**Architecture:** apm runs only inside a nix build derivation that generates a root consumer `apm.yml` (local-path deps), composes per-harness flat skill trees offline, and nix store-pins them for home-manager to symlink. Upstream plugins are nix-pinned via `fetchFromGitHub`; `apm.lock` records per-file content hashes. See `design.md` for the decisions (D1-D7) and `specs/` for the requirements.

**Tech Stack:** nix (flake-parts, home-manager derivations), apm (Agent Package Manager CLI), jj (development join, N=3 chain).

## Approach and sequencing

Spike-first de-risking: Task 1 proves the apm-install-in-nix hermetic compose end to end before any of the ~104 skills move.
Integration is jj-native onto the existing `apm-skills-marketplace` chain in an N=3 development join — no git worktree, no autonomous PR; commits are routed onto the chain by the orchestrator.
Per-phase verification favors nix eval/build slices locally; CI-parity `check-fast` runs only on explicit ask.
The work is reversible: the spike and restructure are additive, so the current flat-nix system keeps working until the Phase 5 cutover.
Out of scope: hooks (stay in agent-specific HM modules), runtime `plugin:skill` namespacing (deferred), and droid/factory apm-targeting (handled via `~/.agents/skills` or retained nix fan-out).

---

## Task 1: De-risk spike (tasks.md §1)

- [ ] **Step 1:** Create `modules/home/ai/plugins/apm-spike/` with a brand-new skill name (verify no `src/core` collision).
- [ ] **Step 2:** Add a nix compose derivation generating a root consumer `apm.yml` listing the spike package + `${pkgs.agent-plugins-superpowers}` as local-path deps; run `apm install --root $out -t agent-skills,claude` offline with HOME and `APM_CACHE_DIR` isolated, `APM_E2E_TESTS=1`, and `apm.lock` `generated_at` stripped.
- [ ] **Step 3:** Gitignore `apm_modules/` and `build/`.
- [ ] **Step 4:** `nix build` and `tree $out`; assert flat `.claude/skills/<spike-skill>/SKILL.md` AND superpowers' skills present, build offline + deterministic, live `~/.claude` untouched (optional isolated `CLAUDE_CONFIG_DIR` live-load).
- [ ] **Step 5:** Route the commit onto the `apm-skills-marketplace` chain.

## Task 2: Taxonomy + bulk restructure (tasks.md §2)

- [ ] **Step 1:** Define the package grouping for the ~104 skills.
- [ ] **Step 2:** `apm marketplace init`.
- [ ] **Step 3:** Per package: `apm plugin init <pkg>` then `apm marketplace package add cameronraysmith/vanixiets --name <pkg> --subdir modules/home/ai/plugins/<pkg> --version '>=1.0.0'`.
- [ ] **Step 4:** Move skills into `.apm/skills/`; commit the producer root `apm.yml`.
- [ ] **Step 5:** Verify `apm marketplace check` passes and `apm pack` is clean; route commits onto the chain.

## Task 3: nix compose + typed HM module (tasks.md §3)

- [ ] **Step 1:** Generalize the Phase-1 derivation over all packages.
- [ ] **Step 2:** Add a typed home-manager module (options: packages, upstream deps, targets).
- [ ] **Step 3:** Rewrite `modules/home/ai/skills/default.nix` to consume `$out` per harness, preserving the codex real-file-copy.
- [ ] **Step 4:** Verify nix eval/build slices pass, all six harness skill paths populated, and `agents-md.nix` `@`-refs still resolve (flat); route commits onto the chain.

## Task 4: Upstream deps + bridge fork (tasks.md §4)

- [ ] **Step 1:** `fetchFromGitHub`-pin superpowers (reuse `pkgs.agent-plugins-superpowers`).
- [ ] **Step 2:** Fork `openspec-schemas-superpowers-bridge` and add one packaging signal (`SKILL.md`/`apm.yml`).
- [ ] **Step 3:** Declare an `agentic-planning-development-workflow` package depending on superpowers + the bridge fork.
- [ ] **Step 4:** Verify apm resolves the dep graph offline and `apm.lock` records the upstream `resolved_commit` + per-file hashes; route commits onto the chain.

## Task 5: Integrate + deploy (tasks.md §5)

- [ ] **Step 1:** `darwin-rebuild switch` on stibnite.
- [ ] **Step 2:** Confirm flat skills + merged superpowers content across harnesses.
- [ ] **Step 3:** Confirm `apm.lock` present and store-symlink immutability intact.
- [ ] **Step 4:** Confirm activation succeeded and all harnesses see the skills.
