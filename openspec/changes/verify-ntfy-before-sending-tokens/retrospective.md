# Retrospective: verify-ntfy-before-sending-tokens

> Written: 2026-11-12, for tasks.md 9.3, after `review.md` (the holistic review of 2026-11-12) and before the operator's dispositions of it, while 7.2, 7.4, 7.5, 9.5, 9.6 and 10.1 wait on the operator or the archive
> Commit range: `ffc79426a^..08fa93c66`, filtered to the change's paths (`git log ffc79426a^..origin/main -- <change paths>`, merge commits excluded)
> Worktree: merged to main through #3827 (`08fa93c66`); the archive is tasks.md 9.6

---

## 0. Evidence

- **Commit range**: `ffc79426a^..08fa93c66`, 11 commits in 8 pull requests: #3770 the plan, #3775 the plan review's corrections, #3780 the archive gates (shared with `bind-mesh-writes`), #3781 caddy's root as clan vars, #3784 the verifying client, #3788 the weekly root check, #3826 the window's records and #3827 the documentation and `verify.md` (`gh pr view`).
- **Diff size**: the five implementation and record pull requests hold +1,185 / -112 lines over 37 file changes (#3781 +257/-10, #3784 +380/-63, #3788 +169/-8, #3826 +10/-9, #3827 +369/-22); the three planning pull requests hold +3,246 / -92 (#3770 +2,857/-0, #3775 +317/-79, #3780 +72/-13); none touches `flake.nix` or `flake.lock`.
- **Plan size**: `plan.md` is a 15,250 B index, and `plan/task-1.md` to `plan/task-9.md` hold 3.7 KB to 27 KB each (`plan/task-4.md` the largest).
- **Tasks done**: 37 of 45 in tasks.md when read (`grep -cE '^- \[x\]'` → 37; open: 7.2, 7.4, 7.5, 8.3, 9.3, 9.5, 9.6, 10.1); 8.3 waited on its pull request, which merged as #3827 at 2026-11-12T20:53:28Z.
- **Acceptance status**: 7.1 and 7.3 passed on 2026-11-12; 7.4 and 10.1 are recorded and wait for the operator's statement on the watch service's email; 7.2 waits for the operator's hook run; 7.5 waits for the Q4 decision (`verify.md` §7, §8, §11).
- **Active hours**: not recorded; #3770 merged 2026-11-07T18:54Z, #3781 2026-11-08T16:31Z, #3784 17:37Z, #3788 18:30Z, the window ran from 19:49:14Z to 20:56Z, and #3826 and #3827 merged 2026-11-12 at 20:45Z and 20:53Z.
- **Subagent dispatches**: not counted in the change folder; the plan review (tasks.md 1.1) and the holistic review (tasks.md 9.3) are each recorded as one read-only Opus subagent.
- **New external dependencies**: none in the flake; caddy's `pki` global option and clan's `clan vars set` are used for the first time in this repository.
- **Bugs encountered post-merge**: none in deployed behaviour; the window's probe stopped one run before any deploy (6.2), and `review.md` found 17 findings, two significant (F1, F2), both statements of the trust boundary narrower than the deployed reality.
- **OpenSpec validate state**: `openspec validate verify-ntfy-before-sending-tokens --strict` passed on 2026-11-12 (`verify.md` §1); the archive-time state is tasks.md 9.6's.
- **Test coverage signal**: `package-ntfy-send-test-tls-verification` (new; `foreignRefusedSource`, `foreignRefusedBuilt`, `ownAccepted`, `bundleAccepted`, `help`, mutant `insecure`); `package-ntfy-send-test-token-transport` (changed; `caUnset`, `caEmpty`, mutant `cacertGuardDropped`); `ntfy-tls-verification` (new; clauses A to C with the mutants `insecureShort`, `insecureCluster`, `insecureLong`, `insecureContinued`, `clientMissing`, `cacertDropped`, `undeclaredClient`; legs `servedHeld`, `servedInOverlap`, `servedDrifted`, `rootExpiring` with `verificationSkipped` and `expirySkipped`); cinnabar's build-time `caddy-root-from-vars` with the overrides `pkiDropped` and `fingerprintOther`; `vmTests.x86_64-linux.caddy-root-from-vars` with its `minting` control.

Commit chain (chronological):

```
ffc79426a #3770 openspec: plan verifying ntfy.zt before sending tokens
aa3d3f6b0 #3775 openspec: apply the plan review of verifying ntfy before sending tokens
c36739f66 #3780 openspec: pass the archive gates of verify-ntfy and bind-mesh-writes
aba1396c7 #3781 caddy-local-root: load cinnabar's caddy root from clan vars
3265c871e #3781 zt-services-trust: read caddy's root from cinnabar's clan vars
35e7b691b #3784 ntfy-send: verify ntfy.zt's certificate against caddy's root
2083fd109 #3784 hooks: post permission notices through ntfy-send
88e23a2c0 #3788 caddy-root-check: verify the chain caddy serves against its root and warn before expiry
52f5ae787 #3788 cinnabar: verify weekly the chain caddy serves for ntfy.zt
5504ee23b #3826 openspec: record the verify-ntfy deploy window
08fa93c66 #3827 Document caddy's root and the ntfy clients that verify it
<close-out: review dispositions as tasks.md §11; 7.2, 7.4, 7.5 and 10.1's operator items; the satisfaction projection and the archive: tasks.md 9.5, 9.6>
```

---

## 1. Wins

- [evidence: `review-plan.md`] The plan review's 14 findings were decided before any code, and three would have failed the plan as written: its F1, clan's temporary file holding the key in clear on stibnite's disk, which became the RAM disk; its F2, a rotation refusing every post while caddy kept serving a leaf under the old root, which became step 4's read against the new root alone; its F3, the scan's clause C failing at the green of 4.5.
- [evidence: `review-plan.md`] Its F4 found that the mutant `verificationSkipped` did not skip verification, and the mutant was rewritten before 5.1.
- [evidence: `1.4-rehearsal-20261108T150117Z.log`] The rehearsal ran the consumer's exact argument list as root on the three NixOS hosts and as `_otelcol` on stibnite, and read the four messages back over a verified connection before any code existed.
- [evidence: `2.4-import-20261108T154324Z.log`, `2.4-import-20261108T152659Z.log`] Both import runs agreed on the fingerprint `7E:78:…:2E:82`, the public-key hash from key and certificate, and the readers `machines/cinnabar users/cameron`; the files clan left in `TMPDIR` were classified without printing them, and none held `PRIVATE KEY`.
- [evidence: `2.1-red-…`, `4.1-red-…`, `4.2-red-…`, `4.4-red-20261108T171003Z.log`, `5.1-red-…`, `5.3-red-…`] Every regulator was seen failing first; 4.4's red found the two hooks' `curl -sfk` that the change then routed through `ntfy-send`.
- [evidence: `2.5-cinnabar-20261108T161043Z.log`] `pkiDropped` and `fingerprintOther` each failed cinnabar's build with their clause's message, and the VM test's `minting` control exited 60 (`2.2-vm-20261108T151130Z.log`).
- [evidence: `3.1-cinnabar-20261108T165013Z.log`] caddy switched to the vars alone, with the served intermediate verifying against RV before and after, and caddy's loaded `pki` reading `null` before and the vars' paths after.
- [evidence: `6.2-probe-20261108T194914Z.log`] The pre-deploy probe stopped the window before any deploy when cinnabar and pyrite refused the unsigned copy, and the read-back exposed the script's own false `rc=0`.
- [evidence: `6.3-…`, `6.4-…`, `6.5-…`, `6.6-stibnite-20261108T195245Z.log`] Every host's delivered `ntfy-send` posted with the token and was read back, its `NTFY_CACERT` `cmp`-equal to RV; magnetite's heartbeats never stopped.
- [evidence: `7.1-foreign-20261112T194942Z.log`] magnetite's delivered `ntfy-send`, pointed at a server under `otel-ca`, exited 60 and posted nothing.
- [evidence: `7.3-root-check-20261112T200226Z.log`] Both hand-run controls of `caddy-root-check` failed with their messages and posted nothing, and the timer's first run on 2026-11-09 passed.
- [evidence: `verify.md` §3] Every new or changed check stayed under 536,870,912 B, the highest 188,097,680 B for the TLS test.
- [evidence: `9.4-rows-20261112T200442Z.log`] The archive-time row check printed only this change's two rows, so rebasing the delta onto the archived table at 1.2 held.

## 2. Misses

- [med] [painful | evidence: `review.md` F1, F2] The trust boundary, A81, ADR-009 and the runbook state that the key is readable only by cinnabar's root and `caddy` accounts and the sops recipients, and that its holder can sign "a certificate every `ntfy.zt` client trusts"; any local account on cinnabar can drive caddy through its admin endpoint, and the root is trusted for every name on stibnite, blackphos and the operator's phone, its key now in a public repository.
- Root cause: A81 was derived from the key file's owner and mode and from the sops recipients, not from what can make the key's owner act, and the root's scope from the clients this change touches, not from every place the root is installed.
- [med] [painful | evidence: `review.md` F4; `verify.md` §4] Six behavioral nouns of the four added `fleet-alerting` requirements resolve to no designation row, against the vocabulary requirement this change itself modifies.
- Root cause: the designation lint ran at close-out (9.1), after the spec text was settled at the plan review.
- [med] [painful | evidence: `review.md` F5; `verify.md` §3] `nixos-pyrite` and `darwin-stibnite` have no "after" figure, though the client's change rebuilt both, and the figures taken at the window's commit include a nixpkgs update.
- Root cause: the plan named "after" measurements per task for the machines each task named, and no item measured every machine whose closure the change rebuilt at the last code commit.
- [low] [painful | evidence: `review.md` F6] cinnabar moved from caddy 2.11.7 to 2.11.9 at the window, because the window's commit `bbbc8da89` carried a nixpkgs update, and A79 still names 2.11.7.
- Root cause: the window gate (6.1) checked that both pull requests were merged, not what else the window's commit changed among the vendors the world assumptions name.
- [low] [painful | evidence: tasks.md 6.2, 7.3; `review.md` F11] The plan's `nix copy` from magnetite to cinnabar and pyrite failed on signatures twice, and 7.3 finished with `--no-check-sigs`.
- Root cause: the rehearsal (1.4) used the curl already in each host's store, so no copy to a host was rehearsed.
- [low] [painful | evidence: `6.2-probe-20261108T194914Z.log`] The probe script printed `rc=0` for hosts where nothing ran, because it read `$?` after a `$(hostname -s)` substitution; the read-back, not the exit code, caught it.
- [low] [painful | evidence: `review.md` F3] A81 is named after no `Discharges:`, which `verify.md` §2 found at close-out.
- [low] [painful | evidence: `review.md` F7] Four runbook statements are inaccurate, among them rotation step 3's "fails caddy's reload and leaves the old root serving", where `restartUnits` restarts caddy.
- [low] [nit | evidence: tasks.md 6.6] stibnite's switch to the window's system was made by the operator before the window, leaves no deploy-record entry, and the deploy-record check ran after it.
- [low] [nit | evidence: `gh pr view 3781 3784`; tasks.md 5.4] The branches of #3781 and #3784 are named `cam87-pr1` and `cam87-pr2`, and #3787 was opened from such a branch before the operator asked for a descriptive name, against the rule on pull-request ordinals.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 2.1, 2.2 | the VM test's three machines are systemd-nspawn containers needing `nixos-test` and `uid-range`, not QEMU nodes; `get` reads curl's exit code from `client.execute` | magnetite offers no `kvm`; the test driver runs commands under errexit |
| 2.4 | the import ran twice, the second run classifying the 20 files clan left in `TMPDIR` | the operator's decision after the first run left 22 files there |
| 4.1 | the test server sends `Content-Length` | curl exited 56 on a TLS stream closed without `close_notify` |
| 4.4 | `fileFilter` per directory, the `invokes` boundary admitting `_` and `-`, and three non-client declarations | faults in the plan's text, found while writing the check |
| 4.7, 5.4, 8.3 | `prek run --files` over the committed files instead of the whole-tree `nix fmt` | the operator's decision: the shared working copy held other sessions' files |
| 5.2 | the legs pass `$LEG_CA` and `$LEG_ADDR` | shellcheck's SC2153 failed `$BUNDLE` and `$CONNECT` |
| 5.4 | #3787 closed and reopened as #3788 from a descriptive branch | the operator asked for a branch name without the ordinal |
| 6.1 | the window's commit `bbbc8da89` also held a nixpkgs update | it merged before the window; caddy moved to 2.11.9 with it (`review.md` F6) |
| 6.2 | `nix copy --substitute-on-destination`, after the first run stopped the window | cinnabar and pyrite refused the unsigned copy |
| 6.5 | `clan machines update pyrite` through its configured target host | the operator's instruction |
| 6.6 | stibnite activated by the operator before the window; the deploy-record check after it | the operator's activation preceded the window |
| 6.7 | cinnabar, pyrite and magnetite rebooted onto Linux 6.18.60 | the operator's decision; the nixpkgs update installed that kernel |
| 7.1 | the ingress's certificate read from stibnite | magnetite has no `openssl` on its `PATH` |
| 7.3 | the two control scripts copied to cinnabar with `--no-check-sigs` | cinnabar refused the unsigned copy, and no cache held the paths |
| 7.5 | the three darwin hosts' states not read | each timed out on port 22 over ZeroTier |
| 8.1 | the charter's v30 entry written after v31's, with the status lines left at v31 | CAM-92 wrote v31 first |
| 9.1 | a third cost column at `bbbc8da89`, with three whole-machine figures unmeasured | the measuring job's 900 s limit (`review.md` F5) |

## 4. Skill / workflow compliance

| Skill | Used |
|-------|------|
| superpowers:brainstorming | yes (`brainstorm.md`, O1 to O12, Q1 to Q7) |
| superpowers:writing-plans | yes (`plan.md` and `plan/task-1.md` to `plan/task-9.md`) |
| superpowers:using-git-worktrees | partial: deploys from the deploy worktree at `origin/main`; stibnite's activation preceded the window (6.6) |
| superpowers:subagent-driven-development | partial: the plan review (1.1) and the holistic review (9.3) are recorded; implementation dispatches are not |
| (transitive) superpowers:test-driven-development | yes (red logs for 2.1, 2.3, 4.1, 4.2, 4.4, 5.1 and 5.3) |
| (transitive) superpowers:requesting-code-review | partial: one read-only Opus subagent in place of the paid review, as in the earlier slices |
| superpowers:finishing-a-development-branch | pending (tasks.md 9.5, 9.6) |

### `stand-up-darwin-collection` §6 rules applied here

| Rule | Applied | What it caught |
|---|---|---|
| A delta that modifies a main requirement is compared with main's text at every rebase | yes: 1.2 rebased the WA delta onto the archived table, restoring 14 rows; 9.4 printed only the two added rows | the stale table before any implementation |
| A statement of what a vendor component does is checked against its source | yes: caddy, clan-core and sops are cited at lines for A79, A83 and D12 | the plan review's F1 (clan's temporary file); missed the version drift at the window (`review.md` F6) |
| The evaluation-cost command writes `.#.checks` | yes: the preamble's method | no offset; missed whole-machine "after" figures (`review.md` F5) |
| An acceptance window names the scheduled events it must contain | yes: 7.4 named the timer's Monday run, observed on 2026-11-09 | — |
| A regulator is rehearsed against the consumer's own behaviour, not only an exit code | yes: 1.4 posted with the exact argument list and read each message back | 6.2's false `rc=0` was caught by the read-back, the same lesson at runtime |

