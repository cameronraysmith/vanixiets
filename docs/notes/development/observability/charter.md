---
title: Fleet observability and CCV feedback-loop charter
status: charter v9
date: 2026-10-15
---

# Fleet observability and CCV feedback-loop charter

Charter version: v9.
A revision is a version bump with a dated entry under "Revision history"; the text of an earlier version is never edited in place.

## Objective

Produce a deployment-ready design, not an implementation, for a fleet observability platform and the continuous-feedback loop that consumes it.
The platform must serve two consumers: fleet infrastructure operation, and the development loop whose real-world consequences are currently invisible.
The second consumer is primary, because the stated limiting factor is not service uptime but the inability to observe what our implementation decisions actually cost once deployed.

The design exists so that a later implementation session proceeds from file-level instructions, named verification slices, and a closed list of human decisions, instead of re-deriving the research.

## Why now

The fleet has no observability surface at all.
A search for `signoz|prometheus|grafana|opentelemetry|greptime|perses|victoriametrics|loki|clickhouse` across `modules/`, `docs/notes/`, `flake.nix` and `justfile` returns zero matches in configuration; every hit is agent-skill prose under `modules/home/ai/plugins/`.
Nineteen service modules exist under `modules/nixos/` and none emits telemetry anywhere.

`preferences-compositional-continuous-verification` names this gap as one of its two open threads, and its adequacy property already treats observability-interaction checks as declared coverage bins rather than an optional flourish.
Under CCV, production observation is the upstream validation channel that updates the coverage model when real usage surfaces bins that were never declared.
Without that channel the apparatus can only ever confirm the envelopes we already thought to write.

## Scope

In scope: fleet infrastructure telemetry, development-loop telemetry, the store and query layer, the dashboard layer, and the feedback path from runtime observation back into the coverage model.
Development-loop telemetry is the primary consumer and drives retention, cardinality, and schema decisions where the two consumers conflict.

Out of scope for this charter: implementation, any `clan vars` mutation, and any deployment.
Corrected in v5: v1 also excluded any change to the in-flight `omnigent-magnetite` chain, which has since merged to `main` (`cameronraysmith/vanixiets@a12b3c6c5`, `cameronraysmith/vanixiets@2931154b1`), so no chain remains in flight.
Clarified in v8: when implementation is authorized it proceeds through one or more OpenSpec changes under `openspec/changes/`, following the precedent of `openspec/changes/stand-up-nixbot-on-magnetite/` and `openspec/changes/stand-up-gitea-mq-on-magnetite/`, each with `proposal.md`, `design.md`, `tasks.md` and `specs/`; this tree remains the design input those changes cite, not their substitute.

## Superseded inputs

The `nix-mpe-signoz-module` chain is deprecated and discarded as a design input.
It seeded a consideration of SigNoz that predates the recognition that an FDAP-aligned stack fits this repository's data-stack preferences better.
Its only commit is an empty seed (`tktswmrx`), but it currently participates in the diamond joins alongside `omnigent-magnetite`; the jj-level abandonment is deferred until that chain merges, so that the other agent's join topology and gate baselines are not disturbed mid-flight.
Corrected in v5: the `omnigent-magnetite` chain has merged to `main` (`cameronraysmith/vanixiets@a12b3c6c5`, `cameronraysmith/vanixiets@2931154b1`), so the deferred abandonment is now dischargeable.

`sciexp/ironstar`'s SigNoz work is superseded in part by this design.
Its artifacts remain readable prior art — `modules/services/signoz.nix` and `docs/notes/development/observability-migration-agent-prompt.md` — and its process-compose boundary argument is retained as evidence, not as a decision.

## World assumptions (indicative)

- W1 The fleet is the inventory in `modules/clan/inventory/machines.nix`: ten machines, NixOS and nix-darwin, meshed over ZeroTier, with `magnetite` the always-on Hetzner `cx53` VPS already running Kanidm, matrix-synapse with LiveKit and coturn, Gitea, gitea-actions-runner, docker, nixbot, gitea-mq, niks3, the Omnigent server and two omnigent-host workers, omnigraph, nix-grpc-daemon, nginx and PostgreSQL.
  buildbot is disabled behind `vanixiets.buildbot.enable`, which defaults to false, and runs no unit on `magnetite`, although its module, generated vars and PostgreSQL database are retained (`cameronraysmith/vanixiets@109c67346:modules/nixos/buildbot.nix:17-20`, `:36-38`).
  Corrected in v4 after `research/fleet-emitter-inventory.md` (refresh R2, R4, R10, R11 and its charter reconciliation); v1 listed buildbot as running and omitted the services added since.
