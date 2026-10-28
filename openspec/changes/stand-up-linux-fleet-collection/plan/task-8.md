### Task 8: Documentation

Implements `tasks.md` 8.1–8.4 (design Migration Plan, pull request 4; FII `This capability states its own trust boundary`, whose statement the runbook carries for the operator).
This is pull request 4; nothing is deployed.
The decision records under `docs/notes/development/observability/`, including `components/otel-collector.md` and `components/host-probes.md`, carry their charter v23 amendments, made outside this change's pull requests; this task does not edit them, and lists for the operator any sentence there that still contradicts the deployed system.
Verification reads the delivered files, which here are the repository files themselves (none is generated).

**Files:**
- Modify: `modules/clan/services/otel-collector/README.md` (sections on roles, the queue `:130-146`, the failure notifier `:148-173`, and a new section on `otel-envelope`)
- Modify: `packages/docs/src/content/docs/development/operations/fleet-observability.md` (new sections on agent hosts and certificates, the ingress, and `otel-envelope`)
- Modify: `modules/README.md:48-70` (gating checks and on-demand tests)
- Create (git-ignored): `logs/s4-evidence/8.<n>-*.log`

**Interfaces:**
- Consumes: everything Tasks 2 to 7 produced, read from the merged code, not from this plan; `logs/s4-evidence/4.5-*.log` (cinnabar's measured queue rate), `7.6-*.log` (the hourly run's duration).
- Produces: the operator's procedures that `verify.md` cites for certificate rotation and for reading an `otel-envelope` failure.

- [ ] **Step 1: The collector README (tasks.md 8.1)**

Describe, one sentence per line, with file paths and option names as they are in the merged code:
- that the agent role covers every host of `flake.lib.observabilityHosts`, generated into the inventory, that a host joins by a row there, and that its `collect` flag gates everything the role runs on the host, so a new host is added with `collect = false` and turned on by its own one-line change before a watched deploy;
- the role switch `vanixiets.otelCollector.ingress`: `forward` on magnetite, `otlp_http/ingress` and `otlp_http/ingress-logs` elsewhere, with their endpoint, TLS 1.3, the two credentials and the CA as a store path;
- `otlp/mesh` on magnetite's ZeroTier address, its client CA, the `zt+` firewall opening and the non-local bind;
- the queues per role (magnetite's seven, 496 MiB; elsewhere 400 and 16 MiB), and cinnabar's measured rate from Task 4;
- the conditional service scrapes, the filesystem scraper over the host's ZFS mountpoints, the `otelcol` self-telemetry scrape and its keep-list, and the SMART exporter with its `ExecStartPre` ACL;
- that `file_log/deploy-record` lives in the agent role, unchanged in id and settings;
- `otel-envelope`: C1 to C4 every 5 min on every host, B1 to B6 hourly on magnetite, what reads as back-pressure rather than loss, and the first run's baseline;
- the replacement of the sentence `:151` that magnetite lists its own notified units: they are now the table's `notifiedUnits`.

Run:

```bash
rg -n 'otlp/mesh|observabilityHosts|otel-envelope|smartctl|otlp_http/ingress' modules/clan/services/otel-collector/README.md | tee logs/s4-evidence/8.1-readme-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: each of the five patterns matches at least once.

- [ ] **Step 2: The runbook (tasks.md 8.2)**

Add to `packages/docs/src/content/docs/development/operations/fleet-observability.md`:
- Adding an agent host: a row in `flake.lib.observabilityHosts` with `collect = false`, then `CLAN_NO_COMMIT=1 clan vars fix <host> --generator otel-ca` and `--generator ntfy-alerter`, then `CLAN_NO_COMMIT=1 clan vars generate <host> --generator otel-cert`, with the hash checks of plan Task 2 Step 4, and never `clan vars generate` on a shared generator; then a one-line change setting `collect = true`, merged immediately before the host's watched deploy.
- Rotating `otel-ca` on compromise: regenerate `otel-ca` and every `otel-cert`, deploy every host, magnetite last, so agents queue until the ingress trusts the new CA; certificates have no revocation, and a lost key stays valid until this is done.
- The trust boundary in the operator's words: any certificate holder can write series under any host name; ZeroTier carries packets and authenticates nothing; nothing here proves a series reached the store end to end.
- The ingress's refusal, as stibnite saw it (`curl: (55)` with `certificate required`), and how to reproduce it.
- Reading a `FAILED otel-envelope.service on <host>`: `sudo journalctl -u otel-envelope -o cat -n 50 | grep '^otel-envelope: '` on the host, what each clause means, and that the evaluator's `RuleSignalMissing <host>` names a silence where the envelope names the cause.
- Deploying cinnabar over `root@49.13.68.78`, because its switch can restart `zerotierone`, with the controller comparison of plan Task 4 Steps 1 and 3; deploying pyrite only with someone at it.

Run `rg -n 'otel-ca|rotation|otel-envelope|49.13.68.78' packages/docs/src/content/docs/development/operations/fleet-observability.md`.
Expected: each pattern matches.

- [ ] **Step 3: `modules/README.md` and the decision records (tasks.md 8.3)**

In `modules/README.md`, list `checks.x86_64-linux.otel-envelope` among the gating checks with what it establishes (the envelope's clauses against recorded telemetry, no running collector), and add under the on-demand tests (`:66-70`) `nix build .#vmTests.x86_64-linux.fleet-ingress   # Magnetite, uid-range`, with what it establishes (mTLS refusal, delivery across the ingress, back-pressure without loss, every envelope clause's negative control, the budget fixtures) and what it does not (the real ZeroTier address and refusal, observed at deploy).
Then read the two components and list any sentence that still contradicts the deployed system:

```bash
rg -n 'otel-envelope|ingress|smartctl|alwaysOn|always-on' docs/notes/development/observability/components/otel-collector.md docs/notes/development/observability/components/host-probes.md | tee logs/s4-evidence/8.3-components-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `otel-envelope` described on every agent host and its budget clauses on the ingress host, and the SMART `ExecStartPre` described (charter v23); a contradiction is put to the operator, not edited here.

- [ ] **Step 4: The pull request (tasks.md 8.4)**

Run `nix fmt` and `nix fmt -- --fail-on-change`, keeping the log; commit with a plain message, for example "Document the collector on every NixOS host, its certificates and its delivery checks"; open pull request 4 with the same kind of title, its body free of slice, decision and task codes.
Expected: nixbot green.