## 5. Surprises

- caddy's admin endpoint on cinnabar answers any local account, `nobody` included (`review.md` F1).
- caddy tries to install even a configured root into the system trust store at every start, and logs an error when its account cannot (`verify.md` §11).
- clan-core `dbae2101` declares a var's sops secret only once its `secret` file exists, so `root.key`'s path evaluated to `/no-such-path` before the import (tasks.md 2.3).
- `clan vars set` left 20 to 22 files at the top of `TMPDIR`, one of them sops's temporary configuration (tasks.md 2.4).
- Python's `ssl` server closes without `close_notify`, and curl exits 56 when it reads to the end of such a stream (tasks.md 4.1).
- cinnabar and pyrite do not trust magnetite's builds without a signature (tasks.md 6.2, 7.3).
- An agent session reproducing a hook race on stibnite posted 63 permission notices in 15 s through the real hook on its `PATH`, the count matching ntfy's default burst (`review.md` F15).
- The repository is public, so the encrypted key is too (`review.md` F2).

## 6. Promote candidates → long-term learning

- [ ] [high] **A key's reader set is derived from every principal that can make the key's owner act, not only from file mode and encryption recipients.** → **Promote to** skill (`preferences-secrets`)
  > **Why**: A81 and the trust boundary omitted caddy's unauthenticated admin endpoint, through which any local account on cinnabar can use the key (`review.md` F1).
  > **How to apply**: for each secret a service reads, list the service's control surfaces (admin APIs, sockets, reload commands, `sudo` rules) and who can reach each, and state them in the assumption that names the readers.