- W2 `magnetite` has no headroom guarantee; an observability store co-located there competes with services already recorded as saturating its resources under `docs/notes/development/incidents/`.
  The incident corpus now records two resource classes: storage exhaustion in the 2026-06-10 events and the 2026-09-02 audit, and whole-host memory exhaustion on 2026-09-27 and 2026-10-01, when nixbot's evaluation overlapped a second `nix-eval-jobs` evaluation until RAM and zram were both full (`cameronraysmith/vanixiets@109c67346:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:5-6`).
  Corrected in v4 after `research/fleet-emitter-inventory.md` (refresh R16).
- W3 No observability module, collector, store, or dashboard exists in `modules/` today, and nothing is collected.
  Emission is not zero, however: `research/fleet-emitter-inventory.md` establishes that gitea, nixbot and niks3 each already expose an unauthenticated Prometheus `/metrics` endpoint, which their vhosts served over public TLS until 2026-10-15.
  Corrected in v2; v1 stated the stronger and false claim that no exporter exists.
  Since #3447, merged 2026-10-15, those three vhosts serve `/metrics` only to loopback and the ZeroTier mesh range (`cameronraysmith/vanixiets@02432c594:modules/lib/nginx-metrics-location.nix`).
  Two further emitters are live without any repository change: zerotierone's bearer-token-authenticated `localhost:9993/metrics` on every NixOS machine, and nginx's `stub_status` at `127.0.0.1/nginx_status` on `magnetite`.
  omp is a native OpenTelemetry emitter of traces, metrics and logs whenever an `OTEL_EXPORTER_OTLP_*ENDPOINT` variable is set, and this repository sets none.
  Corrected in v4 after `research/fleet-emitter-inventory.md` (refresh R13, R14, C6) and `research/dev-loop-signals.md` (refresh RF11); the loopback-and-ZeroTier restriction postdates both refreshes and is cited to #3447 directly.
- W4 `perses` is packaged in nixpkgs at version 0.54.0 against this repository's root `nixpkgs` input, together with a `services.perses` NixOS module (`NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/perses.nix`).
  `flake.lock` holds six distinct nixpkgs tarball nodes, none a git checkout, and citations must name which.
  The root input `nixpkgs` resolves to the node `nixpkgs_10` at rev `ac1faec44836a722f7b003834f367486ff9adfd1` (`releases.nixos.org/.../nixos-26.11pre1086968.ac1faec44836`).
  The root inputs `nixpkgs-darwin-stable` and `nixpkgs-linux-stable` are nodes of the same names, at revs `240fddad86d7a0520319f21d8be1b43db426b18d` and `7993f34ee47e28a3d607a525aadc6c94b73be728`.
  The remaining three nodes each serve one other input: the node named `nixpkgs`, at rev `b6c8664de9b6cc07fe5666a29f91884ba81197c4`, only `catppuccin`; `nixpkgs_2`, at rev `8edc0c72e3a38faf5434e40d1f19431125fe4b30`, `clan-core`; and `nixpkgs_3`, at rev `7bd229cbe77d7746d64a1e8c1a6f6cc08f606fc4`, `cognee-nix`.
  Clarified in v2 by triangulating `research/store-alternatives.md` FL1 against `research/nix-packaging-status.md`: both revisions are real, v1 named only one, and neither node is a git checkout.
  Corrected in v4 after `research/perses.md` (refresh R11, R13) and `research/nix-packaging-status.md` (refresh R1, R13); the rev of the node named `nixpkgs` is read from `flake.lock` directly, because no refresh restates it.
  Corrected in v5 after reading `flake.lock` directly: v2 and v4 counted two tarball nodes and described the node named `nixpkgs` as what other inputs resolve to, whereas `flake.lock` holds six and only `catppuccin` resolves to that node.
