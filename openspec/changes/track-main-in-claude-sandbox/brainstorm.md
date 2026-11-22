# Brainstorm: track `main` in Claude Code cloud sessions

Decision log captured from the operator's decisions of 2026-11-22 (Q97 option 1 and Q98), the archived change `bootstrap-claude-sandbox` (CAM-118, archived 2026-11-21), and the Q97 probe of 2026-11-22 00:55 UTC (`logs/claude-sandbox/q97-probe.md`, a local copy of a report whose branch will be deleted).

## Background

`bootstrap-claude-sandbox` delivered the cloud environment pinned to one closure: a generated setup script names one store path, CI builds it, and the setup step fetches and activates it without evaluating a flake.
Pinning has two costs.
Every change to the profile reaches cloud sessions only when the operator regenerates the script and swaps it in (one approval card).
And niks3 drops a closure 30 days after its last reference, so a pinned environment must be renewed monthly even when nothing changed.
Q97 asked whether a cloud session could instead evaluate `main` itself, with every flake input source served from the fleet's binary cache so the GitHub gate is never asked for them.

## What the probe and the preparatory changes settled

- A cloud session on the operator's Default environment (picked by accident; Default has run the generated script for `7c2a300b`, closure `d96f192x…`, since task 7.2 of `bootstrap-claude-sandbox`) evaluated `homeConfigurations."claude-sandbox@x86_64-linux".activationPackage.outPath` from `git+https://github.com/cameronraysmith/vanixiets?ref=main&shallow=1` with rc=0 in 46 s at about 0.94 GiB peak (`main` at `5967d3ab41d4`).
  It printed `d96f192x…`, the closure already installed, which is why its dry-run realisation found nothing to fetch; the probe changed no environment state, and its result applies directly to Default, the environment tracking targets.
- Nix fetched only the 19 input sources evaluation needed, 18 from `cache.scientistexperience.net` and 1 from `cache.nixos.org`; nothing came from GitHub but the `git+https` clone of vanixiets itself, and no 403 occurred.
- `checks.x86_64-linux.flake-input-sources` (#4127) makes nixbot upload all 77 locked sources to niks3, and all 77 narinfos answer 200; the flake input trim before it (#4126) cut the lock from 123 to 93 nodes, nixpkgs instances from 13 to 5, and source size from 3,657 to 1,987 MiB.
- The probe's prescribed `O="--option substituters $S …"` failed: unquoted expansion word-splits the space-separated substituter and key lists, so `--option` got only the first value; a bash array of the same values worked.
- The git configuration question left open by `bootstrap-claude-sandbox` is answered: `/root/.config/git/config` (home-manager) supplies `ghq.root=/home/user/ghq`, and the harness writes its own `/root/.gitconfig` after activation and injects three `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` overrides, which is how its commit identity and signing apply.

## Q1: how does a session learn what `main` is?

Options:
- (a) the setup script evaluates `main` itself with the caches as substituters (the probe);
- (b) CI writes a pointer branch naming each commit's closure, and an effect publishes it;
- (c) the setup script reads nixbot's API for the newest built closure.
(b) is a third copy of the commit-to-closure function (the flake and CI's build are the other two) and needs its own effect; (c) adds a dependency on a new service and couples the setup step to nixbot's schema.
Decided: (a), Q97 option 1 (2026-11-22). (b) and (c) withdrawn.

## Q2: one fixed script, or one per revision?

Tracking only works if the script text does not change with each commit, because a script change is what triggers the approval card and the snapshot rebuild.
Decided (2026-11-22): the script text is fixed, produced by the existing app in a new track mode; it evaluates and realises `main`'s activation package with the substituters and keys as a bash array, activates unless it is already the current generation, writes the marker line (revision, eval, realise and activate exit codes and seconds), and always exits 0.
An optional `PIN=` line pins a store path; the pinned mode of the app stays, to produce PIN values.

## Q3: when does a session pick up a newer `main`?

The snapshot is rebuilt when the script text or the allowed hosts change, or after about seven days (documented by the platform, not measured).
Refreshing now means any edit to the script text, such as a dated refresh comment, through a card or the claude.ai UI.
A catch-up hook that activates `main` at session start was considered and rejected (2026-11-22): sessions would run with mixed versions, and the catch-up would repeat in every session.
Decided instead: a SessionStart hook that only compares the snapshot's source revision with `main`'s (`git ls-remote`) and logs one line, never activating.

## Q4: what becomes load-bearing?

The 30-day renewal now applies only while pinned: a tracking environment names no store path, and its snapshot is rebuilt at least weekly.
Every lock change must keep all input sources in niks3, or evaluation fails in the sandbox; `flake-input-sources` is now load-bearing.
A miss shows as a non-zero eval code in the marker line, and the hourly cache-completeness timer on magnetite already covers that check's output.

## Q5: what if `main`'s newest commit is not yet published?

A snapshot made between a push to `main` and nixbot publishing its closure would find nothing to fetch, and a snapshot lives about seven days, so losing that race costs up to a week of sessions without the profile.
Local builds were rejected: they would meet the GitHub gate on fixed-output sources such as the composed skills' dependencies, and could run long.
Decided (operator, 2026-11-22): substitute only (`--max-jobs 0`, `--option builders ''`), and walk back `main`'s first-parent history.
From the tip, for each commit fetched with enough depth, evaluate the activation package's store path and accept the first whose narinfo answers 200 from `cache.scientistexperience.net`; a failed evaluation counts as a miss too (a lock change whose sources are not uploaded yet).
The walk is bounded to 5 commits and about 300 s in all, then the step degrades.
The marker records the commit used, its distance from the tip and each skipped commit with its reason, and the staleness notice reports the distance (for example "snapshot from main~2").
`PIN=`, when set, bypasses the walk.
The remaining risk, all 5 commits missing, is accepted, with the marker as its detector.

## Open at capture time

- The snapshot expiry, to be measured.