- [ ] [high] **A certificate authority's trust scope is stated from every place it is installed, and a new root carries a name constraint for the names it serves.** → **Promote to** skill (`preferences-secrets`)
  > **Why**: caddy's root is trusted for every name on two laptops and a phone, while the records describe it as `ntfy.zt`'s, and its key now sits encrypted in a public repository (`review.md` F2).
  > **How to apply**: before a root's key moves or is copied, list its installations (keychains, CA bundles, devices) with their trust settings, and mint any new root with `nameConstraints` for its domain.

- [ ] [med] **The designation lint and the discharge-coverage search run at the plan review, not at close-out.** → **Promote to** schema (OpenSpec tasks template, plan review)
  > **Why**: six nouns without rows and A81 without a `Discharges:` surfaced only in `verify.md` (`review.md` F3, F4).
  > **How to apply**: tasks.md 1.1's review lists every behavioral noun against the table and every requirement and assumption against the `Discharges:` lines, and the operator decides each miss with the other findings.

- [ ] [med] **Whole-machine evaluation cost is measured before and after for every machine whose closure the change rebuilds, at the last code commit before any unrelated input update.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: `nixos-pyrite` and `darwin-stibnite` were rebuilt by the client's change and never measured after, and the window commit's figures mixed in a nixpkgs update (`review.md` F5).
  > **How to apply**: the baseline item lists the rebuilt machines from the closure search it already runs, and the close-out measures the same list at the last code commit.