- W5 `greptimedb` is present at the root pin as version 1.1.4 (`NixOS/nixpkgs@ac1faec4:pkgs/by-name/gr/greptimedb/package.nix:15`), substituted from cache.nixos.org on both `x86_64-linux` and `aarch64-darwin`.
  The nixpkgs derivation builds without the `servers/dashboard` Cargo feature, so it ships no embedded web dashboard, whereas upstream release tarballs embed one (`NixOS/nixpkgs@cbffcb10:pkgs/by-name/gr/greptimedb/package.nix:66`; `GreptimeTeam/greptimedb@179ff8e50:.github/workflows/release.yml:236`).
  Upstream's latest stable release is v1.2.1 of 2026-09-16, and an automated nixpkgs bump to 1.2.1 is open as https://github.com/NixOS/nixpkgs/pull/574558 (fetched 2026-10-15).
  The consequence recorded in v1 — that a first-party derivation is required — is wrong, and no NixOS module exists in any nixpkgs revision either way.
  Corrected in v2 after `research/nix-packaging-status.md`.
  Corrected in v4 after `research/nix-packaging-status.md` (refresh R2, R4, R6, R8, R9, R15); v2 placed the attribute on nixpkgs `master` only, 26 days after a pin that the bump to `nixpkgs_10` has since overtaken.
  Corrected in v6: https://github.com/NixOS/nixpkgs/pull/574558 merged on 2026-10-15, so 1.2.1 reaches the root pin with the next channel update and ADR-001 deploys 1.2.1 rather than 1.1.4.
- W6 `opentelemetry-collector-contrib` 0.155.0, `vector` 0.59.0 and `grafana-alloy` 1.17.1 are available from the root nixpkgs node `nixpkgs_10`.
  The bare `alloy` attribute at 5.1.0 is the AlloyTools relational modeling language, not Grafana Alloy, and is not a telemetry agent; `services.alloy.package` defaults to `grafana-alloy`.
  Corrected in v2 after `research/otel-collector-topology.md` established the mistake in v1.
  Upstream is ahead for two of the three: collector-contrib is at v0.163.0 (2026-10-14) and Grafana Alloy at v1.20.1 (2026-09-28), while vector's latest release is the packaged 0.59.0.
  Corrected in v4 after `research/otel-collector-topology.md` (refresh R2, R3, C2); v1 and v2 recorded vector as 0.57.0.
- W7 GreptimeDB ships both `LICENSE` and `LICENSE-ENTERPRISE`; enterprise files are gated behind the `enterprise` Cargo feature, which is not in the default feature set, so published binaries are the open build.
  The gated set is enumerated in `licenserc-enterprise.toml` and covers in-database trigger DDL, undrop/recycle-bin retention, the `purge_table` admin function, and a mito2 scan-extension hook; nothing else in D1–D8 depends on those.
  Corrected in v2 after `research/greptimedb.md` settled the boundary that v1 recorded as unverified.
  The open/enterprise boundary now touches D8 through partitioned authorization: upstream advertises per-database and per-table authorization only for GreptimeDB Enterprise, through `greptime_ee_user_provider`, which ships in a separate Enterprise binary rather than behind the open repository's `enterprise` Cargo feature (https://docs.greptime.com/enterprise/user, fetched 2026-10-15).
  On `main` after v1.2.1, tracked flow writes, a retry-safe write protocol between flownode, frontend and datanode, moved into the `enterprise` feature set; ordinary Flow remains open and the change is in no tagged release (`GreptimeTeam/greptimedb@c3469fad5`).
  Corrected in v4 after `research/telemetry-security-and-tenancy.md` (refresh R3, R4) and `research/greptimedb.md` (refresh R37, R38).
- W8 `preferences-data-modeling` establishes Arrow, Parquet, DuckDB and DuckLake as this repository's analytics substrate, and does not currently mention FDAP or DataFusion.
- W9 Agent sessions are a telemetry subject: traces and logs from omnigent workers and local harnesses can carry prompt content and repository contents.

## Requirements (optative)

- R1 The design names one store, one query surface, one dashboard layer, one collection topology, one packaging strategy, one host placement, and one access model, each with a rationale paragraph and each rejected alternative in one line.
- R2 The design states which signals the development loop emits and how each closes onto a coverage-model decision, not merely onto a chart.
- R3 The design lists every vanixiets file to add or modify, every flake input to add, and every clan vars generator or sops entry to create, without implementing any of them.
- R4 Every claim about a candidate or reference is traceable to a pinned revision and path.
- R5 Every proposed artifact carries a declared operating envelope and a named regulator, per CCV; an artifact without a regulator is an incomplete deliverable.
- R6 The design is legible and operable by one person under ordinary load; ceremony that does not pay for itself in a named failure it prevents is rejected (see C1).
- R7 Open questions requiring a human decision are listed explicitly rather than resolved by inference.

