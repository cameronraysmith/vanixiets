## RENAMED Requirements

- FROM: `### Requirement: magnetite's collector ships its own deploy records`
- TO: `### Requirement: Each agent host's collector ships its own deploy records`

## MODIFIED Requirements

### Requirement: Each agent host's collector ships its own deploy records

Each agent host's collector SHALL read `/var/log/deploy-record.jsonl` through `file_log/deploy-record`, defined in the agent role, with `start_at: beginning`, `storage: file_storage` and `json_parser`, keeping `host`, `closure`, `previous_closure` and `ts`, under the receiver id and settings magnetite used before, so magnetite's stored offset carries over.

**Discharged by**: `devloop-reconcile`'s comparison of deploy records on magnetite; `vmTests.x86_64-linux.devloop-ingest`'s first-start case; `vmTests.x86_64-linux.fleet-ingress`'s delivery case; the operator's line-count comparison at each agent host's first deploy.

#### Scenario: The receiver reads another file

- **WHEN** `devloop-ingest`'s mutant points `file_log/deploy-record` at another path
- **THEN** `devloop-reconcile` exits non-zero on the deploy-record count

#### Scenario: An agent host without the ingress role ships its records

- **WHEN** `fleet-ingress`'s agent writes three deploy-record lines
- **THEN** three `deploy_record` rows naming that agent's host arrive in `devloop` through `otlp_http/ingress-logs` and `otlp/mesh`

#### Scenario: magnetite's receiver moves into the agent role

- **WHEN** magnetite is first deployed with the receiver defined in the agent role
- **THEN** magnetite's `deploy_record` row count equals its file's line count, and no line is shipped a second time

#### Scenario: Each agent host is first deployed

- **WHEN** cinnabar and pyrite are first deployed with the agent role
- **THEN** the operator records, for each, the line count of its `/var/log/deploy-record.jsonl` and its `deploy_record` row count, and a difference is a finding

### Requirement: Dev-loop sources are stamped and routed to their table

Each dev-loop receiver SHALL feed its own `logs/devloop-<table>` pipeline through `memory_limiter` and a `resource/devloop-<table>` processor that sets `vanixiets.database` to `devloop`, `vanixiets.table` to its table and `host.name`, ending in `forward` on the ingress host and in `otlp_http/ingress-logs` elsewhere, and no `logs/*` pipeline SHALL take an OTLP receiver other than `otlp/mesh`.

**Discharged by**: the R3.1 collector check's clause that no logs pipeline takes an OTLP receiver other than `otlp/mesh`, with its mutant; `vmTests.x86_64-linux.devloop-ingest`'s first-start case and `vmTests.x86_64-linux.fleet-ingress`'s delivery case, in which each table receives its rows.

#### Scenario: The local receiver is added to a logs pipeline

- **WHEN** a mutant of magnetite's collector configuration adds a local OTLP receiver to `logs/devloop-ci_build`
- **THEN** the evaluation-time collector check (R3.1) fails

#### Scenario: Another host's deploy records reach the logs route

- **WHEN** an agent host without the ingress role is evaluated
- **THEN** its `logs/devloop-deploy_record` pipeline ends in `otlp_http/ingress-logs`, and on magnetite `logs/ingress` receives from both `forward` and `otlp/mesh` into the unchanged `routing/logs`

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a dev-loop event reaches the store.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the queries, the journal parse and the deploy snippet select, parse and write the stated fields; that the tables, pipelines and routes carry them into `devloop` keyed as stated; that the readers authenticate by peer under column grants; and that the reconcile compares each signal with its source daily, each as far as its check, container test or recorded observation reaches

#### Scenario: A guarantee about the sources is sought

- **WHEN** someone asks whether an event nixbot or gitea-mq never records is detected
- **THEN** the answer is no: nixbot and gitea-mq produce the source rows and lines, this machine only reads them, and their schema and messages are trusted at the pinned revisions

#### Scenario: A guarantee about secrecy is sought

- **WHEN** someone asks whether only the reconcile can read the `regulator` password or the deploy-record file
- **THEN** the answer is no: any root process on magnetite can read both, and the deploy-record file is world-readable on every host

#### Scenario: A guarantee about other hosts is sought

- **WHEN** someone asks whether deploys on hosts other than magnetite reach `devloop` and are reconciled
- **THEN** the answer is no for reconciliation: every NixOS agent host ships its records through the ingress, but `devloop-reconcile` compares magnetite's alone, the darwin machines ship none until they run collectors of their own, and the snippets are held by the build-time check only on the five x86_64-linux NixOS machines

#### Scenario: A guarantee about a record's host is sought

- **WHEN** someone asks whether a `deploy_record` row's `host` proves which host sent it
- **THEN** the answer is no: any holder of an `otel-ca` certificate can send a row naming any host

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given event reaches the store
- **THEN** the answer is no: each stage's configuration, the gating checks, the container tests and the daily reconcile behave as stated, and nothing here observes every event's whole path
