## ADDED Requirements

### Requirement: A series is stored only under the host that gathered it

A series another agent host, or any other overlay member, sends to the telemetry store SHALL be kept only when it names the host whose collector gathered it, so that no overlay member can write a series under another host's name, including the series whose absence would tell the operator that an always-on host is silent.

**Discharged by**: `fleet-ingress-interface` requirements `A mesh write is accepted only from the host its certificate names, at that host's overlay address`, `A mesh write is stored only under the host that sent it`, `magnetite pins each collecting host's neighbour entry` and `otel-envelope on the ingress host fails when the binding refuses or drops a write`, resting on world assumptions `A71 — ZeroTier delivers a frame for a member's MAC only to that member, whose MAC derives from its node id and the network id`, `A72 — ZeroTier neither inspects an inbound neighbour advertisement nor ties an rfc4193 address to the member sending from it`, `A73 — Linux never changes a permanent neighbour entry on an advertisement, and lets an overriding advertisement rewrite a non-permanent one`, `A74 — The fleet's overlay network assigns rfc4193 addresses with neighbour emulation and carries only the accept-all rule`, `A75 — caddy 2.11.7 exposes a verified client certificate's URI SANs, replaces a forwarded header, passes an upstream status through, and counts a response status` and `A76 — The collector's filter answers success for a dropped write and counts it per processor`.

#### Scenario: An agent host sends a series under another host's name

- **WHEN** pyrite's collector, or a person on pyrite using pyrite's collection certificate, sends a series naming cinnabar
- **THEN** the telemetry store keeps no such series under cinnabar's name, and the operator is told within one regulator period

#### Scenario: An overlay member claims another host's overlay address

- **WHEN** the operator, acting as another overlay member's administrator, makes that member claim stibnite's overlay address and send series naming stibnite
- **THEN** the telemetry store keeps none of them, and the operator records the attempt at acceptance

#### Scenario: A collection certificate is copied to another overlay member

- **WHEN** a copy of cinnabar's collection certificate is used from any overlay member other than cinnabar
- **THEN** the telemetry store keeps nothing it sends, and the operator is told within one regulator period