## Specification (shared phenomena)

- S1 Deliverables live under `docs/notes/development/observability/` as `charter.md` (this file), `README.md` as the documentation map, `architecture/reference-architecture.md`, `components/<component>.md`, `decisions/ADR-NNN-<slug>.md` one decision per file, and `research/<source-slug>.md` one artifact per source.
  Clarified in v8: `architecture/reference-architecture.md` and `components/<component>.md` do not exist yet and remain pending deliverables, so A1 is not satisfied.
- S2 The CCV half lives under `docs/notes/development/continuous-verification/` and is authored after the store and topology decisions land.
- S3 Every factual claim about a reference cites `owner/repo@<short-rev>:<path>` and, where a line matters, `:<line>`; published documentation may be cited by URL followed by `(fetched YYYY-MM-DD)`.
- S4 Prose is one sentence per line, declarative, without marketing language; designation-table terms are used with the meanings given there.
- S5 No committed text contains a machine-local path, a session URL, a token, or an attachment link.

## Designations

| Term | Meaning in this work |
|---|---|
| FDAP stack | The Flight / DataFusion / Arrow / Parquet lineage of open columnar telemetry and analytics engines, as distinct from bespoke storage engines. |
| Store | The system that durably holds telemetry and answers queries over it. |
| Collector | The process that receives, processes and routes telemetry from emitters to the store. |
| Emitter | Any process producing telemetry: a fleet service, a build, a check, or an agent session. |
| Dashboard layer | The system rendering queries for humans, including its as-code definition format. |
| Dev-loop telemetry | Telemetry whose subject is our own development activity: check outcomes, closure timings, cache behavior, deploy outcomes, agent-session results. |
| Operating envelope | Per CCV, the declared conditions under which an artifact is committed to behaving correctly, as a first-class artifact. |
| Regulator | Per CCV, an automated process that samples an artifact's behavior against its envelope. |
| Closure operator | `nix flake check` against pinned inputs. |
| Coverage-model update | A change to a declared envelope or bin set caused by a runtime observation. |

## Constraints and posture

- C1 Anti-ceremony is a first-class constraint: prefer the smallest apparatus that closes the loop, and reject any layer, schema, or process step that cannot name the failure it prevents.
- C2 GreptimeDB plus Perses is the leading candidate stack, evaluated rather than assumed, on the stated grounds of OpenTelemetry-forward design and FDAP-stack fit.
- C3 Governance and sponsor control are explicit evaluation axes: SigNoz and OpenObserve are disfavored for corporate control of the project, and the Prometheus/Grafana/Loki/promtail assembly is disfavored as the legacy shape, but each must still be weighed on evidence rather than dismissed by assertion.
- C4 Planning only: no deploys, no `clan` mutation commands, no secret generation.
- C5 [retired in v5] No edits to files the in-flight `omnigent-magnetite` chain owns; new files under the two new `docs/notes/development/` trees are the safe lane.
  Retired in v5: the chain merged to `main` (`cameronraysmith/vanixiets@a12b3c6c5`, `cameronraysmith/vanixiets@2931154b1`), so no file is owned by an in-flight chain.
- C6 Package ownership follows repository convention: `pkgs/by-name/<name>/`, with a `-bin` proxy derivation only where upstream ships reliable release artifacts.

## Decisions to be made

- D1 Store: GreptimeDB versus alternatives, including the open/enterprise boundary and single-node versus clustered.
- D2 Dashboard layer: Perses and its dashboards-as-code format, versus alternatives, including datasource reachability against the chosen store.
- D3 Collection topology: per-host agent versus central gateway, what a nix-darwin host can run, ZeroTier-only versus public ingress, and transport authentication.
- D4 Signal scope and schema: which signals exist, semantic-convention adherence, and an explicit cardinality and retention budget per consumer.
- D5 Dev-loop instrumentation: what the development loop emits, and for each signal the coverage-model decision it feeds.
- D6 Storage substrate and lakehouse seam: whether telemetry lands as Parquet reachable by the repository's existing DuckDB/DuckLake analytics path, or in a separate silo.
  Clarified in v8: R2 storage follows web-verification D9 (`docs/notes/development/web-verification/decisions.md:77-104`), using the existing bucket `sciexp` under the prefixes `projects/vanixiets/observability/store/` and `projects/vanixiets/observability/export/`, with no new bucket and no second lifecycle resource (ADR-006).
