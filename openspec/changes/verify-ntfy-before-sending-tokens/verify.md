# Verification Report

**Change**: `verify-ntfy-before-sending-tokens` (CAM-87)
**Verified at**: 2026-11-12 20:10 UTC, for tasks.md 9.1, 9.2, 9.4 and 10.1, after the window of 2026-11-08 and the acceptance runs of 7.1, 7.3, 7.4 and 7.5 on 2026-11-12
**Verifier**: written from `tasks.md`, `design.md`, `plan/`, `specs/` and `logs/cam87-evidence/`, with read-only commands on magnetite, cinnabar, pyrite and stibnite and the two runtime controls of 7.1 and 7.3; nothing was deployed or activated

Evidence names are files under `logs/cam87-evidence/`, which is git-ignored.
Times are UTC.
Four entries wait for others and are marked as open slots: the operator's hook run (7.2, §8), the operator's decision on telling the users of the hosts outside the window (7.5, §7), the holistic review (9.3, §12) and the archive (9.6, §13).

## 1. Structural validation

`openspec validate verify-ntfy-before-sending-tokens --strict` on 2026-11-12 after this file was written:

```text
Change 'verify-ntfy-before-sending-tokens' is valid
```

## 2. Requirements and their discharges

`FA` is `fleet-alerting`, `FAI` `fleet-alerting-interface` and `WA` `world-assumptions`.
Every requirement of the three deltas is named after a `Discharges:` in `tasks.md`, except A81, which §5 covers.

| Requirement | Discharged by | Evidence |
|---|---|---|
| FA `A host posts to the notification service only over a verified connection` | 4.3, 6.3, 7.1, 7.4 | `4.3-green-20261108T170544Z.log`, `6.3-magnetite-20261108T195108Z.log`, `7.1-foreign-20261112T194942Z.log`, `7.4-day-20261112T195115Z.log` |
| FA `The service authority's expiry reaches a person 180 days ahead` | 5.1, 7.3 | `5.1-red-20261108T173938Z.log`, `5.2-green-20261108T174138Z.log`, `7.3-root-check-20261112T200226Z.log` |
| FA `Replacing the service authority loses no post` | 8.2 | the runbook's "caddy's root", "Rotating caddy's root" |
| FA `A reinstall of cinnabar keeps the service authority` | 2.1, 2.5, 3.1 | `2.1-red-20261108T150542Z.log`, `2.2-vm-20261108T151130Z.log`, `2.5-cinnabar-20261108T161043Z.log`, `3.1-cinnabar-20261108T165013Z.log` |
| FAI `ntfy-send verifies ntfy.zt against caddy's root and fails closed` | 4.1, 4.2, 4.3, 4.5, 7.1, 7.2 | `4.1-red-20261108T170436Z.log`, `4.2-red-20261108T170506Z.log`, `4.3-green-20261108T170544Z.log`, `4.5-green-20261108T171044Z.log`, `7.1-foreign-20261112T194942Z.log`; 7.2 open (§8) |
| FAI `No ntfy.zt client in the repository skips verification` | 4.4, 4.5 | `4.4-red-20261108T171003Z.log`, `4.4-mutants-hookless-20261108T170939Z.log`, `4.5-green-20261108T171044Z.log` |
| FAI `cinnabar checks the root caddy serves weekly` | 5.1, 5.3, 6.4, 7.3 | `5.2-green-20261108T174138Z.log`, `5.3-units-20261108T175119Z.log`, `6.4-cinnabar-20261108T195813Z.log`, `7.3-root-check-20261112T200226Z.log` |
| FAI `caddy on cinnabar loads its root from the caddy-root-ca vars` | 2.2, 2.5 | `2.2-vm-20261108T151130Z.log`, `2.5-cinnabar-20261108T161043Z.log` |
| FAI `This capability states its own trust boundary` (modified) | 8.2, 9.1 | the runbook's "caddy's root" and "What the certificates do not prove"; §4 and §5 here |
| WA `Grounded vocabulary for behavioral requirements` (modified) | 9.1 | §4 and the row check of §9 |
| WA A78 to A83 | 2.1, 2.4, 3.1, 6.6, 7.1, 7.4 | §5 |

## 3. Evaluation cost of each new or changed check

