# S3 holistic review

A read-only review of slice S3 as merged and deployed, read against this change's proposal, design, specs, tasks and verify.md and the observability decision records, made on 2026-10-18 by a subagent in place of the paid codex review the plan named (plan.md Task 8 Step 11), at the operator's direction, as in S1.
It asked four questions: critical oversights, significant architecture improvements, checks that cannot fail or properties no check covers, and checks or mechanisms that cost more than the invariant they protect.
It found nothing critical and eleven findings, four significant and seven minor.
F12 was added when the follow-ups were planned: verify.md §4's first run found that the title requirement stated only `[FIRING] <alert> <host>`, while alerts that are not about one host post without a host.
Nine findings were applied in #3516 and #3519, as tasks.md section 10 records with its verification; F4 was documented and scheduled, and F10 deferred to S2; charter v20 and v21 record the amendments to the decision records.

| Finding | Category | Severity | Applied in |
|---|---|---|---|
| F1 the memory signal that defines a reporting host could not raise `RuleSignalMissing` | oversight, check gap | significant | #3516, tasks.md 10.2, charter v20 |
| F2 a failed notifier post was lost, and nothing reported it | oversight, architecture | significant | #3516, tasks.md 10.3 |
| F3 the dead-man legs evaluated cinnabar inside the check, at 91 % of its budget | overzealous | significant | #3519, tasks.md 10.8, charter v20 |
| F4 the ntfy-outage residual risk (CAM-76) is acceptable for S3, but not past S5 | oversight | significant | documented: the runbook and charter v21 state that an ntfy outage shows only as a missing Monday `WeeklyPipelineTest`, up to 7 days later; CAM-76 now blocks CAM-72 (S5) |
| F5 R9.5 copied two literals and left out the notifier's start hook | check gap | minor | #3516, tasks.md 10.4, charter v20 |
| F6 the token-path assertions compared a value with the line that set it | overzealous | minor | #3519, tasks.md 10.9, charter v20 |
| F7 six fire-and-resolve legs took their expected values from the evaluator's own rules | overzealous | minor | #3519, tasks.md 10.10, charter v20 |
| F8 an unreadable `failed.log` counted as an empty one | check gap | minor | #3516, tasks.md 10.5 |
| F9 `greptimedb-schema` stayed inactive after the store was stopped and started | oversight | minor | #3516, tasks.md 10.6 |
| F10 the evaluator sends one database header for every query | architecture | minor | deferred to S2, whose dev-loop SLO burn rule adds a per-rule `database` field (charter v21) |
| F11 `state.hosts` was written but never read | overzealous | minor | #3516, with F1, tasks.md 10.2 |
| F12 alerts that are not about one host post titles without a host, which the title requirement did not state | oversight | minor | #3516, tasks.md 10.7 |

The handoffs the dispositions create: CAM-76's watch from outside cinnabar lands before S5 adds laptops, and S2 adds the per-rule `database` field with its fixture and `promtool` support.

## Report

The review's report, verbatim:

I found nothing critical in S3.
I found 11 findings: 4 significant and 7 minor.
The closest to critical is F1: if magnetite's metrics stop reaching the store, the whole rule set goes quiet while the heartbeat stays green.

I worked against `origin/main` at `89228a794` in a detached worktree, which I have since removed.
I read the evidence under `logs/s3-evidence/` and ran the read-only `gh api` calls and `nix eval` runs quoted below.
I did not SSH to any host and ran no builds or checks.

| Finding | Category | Severity | Belongs in |
|---|---|---|---|
| F1 the memory signal that defines a reporting host cannot raise `RuleSignalMissing` | 1, 3 | significant | S3 now (ADR-009 item 16 amendment) |
| F2 a failed notifier post is lost, and nothing reports it | 1, 2 | significant | S3 now |
| F3 the dead-man legs evaluate cinnabar inside the check, which puts it at 91 % of its budget | 4 | significant | S3 now |
| F4 the ntfy-outage residual risk (CAM-76) is acceptable for S3, but not past S5 | 1 | significant | CAM-76, before S5 |
| F5 R9.5 copies two literals and leaves out the notifier's start hook | 3 | minor | S3 now |
| F6 the token-path assertions compare a value with the line that sets it | 4 | minor | S3 now |
| F7 six fire-and-resolve legs take their expected values from the evaluator's own rules | 4 | minor | S3 now |
| F8 an unreadable `failed.log` counts as an empty one | 3 | minor | S3 now |
| F9 `greptimedb-schema` stays inactive after the store is stopped and started | 1 | minor | S3 §10, or S4 |
| F10 the evaluator sends one database header for every query | 2 | minor | S2 |
| F11 `state.hosts` is written but never read | 4 | minor | with F1 |

