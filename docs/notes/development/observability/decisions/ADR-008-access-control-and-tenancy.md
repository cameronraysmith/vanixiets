---
title: "ADR-008: Access control and tenancy"
---

## Status

Proposed

## Context

Charter D8 asks for one access model, covering the prompt-content hazard of W9 and the relationship to the omnigent worker-isolation boundary.
RK5 has fired and RK9 binds: content must be excluded by the collector, and the store authenticates but does not authorize (charter RK5, RK9).

What the open GreptimeDB build does:

- With no user provider configured, every request is admitted as an anonymous user (`research/telemetry-security-and-tenancy.md` F31).
- With a provider configured, every path under `/v1/`, including the OTLP routes, requires credentials, and only four health paths bypass (`research/telemetry-security-and-tenancy.md` F32).
- The only credential is HTTP Basic against a static or watched file; no released version authenticates a bearer token (`research/telemetry-security-and-tenancy.md` R5, R6; `research/otel-collector-topology.md` C1).
- Both open user providers implement `authorize` as allow-all at 1.1.4, 1.2.1 and `main` (`research/telemetry-security-and-tenancy.md` R1).
- The one enforced lever is a per-user `rw`, `ro` or `wo` mode, checked against whether a request reads or writes (`research/telemetry-security-and-tenancy.md` R2; `research/greptimedb.md` R26, R27).
- The database is selected by the caller through `x-greptime-db-name` or `db`, so a database is a label, not a boundary (`research/telemetry-security-and-tenancy.md` F30).
- Per-database and per-table authorization exists only in the separate Enterprise binary's `greptime_ee_user_provider` (`research/telemetry-security-and-tenancy.md` R3, R4).
- The watched credential file does not follow a sops-nix symlink swap before 1.3.0-beta.1, so rotation needs a restart (`research/telemetry-security-and-tenancy.md` R7).

What Perses does:

- Enabling auth forces native authorization on, and every proxy request is checked against the project, scope and action (`research/telemetry-security-and-tenancy.md` R11).
- The saved-datasource proxy checks only `read` on `Datasource` in the project, matches `allowedEndpoints` against method and path only, and inspects neither query string nor body, so a project reader can send arbitrary SQL, including fully qualified names in other databases, under the datasource's stored credential (`research/perses.md` R27, R28, R29, C8).
- `guest_permissions` apply to every logged-in user in every project (`research/perses.md` R33).
- Perses 0.54.0 forwards the caller's session token to the datasource and accepts a default encryption key with auth enabled; both are fixed only in the 0.55 line (`research/telemetry-security-and-tenancy.md` R14, R15, C4, C5).

What the emitters and the worker boundary do:

- Each omnigent worker is a separate Unix account with a locked password and an `0700` home, and the account is the whole-worker boundary (`research/telemetry-security-and-tenancy.md` R19, R20).
- Any code a worker runs can set its own `OTEL_*` variables, and the reserved-environment policy covers `CLAUDE_`, `OMNIGENT_`, `PI_` and `OMP_` but not `OTEL_` (`research/telemetry-security-and-tenancy.md` R22).
- omp captures message content only when `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT` is set, but forwards every internal logger event as an OTLP log record with its message under no gate (`research/dev-loop-signals.md` RF11).
- omp honours `OTEL_LOGS_EXPORTER=none` per signal and `telemetry.otlpExportEnabled: false` as a whole (`can1357/oh-my-pi@c2cb79e4c:docs/environment-variables.md:651,659`).
- The contrib `redaction` processor is fail-closed on attribute keys with `allow_all_keys: false`, but a string log body takes a branch that applies only blocked-value patterns, so a prompt in a string body survives (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:processor/redactionprocessor/processor.go:188-235`; `research/telemetry-security-and-tenancy.md` R25, R26).
- The journald receiver delivers each entry as a map body containing every journal field (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:pkg/stanza/operator/input/journald/input.go:203`), and omnigent workers on NixOS log to the journal (`research/fleet-emitter-inventory.md` R10).