The budget is 536,870,912 B of `gc.totalBytes` for a check this change adds or changes; a whole-machine check is recorded and any increase put to the operator (tasks.md preamble).
The method is `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file> nix eval --option eval-cache false --raw .#.checks.<system>.<check>.drvPath`, reading `.gc.totalBytes` and `.cpuTime`.
"Before" is 1.3's figure at `main@origin` `68baae384b16` (`1.3-baseline-20261108T145709Z.log`); "after" is the figure each pull request's task recorded, and the last column is the figure at the window's commit `bbbc8da89` (`9.1-cost-after-20261112T200528Z.log`), which also holds the nixpkgs update that came before the window, so it is not a measure of this change alone.

| Check | Before (B, s) | After (B, s), at | At `bbbc8da89` (B, s) |
|---|---|---|---|
| `package-ntfy-send-test-tls-verification` (new) | none | 188,097,680, 0.57, 4.3 | 177,921,312, 0.88 |
| `package-ntfy-send-test-token-transport` (changed) | 133,189,344, 0.29 | 133,217,328, 0.29, 4.3 | 123,035,200, 0.39 |
| `ntfy-tls-verification` (new) | none | 104,563,232, 0.30, 4.5; 159,460,320, 0.61, 5.2; 160,257,616 at `52f5ae78`, 5.4 | 151,979,344, 0.78 |
| `hook-gate-dangerous-commands` (changed) | 101,201,792, 0.28 | 101,258,912, 0.27, 4.5 | 93,789,552, 0.42 |
| `fleet-alert` (rebuilt through `ntfy-send`) | 377,847,632, 1.15 | 389,388,000, 1.17, 4.3; 389,705,968 at `52f5ae78`, 5.4 | 370,487,360, 1.59 |
| `otel-collector-config` (rebuilt through `ntfy-send`) | 477,798,144, 1.52 | not recorded per pull request | 454,648,624, 1.97 |
| `otel-collector-darwin` (rebuilt through `ntfy-send`) | 175,474,368, 0.60 | not recorded per pull request | 167,110,480, 0.88 |
| `nixos-cinnabar` (whole machine) | 2,568,355,904, 10.89 | 2,569,002,080, 11.12, 2.5 (+88,368 over 2,568,913,712 at 2.5's start); 2,570,118,784 at `52f5ae78`, 5.4 (+1,116,704) | not measured |
| `nixos-magnetite` (whole machine) | 2,853,054,928, 11.56 | 2,853,449,104 at `52f5ae78`, 5.4 (+394,176) | 2,729,760,368, 14.56 |
| `nixos-pyrite` (whole machine) | 3,043,141,520, 11.65 | not recorded per pull request | not measured |
| `darwin-stibnite` (whole machine) | 3,272,659,504, 11.70 | not recorded per pull request | not measured |

The evaluation of `nixos-cinnabar` at `bbbc8da89` had not finished when the measuring job's 900 s limit stopped it, so the last three whole-machine figures there were not measured.
Every figure for a check this change adds or changes is under the budget, and the operator accepted the whole-machine increases recorded at 2.5 and 5.4.

## 4. Designation lint

The lint read the statements of `fleet-alerting`'s four added requirements, without scenarios, and looked up each content noun in the `Term` column of this change's `world-assumptions` table; host and component names (`cinnabar`, `caddy`, `caddy-root-check`) and quantities were not counted.

These nouns resolve to a row: `host`, `notification service`, `verified connection`, `credential`, `service authority`, `failure notice`, `person`, `unit`, `operator`, `certificate`.

These resolve to no row of their own:

| Noun | Requirement | Nearest grounding |
|---|---|---|
| root (the service authority's) | `The service authority's expiry reaches a person 180 days ahead`, `Replacing the service authority loses no post` | the `service authority` row's definition, "together with the root certificate that identifies it" |
| journal (a unit's) | `The service authority's expiry reaches a person 180 days ahead` | none |
| running host | `Replacing the service authority loses no post` | the `host` row; "running" is not designated |
| mesh-only name | `A reinstall of cinnabar keeps the service authority` | named inside the `service authority`, `verified connection` and `overlay network` definitions, with no row of its own |
| device, the operator's phone | `A reinstall of cinnabar keeps the service authority` | named inside the `notification service` and `topic` definitions, with no row of its own |
| caddy's storage, reinstall | `A reinstall of cinnabar keeps the service authority` | none |

The lint is non-blocking; whether these nouns gain rows is for the holistic review of 9.3.

## 5. World assumptions A78 to A83

| Assumption | Discharged by, evidence | Status and window |
|---|---|---|
| A78 — cinnabar's caddy signs ntfy.zt's certificate under the root kept as cinnabar's caddy-root-ca vars | 3.1, 7.4; the served intermediate `FF:1F:51:27:…:1F:2C` verified against RV before and after the switch (`3.1-cinnabar-20261108T165013Z.log`); `caddy-root-check` passed on 2026-11-08 at 20:01:00Z and on its timer on 2026-11-09 at 14:00:02Z; the reissued intermediate `EC:84:82:32:…:2D:73` verified against RV on 2026-11-12 (`10.1-integration-20261112T200040Z.log`) | observed from 2026-11-08T16:52Z to 2026-11-12T20:00Z, not violated |
| A79 — caddy loads a configured root from its files, never mints or renews it, and derives intermediates from it | 2.1; `vmTests.x86_64-linux.caddy-root-from-vars` (`2.2-vm-20261108T151130Z.log`); caddy's loaded `pki` names RV's store path and the deployed key after the switch (`3.1-cinnabar-…`); the root's fingerprint unchanged across caddy restarts and the reboot of 2026-11-08 | configured, and observed from 2026-11-08T16:52Z to 2026-11-12T20:00Z |
| A80 — curl given a CA file trusts only that file's certificates, any of them, and -k disables verification | 7.1; magnetite's delivered `ntfy-send` pointed at the ingress, whose certificate `otel-ca` signed, exited 60 on 2026-11-12 at 19:49Z (`7.1-foreign-20261112T194942Z.log`); `tls-verification`'s one-root and two-root cases (`4.3-green-…`) | observed on 2026-11-12, with curl 8.22.0 |
| A81 — caddy's root key is readable only by cinnabar's root and caddy accounts and by the sops recipients of its var | named after no `Discharges:`; the var's readers `machines/cinnabar` and `users/cameron` at the import (`2.4-import-20261108T154324Z.log`), still the only entries on 2026-11-12; the deployed key owned by `caddy`, mode `0400` (`3.1-cinnabar-…`) | configured; not violated from 2026-11-08T15:43Z to 2026-11-12; a missing discharge for 9.3 |
| A82 — A store-built curl on stibnite reaches ntfy.zt over ZeroTier from a launchd job's account | 6.6; the delivered `ntfy-send` posted as `_otelcol` with exit 0 (`6.6-stibnite-20261108T195245Z.log`); `notify.log` holds no `FAILED` since 2026-11-05 | observed on 2026-11-08 at 19:52Z, not violated to 2026-11-12 |
| A83 — clan neither regenerates an imported generator nor stores a value other than what clan vars set received | 2.4; `clan vars check` `rc=0` and RV's fingerprint equal to the live root's (`2.4-import-…`); the vars' only commit on `origin/main` is `aba1396c7`, and RV's fingerprint on 2026-11-12 is still `7E:78:…:2E:82` | observed on 2026-11-08, not violated to 2026-11-12 |

## 6. The import and the served chain

The import of tasks.md 2.4 ran on 2026-11-08 with the operator (crs58) present and confirming at 15:43:24Z (`2.4-import-20261108T154324Z.log`, from `2.4-import.sh`).
The live root and the var's `root.crt` both had fingerprint `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82` and `notAfter=Dec  6 14:29:17 2035 GMT`, the public-key hash `95e80b1e…7729` came from both `root.key` and `root.crt`, the readers were `machines/cinnabar users/cameron`, and `clan vars check` returned 0.
`TMPDIR` was a RAM disk that was detached afterwards; clan left 20 files there, none holding `PRIVATE KEY`, as tasks.md 2.4's deviation records.

The served-chain reads of tasks.md 3.1, from stibnite on 2026-11-08 before and after `clan machines update cinnabar` at 16:52:14Z (`3.1-cinnabar-20261108T165013Z.log`), found the intermediate `FF:1F:51:27:…:1F:2C` both times, `OK` against RV both times; caddy's loaded `pki` was `null` before and named RV's store path and `/run/secrets/vars/per-machine/cinnabar/caddy-root-ca/root.key` after.

## 7. Hosts outside the window (tasks.md 7.5)

Read on 2026-11-12 at 19:59Z (`7.5-hosts-20261112T195950Z.log`): the `enabled` lines at `origin/main` `74e013954`, and the last deploy record over ZeroTier for the three darwin hosts, each of which timed out on port 22.

| Host | State | Since the window |
|---|---|---|
| electrum | `enabled = false` (`modules/terranix/hetzner.nix:18`) | not provisioned |
| galena | `enabled = false` (`modules/terranix/gcp.nix:32`) | not provisioned |
| scheelite | `enabled = false` (`modules/terranix/gcp.nix:40`) | not provisioned |
| argentum | deploy record not readable: unreachable over ZeroTier on 2026-11-12 | last activation not known; its `ntfy-send` keeps `-k` until its next activation |
| blackphos | deploy record not readable: unreachable over ZeroTier on 2026-11-12 | last activation not known; its `ntfy-send` keeps `-k` until its next activation |
| rosegold | deploy record not readable: unreachable over ZeroTier on 2026-11-12 | last activation not known; its `ntfy-send` keeps `-k` until its next activation |

The operator's decision on telling the users of argentum, blackphos and rosegold (Q4): *open slot, the operator's*.

## 8. Acceptance (tasks.md group 7)

- 7.1, 2026-11-12 at 19:49:42Z (`7.1-foreign-20261112T194942Z.log`): on magnetite, the `ntfy-send` in `fleet-alert.service`'s closure, `mn5rhdfi…`, with `NTFY_CACERT` `q473b07v…-value`, given the token and `--connect-to ntfy.zt:443:[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318`, exited `rc=60`; the ingress there serves `CN=magnetite` issued by `CN=otel-ca`; nothing appeared on `fleet-alerts` or `fleet-acceptance`.
- 7.2: *open slot, the operator's hook run on stibnite*.
- 7.3, 2026-11-12 at 20:03Z (`7.3-build-20261112T195009Z.log`, `7.3-root-check-20261112T200226Z.log`): the two scripts were built from the window's commit `bbbc8da89`, where `modules/lib/caddy-root-check.nix` is unchanged on `origin/main`; each differs from the deployed `yb9vfhrv…-caddy-root-check` only in the argument changed, and the build with the deployed arguments differs only in the bundle's store-path name; run by hand on cinnabar as root, outside the unit, the first printed `does not verify against …-value` (`otel-ca`) with `rc=1`, the second `caddy's root expires Dec  6 14:29:17 2035 GMT, within 3650 days` with `rc=1`; the unit's last run stayed 2026-11-09 14:00:02Z, `success`, and nothing posted.
- 7.4, 2026-11-08T19:39:21Z to 2026-11-09T19:39:21Z (`7.4-day-20261112T195115Z.log`): §11 lists the posts and their causes; the dead-man ran 288 times, each counting 9 or 10 heartbeats, with 288 pings accepted and the longest gap between them 302 s; `caddy-root-check.timer` lists Monday 2026-11-16 14:00:00 UTC next.
  The operator's statement on whether healthchecks.io sent any email over the window is not yet recorded; the ping record holds no gap the check's 5 min period and 10 min grace would report.

## 9. Archive-time row check (tasks.md 9.4)

Run on 2026-11-12 against the working copy (`9.4-rows-20261112T200442Z.log`); the corpus file's last change on `origin/main` is `87b95eb29`, the archive of `stand-up-darwin-collection`, so no change has modified the table since 1.2:

```text
	| service authority | — | the private key that signs the certificates of the fleet's mesh-only names, `ntfy.zt` among them, together with the root certificate that identifies it, both kept as cinnabar's encrypted clan vars from which cinnabar's caddy loads them | shared |
	| verified connection | — | a connection to a mesh-only name on which the connecting host has checked that the server's certificate chains to a root the repository keeps, so that only a holder of the service authority's key can answer it | shared |
```

The corpus holds 224 table lines and the delta 226; `comm -3` prints only the two added rows, both in the second column.

## 10. Migration flags (tasks.md 9.2)

The files of the change's seven commits on `origin/main` (`aba1396c7`, `2021f22d8`, `3265c871e`, `35e7b691b`, `2083fd109`, `88e23a2c0`, `52f5ae787`) were searched for migration, one-shot, temporary, removal and fallback wording and for `NTFY_CURL_BIN` (`9.2-flags-20261112T200646Z.log`).

| Item | Location | Disposition |
|---|---|---|
| `NTFY_CURL_BIN` | `pkgs/by-name/ntfy-send/ntfy-send.sh:46`, `:48`; `package.nix:36`; `test-token-transport.nix`, `test-tls-verification.nix` | permanent: the tests' seam, which the wrapper sets to the store curl |
| `NTFY_CACERT`'s guard | `pkgs/by-name/ntfy-send/ntfy-send.sh:38` | permanent: the fail-closed clause |
| `caddy-root-ca`'s failing `script` | `modules/machines/nixos/cinnabar/caddy-root-ca.nix` | permanent: it keeps clan from minting a root |

No one-shot branch or migration flag was added, and the close-out removes no code.

## 11. Integration (tasks.md 10.1)

Read on 2026-11-12 from 20:00:40Z (`10.1-integration-20261112T200040Z.log`, `10.1-posts-24h.txt`).

Each host's current system, filtered to `ntfy-send` and `notify-permission` paths:

| Host | System | Paths | `-sfk` or `--insecure` | `--cacert` |
|---|---|---|---|---|
| magnetite | `flsyv1xc…`, deployed 2026-11-09 05:20Z | `mn5rhdfi…-ntfy-send`, `3hkhna6y…-notify-permission-prompt`, `d55prnhi…-notify-permission-wait` | none | `mn5rhdfi…-ntfy-send/bin/ntfy-send` |
| cinnabar | `7f8v9yiy…`, deployed 2026-11-09 06:16Z | the same three | none | `mn5rhdfi…-ntfy-send/bin/ntfy-send` |
| pyrite | `hwbjyw4x…`, deployed 2026-11-09 06:16Z | the same three | none | `mn5rhdfi…-ntfy-send/bin/ntfy-send` |
| stibnite | `ymccx1f1…`, activated 2026-11-12 15:27Z | `4xs98yxp…-ntfy-send`, `9cn6mwmv…-notify-permission-wait`, `x50fjjkl…-notify-permission-prompt` | none | `4xs98yxp…-ntfy-send/bin/ntfy-send` |

Posts over the last 24 h, from 2026-11-11T20:01:08Z:

- `fleet-alerts`: `[RESOLVED] PullRequestQueueWaitBurn` at 2026-11-11T20:31:03Z, the evaluator's rule on nixbot's queue wait resolving the episode that fired at 13:13:02Z; magnetite's journal holds that post and 1,441 heartbeat posts, and nothing else.
- `fleet-acceptance` and the topics `magnetite`, `cinnabar` and `pyrite`: nothing.
- `stibnite`: 63 posts titled `Permission: Bash`, "Waiting for permission: Bash: git reset --hard HEAD~1", from 19:57:29Z to 19:57:44Z, in the title and message form `notify-permission-wait` posts through `ntfy-send` for a session's permission request on stibnite; nothing in this change sets how often a session invokes the hook, and why it ran 63 times in 15 s was not investigated.
- cinnabar's journal: the dead-man ran 288 times, with 288 pings accepted, none missed and the longest gap between pings 302 s; pyrite's journal holds no `observability-notify@` unit; stibnite's `notify.log` holds no `FAILED` since 2026-11-05.

The operator's statement on whether healthchecks.io sent any email over the last 24 h is not yet recorded.

`caddy-root-check` ran on its timer on 2026-11-09 at 14:00:02Z and exited 0, naming root `7E:78:…:2E:82`, beside the manual run of 6.4 on 2026-11-08 at 20:01:00Z.

caddy's journal since 3.1's switch (`@1794156617`) holds three `pki.ca.local` lines at `error` level, one per caddy start, at 2026-11-08 16:52:17Z, 20:00:58Z and 20:03:15Z: `failed to install root certificate`, `failed to execute tee: exit status 1`, for RV's store path.
3.1 records their cause, which predates this change: caddy runs unprivileged and cannot write the system trust store, and every restart of caddy since 2026-10-07 logs the line.
No other PKI line appears, so caddy logged no error loading the root or issuing an intermediate or leaf.
Whether these three lines count as the PKI error 10.1 excludes is put to the operator.

From stibnite, the served intermediate `CN=Caddy Local Authority - ECC Intermediate`, fingerprint `EC:84:82:32:4F:FD:29:D7:38:24:8E:22:D9:0E:5D:04:06:F0:AA:4B:2C:76:D8:37:F7:97:91:A4:F5:DE:2D:73`, `notAfter` 2026-11-16 09:33:15Z, verifies against RV with `OK`, and `openssl s_client -CAfile RV -verify_return_error` returns `0 (ok)`.

## 12. Holistic review (tasks.md 9.3)

*Open slot: `review.md` and `retrospective.md`.*

## 13. Archive (tasks.md 9.6)

*Open slot: the archive, the spec sync and the Linear transitions.*