**F1 (categories 1 and 3, significant): `RuleSignalMissing` cannot fire for `system_memory_usage_bytes`, the signal that decides which hosts count as reporting.**
- **Evidence:**
  - `reporting` is the set of hosts returned by the `system_memory_usage_bytes` presence query (`modules/nixos/fleet-alert.nix:206`).
  - `RuleSignalMissing` fires only while an expected host is in `reporting` (`transition.jq:75-76`). So when that one selector is empty, the alert's own gate is closed.
  - The same empty `reporting` freezes every instance labelled `host_name` (`transition.jq:81-86`).
  - `WeeklyPipelineTest` counts that same metric (`rules.nix:123`), so the Monday message also stops.
  - The fixture leg `silentGapLeg` (`modules/checks/fleet-alert.nix:790`) asserts this silence as the expected behaviour.
  - ADR-009:90,127 gives host freshness to `otel-envelope` (R3.2), which ships in S4.
- **Consequence:** until S4, magnetite is the only host.
  If its collector stays up but its exports fail, the store keeps answering queries and the heartbeat stays green, yet no alert can fire.
  Collector-side failures like this are how S1 lost 279 points at its first deploy.
  A full disk is still caught by `greptimedb-envelope`.
- **Change:**
  - Mark hosts as always-on in the rules table (only magnetite in S3).
  - Raise `RuleSignalMissing{selector="system_memory_usage_bytes",host_name=…}` when the store answered but an always-on host has been missing from `reporting` for 10 minutes.
    Use `state.hosts` as the last-seen time (see F11).
  - Amend ADR-009 item 16 for always-on hosts, and add a fixture leg plus a mutant.
  - In S4, this rule can replace R3.2's per-host freshness clause.

**F2 (categories 1 and 2, significant): a failed notifier post is lost, and nothing reports the loss.**
- **Evidence:**
  - `observability-notify@` is a oneshot with no `Restart=` (`observability-notify.nix:196-204`). When its post fails it writes no stamp, so only the unit's *next* failure posts again.
  - `SystemdUnitFailed` excludes every notified unit (D10).
  - The collector's unit allow-list does not include `observability-notify@*` (`otel-collector/schema.nix:14-38`), so a failed notifier is not reported either.
  - Units that fail once, such as `greptimedb-schema` and the `zfs-*` boot oneshots, therefore lose their only notice for good if ntfy or caddy restarts, or ZeroTier drops, during the single `curl -m 5` attempt.
  - The evaluator, by contrast, keeps unposted transitions in its state and retries them every run.
- **Change:** pick one of these:
  - Add `observability-notify@*.service` to `schema.systemdUnits`. A failed notifier then becomes a `SystemdUnitFailed` instance that the evaluator retries until ntfy accepts it, and the rule's regex already leaves it uncovered by the exclusion.
  - Or give the template `Restart=on-failure` with `RestartSec=60`.

**F3 (category 4, significant): the dead-man parts evaluate all of cinnabar inside `checks.fleet-alert`, which breaks the S3 rule that relations within one host are host assertions.**
- **Measured** (cold, `--option eval-cache false`, `.#.checks.x86_64-linux.…drvPath`):

  | What was evaluated | Allocation | CPU |
  |---|---|---|
  | `fleet-alert` (whole check) | 487 MB | 1.5 s |
  | its `deadmanClause` part | 426 MB | 1.3 s |
  | its `deadmanRehearsal` part | 411 MB | 1.3 s |
  | its `fixtureRehearsal` part | 265 MB | 0.8 s |
  | its `propertyRehearsal` part | 128 MB | 0.3 s |
  | cinnabar's `FLEET_DEADMAN_CONFIG` alone | 347 MB | 1.0 s |
  | `ntfy-provisioning` | 256 MB | 0.7 s |

- **Clauses that cannot catch a real mistake:**
  - `execStart == deployedDeadman` (`:404`) rebuilds the same function with the same arguments.
  - `pathUnits == deadmanPathUnits` (`:412`) and the ordering mutants copy the module's literal `after` list.
- **Change:**
  - Move the access decision, the `ntfyUrl`/`listen-http` relation and the ordering into cinnabar's assertions.
    Delete the `execStart` clause and the `pathUnits` copy.
  - Feed the dead-man legs a configuration rendered by a `flake.lib` function from the module's default options.
  - Keep in the check only the relations between hosts: the heartbeat topic, the alert topic and `evaluatorHost`.
  - Expected result: the check falls back toward Task 4's 0.25 GiB, which leaves room for the rules S4 and S5 add.