Public surfaces:

- The gitea, nixbot and niks3 `/metrics` locations now admit only loopback and the ZeroTier /64 (`cameronraysmith/vanixiets@02432c594:modules/lib/nginx-metrics-location.nix`).
- gitea-mq serves an unauthenticated HTML queue dashboard on its public vhost showing pull-request titles and authors (`research/fleet-emitter-inventory.md` R6, Q7).
- gitea-mq uses that public URL as the commit-status target and webhook base (`Mic92/gitea-mq@9bad60d8f:internal/batch/batch.go:222,628`; `Mic92/gitea-mq@9bad60d8f:cmd/gitea-mq/main.go:108`), and its only configured repository is `cameronraysmith/vanixiets` (`cameronraysmith/vanixiets@109c67346:modules/nixos/gitea-mq.nix:33-35,74`), which is public.

## Decision

Adopt a content-free shared read zone: the per-host collector is the only content boundary and the only path into the store, the store holds the four mode-separated credentials of ADR-007 of which no worker holds any, and every admitted reader may read all stored telemetry.

What is enforceable with the open build, and is enforced:

1. Authentication on every store request, by configuring the user provider from ADR-007's `greptimedb-users` file; the store listener requires credentials even on loopback because loopback is reachable by every local UID, including magnetite's two worker accounts.
2. Read/write separation by user mode, with the four users ADR-007 enumerates: `collector` is `wo` and held only by the ingress collector on magnetite (ADR-003); `perses` is `ro` and held only by Perses (ADR-002); `regulator` is `ro` and held only by the read-only regulator units `otel-envelope` (ADR-003, ADR-004, this record), `devloop-reconcile` (ADR-005) and `greptimedb-envelope` (ADR-007); `admin` is `rw` and held only by the local schema, export and envelope oneshots of ADR-007 and ADR-006.
3. Network placement: the store's HTTP port binds loopback only for ingest (ADR-007), and the only mesh-facing telemetry listener is the mTLS ingress receiver (ADR-003).
4. Configuration immutability against workers: each collector runs under a system account outside every worker UID, NixOS `DynamicUser` or darwin `_otelcol`, with its configuration in the Nix store and its credentials delivered by `LoadCredential` or as `0400` files owned by that account.
5. Content exclusion at that collector, fail-closed, as follows.

Collector content stages, applied on every agent before any exporter:

1. No logs pipeline consumes the local OTLP receiver, so OTLP log records from any emitter are refused regardless of emitter settings.
2. On the agent (omp) pipeline only, `redaction` on traces and metrics with `allow_all_keys: false`, `allowed_keys` from ADR-004's agent key allow-list, and `summary: silent`, plus a `filter` that drops every omp metric whose name is not on ADR-004's metric-name allow-list (`omp.agent.tool.calls` and `omp.agent.errors`); Prometheus-scraped and `host_metrics` points keep their native label keys, bounded by ADR-004's cardinality rules rather than by key redaction.
3. `transform` on traces clearing span status messages and removing span events named `exception`.
4. On journald logs, a `filter` that drops every record whose `_SYSTEMD_UNIT` is not on ADR-004's unit allow-list, independent of the receiver's own `units` setting.
5. A `transform` that replaces each surviving journald map body with its `MESSAGE` string and keeps only the journal fields on ADR-004's journald field allow-list as attributes, so no string body enters the store from a source not on the unit allow-list, because `redaction` does not protect string bodies.
6. Every record bound for `devloop` keeps only the columns on ADR-004's per-signal `devloop` column allow-list, under the primary key and time index ADR-004 states for that table.

Emitter posture, a starting state and not an enforcement point:

