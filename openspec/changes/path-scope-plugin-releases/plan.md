# Path-scoped plugin releases Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.
>
> **Process note:** `superpowers:writing-plans` is an interactive skill designed for a live human collaborator; this plan was authored manually (per that artifact's own documented fallback) by a non-interactive subagent, decomposing tasks.md and design.md directly rather than through the skill's live Q&A loop. Micro-steps below are sized for a single sitting each, matching the skill's stated 2-5 minute granularity where the underlying action supports it (config edits, single verification commands); a few steps (waiting for a real release to cut, or for a GH Actions run to fire) are external-event waits rather than active work and are marked as such.

**Goal:** Repoint the 18 first-party plugin dependencies from the moving `main` branch to release-derived tags, so `apm outdated` and relocking become accurate, deliberate signals of real change under `modules/home/ai/plugins/`.

**Architecture:** A new `semantic-release-monorepo` release line rooted at `modules/home/ai/plugins/package.json` mints a canonical `@vanixiets/plugins-v*` tag plus 18 per-directory alias tags (via `semantic-release-major-tag`) on every qualifying release, driven by the existing `release-packages` hercules-ci effect once `list-packages-json.sh` discovers the new package. The 18 first-party `apm.yml` entries then pin each alias tag by literal name (not a SHA, and not the shared canonical tag), which is the one apm resolution path that reports real staleness given this repo's lightweight-tag tooling. A new tag-triggered GH Actions workflow relocks and opens a PR whenever the canonical tag advances.

**Tech Stack:** Nix (flake-parts, hercules-ci-effects), Bash (`list-packages-json.sh`, `release.sh`), `semantic-release` + `semantic-release-monorepo` + `semantic-release-major-tag` (bun-managed devDependencies), `apm` (agent package manager CLI), GitHub Actions.

---

## Task 1: Generalize package discovery (tasks.md 1.1-1.2)

- [ ] **Step 1:** Read `modules/apps/cluster/list-packages-json.sh` in full; identify the exact `for dir in */; do ... done` loop scoped to `$repo_root/packages`.
- [ ] **Step 2:** Add a second, explicit check (not a recursive glob — see design.md's namespace-collision risk note) for `$repo_root/modules/home/ai/plugins/package.json`; if present, append `{"name":"plugins","path":"modules/home/ai/plugins"}` to the emitted array using the same string-building approach already used for `packages/*`.
- [ ] **Step 3:** Run `nix run .#list-packages-json` against the current worktree (before `modules/home/ai/plugins/package.json` exists) and confirm the new entry is absent; this is the negative control.
- [ ] **Step 4 (after Task 2):** Re-run `nix run .#list-packages-json` and confirm `{"name":"plugins","path":"modules/home/ai/plugins"}` appears alongside the existing `packages/docs` entry.
- [ ] **Step 5:** Confirm `modules/apps/release/release.sh`'s `cd "$package_path"` (line 175) accepts `modules/home/ai/plugins` as `$package_path` unmodified — read the script to confirm no `packages/`-relative assumption exists downstream of that line (there is none per design.md D1's citation), so no `release.sh` edit is required.

## Task 2: Author the plugins release-line package.json (tasks.md 2.1-2.3)

- [ ] **Step 1:** Read `packages/docs/package.json`'s `release` block in full as the template to adapt.
- [ ] **Step 2:** Create `modules/home/ai/plugins/package.json` with `name: "@vanixiets/plugins"`, `private: true`, `version: "0.0.0-development"`, and a `release` block: `extends: semantic-release-monorepo`, the same `branches` (`main`, `beta` prerelease), the same `commit-analyzer`/`release-notes-generator`/`changelog`/`github` plugin chain as docs, `npmPublish: false`.
- [ ] **Step 3:** Enumerate all 18 directory names via `ls modules/home/ai/plugins/*/apm.yml` (excluding the 4 `agent-context-*` directories, which are marketplace-published but not in `dependencies.apm` — confirmed in brainstorm.md background) and build the `customTags` array: `["<name>-v${major}.${minor}.${patch}", ...]` for each.
- [ ] **Step 4:** Add `["semantic-release-major-tag", { "customTags": [...] }]` to the plugins list, after the `@semantic-release/github` entry (matching root `package.json`'s existing plugin ordering).
- [ ] **Step 5:** Add a comment (JSON has no native comments; use an adjacent `// NOTE:`-style entry is invalid JSON — instead place the explanatory note in a sibling `README` fragment or in the `description` field, OR record it in `modules/home/ai/plugins/README.md` if one exists; resolve the concrete placement against this repo's convention for commenting `package.json` files before writing, since `packages/docs/package.json` itself carries no inline comments to pattern-match against — check whether any other `package.json` in this repo carries a documented convention for this).
- [ ] **Step 6:** `bun run test-release` with `cwd=modules/home/ai/plugins` (`semantic-release --dry-run --no-ci`) to confirm the config parses and validates.

## Task 3: Rehearsal verification (tasks.md 3.1-3.2)

- [ ] **Step 1:** Confirm the hermetic `release-rehearsal` check exists (`nix build .#checks.x86_64-linux.release-rehearsal`); it runs the same release program as the `release-packages` effect against stubs, so it never pushes a tag. If it has not landed yet, use the local equivalent `nix run .#release -- modules/home/ai/plugins -- --dry-run` (semantic-release's own dry run with the production plugins; needs `GITHUB_TOKEN`).
- [ ] **Step 2:** Run it against a commit that touches `modules/home/ai/plugins/`; capture the log.
- [ ] **Step 3:** Confirm the log shows the plugins package discovered and analyzed, with no tag push attempted.
- [ ] **Step 4:** Re-run against a commit that does NOT touch `modules/home/ai/plugins/`, confirming `packages/docs`'s own rehearsal outcome is unaffected (regression check for Task 1's discovery change).

## Task 4: First-party dependency repointing (tasks.md 4.1-4.4) — gated on a real release existing

- [ ] **Step 1 (external-event wait):** Wait for Task 2's package.json to merge to `main` and for the `release-packages` effect to cut the first real `@vanixiets/plugins-v1.0.0` tag plus its 18 aliases (observable via `git ls-remote --tags` against the GitHub remote).
- [ ] **Step 2:** For each of the 18 entries in root `apm.yml`'s `dependencies.apm` list, change `#main` to `#<directory-name>-v1.0.0`.
- [ ] **Step 3:** Add the manifest-comment departure note (design.md D2's mitigation) above the repointed block, citing the offline/sandboxing distinction (`apm-skills-install.sh` vs. `apm-skills-compose`).
- [ ] **Step 4:** Run `just agents-relock`; diff `apm.lock.yaml` for the 18 affected entries, confirming `resolved_ref` now reads the alias tag and `resolved_commit` is a full 40-char SHA.
- [ ] **Step 5:** Run `apm outdated`; confirm no first-party entry reports `status: unknown` / `source: git branch`; each now reports `source: git tags`.

## Task 5: Relock notification workflow (tasks.md 5.1-5.2)

- [ ] **Step 1:** Copy `.github/workflows/regenerate-lock-files.yaml`'s structure (checkout, setup-nix, run-and-amend, push) as the starting template.
- [ ] **Step 2:** Change the trigger to `on: push: tags: ['@vanixiets/plugins-v*']`; replace the `nix flake lock` / `regenerate-bun-nix` steps with `just agents-relock`; replace the amend-in-place-on-existing-PR logic with a fresh-branch-plus-`gh pr create` step (there is no existing PR to amend on a tag push, unlike the Renovate-PR-synchronize case this template was built for).
- [ ] **Step 3:** Add a guard so the workflow only opens a PR when `git diff --quiet apm.lock.yaml` reports a real diff (mirroring `regenerate-lock-files.yaml`'s own no-op short-circuit).
- [ ] **Step 4:** Push a throwaway tag (`@vanixiets/plugins-v0.0.0-test`) to a scratch point and confirm the workflow run appears in the Actions tab (settles design.md Open Question 2).
- [ ] **Step 5:** Delete the throwaway tag after confirming the trigger fires.

## Task 6: Integration Verification (tasks.md 6.1-6.3)

- [ ] **Step 1:** End-to-end trace: touch one plugin directory, follow it through release, alias tag, notification PR, and a confirmed prior `apm outdated`-reported staleness — assemble the log/PR trail as evidence.
- [ ] **Step 2:** Negative control: a docs-only or root-only commit produces no new plugins tag and no new relock PR.
- [ ] **Step 3:** Confirm `aiSkills.composed` (the deployed skill tree) builds unchanged, proving the repointed refs never reach the nix-sandboxed compose derivation.