- D7 Packaging, host placement, and clan service shape.
- D8 Access control and tenancy, including the prompt-content hazard in W9 and the relationship to the omnigent worker-isolation boundary.
- D9 Alerting: how fleet conditions become human notifications, including watching the store itself; added in v7.

## Acceptance criteria and regulators

| Criterion | Regulator | Kind |
|---|---|---|
| A1 Deliverable structure matches S1 | file-existence check over the named paths | deterministic |
| A2 Every `owner/repo@rev:path` citation resolves | per-citation `git cat-file -e` in the referenced checkout; for every nixpkgs tarball node of W4, none of which has a git checkout, resolution is by `nix eval` against the named node instead, and the citation must name the node; corrected in v5 from "the two tarball nixpkgs nodes of W4" | deterministic |
| A3 One sentence per line (S4) | grep for `[a-z]\. [A-Z]` outside tables and fences prints nothing | deterministic, approximate |
| A4 No machine-local paths, tokens or session links (S5) | grep for `(^\|[[:space:]"'(=])/(Users\|home)/`, `ghp_`, `/attachments/` prints nothing; the leading-delimiter class is required so that in-repo citation paths such as `modules/home/...` do not false-positive | deterministic |
| A5 Each decision D1–D9 has a rationale and every rejected alternative (R1); extended in v7 from D1–D8 | review plus human gate | recorded human judgment |
| A6 Each proposed artifact names an envelope and a regulator (R5) | review plus human gate | recorded human judgment |
| A7 [vacuous as written; see v3] Formatting | `nix fmt -- --ci` exits 0, but `modules/formatting.nix:13` enables `nixfmt` alone, so treefmt traverses this corpus and emits zero of its files for processing: the regulator passes without sampling anything | vacuous, pending rebinding |
| A7a Markdown well-formedness | until a markdown formatter is added to the treefmt set, A1, A3 and A4 are the only deterministic regulators that actually bind on this corpus, and A7 must not be cited as formatting evidence | deterministic, by substitution |
| A8 Anti-ceremony (C1, R6) | for each proposed layer, the document names the failure it prevents; human gate rejects any that cannot | recorded human judgment |

## Risks

- RK1 [retired in v2] GreptimeDB's open/enterprise split withholds a capability the design depends on.
  `research/greptimedb.md` established that the `enterprise` Cargo feature is absent from the default feature set, that published binaries are the open build, and that the gated set does not intersect D1–D8.
  Reopens only if the design comes to depend on in-database trigger DDL, undrop/recycle-bin retention, `purge_table`, or the mito2 scan-extension hook.
- RK2 [retired in v2] Perses cannot query the chosen store without a plugin we would have to write and maintain.
  `research/perses.md` established that a stock `PrometheusDatasource` reaches GreptimeDB's PromQL router at `/v1/prometheus` with every required `/api/v1/*` path registered, at the packaged 0.53.1.
  Superseded by RK7, which is the constraint that actually binds.
  Corrected in v5: the packaged version at the root pin is now 0.54.0 (W4); this retirement rests on the reading at 0.53.1.
- RK3 [fired in v4 for memory] `magnetite` lacks headroom for a telemetry store alongside its current services (W2).
  Confirming observation: the incident notes record saturation on the same resources the store requires.
  `research/fleet-emitter-inventory.md` refresh R16 established that the observation is satisfied for memory: the 2026-10-01 note records RAM and zram both exhausted, and on 2026-09-27 the kernel OOM killer took roughly 47 processes across services before it reached an evaluator.
  No `MemoryLow` floor protects any service today, so a co-located store process would be an ordinary OOM candidate alongside PostgreSQL and kanidm.
  Corrected in v4 after `research/fleet-emitter-inventory.md` (refresh R16 and its RK3 reconciliation).
- RK4 Dev-loop telemetry proves to need a different store than fleet telemetry, splitting D1.
  Confirming observation: the cardinality or retention budget in D4 is unsatisfiable by one system under C1.
