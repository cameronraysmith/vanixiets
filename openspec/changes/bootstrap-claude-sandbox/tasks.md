D1–D5 were decided by the operator on 2026-11-21 (design.md §Decisions).
Group 4's hook wiring is gated on probe P4 (task 3.4); group 6's operator steps 6.1 and 6.2 are done, and its encryption step 6.4 is run on stibnite with the admin key.
`plan.md` decomposes groups 1–8 into steps.

## 0. Probes (completed 2026-11-21)

- [x] 0.1 Record the platform facts from session 99972732 (cloud, then teleported) — verify: the brief's V1–V35 and C1–C18 items, quoted where used in `specs/world-assumptions` (A172, A175, A177, A178).
- [x] 0.2 Probe session 1 (`setup-v0.sh`, `prompt-session1.md`): context loading (P3), shell environment (P4, first part), setup identity and output (P6), registry (P8), disk (P9), session tools (P1), pushing (P2) — verify: its report, quoted in A167, A172, A173, A174, A175, A177 and A179.
- [x] 0.3 Probe session 2 controller (`setup-v1{a,b,c}.sh`, `prompt-session2.md`) with children A, A2, B, B2 and D against the probe flake `bootstrap/claude-sandbox` at `7fffbd2c2464f7663348fde7882541b430507714` on branch `claude-sandbox-dev` — verify: its controller report, quoted in A167–A171, A176, A178 and A179.

## 1. D1: the `claude-sandbox` profile and the shared `sandbox` aggregate

- [ ] 1.1 Factor the systemd-less sandbox handling out of `modules/home/users/ubuntu/default.nix` into a `sandbox` aggregate parameterised by its tmpfs directory, and import it from `ubuntu` — verify: `ubuntu@x86_64-linux`'s rendered `home-files` and activation script are identical before and after, compared by `nix build` and `diff -r` on magnetite.
- [ ] 1.2 Add the `claude-sandbox` user (username `root`, home `/root`, `systems = [ "x86_64-linux" ]`) importing `sandbox`, `agents-md`, `agent-context`, `ai-capabilities`, a sandbox-safe Claude Code subset with `programs.claude-code.enable`, and R12's tool set — verify: `nix eval .#homeConfigurations."claude-sandbox@x86_64-linux".config.home.homeDirectory` is `/root`, and the configuration evaluates with no sops secret except D5's.
- [ ] 1.3 Add `claude-sandbox@x86_64-linux` to `modules/checks/structure/flake-shape.nix` — verify: the flake-shape check passes with it and fails without it.
- [ ] 1.4 Build the activation package and list what it delivers — verify: `nix build` on magnetite; its `home-files` contain `.claude/CLAUDE.md` equal to crs58's, one `.claude/skills/<n>` per skill in `skills.json` (minus the excluded ones), and `home-path/bin` contains every R12 tool; record `nix path-info -S` of the closure.
- [ ] 1.5 Confirm no path the profile writes is harness-owned (A178) — verify: the list of `home-files` paths under `.claude` contains none of `launcher-settings.json`, `session-start-setup-script-failure.sh`, `stop-hook-git-check.sh`, `environment-manager/`, `skills/session-start-hook`, `skills/synced`.

## 2. D4: hook commands by store path

- [ ] 2.1 Change `modules/home/ai/claude-code/hooks.nix` to refer to every hook command by its store path — verify: `nix eval` of crs58's and `claude-sandbox`'s Claude Code `settings.json` hooks shows only `/nix/store/...` commands; after activation on stibnite, a Bash and an Edit tool call in a local Claude Code session run their hooks with no "command not found".

## 3. D2: CI-built activation package and the pinned bootstrap

- [ ] 3.1 Add one `checks.x86_64-linux` attribute that builds `claude-sandbox@x86_64-linux`'s activation package — verify: nixbot builds it on a pull request and `nix path-info --store https://cache.scientistexperience.net <path>` answers after the build.
- [ ] 3.2 Replace the probe app in `bootstrap/claude-sandbox` with the bootstrap app (realise the pointed store path with `cache.scientistexperience.net` and its key as options, export `USER=root`, activate, write the bootstrap report under `/var/log/claude-sandbox-bootstrap/`, exit 0 on every path), keeping a channels-only input — verify: `nix flake metadata` of the sub-flake lists no `github` input; running the app in an Ubuntu 24.04 container with no network to the cache exits 0 and writes a report naming the miss.
- [ ] 3.3 Generate the pointer file and add the check that fails when it differs from the evaluated activation package — verify: the check passes on the generating commit and fails on a mutant pointer; a commit changing only the pointer leaves the activation package's store path unchanged (S4).
- [ ] 3.4 First bootstrap test, including probe P4: from a controller session on `nix-sandbox-test`, swap the setup step to the one pinned line for this group's revision and create a child — verify: the child's report shows the user context loaded and a composed skill listed and loaded in its first prompt; the bootstrap report's per-step times and total (against 360 s); the agent's shell `PATH` and each R12 tool's version by bare name; whether a SessionStart hook from the setup-written `~/.claude/settings.json` ran, with its `PATH` and `CLAUDE_ENV_FILE`; whether an environment variable is visible to the hook and the shell (names only).
- [ ] 3.5 Record P4's results against S6, S7 and S8 in design.md, and pick the PATH route for R12 if S6 fails (a `CLAUDE_ENV_FILE` line written by the hook, or links into `/usr/local/bin`) — verify: design.md's assumption table updated with the observed values; R12 re-tested in a child session.
- [ ] 3.6 Snapshot reuse on the bootstrap revision — verify: a second child created without changes starts without running setup (its bootstrap report holds only runs from before it booted).

