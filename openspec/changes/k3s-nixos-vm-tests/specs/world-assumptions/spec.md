## ADDED Requirements

### Requirement: A13 — The Nix build sandbox has no network, so every remote artifact a check needs is a build input

It is true of Nix's sandboxed builds, independent of what this fleet builds, that a derivation without a fixed output hash cannot open a network connection, so an OCI image, a Helm chart, or a DNS answer a check needs at run time exists only if it was fetched by a fixed-output derivation and passed in as an input.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: A sandboxed non-fixed-output derivation reaches the network

- **WHEN** a derivation without a fixed output hash, built under the fleet's sandbox settings, successfully pulls an image, fetches a chart, or resolves a public name
- **THEN** this assumption is void, and the `k3s-platform-vm-regulator` requirement `Every image and chart the platform needs is a build input` loses the discharge argument that rests on hermeticity being enforced by the sandbox rather than by discipline

### Requirement: A14 — GitHub-hosted runner nested virtualization is unsupported by the vendor

It is true of GitHub's hosted runners, independent of what this fleet builds, that the vendor documents nested virtualization as technically possible but not officially supported and offers no guarantee of its stability, performance, or availability, so `/dev/kvm` being present on one image today is not a commitment that it will be present tomorrow.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: The vendor documents nested virtualization as supported

- **WHEN** GitHub's hosted-runner documentation states that nested virtualization is officially supported on the image the fleet uses
- **THEN** this assumption is void, and the `k3s-integration-ci-execution` requirement `VM leaves gate CI only from a runner whose KVM has been probed` may be relaxed to rely on the vendor's commitment rather than on a repeated probe

### Requirement: A15 — A Gateway becomes Programmed only once an address is assigned to it

It is true of the Cilium Gateway API implementation this fleet deploys, independent of what this fleet builds, that the controller sets `Programmed=True` on a Gateway only after the Service it generates for the Gateway has an ingress address, and reports `AddressNotAssigned` until then, so a cluster with no LoadBalancer address mechanism never produces a Programmed Gateway.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: A Gateway is Programmed with no address

- **WHEN** a Gateway managed by the deployed Cilium version reports `Programmed=True` while its generated Service has no ingress address
- **THEN** this assumption is void, and the `k3s-platform-vm-regulator` requirement `Gateway address assignment follows production's mechanism` loses the argument that a Programmed Gateway is evidence the address mechanism works
