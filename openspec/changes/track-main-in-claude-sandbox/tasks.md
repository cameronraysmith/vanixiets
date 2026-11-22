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

- [ ] 3.1 From a controller session on `nix-sandbox-test`, swap its setup step to the track-mode script (one approval card) and create a cold-start child — verify: the child's `setup.log` marker shows `mode=track`, the commit and its distance, and codes 0; its first prompt has the user context and a composed skill; every R12 tool runs by name; its `run.log` holds a `staleness` line.
- [ ] 3.2 Only after 3.1 passes, switch Default the same way (one approval card) and create a child — verify: the same checks as 3.1 on Default; Default's previous pinned script for `7c2a300b` is recorded verbatim in this change before the swap.
- [ ] 3.3 Measure the snapshot expiry on one tracking environment — verify: children created at intervals over at least eight days, with no script or host change, each report `uptime -s` and their `setup.log` lines; the first child whose marker is newer than the previous snapshot's dates the rebuild, recorded against A185.

## 4. Integration Verification

- [ ] 4.1 Verify the walk in the cloud — verify: a child created while `main`'s tip is unpublished (right after a push, before nixbot's build) records the tip as a miss and runs `main~1`'s closure; if no such window is caught, record that and the container evidence of 1.3 instead.
- [ ] 4.2 Verify the input-sources requirement after a lock change — verify: after the next `flake.lock` change lands, `checks.x86_64-linux.flake-input-sources`'s output is served by `cache.scientistexperience.net` and a cloud session's marker shows an `eval` code 0 for that commit.