## 4. D3: repository context from a SessionStart hook (gated on 3.4)

- [ ] 4.1 Declare a SessionStart hook in the profile that runs `apm-context-compile --auto` by store path in each attached repository under `/home/user` with an `apm.yml`, always exits 0 and appends to the bootstrap report — verify: `nix eval` of the profile's `settings.json` hooks; in a child session with vanixiets attached, `AGENTS.md` and `CLAUDE.md` exist in its working tree before the first command, and `.agents/.context-compile-key` names the `default` tier.
- [ ] 4.2 Check the repository context does not repeat the user context — verify: in that child, no heading of `~/.claude/CLAUDE.md` appears in the repository's `AGENTS.md`.

## 5. Bootstrap report and idempotence

- [ ] 5.1 Make a second bootstrap run in the same container a no-op apart from its report — verify: run the app twice in an Ubuntu 24.04 container; `find /root -newer <marker>` after the second run lists only report files, and the network log shows no request other than to the channels, GitHub's git service and the two caches.
- [ ] 5.2 Search the setup step, a snapshot-started child's disk and every report for secrets — verify: `rg` for the Linear key prefixes and `AGE-SECRET-KEY` over `/root`, `/var/log/claude-sandbox-bootstrap` and `/nix/var` in a child session prints nothing.

## 6. D5: Linear credentials for cloud sessions

- [x] 6.1 Operator steps: create the Bitwarden SSH key `sops-claude-sandbox`; derive its age recipient `claude-sandbox-user` with `ssh-to-age` from its public key `sops-claude-sandbox.pub` and supply only the public recipient — verify: the recipient, which `age` accepts, is recorded here.
  Done by the operator on 2026-11-21: `claude-sandbox-user` = `age1sfddwr9waenu8du9mpxj7l4cfz7w3pkng4tc6xk4k4z09wj9tu8smr9xcf`.
- [x] 6.2 Operator step: put the private age key directly into the `nix-sandbox-test` environment's `SOPS_AGE_KEY` variable in claude.ai's environment settings, never through chat or the clipboard — verify: `get_environment` lists `SOPS_AGE_KEY` among `environment_variable_names` (names only).
  Done by the operator on 2026-11-21; the `get_environment` listing is read in the first D5 session (task 6.5).
- [ ] 6.3 Add `api.linear.app` to `nix-sandbox-test`'s allowed hosts (one approval card) — verify: `get_environment` lists it among the allowed hosts.
- [ ] 6.4 On stibnite with the admin key: add `claude-sandbox-user` to `.sops.yaml` with a rule for `secrets/home-manager/users/claude-sandbox/.*\.yaml$` encrypted to `admin`, `admin-user` and `claude-sandbox-user`, and create that file — verify: `sops -d` with the admin key opens the file; its keys are exactly `linear-api-key-{personal,work}` and `linear-workspace-{personal,work}`; its recipients are exactly those three.
- [ ] 6.5 Declare those secrets in the `claude-sandbox` profile and render `~/.config/linear/credentials.toml` with `mkLinearCredentialsTemplate`, decrypted at session start through the `sandbox` aggregate's hook into `/dev/shm` — verify: `nix eval` of the profile's sops paths shows only `/dev/shm` targets; in a child session, `linear auth whoami --workspace cameronraysmith` succeeds and `/dev/shm` holds the plaintext while `/root` holds only symlinks.
- [ ] 6.6 Write the revocation procedure next to the sops rule: remove the recipient, `sops updatekeys` that one file, rotate the Linear keys, clear the variable — verify: the procedure is in the profile's README and names exactly those steps.

## 7. Default environment and documentation

- [ ] 7.1 Document the cloud environment, the one pinned line, the controller loop and the operator steps in the nearest README of the profile and of `bootstrap/claude-sandbox` — verify: both READMEs exist and name the pinned-line format and the approval-card cost.
- [ ] 7.2 Switch the operator's default cloud environment's setup step to the pinned line — verify: `get_environment` on it shows the line; a new session on it passes 8.1.
- [ ] 7.3 Delete the scratch probe report branches once this change has landed: `claude/sandbox-reports`, `sandbox-reports-plain`, `claude/sandbox-reports-s2`, `-s2A`, `-s2A2`, `-s2B`, `-s2B2` — verify: `git ls-remote --heads origin 'claude/sandbox-reports*' sandbox-reports-plain` prints nothing.

## 8. Integration Verification

- [ ] 8.1 Verify a fresh cloud session satisfies R1, R7, R8, R12 and R14 together with one child session created by a controller on the final revision — verify: the child's report shows the user context and skill corpus in its first prompt, every R12 tool by name, vanixiets' repository context present, `linear auth whoami --workspace cameronraysmith` succeeding, and a bootstrap report.
- [ ] 8.2 Verify R3 with a deliberately broken revision (pointer to a path the cache lacks) — verify: the child session starts, and its bootstrap report names the missing path.
- [ ] 8.3 Verify R5 — verify: the child's harness-owned paths under `/root/.claude` have the same names and sizes as in a session on an environment with no setup step.
- [ ] 8.4 Verify R10 — verify: the operator's actions across 3.4–8.3 were one controller prompt per round plus one approval card per setup step change, recorded in the controller's report.
