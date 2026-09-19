---
title: Fleet observability and CCV feedback-loop charter
status: charter v1
date: 2026-09-18
---

# Fleet observability and CCV feedback-loop charter

Charter version: v1.
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

Out of scope for this charter: implementation, any `clan vars` mutation, any deployment, and any change to the in-flight `omnigent-magnetite` chain.

## Superseded inputs

The `nix-mpe-signoz-module` chain is deprecated and discarded as a design input.
It seeded a consideration of SigNoz that predates the recognition that an FDAP-aligned stack fits this repository's data-stack preferences better.
Its only commit is an empty seed (`tktswmrx`), but it currently participates in the diamond joins alongside `omnigent-magnetite`; the jj-level abandonment is deferred until that chain merges, so that the other agent's join topology and gate baselines are not disturbed mid-flight.

`sciexp/ironstar`'s SigNoz work is superseded in part by this design.
Its artifacts remain readable prior art — `modules/services/signoz.nix` and `docs/notes/development/observability-migration-agent-prompt.md` — and its process-compose boundary argument is retained as evidence, not as a decision.

## World assumptions (indicative)

- W1 The fleet is the inventory in `modules/clan/inventory/machines.nix`: ten machines, NixOS and nix-darwin, meshed over ZeroTier, with `magnetite` the always-on Hetzner `cx53` VPS already running Kanidm, matrix-synapse, Gitea, buildbot, niks3, nginx and PostgreSQL.
- W2 `magnetite` has no headroom guarantee; an observability store co-located there competes with services already recorded as saturating its resources under `docs/notes/development/incidents/`.
- W3 No observability module, collector, store, or dashboard exists in `modules/` today, and nothing is collected.
  Emission is not zero, however: `research/fleet-emitter-inventory.md` establishes that gitea, nixbot and niks3 each already expose an unauthenticated Prometheus `/metrics` endpoint reachable over public TLS.
  Corrected in v2; v1 stated the stronger and false claim that no exporter exists.
- W4 `perses` is packaged in nixpkgs at version 0.53.1 against this repository's root `nixpkgs` input.
  `flake.lock` holds two distinct nixpkgs tarball nodes and citations must name which: the root input is the node `nixpkgs_9` at rev `85f62611fa3f3eacbcfe3bc7a6d6518b443ca442` (`releases.nixos.org/.../nixos-26.11pre1047825.85f62611fa3f`), while the node named `nixpkgs`, at rev `044bfe75bfe4c7bbe043dc17b5e42ea823b84a09`, is what other inputs resolve to.
  Clarified in v2 by triangulating `research/store-alternatives.md` FL1 against `research/nix-packaging-status.md`: both revisions are real, v1 named only one, and neither node is a git checkout.
- W5 `greptimedb` is absent from the root pin, but present in nixpkgs `master` as `pkgs/by-name/gr/greptimedb/package.nix`, initialized at 1.1.4 on 2026-08-30, which is 26 days after the root pin and not an ancestor of it.
  The consequence recorded in v1 — that a first-party derivation is required — is therefore wrong; bumping the pin or selecting the attribute through a second nixpkgs input are both cheaper routes, and no NixOS module exists in any nixpkgs revision either way.
  Corrected in v2 after `research/nix-packaging-status.md`.
- W6 `opentelemetry-collector-contrib` 0.155.0, `vector` 0.57.0 and `grafana-alloy` 1.17.1 are available from the pinned nixpkgs.
  The bare `alloy` attribute at 5.1.0 is the AlloyTools relational modeling language, not Grafana Alloy, and is not a telemetry agent; `services.alloy.package` defaults to `grafana-alloy`.
  Corrected in v2 after `research/otel-collector-topology.md` established the mistake in v1.
- W7 GreptimeDB ships both `LICENSE` and `LICENSE-ENTERPRISE`; enterprise files are gated behind the `enterprise` Cargo feature, which is not in the default feature set, so published binaries are the open build.
  The gated set is enumerated in `licenserc-enterprise.toml` and covers in-database trigger DDL, undrop/recycle-bin retention, the `purge_table` admin function, and a mito2 scan-extension hook; nothing else in D1–D8 depends on those.
  Corrected in v2 after `research/greptimedb.md` settled the boundary that v1 recorded as unverified.
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
- C5 No edits to files the in-flight `omnigent-magnetite` chain owns; new files under the two new `docs/notes/development/` trees are the safe lane.
- C6 Package ownership follows repository convention: `pkgs/by-name/<name>/`, with a `-bin` proxy derivation only where upstream ships reliable release artifacts.

## Decisions to be made