1. omp is configured with `OTEL_LOGS_EXPORTER=none` and without `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`, pointing at the local agent (see ADR-005).
2. `OTEL_` is added to the reserved worker-environment prefixes, which prevents role settings from enabling a content gate but does not constrain code a worker runs (Q4).
3. In this slice no omnigent worker account receives an OTLP endpoint or credential, so worker sessions emit no telemetry to any collector; enabling worker telemetry requires revising this record (Q3; ADR-004 Q5 and ADR-005 Q5 defer here).

What is not enforceable with the open build, and is therefore not promised:

1. Per-person, per-database or per-table read partitioning in the store: `authorize` is allow-all and the Enterprise provider is not available.
2. Per-person read partitioning through Perses: a reader of any project holding a GreptimeDB datasource can query every database under the `perses` credential.
3. Write partitioning: the `wo` credential can insert into any database.
4. Attribution of a local OTLP write to the Unix account that sent it: the agent's loopback receiver cannot see the sender's UID, so a worker can inject telemetry attributed to its host.
5. Emitter-side content gates: every gate is an environment variable or setting under the worker's control.
6. Credential rotation without restart on GreptimeDB below 1.3.0-beta.1.
7. Identity-provider login to the store: no OIDC, LDAP or mTLS provider exists in the open build.

Readers and admission:

1. Humans read only through Perses, authenticated by a direct Kanidm OIDC client rather than `sso-gateway` (`research/telemetry-security-and-tenancy.md` F16), with a Kanidm scope map restricting login to one group.
2. Perses runs with auth enabled, `guest_permissions` empty, `security.readonly: true`, `security.encryption_key` from a clan vars secret, one project, and RoleBindings naming each admitted person explicitly, because 0.54.0 has no claim-based roles (ADR-002).
3. Every admitted person reads every stored signal, including the other person's harness metrics; the boundary that makes this acceptable is that the store holds no content and no person identifier (ADR-004).
4. GreptimeTeam/dashboard is not deployed, because it keeps a store password in browser storage and has no authorization of its own (`research/perses.md` R41; ADR-002).
5. No worker account and no worker-run process holds any store credential or Perses datasource secret.

Public surfaces:

1. The three `/metrics` endpoints stay restricted to loopback and the mesh as already committed.
2. The gitea-mq dashboard stays public while its configured repositories are public, because commit-status links and the webhook depend on its public vhost; adding a private repository requires restricting `/` to the mesh first.

## Rationale

Per-person read partitioning has no enforcement point in this stack: the store authorizes nothing (RK9), the Enterprise provider is a paid product, and Perses' project RBAC does not constrain the SQL its proxy forwards (`research/perses.md` C8).
The original reliance on Perses projects as the partition (charter RK9 consequence) is therefore withdrawn, and the boundary moves to what enters the store.
Content exclusion can be enforced, because the collector runs outside every worker account with immutable configuration (`research/telemetry-security-and-tenancy.md` refresh, Bearing on D8 and D3), and because an attribute allow-list fails closed.
Refusing OTLP logs structurally, rather than redacting them, is required because omp's log signal has no content gate and string bodies defeat the redaction processor.
The journald path needs its own unit allow-list for the same reason: worker output reaches the journal as string messages that no key allow-list inspects.
Holding the store credentials only in the ingress collector, in Perses, in the read-only regulator units and in the store's administrative oneshots means a worker compromise yields at most telemetry injection on its own host, never a read channel over the fleet (`research/telemetry-security-and-tenancy.md` F25, F26).
A shared read zone among admitted people is the smallest model that is true as stated; a partition model would describe a boundary that the software does not enforce.

## Rejected alternatives

