# Bootstrap Claude Code cloud sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A cloud session started on the operator's cloud environment gets the user context, the skill corpus, the required tools, each attached repository's context and the Linear credentials, from one pinned setup line.

**Architecture:** A `claude-sandbox@x86_64-linux` home configuration (D1) is built by one CI check and published to `cache.scientistexperience.net` (D2).
A channels-only sub-flake at `bootstrap/claude-sandbox` carries a generated pointer to that activation package; the setup step runs it by pinned revision, it substitutes and activates without evaluating the main flake, reports, and always exits 0.
Session-time work (repository context, D3; Linear secrets, D5) runs from hooks whose commands are store paths (D4).

**Tech Stack:** Nix flakes (flake-parts, import-tree), home-manager, sops-nix, `apm-context-compile`, nixbot and niks3, Claude Code cloud environments.

**Spec:** `openspec/changes/bootstrap-claude-sandbox/` — `specs/claude-sandbox-bootstrap/spec.md` (requirements), `specs/world-assumptions/spec.md` (A167–A179), `design.md` (D1–D5, assumptions S1–S10, probe P4), `tasks.md` (task groups 1–8, which this plan's tasks map to).

## Global Constraints

- Platform: `x86_64-linux` only; username `root`; home `/root`.
- The setup step is one line: `nix run "git+https://github.com/cameronraysmith/vanixiets?rev=<40-hex sha>&shallow=1&dir=bootstrap/claude-sandbox"; exit 0`, within 100 lines of 200 bytes.
- `bootstrap/claude-sandbox/flake.nix` has no `github:` input; its only input is `https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz`.
- Every bootstrap and hook path exits 0.
- Setup finishes within 360 seconds on a cache hit.
- No secret in the setup step, in any file under `/root`, `/var/log/claude-sandbox-bootstrap` or `/nix`, or in any report; secrets are decrypted only into `/dev/shm`.
- Never write `launcher-settings.json`, `session-start-setup-script-failure.sh`, `stop-hook-git-check.sh`, `environment-manager/`, `skills/session-start-hook` or `skills/synced` under `/root/.claude`.
- Binary cache: `https://cache.scientistexperience.net`, key `cache.scientistexperience.net-1:N9ZeWasooJLXEwaN+rd4MMyBuGpAtcUAXrEUPBT5cXI=` (from `flake.nix` `nixConfig`).
- Reports go to `/var/log/claude-sandbox-bootstrap/`.
- x86_64-linux builds run on magnetite; darwin configurations are evaluated only.
- Prose in READMEs: one sentence per line.

## Review Focus

1. A stale pointer: the pointer names a store path that the revision's activation package no longer has → the pointer check fails CI (Task 4, mutant test).
2. A realise that fails halfway → nothing is activated, the report names the failed path, exit 0 (Task 5, cache-miss test).
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

### Task 4: CI check and pointer (tasks.md 3.1, 3.3)

**Files:**
- Create: `modules/checks/claude-sandbox.nix`, `bootstrap/claude-sandbox/activation.json`, `modules/apps/claude-sandbox-pointer.sh` (registered as `apps.claude-sandbox-pointer`)

**Interfaces:**
- Produces: `checks.x86_64-linux.claude-sandbox-activation` (the activation package itself) and `checks.x86_64-linux.claude-sandbox-pointer` (fails unless `activation.json`'s `.activationPackage` equals the evaluated store path); `nix run .#claude-sandbox-pointer` rewrites `activation.json` as `{"activationPackage": "<store path>", "system": "x86_64-linux"}`.

- [ ] **Step 1: Write the pointer check and a mutant test** — the check reads `bootstrap/claude-sandbox/activation.json` with `builtins.fromJSON (builtins.readFile ...)`; a mutant with a changed hash must fail.
- [ ] **Step 2: Run** `nix build .#checks.x86_64-linux.claude-sandbox-pointer` with no pointer file. Expected: FAIL.
- [ ] **Step 3: Implement the app and generate the pointer.**
- [ ] **Step 4: Run both checks.** Expected: PASS; then change only `activation.json`'s whitespace and confirm `nix eval .#homeConfigurations."claude-sandbox@x86_64-linux".activationPackage.outPath` is unchanged (S4).
- [ ] **Step 5: Commit** — `feat(checks): build and point at the claude-sandbox activation package`; after merge, confirm `nix path-info --store https://cache.scientistexperience.net <path>` answers.

### Task 5: The bootstrap sub-flake (tasks.md 3.2, 5.1)

**Files:**
- Create: `bootstrap/claude-sandbox/flake.nix`, `bootstrap/claude-sandbox/bootstrap.sh`, `bootstrap/claude-sandbox/README.md`

**Interfaces:**
- Consumes: `activation.json` (Task 4).
- Produces: `apps.x86_64-linux.default`, a `writeShellApplication` `claude-sandbox-bootstrap` that: records start time, `nix --version` and the pointer to `/var/log/claude-sandbox-bootstrap/report.md`; runs `nix-store --realise <path> --option extra-substituters https://cache.scientistexperience.net --option extra-trusted-public-keys <key>` under `timeout`; on success, `USER=root <path>/activate`; records each step's exit code and duration; exits 0 on every path.
  A second run with the same store path already activated records "already active" and does nothing else.

- [ ] **Step 1: Write the container test** `bootstrap/claude-sandbox/test.sh`: in an Ubuntu 24.04 container with Nix 2.34.6 installed single-user, (a) a cache miss (pointer to a nonexistent hash) must exit 0 and leave `report.md` naming the path and `activate` not run; (b) a hit must exit 0 with `/root/.claude/CLAUDE.md` present; (c) a second run must change no file but the report.
- [ ] **Step 2: Run it.** Expected: FAIL (no app).
- [ ] **Step 3: Implement the flake and script.**
- [ ] **Step 4: Run the test** and `nix flake metadata ./bootstrap/claude-sandbox --json | jq '[.locks.nodes[] | .locked.type?] | unique'`. Expected: PASS; no `github`.
- [ ] **Step 5: Commit** — `feat(bootstrap): substitute and activate the claude-sandbox profile`.

### Task 6: First bootstrap test and probe P4 (tasks.md 3.4–3.6)

**Files:**
- Create: `logs/claude-sandbox/prompt-bootstrap1.md`
- Modify: `openspec/changes/bootstrap-claude-sandbox/design.md` (assumption table)

- [ ] **Step 1: Write the controller prompt** modelled on `prompt-session2.md`: swap `nix-sandbox-test`'s setup step to the one pinned line at the merged revision, create child E, then child E2 with no change, and restore; each child reports its first-context check (user context marker heading, a named composed skill listed and loaded), `report.md`, `echo $PATH`, `<tool> --version` for each R12 tool, whether `~/.claude/settings.json`'s SessionStart hook ran (a hook that appends `date`, `$PATH` and `${CLAUDE_ENV_FILE:+set}` to `/var/log/claude-sandbox-bootstrap/hook.log`), and the names of environment variables visible to the hook and the shell.
- [ ] **Step 2: The operator starts the controller session** with that prompt and accepts its approval cards.
- [ ] **Step 3: Record** E's setup duration against 360 s, E2's start without setup, and S6, S7 and S8's outcomes in design.md.
- [ ] **Step 4: If S6 failed**, add to the bootstrap the PATH route the observation supports (links into `/usr/local/bin`, or a `CLAUDE_ENV_FILE` line from the hook), repeat Steps 2–3.
- [ ] **Step 5: Commit** — `docs(openspec): record the first claude-sandbox bootstrap test`.

### Task 7: Repository context from a SessionStart hook (tasks.md 4.1, 4.2)

**Files:**
- Modify: `modules/home/users/claude-sandbox/default.nix`

**Interfaces:**
- Consumes: `apm-context-compile` (store path), P4's outcome.
- Produces: a SessionStart hook `claude-sandbox-repo-context` that, for each `/home/user/*/apm.yml`, runs `apm-context-compile --auto --if-stale` in that repository, appends one line per repository to `report.md`, and exits 0.

- [ ] **Step 1: Write the test** in `bootstrap/claude-sandbox/test.sh`: with `~/.claude/CLAUDE.md` present, a repository with `apm.yml` gets `AGENTS.md` and `.agents/.context-compile-key` naming the `default` tier; a repository without `apm.yml` is skipped; a second run changes nothing.
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

- [ ] **Step 1: README** for `bootstrap/claude-sandbox` and the profile: the pinned-line format, the controller loop, the approval-card cost, the operator steps.
- [ ] **Step 2: Integration round** from a controller session: 8.1 (all of R1, R7, R8, R12, R14), 8.2 (pointer to a missing path: session starts, report names it), 8.3 (harness-owned names and sizes match a session with no setup step), 8.4 (operator actions counted).
- [ ] **Step 3: Switch the default environment** to the pinned line (one approval card).
- [ ] **Step 4: Delete the scratch report branches** listed in tasks.md 7.3.
- [ ] **Step 5: Commit** — `docs(claude-sandbox): document the cloud environment bootstrap`.
