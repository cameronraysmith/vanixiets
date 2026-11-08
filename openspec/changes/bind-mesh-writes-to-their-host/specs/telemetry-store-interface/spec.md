## MODIFIED Requirements

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that a series reaches the telemetry store or that a failure reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the telemetry store and its scrape targets listen only on loopback, that four accounts with fixed modes gate every `/v1/` path, that ingest and reads use the stated paths and headers, that the databases carry their declared retention, that object data is configured under one prefix of one bucket, that credentials exist only as activation-resolved files owned by non-worker users, that the store and collector run inside the declared envelope, darwin's runtime memory clause included, that the queue is persistent and bounded, and that the named units and darwin's wrapped `otel-envelope` hand their failures to the notifier's posting code, which posts with the `alerter` token, each as far as its own check, assertion, test or recorded observation reaches

#### Scenario: A guarantee about R2 is sought from this capability

- **WHEN** someone asks whether these properties guarantee that object data is durable or that the R2 token is scoped to the store prefix
- **THEN** the answer is no: the token's scope and the bucket's durability are set and provided by Cloudflare, and this machine does not assert them

#### Scenario: A guarantee about who can reach the loopback listener is sought

- **WHEN** someone asks whether loopback binding limits access to the named consumers
- **THEN** the answer is no: any root process on magnetite can reach the loopback listener, and only the account credentials distinguish it from the named consumers

#### Scenario: A guarantee about a series' host is sought

- **WHEN** someone asks whether a series' `host_name` in the store names the host that gathered it
- **THEN** the answer is yes for a series written over the mesh, as far as the `fleet-ingress-interface` binding requirements reach, and no otherwise: any root process on magnetite can reach the loopback listener and write any `host_name`, and magnetite's own agent stamps its series through the in-process `forward` connector, which the binding does not judge

#### Scenario: A guarantee about notice delivery or publishing is sought

- **WHEN** someone asks whether these properties guarantee that a failure notice reaches a person, or that only the notifier and the alert evaluator publish to `fleet-alerts`
- **THEN** the answer is no: ntfy on cinnabar enforces that only the `alerter` token publishes to `fleet-*`, and this machine only configures it; any root process on a host holding a copy of that token can read it, magnetite, cinnabar and every other NixOS agent host, and stibnite, where the copy is owned by `_otelcol`; and cinnabar is a single delivery path that nothing here watches

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that a given series reaches the telemetry store
- **THEN** the answer is no: each stage's configuration is checked and the tested pipeline behaves as stated, and nothing here observes the whole path on magnetite end to end
