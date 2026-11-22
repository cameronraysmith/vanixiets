D1–D7 were decided by the operator on 2026-11-22 (design.md §Decisions).
`plan.md` decomposes groups 1–4 into steps.

## 0. Evidence (completed 2026-11-22)

- [x] 0.1 Record the Q97 probe's measurements before its report branch is deleted — verify: design.md §What the Q97 probe measured and `specs/world-assumptions` A184 and A186 quote its lines, with the session's environment (Default) and `main`'s revision `5967d3ab41d4`.
- [x] 0.2 Lint the behavioral delta's nouns against the designation table as this change's world-assumptions delta leaves it — verify: a script matching 20 listed nouns of the three behavioral requirements against the table's Term column reports none unresolved, after adding `main branch` and `input source`.

## 1. D2, D3: the track mode and its check

- [x] 1.1 Add a track mode to `modules/apps/claude-sandbox-setup-script.nix` printing fixed text: a commented `#PIN=` line, the two caches and keys as bash arrays, a depth-5 first-parent fetch of `main` into a temporary clone, per commit from the tip an `eval` of the activation package path through `git+https://github.com/cameronraysmith/vanixiets?rev=<sha>&shallow=1` and a narinfo request to `cache.scientistexperience.net`, the first 200 accepted within 5 commits and about 300 s, a realise with `--max-jobs 0` and `--option builders ''`, activation unless current, the marker line and `exit 0` — verify: the printed script passes `bash -n` and `shellcheck`; it is byte-identical at two revisions.
- [x] 1.2 Extend `modules/checks/claude-sandbox-setup-script.nix` to hold the track-mode template: at most 100 lines of at most 200 bytes, last line `exit 0`, no 40-hex revision, no `/nix/store/` path, `--max-jobs 0` present, substituters passed as an array — verify: the check fails evaluation on a mutant for each condition and passes on the template; the pinned mode's existing asserts still hold.
- [x] 1.3 Exercise the walk in an Ubuntu 24.04 container that mimics the cloud session (the archived change's 5.1 container) — verify: with every closure published, the run accepts the tip (`dist=0`); with the tip's narinfo blocked, it accepts `main~1` and records the tip as a `narinfo` miss; with the cache host blocked, it records 5 misses or the budget, activates nothing and exits 0; with `PIN=` set, it evaluates nothing; a second run reports `activate=current`.

## 2. D5: the staleness notice

- [x] 2.1 Add a SessionStart hook `claude-sandbox-staleness` to `modules/home/users/claude-sandbox/default.nix`, by store path, that reads the last marker, runs `git ls-remote` for `refs/heads/main`, appends one `staleness` line to `run.log` (commit, recorded distance, tip moved or not), prints nothing and exits 0 — verify: `nix eval` of the profile's SessionStart hooks lists it by store path; in the container, with a marker at `main~2` and a moved tip, `run.log` gains that line, stdout is empty and the current generation is unchanged; with no marker or no network it logs `unknown` and exits 0.

## 3. Rollout and measurement

- [x] 3.1 From a controller session on `nix-sandbox-test`, swap its setup step to the track-mode script (one approval card) and create a cold-start child — verify: the child's `setup.log` marker shows `mode=track`, the commit and its distance, and codes 0; its first prompt has the user context and a composed skill; every R12 tool runs by name; its `run.log` holds a `staleness` line.
  Done 2026-11-22 (controller report `reports/claude-sandbox/task31-controller.md` on `claude/sandbox-reports-31c`, child report on `claude/sandbox-reports-31`; both branches are deleted after this record, so the lines are quoted here).
  The operator approved the `update_environment` card for `nix-sandbox-test` (`env_01GcXHMR3GM8Nv2encoaVjvs`) at about 01:39:40Z (`"setup_script_replaced":true`); its previous script is in design.md §Setup scripts to restore.
  The child `session_01HDH4XjJJvXCtnRc6MdMJhe` booted at 01:37:40Z, and its one `setup.log` line was `2026-11-22T01:41:26Z mode=track tip=f4b15ab3e17c1e1837aa7c814c4be8d09d4ee42a rev=f4b15ab3e17c1e1837aa7c814c4be8d09d4ee42a dist=0 skip= eval=0/48s realise=0/29s activate=0/3s nix=2.34.6 P=/nix/store/w6c3n94q72snq6jcsc804qw3n3g7lx6n-home-manager-generation`, with `git ls-remote` giving the same tip and the gcroot equal to `P`.
  `run.log` held `2026-11-22T01:41:27Z staleness rev=f4b15ab… dist=main~0 main=f4b15ab… moved=no`; its `filter|unshallow|fatal|403|forbidden` grep counted 2 lines, both the `perl5.42.3-Test-Fatal` store path, and the only `error` hits are the `libgpg-error` store path.
  Before any command the child reported `/root/.claude/CLAUDE.md` starting "## How this context is composed", `preferences-nix-development` listed and vanixiets' `AGENTS.md` in context; `CLAUDE.md` sha256 `2b37fb62af90364154457ec479714844c7c493f7cb2ea8f1b50ef7e16fcfe6c5` MATCH; 176 skills; nix 2.34.6 and openspec, linear, jj, git, gh, ghq, jq, rg, fd, just, uv and sops under `/nix/var/nix/profiles/default/bin`; `SOPS_AGE_KEY=set` and `linear auth whoami` reported the `cameronraysmith` workspace.
  This closes T2's gate question (design.md §Assumptions): the treeless clone and the by-SHA fetch go through the gate.
  Observed: `setup.log` held one line, not two; the child read it at 01:41:38Z, 12 s after it was written, so a second setup run may not have happened yet, and whether setup runs twice on first use is not settled by this run.
  Observed: `git config --global --get ghq.root` printed nothing (exit 1); design.md §What the Q97 probe measured explains this as `--global` reading only `/root/.gitconfig`, not as a profile defect.
- [ ] 3.2 Only after 3.1 passes, switch Default the same way (one approval card) and create a child — verify: the same checks as 3.1 on Default; Default's previous pinned script for `7c2a300b` is recorded verbatim in this change before the swap.
  Recorded before the swap: Default's current script, as `bootstrap-claude-sandbox` task 7.2 applied it, is in design.md §Setup scripts to restore; 3.2's controller re-records it from `get_environment`.
- [ ] 3.3 Measure the snapshot expiry on one tracking environment — verify: children created at intervals over at least eight days, with no script or host change, each report `uptime -s` and their `setup.log` lines; the first child whose marker is newer than the previous snapshot's dates the rebuild, recorded against A185.

## 4. Integration Verification

- [ ] 4.1 Verify the walk in the cloud — verify: a child created while `main`'s tip is unpublished (right after a push, before nixbot's build) records the tip as a miss and runs `main~1`'s closure; if no such window is caught, record that and the container evidence of 1.3 instead.
- [ ] 4.2 Verify the input-sources requirement after a lock change — verify: after the next `flake.lock` change lands, `checks.x86_64-linux.flake-input-sources`'s output is served by `cache.scientistexperience.net` and a cloud session's marker shows an `eval` code 0 for that commit.
