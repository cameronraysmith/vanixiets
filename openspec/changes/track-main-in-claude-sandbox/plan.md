# Track `main` in Claude Code cloud sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The cloud environment's setup step follows `main`'s newest published closure with fixed text, with an optional pin, and each session logs its staleness.

**Architecture:** The existing `claude-sandbox-setup-script` app gains a track mode whose fixed text walks back at most 5 first-parent commits of `main`, evaluating each commit's activation package path with the caches as substituters and accepting the first whose narinfo the fleet cache serves; it realises substitute-only and activates.
A read-only SessionStart hook compares the marker's commit with `main`'s tip.

**Tech Stack:** bash, Nix 2.34 flakes, home-manager, git, curl, nixbot and niks3.

**Spec:** `openspec/changes/track-main-in-claude-sandbox/` (`specs/claude-sandbox-interface`, `specs/claude-sandbox-bootstrap`, `design.md` D1–D7, `tasks.md`).

## Global Constraints

- Script limits: at most 100 lines of at most 200 bytes; last line `exit 0`.
- Track-mode text holds no 40-hex revision, no `/nix/store/` path and no date.
- Caches: `https://cache.nixos.org` and `https://cache.scientistexperience.net?priority=45`, keys from `lib/caches.nix`, passed as bash arrays, never as one unquoted string.
- Realise with `--max-jobs 0 --option builders ''`; never build.
- Walk: at most 5 commits and about 300 s; a failed `eval` is a miss.
- Flake reference per commit: `git+https://github.com/cameronraysmith/vanixiets?rev=<sha>&shallow=1`.
- Logs: `/var/log/claude-sandbox-bootstrap/setup.log` (one marker line per run) and `run.log`.
- Every hook and script path exits 0; the hook prints nothing.

## Review Focus

1. Unquoted substituter strings word-splitting → Task 1's check asserts the array form, and the container test runs the printed script.
2. The tip unpublished right after a push → Task 1's container test blocks the tip's narinfo and expects `main~1`.
3. A lock change whose sources are not yet in niks3 → the walk treats the failed eval as a miss (container test with an unfetchable input).
4. No network, or no marker, at session start → Task 2's hook logs `unknown` and exits 0 with empty stdout.
5. A rerun with the accepted path already current → `activate=current`, nothing under `/root` changes.

---

### Task 1: Track mode and its check (tasks.md 1.1–1.3)

**Files:**
- Modify: `modules/apps/claude-sandbox-setup-script.nix`, `modules/checks/claude-sandbox-setup-script.nix`
- Test: the container test used by the archived change's task 5.1

**Interfaces:**
- Produces: `flake.lib.claudeSandboxSetupScript.trackTemplate` (string); the app prints it with `--track` and keeps the pinned output by default.

- [ ] **Step 1:** Add the track-mode asserts to the check (lines, bytes, `exit 0`, no revision, no store path, `--max-jobs 0`, array form); build it against an empty template. Expected: FAIL.
- [ ] **Step 2:** Write `trackTemplate` and the `--track` branch of the app.
- [ ] **Step 3:** Build the check; print the script at two revisions and `cmp` them. Expected: PASS, identical.
- [ ] **Step 4:** Run the container cases of tasks.md 1.3. Expected: each marker as listed there.
- [ ] **Step 5:** Commit `feat(claude-sandbox): add a track mode that follows main`.

### Task 2: Staleness hook (tasks.md 2.1)

**Files:**
- Modify: `modules/home/users/claude-sandbox/default.nix`

- [ ] **Step 1:** Add `claude-sandbox-staleness` (a `writeShellApplication`) and register it under SessionStart by store path.
- [ ] **Step 2:** `nix eval` the profile's hooks; run the container cases of tasks.md 2.1. Expected: as listed.
- [ ] **Step 3:** Commit `feat(claude-sandbox): log a session's staleness against main`.

### Task 3: Rollout (tasks.md 3.1, 3.2)

- [ ] **Step 1:** Write a controller prompt in `logs/claude-sandbox/` for `nix-sandbox-test`: record the current script, swap to the track-mode script, create a cold-start child, read its report.
- [ ] **Step 2:** The operator runs it and accepts the card; record 3.1's evidence.
- [ ] **Step 3:** Only on a pass, repeat for Default; record 3.2's evidence and Default's previous script verbatim.

### Task 4: Measurement and integration (tasks.md 3.3, 4.1, 4.2)

- [ ] **Step 1:** Create children on one tracking environment over at least eight days; date the snapshot rebuild against A185.
- [ ] **Step 2:** Catch a push-to-publish window if one occurs (4.1); otherwise record the container evidence.
- [ ] **Step 3:** After the next `flake.lock` change, confirm 4.2.