- RK5 [fired in v2] Agent-session telemetry leaks prompt or repository content into a fleet-readable store (W9).
  `research/telemetry-security-and-tenancy.md` established that the confirming observation is already satisfied by the default emitter schema, because the `api_error.error` field is free-form and ungated.
  This is therefore a design obligation rather than a risk: D4 and D8 must specify collector-side redaction with an enumerated allow-list, since every emitter-side gate is an environment variable the collector cannot rely on.
- RK6 [retired in v2] GreptimeDB being absent from nixpkgs makes us the maintainer of a large Rust derivation.
  `research/nix-packaging-status.md` established that upstream ships checksummed linux-amd64/arm64 and darwin-arm64/amd64 release tarballs across the last six releases and that nixpkgs `master` already carries a from-source derivation.
  Residual risk, narrowed: the root pin predates that derivation by 26 days, and no NixOS module exists in any nixpkgs revision, so the module is ours to write regardless.
  Corrected in v5: W5 (v4) places greptimedb 1.1.4 in the root pin, so the 26-day gap no longer applies, and the only residual risk is that the NixOS module is ours to write.
- RK7 [resolved in v4] The store holds all three signals but the dashboard layer can only render one of them.
  `research/perses.md` refresh R3, R5 and R12 established that the stable Perses 0.54.0 default plugin set, and the nixpkgs vendored set at `nixpkgs_10`, contain the GreptimeDB plugin 0.1.0 with `GreptimeDBLogQuery` and `GreptimeDBTraceQuery`, whose generic `LogQuery` and `TraceQuery` kinds the stock log and trace panels render.
  Confirming observation, retained: a D2 design that promises trace or log dashboards over a GreptimeDB-only store without naming the plugin and version that serves them.
  Residual risk: the trace query maps result columns by name (refresh R8), and log and trace rendering has not been exercised against a live GreptimeDB.
  Corrected in v4 after `research/perses.md` (refresh R3, C1); v2 recorded the GreptimeDB plugin as first entering the default set at 0.55.0-beta.0.
- RK8 [narrowed in v4] A regulator built on `percli lint` is tautologically green.
  `research/perses.md` established that without `--plugin.path` and without `--online`, `percli lint` validates nothing beyond unmarshalling, skips custom lint rules, and still reports success.
  This is a direct CCV integrity failure of exactly the kind the closure operator is supposed to exclude, so any dashboard regulator must be demonstrated to fail on a mutant before it is accepted.
  `research/perses.md` refresh R17 and R18 reconfirmed this at 0.54.0 for bare lint and for `--custom-rule.path` alone, and refresh R21, R22 and R24 showed that lint with `--plugin.path` pointing at a directory of extracted plugins, or `--online` against a server with the plugin archives loaded, rejects schema and custom-rule mutants.
  `--plugin.path` pointing at the directory of plugin archives fails every input, valid or not, and is equally non-discriminating (refresh R19, R20).
  Corrected in v4 after `research/perses.md` (refresh R21, R24).
- RK9 [strengthened in v4] The store authenticates but does not authorize.
  `research/telemetry-security-and-tenancy.md` established that GreptimeDB's open-build user providers implement `authorize` as allow-all, that the only lever is a per-user `rw`/`ro`/`wo` mode, and that the table-target `PermissionChecker` trait has no in-tree implementation.
  Consequence for D8: per-person read partitioning cannot be enforced by the store, and Perses project RBAC gating its datasource proxy cannot enforce it either, because a project reader can send arbitrary SQL under the datasource's stored credential.
  Reversal is unlikely rather than pending: upstream advertises per-database and per-table authorization only for GreptimeDB Enterprise, whose user provider is absent from the open repository.
  Corrected in v4 after `research/telemetry-security-and-tenancy.md` (refresh R1–R4, C2) and `research/perses.md` (refresh R27–R29, C8); v2 assigned per-person read partitioning to Perses project RBAC.

## Rule

Raise an open question instead of guessing.
A research unit that meets ambiguity returns it in its questions section; the orchestrator carries it to the human gate.

## Revision history

- v1 (2026-09-18): initial charter.
  Scope fixed to both fleet and dev-loop telemetry with dev-loop primary.
  GreptimeDB plus Perses fixed as the leading evaluated candidate stack.
  The `nix-mpe-signoz-module` seed and ironstar's SigNoz work recorded as superseded inputs.
  Anti-ceremony recorded as constraint C1.