- [ ] [med] **A deploy window's commit is diffed against the change's last merge for vendor versions the world assumptions name, and any change re-reads those assumptions before the window opens.** → **Promote to** schema (OpenSpec tasks template, deploy window gate)
  > **Why**: caddy moved from 2.11.7 to 2.11.9 inside the window while A79 named 2.11.7 (`review.md` F6).
  > **How to apply**: the window gate evaluates each named vendor's version at the window's commit and at the last code merge, and records the comparison or the re-read.

- [ ] [med] **The rehearsal includes every transport step a probe needs, such as copying a build to each host, with the exact command.** → **Promote to** skill (`writing-plans`)
  > **Why**: the plan's `nix copy` failed on signatures at 6.2 and 7.3 because 1.4 reused paths already in the hosts' stores (`review.md` F11).
  > **How to apply**: the rehearsal copies one store path built on the builder to each target with the plan's own command and records the result.

- [ ] [low] **A procedure no check can run, such as a rotation, is rehearsed in a VM or container test before a requirement rests on it.** → **Promote to** skill (`preferences-validation-assurance`)
  > **Why**: `Replacing the service authority loses no post` rests on an unrun runbook, whose step 3 misstates caddy's restart and whose keychain step keys on a fixed name (`review.md` F7, F8).
  > **How to apply**: the plan adds a test node per procedure stage and names the requirement's runtime discharge as pending until it passes.

- [ ] [low] **A probe's exit status is captured immediately after the command it judges.** → **Promote to** skill (`writing-plans`)
  > **Why**: 6.2's script read `$?` after a command substitution and printed `rc=0` for hosts where nothing ran.
  > **How to apply**: write `cmd; rc=$?` on one line, and have the read-back, not the exit code, decide the step.

- [ ] [low] **A reproduction loop over a hook that posts notifications runs with a `PATH` that excludes the user profile.** → **Promote to** one-off (the fix of the `gate-dangerous-commands` race)
  > **Why**: 300 runs posted 63 notices to the operator's topic (`review.md` F15).
  > **How to apply**: build the loop's `PATH` from the hook derivation's `runtimeInputs` only, or stub `notify-permission-wait`.