- Per-person read partitioning through Perses projects: the proxy forwards arbitrary SQL under one credential, so the partition is not enforced.
- One GreptimeDB instance per person: doubles the store on a memory-constrained host to protect data that the allow-list already excludes.
- GreptimeDB Enterprise for table ACLs: a paid, separate binary to partition data that contains no content.
- A query-rewriting proxy in front of GreptimeDB: new security-critical code that must parse SQL correctly forever.
- Write-only store credentials in worker accounts: usable by any code the worker runs and able to write into any database.
- Redacting omp OTLP logs instead of refusing them: string bodies pass the redaction processor by value-pattern only.
- Trusting emitter content gates: each is an environment variable the worker controls.
- Admission through `sso-gateway`: disabled, redirect-based, and double-gates a service with native OIDC.
- Deploying GreptimeTeam/dashboard for exploration: browser-stored store password and the store's allow-all authorization.
- Closing the gitea-mq dashboard now: breaks commit-status links and webhooks while showing only a public repository's pull requests.

## Consequences

Every admitted reader sees all telemetry, so admission to the Kanidm group is the only read decision, and its membership lives in the running Kanidm database rather than in the repository (`research/telemetry-security-and-tenancy.md` F13, R23).
Content-bearing diagnostics, such as error messages and exception text, are unavailable from the store; failure classes come from `error.type` only (ADR-004).
A worker can inject misleading telemetry for its own host; the dev-loop consumer must treat agent-harness metrics as emitter-claimed.
Raising the content bar later, for example admitting a single opt-in content session, requires a separate store or the Enterprise provider, not a configuration change.
Perses 0.54.0 forwards the reader's Perses session token on proxy requests, but it does not reach the store in the `Authorization` header, because the datasource's `basicAuth` makes `SetBasicAuth` replace that header; whether the session cookies are also forwarded is not established, and their only receiver is the loopback store on magnetite (ADR-002, which decides the version).
Rotation of store credentials requires `restartUnits` on the store, the ingress collector and Perses until GreptimeDB 1.3.0-beta.1 or later is deployed.
The relationship to worker isolation is that the worker account boundary protects the collector's configuration and credentials, not the emitter's output, which remains untrusted.

## Operating envelope and regulator

Envelope: no stored record carries a value from a key outside ADR-004's allow-lists (agent keys, journald fields, `devloop` columns) or an omp metric name outside ADR-004's metric-name allow-list, no stored log record originates from OTLP or from a unit outside the unit allow-list, and no store credential file is readable by a worker UID.

Regulator R8.1, deterministic, build time: the flake check `checks.x86_64-linux.otel-redaction` runs `otelcol-contrib` with each agent's generated processor stages between an `otlpjsonfile` receiver and a `file` exporter, over fixtures that place one canary string in every never-stored key, in a span status message, in an `exception` event, in an unknown attribute, in an OTLP log record, and in a journald-shaped record from `omnigent-host-cameron`.
It asserts that the canary appears nowhere in the output, that a positive-control allow-listed field and an allow-listed unit's message do appear, and, by evaluation, that no logs pipeline consumes the local OTLP receiver.
It is shown able to fail at acceptance by two mutants: `allow_all_keys: true`, and removal of the journald unit filter, each of which must make the check fail with the canary in the output.

Regulator R8.2, deterministic, evaluation time: assertions that every file of the `greptimedb-users` and `otel-cert` generators is owned by a non-worker account with mode `0400`, that the store's HTTP bind is loopback, and, if Q4 is accepted, that the existing mutant-tested oracle in `modules/checks/omnigent-environment.nix` rejects an `OTEL_` name in worker environment.
It is shown able to fail by a mutant that sets a worker as owner of `collector-password`.

Regulator R8.3, runtime: the `otel-envelope` timer of ADR-003, using ADR-007's `regulator` (`ro`) credential, lists the columns of every table in `fleet`, `devloop` and `agent` from `information_schema.columns` and fails when a column of an `agent` table is outside ADR-004's agent key allow-list, a column of a `devloop` table is outside ADR-004's `devloop` column allow-list for that table, or a column of a `fleet` log table is outside ADR-004's journald field allow-list, because GreptimeDB creates a column for each new attribute key; scraped and `host_metrics` tables keep native label columns, bounded by ADR-004's cardinality rules rather than by this check.
It is shown able to fail at acceptance by writing one span with a disallowed attribute through an administrative credential and observing the unit fail.