- v2 (2026-09-18): revision after the eight research units landed; the body corrections below are the only edits to earlier text.
  - W3 corrected: emission is not zero, because gitea, nixbot and niks3 already expose unauthenticated public Prometheus endpoints.
  - W4 clarified: `flake.lock` holds two nixpkgs tarball nodes, neither a git checkout, and citations must name the node.
  - W5 corrected: greptimedb exists in nixpkgs `master` 26 days after the root pin, so a first-party derivation is not required.
  - W6 corrected: the telemetry agent is `grafana-alloy` 1.17.1; the bare `alloy` attribute is an unrelated formal-methods language.
  - W7 corrected: the enterprise boundary is settled and does not intersect D1–D8.
  - A2 extended to cover tarball nixpkgs nodes by evaluation rather than `git cat-file`.
  - A4 anchored with a leading-delimiter class so in-repo `modules/home/` citations do not false-positive.
  - RK1, RK2 and RK6 retired with evidence; RK5 recorded as fired and converted into a D4/D8 obligation; RK7, RK8 and RK9 added.
- v3 (2026-09-18): integrity correction to this charter's own regulator suite, found by running it.
  A7 is recorded as vacuous: `nix fmt -- --ci` exits 0 over this corpus while emitting zero of its ten files for processing, because `modules/formatting.nix:13` enables `nixfmt` alone and no markdown formatter exists in the treefmt set.
  A vacuous regulator is precisely what CCV's integrity property exists to exclude, so A7 is marked rather than counted, and A7a records that A1, A3 and A4 are the only deterministic regulators binding on this corpus.
  Rebinding A7 requires adding a markdown formatter to `modules/formatting.nix`, which is outside this work's safe lane under C5 and is therefore deferred to the same window as the other `modules/` follow-ups.
  `modules/lib/md-format.nix` was considered and rejected as the binding: it is a submodule type that generates markdown with YAML frontmatter for `modules/home/modules/agents-md.nix`, not a linter, and has no path over `docs/notes/`.
- v4 (2026-10-15): revision after the eight research units gained `## Refresh (2026-10-15)` sections; the body corrections below are the only edits to earlier text, and D1–D8, the requirements and the acceptance criteria are unchanged.
  - W1 corrected: `magnetite` now runs nixbot, gitea-mq, the Omnigent server, omnigraph and nix-grpc-daemon among others, and buildbot is disabled behind `vanixiets.buildbot.enable` rather than running.
  - W2 corrected: the incident corpus records whole-host memory exhaustion on 2026-09-27 and 2026-10-01 in addition to storage exhaustion.
  - W3 corrected: zerotierone and nginx `stub_status` already emit on loopback, omp is a native OpenTelemetry emitter, and #3447 restricted the three `/metrics` endpoints to loopback and ZeroTier on 2026-10-15.
  - W4 corrected: the root nixpkgs node is now `nixpkgs_10` at `ac1faec4`, which packages perses 0.54.0 with a `services.perses` NixOS module; the node named `nixpkgs` moved to `b6c8664d`.
  - W5 corrected: greptimedb 1.1.4 is in the root pin, the nixpkgs build omits the embedded dashboard, and upstream's latest stable release is v1.2.1.
  - W6 corrected: at the new pin the versions are otel-collector-contrib 0.155.0, vector 0.59.0 and grafana-alloy 1.17.1, with upstream ahead for contrib and Alloy.
  - W7 corrected: the enterprise boundary now touches D8 through partitioned authorization, and tracked flow writes moved to the enterprise set on `main` after v1.2.1.
  - RK3 recorded as fired for memory.
  - RK7 resolved: the GreptimeDB plugin 0.1.0 with log and trace query plugins is in Perses 0.54.0's default set and in the nixpkgs vendored set.
  - RK8 narrowed: lint fails mutants when given an extracted plugin directory or `--online`, while bare lint and the archive-directory form remain non-discriminating.
  - RK9 strengthened: reversal through an open store implementation is unlikely, and Perses project RBAC cannot partition reads per person either.
