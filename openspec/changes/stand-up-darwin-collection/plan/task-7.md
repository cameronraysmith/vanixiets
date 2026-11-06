### Task 7: Documentation

Implements `tasks.md` 7.1–7.4 (design "Decision records amended under charter v29", Migration Plan pull request 4; FII `This capability states its own trust boundary`; FAI `This capability states its own trust boundary`, whose statements the runbook carries for the operator).
This is pull request 4; nothing is deployed.
It starts after Task 5 Step 3, whose observation of C1 decides the `ntfy-send` note, and after Task 6, whose rules the documents describe; the runbook's kickstart procedure is confirmed by Task 8 Step 4 and amended there if the observation differs.
Verification reads the delivered files, which here are the repository files themselves (none is generated).

**Files:**
- Modify: `modules/clan/services/otel-collector/README.md` (a darwin section: the role's `darwinModule`, the fragment, the five launchd jobs, the renderers, the probe and its fixtures, the wrapper, the darwin envelope and C5)
- Modify: `packages/docs/src/content/docs/development/operations/fleet-observability.md` (a darwin host section)
- Modify: `docs/notes/development/observability/charter.md` (the v29 entry), `decisions/ADR-003-collection-topology.md`, `decisions/ADR-004-signal-scope-and-schema.md`, `decisions/ADR-009-alerting.md`, `components/otel-collector.md`, `components/host-probes.md`, `components/fleet-alert.md` under `docs/notes/development/observability/`
- Modify: `pkgs/by-name/ntfy-send/package.nix:5-8` (the endpoint-security note), `modules/README.md` (gating checks)
- Create (git-ignored): `logs/s5-evidence/7.<n>-*.log`

**Interfaces:**
- Consumes: everything Tasks 2, 3 and 6 produced, read from the merged code, not from this plan; `logs/s5-evidence/5.3-*.log` (C1's observation and the collectors' memory), `6.1-replay-*.log` (the confirmed C5 limits).
- Produces: the operator's procedures that `verify.md` cites for adding a darwin host, reading `FAILED otel-envelope on stibnite`, and clearing a crashed kept-alive job's exit code.

- [ ] **Step 1: The collector README (tasks.md 7.1)**

Describe, one sentence per line, with file paths and option names as they are in the merged code:
- that the agent role's `perInstance.darwinModule` declares `otel-ca`, `otel-cert` and `ntfy-alerter` on every darwin row and imports `flake.modules.darwin.otel-collector-agent` only where `collect` is true, and that `restartUnits` is set only in the NixOS module, because clan-core rejects it on darwin;
- the five launchd jobs with their users and schedules (`otelcol` as `_otelcol` kept alive, `otelcol-process` as root kept alive with no listener, node_exporter with only `textfile` on `127.0.0.1:9100`, `otel-host-probe` every 60 s, `otel-envelope` every 300 s), and that none uses `StartCalendarInterval`, which the fragment asserts;
- `flake.lib.otelCollectorDarwin`, `flake.lib.otelHostProbe` and `flake.lib.observabilityNotifyRun`, rendered from `flake.lib` data so `checks.x86_64-linux.otel-collector-darwin` validates and tests them on Linux;
- the probe's two vendored calls, its `-1` for a missing exit code, `unloaded` for a label launchd does not know, the owner alias, and the parser fixtures recorded on macOS 26.7.1;
- the wrapper's `FAILED` and `RESOLVED` posts, its 900 s rate limit and `notify.log`, shared with the NixOS notifier template;
- the darwin envelope's clauses C1 to C4 and C5 with its two limits as confirmed in Task 6 Step 1, and the queues of 400 and 16 MiB.

Run:

```bash
rg -n 'otelcol-process|otel-host-probe|observability-notify-run|darwinModule' modules/clan/services/otel-collector/README.md | tee logs/s5-evidence/7.1-readme-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: each of the four patterns matches at least once.

- [ ] **Step 2: The runbook (tasks.md 7.2)**

Add to `packages/docs/src/content/docs/development/operations/fleet-observability.md` a darwin host section:
- Adding a darwin host: a row in `flake.lib.observabilityHosts` with `platform = "darwin"` and `collect = false`, matching the inventory's `machineClass`; then `CLAN_NO_COMMIT=1 clan vars fix <host> --generator otel-ca` and `--generator ntfy-alerter`, and `CLAN_NO_COMMIT=1 clan vars generate <host> --generator otel-cert`, with the hash checks of plan Global Constraints, never `clan vars generate` on a shared generator, and `CLAN_NO_COMMIT=1` on every clan vars command so the vars are committed with jj in the change's own commit; then a one-line change setting `collect` true, activated with `just activate` at the machine and followed by magnetite's deploy, because the evaluator reads the row from magnetite's closure.
- Reading `FAILED otel-envelope on stibnite`: the envelope's output file named by the plist's `StandardOutPath` (`/usr/bin/plutil -extract StandardOutPath raw /Library/LaunchDaemons/org.nixos.otel-envelope.plist`), what each clause means, and `notify.log` under `/var/lib/otel-envelope`.
- Clearing a crashed kept-alive job's exit code: read its cause first (`launchctl print system/org.nixos.<label>` and the job's log), then `sudo launchctl kickstart -k system/org.nixos.<label>`, after which `LaunchdJobFailed` resolves once the probe reads exit code 0.
- The trust boundaries in the operator's words: any `otel-ca` certificate holder can write series under any host name, so a lost or stolen laptop's key stays valid until `otel-ca` is rotated, and the rotation covers stibnite; a compromised stibnite can post to any `fleet-*` topic with the alerter token, as pyrite can; an anonymous post to a `fleet-*` topic is refused (Task 8 Step 8).
- The endpoint-security note's outcome from Task 5 Step 3: a store-built `otelcol-contrib` reached the ingress over ZeroTier, or the operator's decision if it did not.

Run:

```bash
rg -n 'stibnite|kickstart|just activate|platform' packages/docs/src/content/docs/development/operations/fleet-observability.md | tee logs/s5-evidence/7.2-runbook-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: each pattern matches.

- [ ] **Step 3: The decision records, the `ntfy-send` note and `modules/README.md` (tasks.md 7.3)**

Add the charter's v29 entry and make the amendments design "Decision records amended under charter v29" lists, each citing the merged file and line it describes: ADR-003's R3.2 and its implementation surface (the darwin envelope as a `StartInterval` job under the platform-neutral notifier), item 23 (`-1` for a missing exit code) and its envelopes (C5); ADR-004:121-123 (`org.nixos.otel-envelope` in the allow-list); ADR-009:131-132 and item 17 (`LaunchdJobNotRunning` on unloaded jobs, `LaunchdJobFailed` excluding self-notifying labels, pending time counting only while the host reports); `components/otel-collector.md`, `components/host-probes.md` and `components/fleet-alert.md` to match.
Correct `pkgs/by-name/ntfy-send/package.nix:5-8`'s note per Task 5 Step 3: if the store-built collector reached the ingress, the note says that a store-built binary on stibnite reached the ingress over ZeroTier on the observed date, and `ntfy-send` keeps `/usr/bin/curl` only if the operator decides so; otherwise the note is kept.
In `modules/README.md`, list `checks.x86_64-linux.otel-collector-darwin` among the gating checks with what it establishes (the darwin configurations validated by the pinned collector, the probe's parser over recorded `launchctl print` and `smartctl` output, the wrapper's episodes) and what it does not (any darwin process start, which stibnite's activation and Task 8 observe).
Run:

```bash
L=logs/s5-evidence/7.3-records-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
rg -n 'v29' docs/notes/development/observability/charter.md | tee "$L"
rg -n 'otel-collector-darwin' modules/README.md | tee -a "$L"
rg -n 'otel-envelope|unloaded|-1|observability-notify-run' docs/notes/development/observability/decisions/ADR-003-collection-topology.md docs/notes/development/observability/decisions/ADR-004-signal-scope-and-schema.md docs/notes/development/observability/decisions/ADR-009-alerting.md docs/notes/development/observability/components/host-probes.md docs/notes/development/observability/components/fleet-alert.md | tee -a "$L"
```

Expected: the v29 entry, the gating-check line, and each amendment matched; a sentence in the records that still contradicts the deployed system is listed for the operator.

- [ ] **Step 4: The pull request (tasks.md 7.4)**

Run `nix fmt` and `nix fmt -- --fail-on-change`, keeping the log; commit with a plain message, for example "Document host-metrics collection on stibnite, its launchd jobs and its delivery check"; open pull request 4 with the same kind of title, its body free of slice, decision and task codes.
Expected: nixbot green.
