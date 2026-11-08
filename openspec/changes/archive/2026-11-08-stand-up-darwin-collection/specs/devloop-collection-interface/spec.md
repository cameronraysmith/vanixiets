## MODIFIED Requirements

### Requirement: Each agent host's collector ships its own deploy records

Each agent host's collector SHALL read `/var/log/deploy-record.jsonl` through `file_log/deploy-record`, defined in the agent role for NixOS hosts and in `flake.lib.otelCollectorDarwin`'s agent configuration for darwin hosts, with `start_at: beginning`, `storage: file_storage` and `json_parser`, keeping `host`, `closure`, `previous_closure` and `ts`, under the receiver id and settings magnetite used before, so magnetite's stored offset carries over.

**Discharged by**: `devloop-reconcile`'s comparison of deploy records on magnetite; `vmTests.x86_64-linux.devloop-ingest`'s first-start case; `vmTests.x86_64-linux.fleet-ingress`'s delivery case; `checks.x86_64-linux.otel-collector-darwin`'s `otelcol-contrib validate` case over the rendered darwin agent configuration; the operator's line-count comparison at each agent host's first deploy or activation.

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

#### Scenario: The darwin agent configuration is rendered

- **WHEN** `flake.lib.otelCollectorDarwin`'s agent configuration is evaluated
- **THEN** its `logs/devloop-deploy_record` pipeline takes `file_log/deploy-record` through `resource/devloop-deploy_record` with the deploy-record keep-list rendered from the devloop allow-list and ends in `otlp_http/ingress-logs`, and `otel-collector-darwin` validates the configuration with the root pin's `otelcol-contrib`

#### Scenario: stibnite is first activated with the agent

- **WHEN** stibnite is first activated with its collector after its `collect` is set
- **THEN** the operator records the line count of stibnite's `/var/log/deploy-record.jsonl`, which `flake.modules.darwin.deploy-record` has appended to since before stibnite had a collector, and stibnite's `deploy_record` row count, and a difference is a finding

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
- **THEN** the answer is no for reconciliation: every NixOS agent host and stibnite ship their records through the ingress, but `devloop-reconcile` compares magnetite's alone, stibnite's are compared only by the operator at its first activation, the darwin machines without a collector ship none until they run collectors of their own, and the snippets are held by the build-time check only on the five x86_64-linux NixOS machines

#### Scenario: A guarantee about a sleeping host's records is sought

- **WHEN** someone asks whether a deploy record stibnite writes reaches `devloop` while stibnite sleeps or is off the mesh
- **THEN** the answer is no: stibnite's collector sends nothing while it sleeps or cannot reach the ingress, and its records arrive only after it is awake and reaches the ingress again

#### Scenario: A guarantee about a record's host is sought

- **WHEN** someone asks whether a `deploy_record` row's `host` proves which host sent it
- **THEN** the answer is no: any holder of an `otel-ca` certificate can send a row naming any host

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given event reaches the store
- **THEN** the answer is no: each stage's configuration, the gating checks, the container tests and the daily reconcile behave as stated, and nothing here observes every event's whole path