- v5 (2026-10-15): consistency revision after the eight decision records were drafted at Proposed; the body corrections below are the only edits to earlier text, and D1–D8, the requirements and the acceptance criteria other than A2's scope are unchanged.
  - Frontmatter corrected: `status` and `date` had stayed at v1 values while the body reached v4.
  - Scope corrected and C5 retired: the `omnigent-magnetite` chain merged to `main` (`cameronraysmith/vanixiets@a12b3c6c5`, `cameronraysmith/vanixiets@2931154b1`), so no chain is in flight.
  - Superseded inputs annotated: the deferred abandonment of the `nix-mpe-signoz-module` seed is now dischargeable.
  - W4 corrected: `flake.lock` holds six nixpkgs tarball nodes, the root input resolves to `nixpkgs_10`, and the node named `nixpkgs` is consumed only by `catppuccin`.
  - A2 corrected: `nix eval` resolution applies to every nixpkgs tarball node of W4, not to two.
  - RK2 annotated: the packaged Perses version is now 0.54.0.
  - RK6 annotated: the residual risk is only that the GreptimeDB NixOS module is ours to write.
- v6 (2026-10-15): the body correction below is the only edit to earlier text.
  - W5 corrected: the nixpkgs bump to GreptimeDB 1.2.1 (https://github.com/NixOS/nixpkgs/pull/574558) merged on 2026-10-15; ADR-001 and ADR-007 now deploy 1.2.1 through a root-pin bump, with a `greptimedb-bin` fallback only for a channel delay at implementation time.
- v7 (2026-10-15): extension after the human approved host-level signals and an alerting decision; the body corrections below are the only edits to earlier text, and D1–D8 and the requirements are unchanged.
  - D9 added: alerting, because ADR-001 placed alerting outside the store and no decision record chose it, so per-process memory growth, systemd restart loops and storage degradation are visible today only to someone watching a dashboard.
  - A5 extended from D1–D8 to D1–D9.
  - The host-level signal additions (per-process metrics, systemd unit state and restart counts, ZFS and disk health) fall under D3 and D4 and are recorded in ADR-003 and ADR-004 rather than as new decisions.
- v8 (2026-10-15): convention reconciliation after an audit of the decision records against conventions already decided elsewhere in the repository; the body clarifications below are the only edits to earlier text, and D1–D9, the requirements and the acceptance criteria are unchanged.
  - Scope clarified: implementation proceeds through OpenSpec changes following the `openspec/changes/stand-up-*` precedent, so the decision records feed a proposal, design and task list rather than being implemented directly.
  - S1 clarified: `architecture/` and `components/` remain pending deliverables, and A1 is not yet satisfied.
  - D6 clarified: R2 storage follows web-verification D9, a single adopted `sciexp` bucket with `projects/vanixiets/observability/{store,export}/` prefixes, replacing the separate buckets ADR-006 first proposed.
- v9 (2026-10-15): record of the human gate; no earlier text is edited beyond the status and version lines, and D1–D9, the requirements and the acceptance criteria are unchanged.
  - The human gate accepted the recommended answer of every question in ADR-001 to ADR-009, with exactly one exception, and each decision record now reads Accepted with a per-question resolution, ADR-009 with that exception noted.
  - ADR-002 Q6 is answered as `perses.scientistexperience.net` behind Kanidm, and ADR-003 Q15 as SMART on pyrite and stibnite.
  - ADR-009 Q5, whether an external dead-man service watches cinnabar itself, is deferred to the end of implementation; the candidate is an external heartbeat from a free uptime service, weighed against the third-party dependency.
  - A5, A6 and A8 are discharged as recorded human judgment on 2026-10-15.
  - Consistency corrections with no new decision, aligning the decision records to ADR-009, the later and more specific record, and to the accepted ADR-007 Q6:
    - `regulator:ro` holders are `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope` and `fleet-alert.service`, which ADR-009 has load `regulator-password`; ADR-007 and ADR-008 now list `fleet-alert.service`.
    - `admin:rw` holders are the `greptimedb-schema` and `greptimedb-export` oneshots only, per ADR-007; ADR-008's list no longer names the envelope oneshot, which uses `regulator`.
    - The `observability-notify@` template moves from the `ingress` role to the `agent` role of ADR-003, so every in-scope NixOS host has it, cinnabar included, because ADR-009's `fleet-deadman` on cinnabar notifies through it; it calls the existing `ntfy-send` against `ntfy.zt`, ADR-003's `OnFailure=` list adds `fleet-alert.service` and `fleet-deadman.service`, and ADR-009's file list names the `agent` role.
    - Restart-on-rotation stays after GreptimeDB 1.3, per ADR-007 Q6, because `LoadCredential` snapshots credentials at start; ADR-001 and ADR-008 now say so, and only the collector's histogram conversion is removed at 1.3.
