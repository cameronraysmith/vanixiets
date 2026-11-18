## RENAMED Requirements

- FROM: `### Requirement: The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`
- TO: `### Requirement: The ingress receiver accepts only certificate holders on magnetite's overlay address`

## MODIFIED Requirements

### Requirement: The ingress receiver accepts only certificate holders on magnetite's overlay address

The ingress role SHALL run `otlp/mesh`, an OTLP/HTTP receiver at `[${flake.lib.hosts.magnetite.address}]:4318` with `tls` from `otel-cert`, `client_ca_file` the `otel-ca` certificate and `min_version: "1.3"`, feeding `metrics/ingress` and `logs/ingress`, and SHALL open TCP 4318 on `flake.lib.meshInterfaces` only; it SHALL be the only collector endpoint off loopback.

**Discharged by**: R3.1's endpoint clause with its mutants; `vmTests.x86_64-linux.fleet-ingress`'s refusal case; the operator's refused request from stibnite at deploy.

#### Scenario: The endpoint is evaluated

- **WHEN** the evaluation-time collector check (R3.1) builds against magnetite's configuration
- **THEN** every receiver, exporter and scrape target endpoint is loopback except `otlp/mesh`'s, whose address equals `flake.lib.mesh.addressOf "vanixiets" "magnetite"`

#### Scenario: The endpoint is widened or moved

- **WHEN** a mutant sets `otlp/mesh`'s endpoint to `[::]:4318`, adds a second receiver on magnetite's overlay address, or gives the check an address other than magnetite's derived one
- **THEN** the evaluation-time collector check (R3.1) fails

#### Scenario: A client without a valid certificate connects

- **WHEN** `fleet-ingress` connects to the receiver without a client certificate, with a certificate from another CA, or offering at most TLS 1.2
- **THEN** each connection is refused during the handshake and no request reaches a pipeline

#### Scenario: A mesh member without a certificate connects at deploy

- **WHEN** after magnetite's deploy the operator sends an OTLP request from stibnite to `https://magnetite.vanixiets.internal:4318` without a client certificate
- **THEN** the handshake is refused, and the operator records the client's error