- D1 Store: GreptimeDB versus alternatives, including the open/enterprise boundary and single-node versus clustered.
- D2 Dashboard layer: Perses and its dashboards-as-code format, versus alternatives, including datasource reachability against the chosen store.
- D3 Collection topology: per-host agent versus central gateway, what a nix-darwin host can run, ZeroTier-only versus public ingress, and transport authentication.
- D4 Signal scope and schema: which signals exist, semantic-convention adherence, and an explicit cardinality and retention budget per consumer.
- D5 Dev-loop instrumentation: what the development loop emits, and for each signal the coverage-model decision it feeds.
- D6 Storage substrate and lakehouse seam: whether telemetry lands as Parquet reachable by the repository's existing DuckDB/DuckLake analytics path, or in a separate silo.
- D7 Packaging, host placement, and clan service shape.
- D8 Access control and tenancy, including the prompt-content hazard in W9 and the relationship to the omnigent worker-isolation boundary.

## Acceptance criteria and regulators

| Criterion | Regulator | Kind |
|---|---|---|
| A1 Deliverable structure matches S1 | file-existence check over the named paths | deterministic |
| A2 Every `owner/repo@rev:path` citation resolves | per-citation `git cat-file -e` in the referenced checkout; for the two tarball nixpkgs nodes of W4, which have no git checkout, resolution is by `nix eval` against the named node instead, and the citation must name the node | deterministic |
| A3 One sentence per line (S4) | grep for `[a-z]\. [A-Z]` outside tables and fences prints nothing | deterministic, approximate |
| A4 No machine-local paths, tokens or session links (S5) | grep for `(^\|[[:space:]"'(=])/(Users\|home)/`, `ghp_`, `/attachments/` prints nothing; the leading-delimiter class is required so that in-repo citation paths such as `modules/home/...` do not false-positive | deterministic |
| A5 Each decision D1–D8 has a rationale and every rejected alternative (R1) | review plus human gate | recorded human judgment |
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
- RK3 `magnetite` lacks headroom for a telemetry store alongside its current services (W2).
  Confirming observation: the incident notes record saturation on the same resources the store requires.
- RK4 Dev-loop telemetry proves to need a different store than fleet telemetry, splitting D1.
  Confirming observation: the cardinality or retention budget in D4 is unsatisfiable by one system under C1.
- RK5 [fired in v2] Agent-session telemetry leaks prompt or repository content into a fleet-readable store (W9).
  `research/telemetry-security-and-tenancy.md` established that the confirming observation is already satisfied by the default emitter schema, because the `api_error.error` field is free-form and ungated.
  This is therefore a design obligation rather than a risk: D4 and D8 must specify collector-side redaction with an enumerated allow-list, since every emitter-side gate is an environment variable the collector cannot rely on.
- RK6 [retired in v2] GreptimeDB being absent from nixpkgs makes us the maintainer of a large Rust derivation.
  `research/nix-packaging-status.md` established that upstream ships checksummed linux-amd64/arm64 and darwin-arm64/amd64 release tarballs across the last six releases and that nixpkgs `master` already carries a from-source derivation.
  Residual risk, narrowed: the root pin predates that derivation by 26 days, and no NixOS module exists in any nixpkgs revision, so the module is ours to write regardless.
- RK7 [new in v2] The store holds all three signals but the dashboard layer can only render one of them.
  `research/perses.md` established that Perses binds query plugins to datasource kinds, that its log and trace panels are backed only by Loki and Tempo query plugins at 0.53.1, and that the native GreptimeDB plugin is SQL-based and first enters the default plugin set at 0.55.0-beta.0.
  Confirming observation: a D2 design that promises trace or log dashboards over a GreptimeDB-only store without naming the plugin and version that serves them.
- RK8 [new in v2] A regulator built on `percli lint` is tautologically green.
  `research/perses.md` established that without `--plugin.path` and without `--online`, `percli lint` validates nothing beyond unmarshalling, skips custom lint rules, and still reports success.
  This is a direct CCV integrity failure of exactly the kind the closure operator is supposed to exclude, so any dashboard regulator must be demonstrated to fail on a mutant before it is accepted.
- RK9 [new in v2] The store authenticates but does not authorize.
  `research/telemetry-security-and-tenancy.md` established that GreptimeDB's open-build user providers implement `authorize` as allow-all, that the only lever is a per-user `rw`/`ro`/`wo` mode, and that the table-target `PermissionChecker` trait has no in-tree implementation.
  Consequence for D8: per-person read partitioning cannot be enforced by the store and must be enforced by the dashboard layer's project RBAC gating its datasource proxy.

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
