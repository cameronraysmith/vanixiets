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

### Requirement: A16 — An OCI manifest digest is a function of the manifest bytes alone

It is true of the OCI distribution and image specifications, independent of what this fleet builds, that a manifest's digest is the SHA-256 of its exact byte serialization, so a manifest written into an image layout in the Nix sandbox and pushed unmodified to a registry has the same digest in both places, and a registry that reports a different digest has received different bytes.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: A registry re-encodes a pushed manifest

- **WHEN** a push tool or registry accepts a manifest and serves it back under a digest that differs from the digest of the bytes sent
- **THEN** this assumption is void, and the `k3s-manifest-purity-regulator` requirement `The published artifact's digest equals the sandbox-built digest` loses its argument that digest equality is a property of content rather than of the push tool

### Requirement: A17 — cluster-api-k3s defaults the cloud provider to external

It is true of the cluster-api-k3s bootstrap provider at the revision the fleet pins, independent of what this fleet builds, that its defaulting webhook sets `disableCloudController` to `true` and `cloudProviderName` to `external` when neither is given, so a node it bootstraps carries the `node.cloudprovider.kubernetes.io/uninitialized` taint until a cloud-controller manager removes it.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: The provider stops defaulting to external

- **WHEN** a pinned cluster-api-k3s release bootstraps a node with no cloud-controller manager present and the node becomes schedulable without the taint
- **THEN** this assumption is void, and the `capi-cluster-rendering` requirement `Every cloud-init platform variant renders a cloud-controller manager` loses the argument that an absent CCM leaves nodes unschedulable

### Requirement: A18 — Cilium ClusterMesh requires non-overlapping PodCIDRs and a covering native-routing CIDR

It is true of Cilium ClusterMesh, independent of what this fleet builds, that PodCIDR ranges in all connected clusters and nodes must be non-conflicting, that in native-routing mode the native-routing CIDR must cover every connected cluster's PodCIDRs, and that each cluster needs a unique name and numeric id, so two clusters that violate any of these cannot be meshed regardless of how they are otherwise configured.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL be treated as losing its discharge once this assumption's violation condition below is observed.

#### Scenario: Cilium meshes clusters with overlapping PodCIDRs

- **WHEN** a deployed Cilium version establishes pod-to-pod connectivity between two clusters whose PodCIDRs overlap
- **THEN** this assumption is void, and the `capi-cluster-rendering` requirement `ClusterMesh preconditions hold at evaluation` may be relaxed to a warning
