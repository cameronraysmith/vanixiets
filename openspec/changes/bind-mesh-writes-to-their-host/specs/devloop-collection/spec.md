## ADDED Requirements

### Requirement: A deploy record names the collected host that sent it

A deploy record a collected host other than magnetite sends SHALL enter the dev-loop history only when it names that host, so that no overlay member can record a deploy under another host's name.

**Discharged by**: `fleet-ingress-interface` requirements `A mesh write is accepted only from the host its certificate names, at that host's overlay address`, `A mesh write is stored only under the host that sent it` and `otel-envelope on the ingress host fails when the binding refuses or drops a write`; `devloop-collection-interface` requirement `This capability states its own trust boundary`; resting on world assumptions `A71 — ZeroTier delivers a frame for a member's MAC only to that member, whose MAC derives from its node id and the network id`, `A73 — Linux never changes a permanent neighbour entry on an advertisement, and lets an overriding advertisement rewrite a non-permanent one`, `A75 — caddy 2.11.7 exposes a verified client certificate's URI SANs, replaces a forwarded header, passes an upstream status through, and counts a response status` and `A76 — The collector's filter answers success for a dropped write and counts it per processor`.

#### Scenario: A collected host sends a deploy record naming another host

- **WHEN** a deploy record naming cinnabar arrives from electrum's collector
- **THEN** the dev-loop history holds no dev-loop record for it, and the operator is told within one regulator period

#### Scenario: A collected host's own deploys keep arriving

- **WHEN** cinnabar, pyrite and stibnite deploy after the binding is in force
- **THEN** each deploy's dev-loop record names the host that deployed, and the count of each host's dev-loop records keeps equal to the count of its deploy records
