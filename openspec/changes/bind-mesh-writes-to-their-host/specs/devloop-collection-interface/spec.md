## MODIFIED Requirements

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
- **THEN** the answer is yes for a row written over the mesh, as far as the `fleet-ingress-interface` requirement `A mesh write is stored only under the host that sent it` reaches: the ingress stores a record only when its `host` names the host whose certificate and overlay address carried it; it is no for magnetite's own rows, which reach `devloop` through the in-process `forward` connector, and for a row root on the sending host writes into that host's deploy-record file, which names that host

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given event reaches the store
- **THEN** the answer is no: each stage's configuration, the gating checks, the container tests and the daily reconcile behave as stated, and nothing here observes every event's whole path
