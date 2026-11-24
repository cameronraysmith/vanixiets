# Skills single-source marketplaces Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** One authored tree serves the hermetic Nix build, apm consumers and Claude's marketplace dialog, with every generated file and composed tree held by a check.

**Architecture:** Group `apm.yml` files and the root `marketplace:` block are the only authored facts; one derivation runs `apm pack` and a jq filter to write both marketplace files; checks compare the committed files, install them with Claude Code and apm offline, and compare the composed trees with their sources and recorded hashes. Design: `design.md` D1-D12; requirements: `specs/`.

**Tech Stack:** Nix (flake-parts, `runCommand`, filesets), apm 0.38.0 and Claude Code 2.1.330 from `llm-agents`, jq, yq-go, bash.

**Grounding (exact invocations proven on 2026-11-23):**
- Generator manifest: `yq 'del(.dependencies) | del(.compilation) | del(.marketplace.output) | .marketplace.outputs = {"claude": {}, "copilot": {}}' apm.yml`, then `HOME=$TMPDIR/h APM_CACHE_DIR=$TMPDIR/c APM_E2E_TESTS=1 apm pack --offline` in a directory holding that manifest and `modules/home/ai/plugins/*/apm.yml`.
- Claude filter: `jq --argjson skillGroups "$groups" '.metadata = ((.metadata // {}) + {description: $d}) | .plugins |= map(select(.name as $n | $skillGroups | index($n)) | del(.version) + {skills: ["./.apm/skills"], strict: false})'`.
- Claude check body (ran offline in the magnetite sandbox): `HOME=$TMPDIR/home CLAUDE_CONFIG_DIR=$HOME/.claude DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`; `claude plugin validate m`; `claude plugin marketplace add "$PWD/m"`; per entry `claude plugin install "$g@vanixiets"` and `claude plugin details "$g@vanixiets" | sed -n 's/^  Skills (\([0-9]*\)).*/\1/p'`. Compare names, not only counts, by parsing the `Skills (N)` line's list.
- apm consumer check body (ran offline in the magnetite sandbox): `git init -b main` + commit of the marketplace files, group directories and root `apm.yml`; `git clone --bare`; `git config --global url."file://$PWD/served.git".insteadOf https://git.vanixiets.test/cameronraysmith/vanixiets.git`; `apm marketplace add <url> --name vanixiets --ref main`; `apm install <g>@vanixiets -t agent-skills,claude`.

---

## Task 1: Stage 1 close-out (tasks 1.4, 1.5)

- [ ] **Step 1:** Rerun the F6 procedure (edit a file inside `apm_modules/<dep>` after a lock, run `apm install`, expect deletion and re-fetch) with apm 0.38.0 in a scratch HOME; save `logs/apm-verify-f6-038-<ts>.log`.
- [ ] **Step 2:** Rerun F5 (inspect the `apm lock` output of the download for `deployed_files`); save `logs/apm-verify-f5-038-<ts>.log`; update A138 and A140 Evidence in `specs/world-assumptions/spec.md`.
- [ ] **Step 3:** On magnetite build the apm-touching checks (`apps-build`, `package-apm-skills-compose`, `eval-apm-guard`, the release-alignment checks, the home-manager and nixos toplevels listed in the E4 report); evaluate all aarch64-darwin checks.
- [ ] **Step 4:** Commit `docs(openspec): restate apm world assumptions for 0.38`.

## Task 2: Shared group discovery (task 2.1)

- [ ] **Step 1:** Record `nix eval --raw .#apm-skills-compose.drvPath` and `.deps.drvPath` for both systems.
- [ ] **Step 2:** Create `modules/home/ai/plugins/groups.nix` returning `{ all; skills; }` from `builtins.readDir ./.` and `builtins.pathExists (./. + "/${n}/.apm/skills")`.
- [ ] **Step 3:** Use it in `package.nix` (`firstPartyPackages` default), `deps.nix` (`discovered`) and `modules/home/ai/skills/compose.nix` (`aiSkills.packages` default).
- [ ] **Step 4:** Re-evaluate both drvPaths; they must be identical to Step 1. Commit `refactor(apm-skills-compose): discover plugin groups once`.

## Task 3: Compose hardening (tasks 2.2, 2.3)

- [ ] **Step 1:** Mutant first: add `export CI=true` before `apm install` in a local override; build; expect "missing from apm.lock.yaml".
- [ ] **Step 2:** Add `--no-frozen`; rebuild the override; expect success. Remove the override.
- [ ] **Step 3:** Add `rm -f "$out/.apm-local/installation"` after the install; `nix build --rebuild .#apm-skills-compose` must report no difference.
- [ ] **Step 4:** Commit `fix(apm-skills-compose): never frozen, reproducible output`.

## Task 4: Tree oracle (tasks 2.4, 2.5)

