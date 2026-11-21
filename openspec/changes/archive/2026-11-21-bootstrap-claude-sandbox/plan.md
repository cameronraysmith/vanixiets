# Bootstrap Claude Code cloud sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A cloud session started on the operator's cloud environment gets the user context, the skill corpus, the required tools, each attached repository's context and the Linear credentials, from one pinned setup line.

**Architecture:** A `claude-sandbox@x86_64-linux` home configuration (D1) is built by one CI check and published to `cache.scientistexperience.net` (D2).
The setup script, generated for each commit by `nix run .#claude-sandbox-setup-script`, names that activation package by store path; it substitutes and activates it without evaluating any flake, records a marker line, and always exits 0, while the activation itself writes the bootstrap report (D2, revised by Q91 on 2026-11-21).
Session-time work (repository context, D3; Linear secrets, D5) runs from hooks whose commands are store paths (D4).

**Tech Stack:** Nix flakes (flake-parts, import-tree), home-manager, sops-nix, `apm-context-compile`, nixbot and niks3, Claude Code cloud environments.

**Spec:** `openspec/changes/bootstrap-claude-sandbox/` — `specs/claude-sandbox-bootstrap/spec.md` (requirements), `specs/world-assumptions/spec.md` (A167–A180), `design.md` (D1–D5, assumptions S1–S10, probe P4), `tasks.md` (task groups 1–8, which this plan's tasks map to).

## Global Constraints

- Platform: `x86_64-linux` only; username `root`; home `/root`.
- The setup step is the script `nix run .#claude-sandbox-setup-script` prints for the pinned revision, within 100 lines of 200 bytes, ending in `exit 0`; it evaluates no flake.
- The setup step is renewed at least every 30 days, because niks3 drops a closure 30 days after its last reference.
- Every bootstrap and hook path exits 0.
- Setup finishes within 360 seconds on a cache hit.
- No secret in the setup step, in any file under `/root`, `/var/log/claude-sandbox-bootstrap` or `/nix`, or in any report; secrets are decrypted only into `/dev/shm`.
- Never write `launcher-settings.json`, `session-start-setup-script-failure.sh`, `stop-hook-git-check.sh`, `environment-manager/`, `skills/session-start-hook` or `skills/synced` under `/root/.claude`.
- Binary caches: `https://cache.scientistexperience.net` and `https://cache.nixos.org`, with their keys taken from `lib/caches.nix`.
- Reports go to `/var/log/claude-sandbox-bootstrap/`.
- x86_64-linux builds run on magnetite; darwin configurations are evaluated only.
- Prose in READMEs: one sentence per line.

## Review Focus

1. A stale closure: the setup script names a store path other than the one CI builds → the `claude-sandbox-setup-script` check fails evaluation (Task 4, mutant test).
2. A realise that fails halfway → nothing is activated, the marker line records the failed realise, exit 0 (Task 5, cache-miss test).
3. SessionStart fires on resume as well as start → the repository-context hook and the secret hook are no-ops the second time (Tasks 7 and 8, run-twice test).
4. `SOPS_AGE_KEY` unset (environment not yet configured) → the secret hook does nothing and says so in the report, and the Linear skills fail closed (Task 8, unset-key test).
5. An attached repository without `apm.yml`, or a session with no attached repository → the repository-context hook skips it (Task 7, no-`apm.yml` test).

---

### Task 1: Factor the `sandbox` aggregate out of `ubuntu` (tasks.md 1.1)

**Files:**
- Create: `modules/home/sandbox/default.nix`
- Modify: `modules/home/users/ubuntu/default.nix`, `modules/home/users/ubuntu/meta.nix`

**Interfaces:**
- Produces: `flake.modules.homeManager.sandbox`, with option `vanixiets.sandbox.sopsDir` (string, no default) and the session hook at `~/.config/vanixiets/session-env.sh`, unchanged in behaviour from `ubuntu`'s.

- [ ] **Step 1: Record `ubuntu`'s baseline** — Run on magnetite: `nix build .#homeConfigurations."ubuntu@x86_64-linux".activationPackage -o /tmp/ubuntu-before`. Expected: a store path.
- [ ] **Step 2: Move bash-off, ssh-agent-off, C.UTF-8, `sopsInstallWithoutSystemd`, the tmpfs sops environment and `session-env.sh` into `modules/home/sandbox/default.nix`**, reading the directory from `vanixiets.sandbox.sopsDir`; `ubuntu` sets it to `/dev/shm/ubuntu-sops` and adds `sandbox` to its aggregates.
- [ ] **Step 3: Compare** — Run: `nix build .#homeConfigurations."ubuntu@x86_64-linux".activationPackage -o /tmp/ubuntu-after && diff -r /tmp/ubuntu-before/home-files /tmp/ubuntu-after/home-files && diff <(sed 's,/nix/store/[a-z0-9]*-,,g' /tmp/ubuntu-before/activate) <(sed 's,/nix/store/[a-z0-9]*-,,g' /tmp/ubuntu-after/activate)`. Expected: no output.
- [ ] **Step 4: Commit** — `refactor(home): factor the sandbox aggregate out of ubuntu`.

### Task 2: Hook commands by store path (tasks.md 2.1)

**Files:**
- Create: `modules/home/ai/claude-code/hooks-module.nix` (or move the content of `hooks.nix`)
- Modify: `modules/home/ai/claude-code/hooks.nix`, `modules/home/tools/hooks/default.nix`

**Interfaces:**
- Produces: `flake.modules.homeManager.claude-code-hooks`, which defines the hook derivations (moved out of `tools`' `let`), adds them to `home.packages`, and sets `programs.claude-code.settings.hooks` with `lib.getExe` of each; `ai` imports it.
- `tools` keeps exporting the hook packages on PATH for interactive use through `claude-code-hooks`.

- [ ] **Step 1: Write the failing check** — in `modules/checks/claude-code-hooks.nix`, `checks.x86_64-linux.claude-code-hooks-store-paths` asserts that every `command` in `homeConfigurations."crs58@x86_64-linux".config.programs.claude-code.settings.hooks` starts with `/nix/store/`.
- [ ] **Step 2: Run it** — `nix build .#checks.x86_64-linux.claude-code-hooks-store-paths`. Expected: FAIL listing the 13 bare commands.
- [ ] **Step 3: Implement the module** as in Interfaces.
- [ ] **Step 4: Run it again** — Expected: PASS; `nix eval` of crs58's aarch64-darwin hooks also shows only store paths.
- [ ] **Step 5: Commit** — `fix(claude-code): call hooks by store path`.

### Task 3: The `claude-sandbox` home configuration (tasks.md 1.2–1.5)

**Files:**
- Create: `modules/home/users/claude-sandbox/meta.nix`, `modules/home/users/claude-sandbox/default.nix`
- Modify: `modules/checks/structure/flake-shape.nix`

**Interfaces:**
- Consumes: `sandbox` (Task 1), `claude-code-hooks` (Task 2), `agents-md`, `agent-context`, `ai-capabilities`.
- Produces: `homeConfigurations."claude-sandbox@x86_64-linux"`, with `home.username = "root"`, `home.homeDirectory = "/root"` (both `lib.mkForce` over the identity defaults), `vanixiets.sandbox.sopsDir = "/dev/shm/claude-sandbox-sops"`, `programs.claude-code.enable = true` with no MCP servers, wrappers or macOS settings, and `home.packages` holding R12's tools: openspec, linear-cli, jujutsu, gitFull, gh, ghq, mergify, jq, jaq, ripgrep, fd, duckdb, just, playwright-cli, typst, d2, mermaid-cli, pandoc, uv (nix comes from the base image).

- [ ] **Step 1: Add `"claude-sandbox@x86_64-linux"` to `flake-shape.nix`'s expected list** and run `nix build .#checks.x86_64-linux.flake-shape` (attribute name as defined there). Expected: FAIL, missing configuration.
- [ ] **Step 2: Add the user** as in Interfaces; `systems = [ "x86_64-linux" ]`; `sopsAgeKeyId = null`; aggregates `sandbox agents-md agent-context ai-capabilities claude-code-hooks` plus a `claude-sandbox` content module for the tools.
- [ ] **Step 3: Run the flake-shape check.** Expected: PASS.
- [ ] **Step 4: Build and inspect** — on magnetite, `nix build .#homeConfigurations."claude-sandbox@x86_64-linux".activationPackage -o /tmp/cs`; then `cmp /tmp/cs/home-files/.claude/CLAUDE.md <crs58's>`, `ls /tmp/cs/home-files/.claude/skills | wc -l` against `skills.json` minus the excluded skills, `ls /tmp/cs/home-path/bin` contains every tool above, and `ls -a /tmp/cs/home-files/.claude` contains none of the harness-owned names. Record `nix path-info -S /tmp/cs` in the pull request.
- [ ] **Step 5: Commit** — `feat(home): add the claude-sandbox configuration`.

### Task 4: CI check and the generated setup script (tasks.md 3.1, 3.3)

**Files:**
- Modify: `modules/checks/home.nix` (add `claude-sandbox` to the x86_64-linux homes)
- Create: `modules/apps/claude-sandbox-setup-script.nix`, `modules/checks/claude-sandbox-setup-script.nix`

**Interfaces:**
- Produces: `checks.x86_64-linux.home-manager-claude-sandbox` (the activation package itself), `flake.lib.claudeSandboxSetupScript.template` (no commit-dependent value; `@REV@` and `@DATE@` placeholders), `apps.claude-sandbox-setup-script` (prints the template with the revision and date filled in at run time), and `checks.x86_64-linux.claude-sandbox-setup-script` (evaluation-time asserts: at most 100 lines of at most 200 bytes, `exit 0` last, `P=` the path `home-manager-claude-sandbox` builds, no revision in the template).

- [ ] **Step 1: Show the setup-script check absent and failing** — on the parent revision it does not exist; with the app in place, mutants (no `exit 0`, a 215-byte line, 101 lines, `P` set to `ubuntu`'s activation package) each fail evaluation.
- [ ] **Step 2: Implement the app and run the check.** Expected: PASS.
- [ ] **Step 3: Commit** — `feat(claude-sandbox): build the profile in CI and generate its setup script`; after merge, confirm `nix path-info --store https://cache.scientistexperience.net <path>` answers.

### Task 5: The bootstrap report and the container test (tasks.md 3.2, 5.1)

**Files:**
- Modify: `modules/home/sandbox/default.nix` (option `vanixiets.sandbox.bootstrapReport`), `modules/home/users/claude-sandbox/default.nix` (enable it)

**Interfaces:**
- Produces: a home-manager activation step that writes `/var/log/claude-sandbox-bootstrap/report.json` (time, generation, closure size, `home-files` entries two levels deep, skill count, `home-path/bin` names) and appends `run.log`, never failing the activation; off unless enabled, so `ubuntu`'s activation package is unchanged.

- [ ] **Step 1: Container test** on magnetite: an Ubuntu 24.04 image with Nix 2.34.6 installed single-user, no daemon; (a) run the generated script twice: the second run changes nothing but files under `/var/log/claude-sandbox-bootstrap`; (b) with `cache.scientistexperience.net` mapped to 127.0.0.1 in `/etc/hosts`, the script exits 0 and its marker line records the failed realise.
- [ ] **Step 2: Compare `ubuntu`'s activation package derivation** before and after. Expected: identical.
- [ ] **Step 3: Commit** with Task 4.

### Task 6: First bootstrap test and probe P4 (tasks.md 3.4–3.6)

**Files:**
- Create: `logs/claude-sandbox/prompt-bootstrap1.md`
- Modify: `openspec/changes/bootstrap-claude-sandbox/design.md` (assumption table)

- [ ] **Step 1: Write the controller prompt** modelled on `prompt-session2.md`: swap `nix-sandbox-test`'s setup step to the script `nix run .#claude-sandbox-setup-script` prints at the merged revision, create child E, then child E2 with no change, and restore; each child reports its first-context check (user context marker heading, a named composed skill listed and loaded), `report.json` and `setup.log`, `echo $PATH`, `<tool> --version` for each R12 tool, whether `~/.claude/settings.json`'s SessionStart hook ran (a hook that appends `date`, `$PATH` and `${CLAUDE_ENV_FILE:+set}` to `/var/log/claude-sandbox-bootstrap/hook.log`), and the names of environment variables visible to the hook and the shell.
- [ ] **Step 2: The operator starts the controller session** with that prompt and accepts its approval cards.
- [ ] **Step 3: Record** E's setup duration against 360 s, E2's start without setup, and S6, S7 and S8's outcomes in design.md.
- [ ] **Step 4: If S6 failed**, add to the bootstrap the PATH route the observation supports (links into `/usr/local/bin`, or a `CLAUDE_ENV_FILE` line from the hook), repeat Steps 2–3.
- [ ] **Step 5: Commit** — `docs(openspec): record the first claude-sandbox bootstrap test`.

### Task 7: Repository context from a SessionStart hook (tasks.md 4.1, 4.2)

**Files:**
- Modify: `modules/home/users/claude-sandbox/default.nix`

**Interfaces:**
- Consumes: `apm-context-compile` (store path), P4's outcome.
- Produces: a SessionStart hook `claude-sandbox-repo-context` that, for each `/home/user/*/apm.yml`, runs `apm-context-compile --auto --if-stale` in that repository, appends one line per repository to `/var/log/claude-sandbox-bootstrap/run.log`, and exits 0.

- [ ] **Step 1: Write the test** in the magnetite container of Task 5: with `~/.claude/CLAUDE.md` present, a repository with `apm.yml` gets `AGENTS.md` and `.agents/.context-compile-key` naming the `default` tier; a repository without `apm.yml` is skipped; a second run changes nothing.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement the hook.**
- [ ] **Step 4: Run it**, then repeat Task 6's loop with vanixiets attached and check no `~/.claude/CLAUDE.md` heading appears in its `AGENTS.md`. Expected: PASS.
- [ ] **Step 5: Commit** — `feat(claude-sandbox): compile attached repositories' context at session start`.

### Task 8: Linear credentials (tasks.md 6.3–6.6)

**Files:**
- Modify: `.sops.yaml`, `modules/home/users/claude-sandbox/default.nix`, `modules/home/users/claude-sandbox/README.md`
- Create: `secrets/home-manager/users/claude-sandbox/secrets.yaml`

**Interfaces:**
- Consumes: the recipient `claude-sandbox-user` = `age1sfddwr9waenu8du9mpxj7l4cfz7w3pkng4tc6xk4k4z09wj9tu8smr9xcf` (tasks.md 6.1, done), `flake.lib.mkLinearCredentialsTemplate`, the `sandbox` session hook (Task 1).
- Produces: `~/.config/linear/credentials.toml` (mode 0400) as a symlink into `/dev/shm/claude-sandbox-sops`, after the session hook runs with `SOPS_AGE_KEY` set.

- [ ] **Step 1: Allowed host** (tasks.md 6.3): a controller session proposes adding `api.linear.app` to `nix-sandbox-test`'s allowed hosts; the operator accepts the approval card. The key `sops-claude-sandbox` and `SOPS_AGE_KEY` already exist (tasks.md 6.1, 6.2).
- [ ] **Step 2: On stibnite with the admin key** (tasks.md 6.4): add `&claude-sandbox-user` and the creation rule for `secrets/home-manager/users/claude-sandbox/.*\.yaml$` with `admin`, `admin-user`, `claude-sandbox-user`; create the file with exactly `linear-api-key-personal`, `linear-api-key-work`, `linear-workspace-personal`, `linear-workspace-work`.
- [ ] **Step 3: Write the test**: in the container test, with a throwaway age key and a fixture file, the session hook with the key set produces `credentials.toml` whose target is under `/dev/shm`; with the key unset it does nothing and exits 0; a second run is a no-op; `rg AGE-SECRET-KEY /root /var/log/claude-sandbox-bootstrap` prints nothing.
- [ ] **Step 4: Declare the four secrets and the template** in the profile; run the test. Expected: PASS.
- [ ] **Step 5: Write the revocation procedure** in the README: remove the recipient from `.sops.yaml`, `sops updatekeys` that file, rotate both Linear keys, clear `SOPS_AGE_KEY`.
- [ ] **Step 6: Verify in a child session**: `linear auth whoami --workspace cameronraysmith` succeeds.
- [ ] **Step 7: Commit** — `feat(claude-sandbox): Linear credentials from a scoped sops file`.

### Task 9: Default environment, cleanup and integration (tasks.md 7, 8)

- [ ] **Step 1: README** for the profile: `nix run .#claude-sandbox-setup-script`, the 30-day renewal, the controller loop, the approval-card cost, the operator steps.
- [ ] **Step 2: Integration round** from a controller session: 8.1 (all of R1, R7, R8, R12, R14), 8.2 (a setup script whose `P` the cache lacks: session starts, its marker line names it), 8.3 (harness-owned names and sizes match a session with no setup step), 8.4 (operator actions counted).
- [ ] **Step 3: Switch the default environment** to the generated setup script (one approval card), and renew it at least every 30 days.
- [ ] **Step 4: Delete the scratch report branches** listed in tasks.md 7.3.
- [ ] **Step 5: Commit** — `docs(claude-sandbox): document the cloud environment bootstrap`.
