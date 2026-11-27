# Establish the refactor oracle implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a committed `just drv-diff` that proves a refactor changed no derivation it did not declare across the fleet's systems, homes, checks and runtime tests; a committed `just eval-cost` A/B/A/B protocol with recorded baselines; and planning and architecture documents brought current (tasks.md groups 1–7).

**Architecture:** two flake apps in the house pattern of `modules/apps/nix-eval-jobs-identity.{nix,sh}` (a `writeShellApplication` with pinned `runtimeInputs` and `NIX_STOCK = flake.lib.fleetNix`), each fronted by a justfile recipe beside `eval-identity`; both read the two commits through `git+file://<repo>?rev=<commit>` and build nothing. The rest is documentation.

**Tech Stack:** bash, jq, git; stock Nix (`flake.lib.fleetNix`) and `nix-eval-jobs-stock`/`nix-eval-jobs`; flake-parts `perSystem.apps`; markdown under `docs/` and the Starlight docs package.

**Spec:** `openspec/changes/establish-refactor-oracle/` — `design.md` (D1–D13), `specs/refactor-identity-oracle`, `specs/refactor-identity-oracle-interface`, `specs/world-assumptions` (A310–A313), `tasks.md`.

---

## Global Constraints

- One chain, landing as one pull request. Edits in `@`, routed with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`. Every commit evaluates alone.
- No deployed output may change; the checks built from the whole flake source (design D13) change on every commit and are allowed by the base allow-list. Task 6 (tasks.md 3.4) proves it with the tool this change adds.
- Runs expected to exceed 5 minutes (tasks.md 3.1, 3.2, 3.4, 3.5, 4.2) are announced first with expected duration, what they prove that a cheaper run cannot, and what waits on them; an agent applying this plan for someone else returns the notice to whoever assigned the work instead of starting the run.
- The mutant revisions of tasks.md 3.2 and 3.5 live in throwaway jj changes that are abandoned afterwards and never pushed.
- The skill `preferences-nix-checks-architecture` is not edited; its source is `modules/home/ai/plugins/preferences-nix-and-secrets/.apm/skills/…/references/evaluation-cost.md` and the `~/.claude/skills` copy is delivered output, never edited.
- ADR edits are in `packages/docs/src/content/docs/development/architecture/adrs/` (source), never in the built site.

## Grounding: the vendored consumers' interfaces

- `nix-eval-jobs` (vendored), as `modules/apps/nix-eval-jobs-identity.sh:56-62` already invokes it: `--flake <ref> [--force-recurse] --workers N --max-memory-size MIB --gc-roots-dir DIR --option allow-import-from-derivation false --option eval-cache false`. Output: one JSON object per line with `attr`, `drvPath`, `system`, `outputs`, or `error` on failure. The oracle projects `{attr, drvPath, error: has("error")}`. Any pre-merge probe uses exactly this argument list.
- Stock Nix: `nix eval --raw '<ref>#<attr>.drvPath' --option eval-cache false`; `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file>` writes `cpuTime`, `gc.totalBytes`, `nrThunks`, `envs.number` (the fields present in `logs/cross-host-eval-cost-b-20261126-174313.stats.json`).
- Flake reference: `git+file://<abs repo>?rev=<40-hex>`; attribute names with `@` (home configurations) are quoted: `homeConfigurations."crs58@aarch64-darwin".activationPackage`.

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| App | `apps.<system>.drv-diff` (`--before REV --after REV [--allow FILE] [--systems "S…"] [--vm-systems "S…"] [--workers N] [--max-memory-size MIB]`) | Task 1 |
| Recipe | `just drv-diff before after allow="" systems="x86_64-linux aarch64-darwin" vm-systems="x86_64-linux aarch64-linux"` | Task 1 |
| File format | allow-list line: `<set>.<attr> <changed\|added\|removed\|may-change>  # reason`; `<set>` ∈ `nixos`, `darwin`, `home`, `checks.<s>`, `vmTests.<s>`; exact attribute paths only | Task 1 |
| File | `modules/apps/drv-diff-base-allow.txt`: `may-change` entries for the whole-source checks, applied on every run | Task 1 |
| Exit status | 0 pass; 1 undeclared or absent declared difference; 2 usage error (including a change's entry repeating a base entry) or dump failure | Task 1 |
| Evidence | `logs/drv-diff-<before12>-<after12>-<UTC>/{header,<set>.<rev>.json,report}` | Task 1 |
| App | `apps.<system>.eval-cost` (`--attr A --before REV --after REV [--runs N] [--mode drv\|keys] [--label L]`) | Task 2 |
| Recipe | `just eval-cost attr before after runs="2" mode="drv"` | Task 2 |
| Evidence | `logs/eval-cost-<label>-<UTC>.{log,jsonl}` | Task 2 |
| Doc | `docs/notes/development/eval-cost-baselines.md` | Task 4 |

---

## Task 1: `drv-diff` (tasks.md 1.1–1.4)

**Files:** create `modules/apps/drv-diff.sh`, `modules/apps/drv-diff.nix`, `modules/apps/drv-diff-base-allow.txt`; modify `justfile` (after `eval-identity`, `justfile:447-452`).

- [ ] **Step 1:** Write `drv-diff.sh` usage and argument parsing, copying the shape of `nix-eval-jobs-identity.sh:4-45`. Resolve `repo=$(git rev-parse --show-toplevel)`, `before`/`after` with `git -C "$repo" rev-parse --verify "$rev^{commit}"`; missing either is exit 2.
- [ ] **Step 2:** Write the configuration dump. For each commit `c` and set:
  ```bash
  ref="git+file://$repo?rev=$c"
  names() { "$NIX_STOCK" eval --json "$ref#$1" --apply builtins.attrNames | jq -r '.[]'; }
  dump_cfg() { # set attrpath-suffix outer
    local set=$1 outer=$2 suffix=$3 out=$dir/$set.$c.jsonl
    : >"$out"
    while read -r n; do
      if d=$("$NIX_STOCK" eval --raw --option eval-cache false "$ref#$outer.\"$n\".$suffix.drvPath" 2>>"$dir/$set.$c.err"); then
        jq -nc --arg a "$n" --arg d "$d" '{attr:$a, drvPath:$d, error:false}' >>"$out"
      else
        jq -nc --arg a "$n" '{attr:$a, drvPath:null, error:true}' >>"$out"
      fi
    done < <(names "$outer")
  }
  dump_cfg nixos  nixosConfigurations  config.system.build.toplevel
  dump_cfg darwin darwinConfigurations config.system.build.toplevel
  dump_cfg home   homeConfigurations   activationPackage
  ```
  A failure of `names` itself is exit 2.
- [ ] **Step 3:** Write the `checks`/`vmTests` dump with the vendored argument list above (`--force-recurse` for `checks` only); project with `jq -c -S '{attr, drvPath, error: has("error")}' | sort`. Pick `nix-eval-jobs-stock` if `command -v` finds it, else `nix-eval-jobs`; a non-zero exit is exit 2.
- [ ] **Step 4:** Write `header`: both commits, `readlink -f` and `--version` of `$NIX_STOCK`, `readlink -f` of the chosen `nix-eval-jobs` (its store path name carries the version; iets rejects `--version`), host name, `date -u`.
- [ ] **Step 5:** Write the comparison: for each set, `jq -s` over both dumps into `{attr: {before, after}}`; classify each key as identical, both-error, changed, added, removed, error-at-one. Parse the base allow-list (`$DRV_DIFF_BASE_ALLOW`, design D13) and then the `--allow` file (strip `#…`, skip blanks, split on whitespace into key and expectation; an unknown expectation or set is exit 2; a key present at neither commit is exit 2; a key of the `--allow` file already in the base list is exit 2). Fail (exit 1) for every non-identical, non-both-error key without an entry whose expectation matches (`may-change` matches any difference; `changed` matches changed and error-at-one; `added`/`removed` match their own), and for every `changed`/`added`/`removed` entry whose key is identical. Print counts per set and every difference with both drvPaths, marking those allowed by the base list, to stdout and `report`.
- [ ] **Step 6:** `shellcheck modules/apps/drv-diff.sh`. Expected: clean.
- [ ] **Step 7:** Write `drv-diff.nix` from `modules/apps/nix-classic-identity.nix`: `runtimeInputs = [ pkgs.coreutils pkgs.diffutils pkgs.git pkgs.jq ]`, `runtimeEnv.NIX_STOCK = lib.getExe (flakeLib.fleetNix pkgs)`, `runtimeEnv.DRV_DIFF_BASE_ALLOW = ./drv-diff-base-allow.txt`, `meta.description = "Diff drvPaths of every system, home, check and runtime test between two commits"`. Do not put `nix-eval-jobs` in `runtimeInputs`: the host's own name must be used, as in the identity app.
- [ ] **Step 7a:** Write `drv-diff-base-allow.txt` per tasks.md 1.4: `rg -n 'src = self|self\.outPath|"\$\{self\}"|projectRoot' modules/checks modules/formatting.nix`, keep each check whose source is the whole tree, one `checks.<s>.<name> may-change  # <file>:<line>, whole flake source` line per dumped system that defines it.
- [ ] **Step 8:** Add the recipe:
  ```just
  # The cross-revision drvPath oracle: every nixos/darwin toplevel, home activationPackage,
  # checks.<systems> and vmTests.<vm-systems> at two commits, diffed; nothing is built.
  # Differences must be declared in `allow` (see modules/apps/drv-diff.sh --help).
  # Pass a jj change by commit id: $(jj log -r <rev> --no-graph -T commit_id).
  [group('nix')]
  drv-diff before after allow="" systems="x86_64-linux aarch64-darwin" vm-systems="x86_64-linux aarch64-linux":
    nix run --accept-flake-config .#drv-diff -- --before {{before}} --after {{after}} {{ if allow == "" { "" } else { "--allow " + allow } }} --systems "{{systems}}" --vm-systems "{{vm-systems}}"
  ```
- [ ] **Step 9:** `nix run .#drv-diff -- --help` (builds the app only). Expected: usage text.
- [ ] **Step 10:** Commit: `feat(apps): add drv-diff, a cross-revision drvPath oracle`.

## Task 2: `eval-cost` (tasks.md 2.1)

**Files:** create `modules/apps/eval-cost.{sh,nix}`; modify `justfile`.

- [ ] **Step 1:** Arguments `--attr --before --after --runs (2) --mode (drv|keys) --label (default: attr with dots replaced)`. Resolve commits as in Task 1.
- [ ] **Step 2:** Per commit, one untimed `"$NIX_STOCK" flake metadata "$ref" >/dev/null` and one untimed evaluation (warm-up; copies the flake to the store).
- [ ] **Step 3:** For `r` in `1..runs`, for `c` in `before after`: run in a fresh process
  ```bash
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$tmp/$r-$c.json" "$NIX_STOCK" eval --option eval-cache false \
    $( [ "$mode" = keys ] && echo --json "$ref#.$attr" --apply builtins.attrNames || echo --raw "$ref#.$attr.drvPath" ) >/dev/null
  ```
  timing wall with `EPOCHREALTIME`; append `{run:r, commit:c, wall, cpuTime, totalBytes:.gc.totalBytes, nrThunks, envs:.envs.number}` to the `.jsonl`.
- [ ] **Step 4:** Header in `.log`: evaluator `readlink -f` and version, `hostname`, memory (`sysctl -n hw.memsize` on darwin, `/proc/meminfo` on Linux), `pgrep -fl 'nix-eval-jobs|nix eval'` excluding self, both commits. Print a table of every run.
- [ ] **Step 5:** `.nix` and recipe as in Task 1 (`eval-cost attr before after runs="2" mode="drv"`). `shellcheck` clean.
- [ ] **Step 6:** `just eval-cost checks.x86_64-linux <c> <c> 1 keys`. Expected: two rows with equal `nrThunks`.
- [ ] **Step 7:** Commit: `feat(apps): add eval-cost, an interleaved evaluation-cost measurement`.

## Task 3: Validate the oracle (tasks.md 3.1–3.3, 3.5)

- [ ] **Step 1:** Announce, then run `just drv-diff <trunk> <trunk>`. Expected: exit 0, all sets identical. Record the wall time.
- [ ] **Step 2:** `jj new <trunk>`; in `modules/machines/darwin/blackphos/default.nix` add `environment.variables.DRV_DIFF_MUTANT = "1";`; `jj describe -m 'mutant: drv-diff (do not push)'`; read its commit id.
- [ ] **Step 3:** Announce, then run `just drv-diff <trunk> <mutant>`. Expected: exit 1; undeclared differences only `darwin.blackphos` and the `checks.aarch64-darwin` entries that build blackphos (`darwin-blackphos` and any check reading its toplevel); the base list's whole-source checks reported as allowed.
- [ ] **Step 4:** The allow-list cases of tasks.md 3.3, each a file under `$TMPDIR`. Expected exit codes 1, 0, 0, 1, 2, 2.
- [ ] **Step 4a:** `jj new <trunk>`; change one line of `README.md` only; describe it as a mutant; announce, then run `just drv-diff <trunk> <readme-mutant>`. Expected: exit 0; the differing attributes are exactly the base allow-list's entries.
- [ ] **Step 5:** `jj abandon <mutant> <readme-mutant>`.

## Task 4: Baselines (tasks.md 4.1–4.2)

**Files:** create `docs/notes/development/eval-cost-baselines.md`.

- [ ] **Step 1:** Write the note: purpose; the protocol (`just eval-cost`, A/B/A/B, stock Nix, what each run records, the acceptance rule from `evaluation-cost.md:77-88`); a "Reference (not comparable)" table of the seven 2026-11-26 cross-host figures from `brainstorm.md`, with the missing conditions stated.
- [ ] **Step 2:** Announce, then measure on stibnite at one trunk commit: `just eval-cost darwinConfigurations.stibnite.config.system.build.toplevel <c> <c> 2`, `just eval-cost nixosConfigurations.cinnabar.config.system.build.toplevel <c> <c> 2`, `just eval-cost checks.x86_64-linux <c> <c> 2 keys`. Record each table with its header. Record `nix config show sandbox` (for A310) and Task 3 Step 1's wall time.
- [ ] **Step 3:** Commit: `docs(notes/development): record evaluation-cost baselines`.

## Task 5: Documents (tasks.md 5.1–7.2)

**Files:** modify `docs/notes/development/architectural-principles.md`, the three ADRs, `modules/README.md`, `modules/home/README.md`.

- [ ] **Step 1:** `git log -S 'nixosForSystem' --oneline -- modules/checks/machines.nix` and `git log -S 'githubUser' --oneline -- modules/home/development/git.nix` for the O14 and O16 resolution commits.
- [ ] **Step 2:** Apply tasks.md 5.1–5.4 in order. For 5.2, first commit the list of den-readiness findings in the principles document; each listed finding not already an O-entry becomes `### Onn [principle or "no principle"] [severity] <title>` with Location, Current shape, Why this matters, Approach, and the change that closes it.
- [ ] **Step 3:** Apply 6.1–6.3: after the `- **Scope**` / `- **Synthesizes**` line add `- **Amended**: <date>, see [Amendment](#amendment-<date>)`; before `## References` (ADR-0018, -0019) or at the end (ADR-0020, if it has none) add `## Amendment (<date>)` with one bullet per stale statement: what it said, what is true now, where.
- [ ] **Step 4:** Apply 7.1–7.2.
- [ ] **Step 5:** `just docs-linkcheck`. Expected: pass (the site builds with internal link validation).
- [ ] **Step 6:** Commit: `docs: fold the den-readiness audit into the principles, amend ADR-0018/0019/0020, correct READMEs`.

## Task 6: Self-neutrality (tasks.md 3.4, 8.2)

- [ ] **Step 1:** Announce, then run `just drv-diff <base of chain> <head of chain>`. Expected: exit 0, with only the base allow-list's whole-source checks differing.
- [ ] **Step 2:** Keep the report path for the verify record.