**F4 (category 1, significant): the ntfy-outage residual risk (CAM-76) is acceptable for S3, but not past S5.**
- **Evidence:**
  - Every post goes through cinnabar, and the dead-man runs on cinnabar too.
  - During an outage, the evaluator's alerts are delayed but not lost (it retries); the notifier's notices are lost (F2).
  - Detection depends only on the operator noticing that the Monday `info` message did not arrive, which can take up to 7 days.
- **Change:**
  - S3 now: name this detection bound, and F1, in the proposal's residual risks and in the runbook.
  - CAM-76: schedule it before S5, which adds laptops.
    It needs a watcher off cinnabar, for example an external healthcheck pinged by the dead-man and the evaluator that alerts over a channel other than ntfy.

**F5 (category 3, minor): R9.5 can only fail on a deliberate edit, and its time budget leaves out the notifier's start hook.**
- **Evidence:**
  - `fleet-alert.nix:540-541` asserts the same literals it sets.
  - D13 adds up to about 45 s: 30 s of queries, a 5 s heartbeat, and posts started before 40 s that take up to 5 s each.
  - The notifier's `ExecStartPost` hook (`observability-notify.nix:191`) can post `RESOLVED` with another 5 s timeout, which counts against the same `TimeoutStartSec`. The worst case is therefore exactly 50 s.
- **Change:**
  - Assert the relation instead: query deadline + heartbeat + post deadline + one post + one hook post, all strictly below `TimeoutStartSec`, which in turn is below the timer period.
  - Lower `postDeadlineSec` to 35.

**F6 (category 4, minor): the token assertions compare a value with the line that sets it.**
- **Evidence:**
  - `magnetite/default.nix:721` and `cinnabar/fleet-alert.nix:31` compare `tokenFile` with the token path, a few lines from where each host sets it.
  - The credential-name assertions in `fleet-alert.nix` and `observability-notify.nix:118` match strings the same module generates.
    They needed a second hook regex in `otel-collector-config.nix`.
- **Change:**
  - Keep only `unitsWithoutToken`, which can catch a host overriding a unit's hooks.
  - Delete the rest, and delete the widened `resolvedHook` regex with them.

**F7 (category 4, minor): the six fire-and-resolve legs take their expected values from the rules the evaluator reads.**
- **Evidence:** `f = (ruleNamed alert).for` (`checks/fleet-alert.nix:646`), so each leg can fail only on transition behaviour, which the property test already covers.
- **Change:** keep `HostOOMKill`, which carries the attribution text and is the target of the `noStateWrite` mutant, plus `HostMemoryPressure` for the `forZero` mutant.
  Delete the other four.

**F8 (category 3, minor): R9.1 treats an unreadable `failed.log` as an empty one.**
- **Evidence:** `if [ -r "$failed_log" ] … else echo '[]'` (`fleet-alert.nix:189`). A permissions regression would undercount notifier posts without any error.
- **Change:** treat a missing file as empty, but fail the run when the file exists and cannot be read.

**F9 (category 1, minor): after the store is stopped and started by hand, `greptimedb-schema` stays inactive (seen in 7.6).**
- **Evidence:** `greptimedb.nix:273-278` gives the schema job `requires` and `partOf` on the store but no `wantedBy` from it.
  Stopping the store stops the job, and starting the store does not start it again.
  A `restart` of the store does propagate.
- **Consequence:** small today, because the databases persist and the job is idempotent.
  If the store came back with an empty data directory, the databases would be missing until the next deploy or reboot [INFERENCE]. The evaluator would then raise `StoreQueryFailing`, and the collector's writes would get 400s and be dropped.
- **Change:** set `wantedBy = [ "multi-user.target" "greptimedb.service" ]` on the schema job, so starting the store pulls it in again.
  This goes in S3 §10 or S4.

**F10 (category 2, minor): the evaluator sends one database header for every query.**
- **Evidence:** `database = "fleet"` is fixed per evaluator. `fixture_server.py` also answers 400 to any other database.
- **Consequence:** S2's dev-loop SLO burn rule will need a per-rule `database` field, with matching fixture and promtool support.
- **Change:** add the per-rule `database` field in S2.

**F11 (category 4, minor): `state.hosts` is written but never read.**
- **Evidence:** `transition.jq:161` writes it, and `frozen` reads only the current run's `reporting`.
- **Change:** use it for F1, or delete it from `transition.jq`, `model.py` and D15.

I checked and do not count as findings:
- **D1:** ntfy 2.28.0 keys a user without a tier by address (`server/visitor.go:555-565`), so D1's per-client visitors also cover the `alerter` posts.
- **Token transport:** the token stays off argv everywhere I looked: `printf` builtin, `curl -H @-` and `curl --config -`.
- **Mutants:** every mutant I traced exercises its own clause.
- **Load on magnetite:** the evaluator takes about 0.7 s of queries a minute, so I see no risk of starving nixbot.