- [ ] **Step 1:** Change `skills.json` to `{ names: [...], remote: { <name>: "<sha256-…>" } }`; first-party names are those under `pluginsDir/<group>/.apm/skills`, computed at evaluation time.
- [ ] **Step 2:** Update `just agents-skills-index` to write both keys from the built compose (`nix hash path $out/.claude/skills/<n>` for remote names); update every reader of `skills.json` (`modules/home/ai/skills/default.nix`, `passthru.skillNames`) to `.names`.
- [ ] **Step 3:** Replace the 26-path loop in `package.nix` with: names guard (existing), `diff -r` per first-party skill against its source, `nix-hash --type sha256 --sri` (or `nix hash path`) per remote skill against the index, `diff -r .claude/skills .agents/skills`.
- [ ] **Step 4:** Mutants as one-off overrides that alter `$out` just before the oracle: append a byte to `.claude/skills/brainstorming/SKILL.md` (expect hash failure naming `brainstorming`); delete `.claude/skills/nix-flake-pr-cycle/SKILL.md` (expect diff failure). Run each case alone.
- [ ] **Step 5:** Build on aarch64-darwin and on magnetite. Commit `feat(apm-skills-compose): compare composed skills with sources and recorded hashes`.

## Task 5: mattpocock list rule (task 2.6)

- [ ] **Step 1:** In `deps.nix`, select the mattpocock entry from `guard.remoteDeps`; fetch its ref with `git fetch --depth 1` (with blobs; the lazy blob fetch is untested) and read `.claude-plugin/plugin.json` with `git show`.
- [ ] **Step 2:** Compare `jq -r '.skills[] | split("/") | last'` sorted with the declared `skills:` list; print both sides on difference.
- [ ] **Step 3:** Mutant: remove `tdd` from the list; the download is renamed (guard digest) and fails naming `tdd`. Revert.
- [ ] **Step 4:** Commit `feat(apm-deps): check the mattpocock skill list against upstream`.

## Task 6: Delete the per-group plugin.json (tasks 3.1, 3.2)

- [ ] **Step 1:** Delete the 22 files; build the compose on both systems (the tree oracle must pass) and `nix build --rebuild` the download.
- [ ] **Step 2:** Update `modules/home/ai/plugins/README.md` (lines 10-12) and the `agent-context-vanixiets` fragment (lines 10, 23); run `just agents-context`.
- [ ] **Step 3:** Commit `refactor(plugins): drop the per-group plugin.json`.

## Task 7: Generator and drift check (tasks 4.1-4.5)

- [ ] **Step 1:** Edit the root `apm.yml` (delete `packages[].version`, replace `output` with `outputs`); move the three apps' identity guards to `.name == "vanixiets"` and `.marketplace.packages`; point validate's served-file lookup at `.github/plugin/marketplace.json`.
- [ ] **Step 2:** Write `pkgs/by-name/skills-marketplace/package.nix` with the grounding commands above and the three structural assertions (no group `plugin.json` or `.claude-plugin/`; published list equals `groups.all`; names equal directories).
- [ ] **Step 3:** Add `just agents-marketplace` (build, copy both files into place); run it; commit the two files.
- [ ] **Step 4:** Add `modules/checks/skills-marketplace.nix` with `checks.x86_64-linux.skills-marketplace-drift` (`diff` of committed against generated; `lib.optionalAttrs (system == "x86_64-linux")`).
- [ ] **Step 5:** Mutant: edit one description without regenerating; the check fails with the diff. Revert. Commit `feat(plugins): generate the apm and Claude marketplace files`.

## Task 8: Claude install check (task 4.6)

- [ ] **Step 1:** Add `checks.x86_64-linux.claude-marketplace-install` to the same module, using the grounding body; its source is a fileset of `.claude-plugin/` and `modules/home/ai/plugins/`.
- [ ] **Step 2:** Mutants, one at a time: `skills: [".apm/skills"]`; a missing `source`; an entry without `skills`. Each must fail at the named step.
- [ ] **Step 3:** Commit `feat(checks): install every Claude marketplace entry offline`.

## Task 9: Consumer route and docs (tasks 5.1-5.4)

- [ ] **Step 1:** Add `checks.x86_64-linux.apm-marketplace-consumer` with the grounding body over the groups without remote dependencies plus `agent-context-core`; mutant: misspell one `source`.
- [ ] **Step 2:** Add `agents-marketplace-remote *args:` to `justfile` with body `{{nix_cmd}} run .#apm-marketplace-validate -- --remote {{args}}` (the app is already `writeShellApplication` plus sidecar; no new script).
- [ ] **Step 3:** Write the Claude-user section in the plugins README and the docs guide.
- [ ] **Step 4:** Commit; after merge, ask the operator to delete `origin/claude-marketplace`, and run the integration verification in `tasks.md` §6.