Perses' own configuration regulator, covering `guest_permissions`, auth and `readonly`, is ADR-002's.

## Failure prevented

- Collector content stages: prompt, tool or repository content reaches a store every admitted reader can query (RK5, W9).
- Refusing OTLP logs: omp's ungated log messages bypass every content gate.
- journald unit filter and body transform: worker output in the journal enters the store as a string body the redaction processor does not inspect.
- Credentials only in the ingress collector, Perses, the read-only regulator units and the administrative oneshots: a compromised or prompt-injected worker obtains a read channel over all fleet telemetry.
- Mode-separated users: the collector credential can read, or the dashboard credential can write.
- Authentication on loopback: a local worker on magnetite reads the store without credentials.
- Shared read zone stated explicitly: the design claims a per-person boundary that the software does not enforce.
- Reserved `OTEL_` prefix: a role setting enables an emitter content gate fleet-wide by configuration.
- R8.1: a configuration change that admits content ships.
- R8.2: a credential becomes readable by a worker through an ownership change.
- R8.3: content or an unknown attribute reaches the store through a path the build-time fixtures did not model.

## Implementation surface

- Add `modules/checks/otel-redaction.nix`: regulator R8.1, reading `modules/clan/services/otel-collector/schema.nix` (ADR-004).
- Modify `modules/clan/services/otel-collector/flake-module.nix` (ADR-003): the content stages above, the absence of a logs pipeline on the local OTLP receiver, and the R8.2 ownership assertions for `otel-cert`.
- Modify `modules/lib/omnigent-environment.nix`: add `OTEL_` to the reserved prefixes, if Q4 is accepted.
- Modify `modules/checks/omnigent-environment.nix`: add an `OTEL_` policy mutant, if Q4 is accepted.
- Modify `modules/nixos/kanidm.nix`: a group for observability readers, members operational as for `omnigent_users`, and an OAuth2 client for Perses with a scope map for that group (ADR-002 owns the Perses side).
- Add the R8.3 query to the `otel-envelope` unit of ADR-003.
- Modify `modules/home/ai/omp/default.nix`: `OTEL_LOGS_EXPORTER=none` alongside the endpoint ADR-005 sets.
- Consumed, not created here: the `greptimedb-users` generator of ADR-007 with users `admin` (`rw`), `collector` (`wo`), `perses` (`ro`) and `regulator` (`ro`), and the Perses OIDC client secret and encryption key generators of ADR-002.
- No flake input is added.

## Questions for the human gate

1. Q1: Accept the shared read zone and drop per-person partitioning? Recommended: yes; the alternative requires a second store, the Enterprise build, or a SQL-rewriting proxy.
2. Q2: Who is admitted to the observability reader group? Recommended: Cameron only at first, Janette when she chooses; admitting both makes each person's harness metrics readable by the other.
3. Q3: If worker telemetry is later enabled (ADR-005 Q5), do Janette's worker sessions emit it? Recommended: no until she consents; the alternative records her agent activity in a store Cameron reads.
4. Q4: Add `OTEL_` to the reserved worker-environment prefixes? Recommended: yes; the alternative lets a role setting enable a content gate, though the collector still drops the content.
5. Q5: Is content exclusion absolute, with no opt-in content session? Recommended: yes; the alternative needs a separate store with its own access model.
6. Q6: Disable omp's log signal at the emitter with `OTEL_LOGS_EXPORTER=none`? Recommended: yes, in addition to the collector refusing OTLP logs; the alternative sends records that are refused and logged as export errors.
7. Q7: Keep the gitea-mq dashboard public? Recommended: yes while only public repositories are queued; restricting it breaks commit-status links and webhook delivery.
8. Q8: Buy or trial GreptimeDB Enterprise for table ACLs? Recommended: no; nothing in the content-free store needs partitioning.
