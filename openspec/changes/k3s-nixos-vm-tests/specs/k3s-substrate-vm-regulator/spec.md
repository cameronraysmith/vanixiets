## ADDED Requirements

### Requirement: The production k3s module is exercised unmodified

Every substrate regulator SHALL compose its machines from `flake.modules.nixos.k3s-server` as exposed by the flake, adding only the option values a test needs (`enable`, `role`, `clusterInit`, `serverAddr`, `tokenFile`, `snapshotter`, `bootstrap`) and synthetic glue that the production module does not own, and SHALL NOT restate any production module content inline.

#### Scenario: A regulator's machine definition duplicates module content

- **WHEN** a substrate regulator's machine configuration sets `services.k3s.extraFlags`, `services.k3s.disable`, `boot.kernelModules`, `boot.kernel.sysctl`, or `networking.firewall.*` values that the production module already declares
- **THEN** review rejects the regulator, because a green result would no longer be evidence about the production module

#### Scenario: A property the fleet wants regulated is not reachable through the module

- **WHEN** a regulator needs to set a k3s option the production module does not expose (for example the node IP for a multi-node topology)
- **THEN** the regulator sets the underlying `services.k3s.*` option directly as glue and the gap is recorded as a finding about the module, not closed by copying the module

### Requirement: Evaluated node properties are asserted without a virtual machine

There SHALL be a regulator that evaluates the production module standalone on a Linux system and asserts the rendered k3s `ExecStart` contains `--flannel-backend=none`, `--disable-kube-proxy`, `--disable-network-policy`, `--disable-cloud-controller`, each `--disable=` entry the module declares, the server-role `--cluster-cidr` and `--service-cidr`, `--snapshotter nix` when `k3s-server.snapshotter` is `"nix"`, that `pkgs.nix` is on the k3s unit's `path`, and that `virtualisation.containerd.enable` is `false` and no `/etc/containerd/config.toml` is produced, and this regulator SHALL run without `kvm` or `nixos-test` system features.
Coverage bin: T1 existence regulator for the module's evaluated form; non-vacuity: each assertion is a string match on a value the module computes, shown to fail under the mutations below.

#### Scenario: A flag is removed from the module

- **WHEN** `--disable-kube-proxy` is removed from `k3s-server`'s `extraFlags` and the regulator is rebuilt
- **THEN** the regulator fails naming the missing flag, and passes again when the flag is restored

#### Scenario: The snapshotter default is changed

- **WHEN** `k3s-server.snapshotter` is set to `"overlayfs"` in a machine using the module and the regulator is rebuilt against that machine
- **THEN** the regulator fails naming the absent `--snapshotter nix` flag

#### Scenario: The host containerd block is made live

- **WHEN** a change sets `virtualisation.containerd.enable = true` or moves the settings into `services.k3s.containerdConfigTemplate`
- **THEN** the regulator's containerd assertion fails, and is updated in the same change to assert the corrected shape

### Requirement: Effective node properties are observed on a booted kernel

There SHALL be a regulator that boots one QEMU machine importing the production module with no CNI and asserts, on the running guest: `k3s.service` is active; `kubectl get node` lists the machine; the node's `Ready` condition is `False` with reason `KubeletNotReady` and a message naming the uninitialized CNI; the CoreDNS pod is `Pending`; no `flannel` or `cni0` link and no `cni-` network namespace exist; no `kube-proxy` process and no `KUBE-SERVICES` iptables chain exist; the kernel modules `br_netfilter`, `nf_conntrack`, `overlay` are loaded; the sysctls `net.ipv4.ip_forward`, `net.bridge.bridge-nf-call-iptables`, and `vm.overcommit_memory` have the module's values; the firewall accepts TCP 6443 and drops an unlisted port; the kubeconfig is unreadable by an unprivileged user; and `k3s-killall.sh` stops the service and removes container namespaces.
Coverage bin: T2 adequacy regulator for the effective substrate; non-vacuity: every assertion observes guest state through the test driver, and at least two are shown to fail under the mutations below.

#### Scenario: The node is NotReady for the expected reason

- **WHEN** the guest reaches `multi-user.target` and `k3s.service` becomes active
- **THEN** within the test timeout the node condition `Ready` is `False`, its `reason` is `KubeletNotReady`, and its `message` contains `cni plugin not initialized`

#### Scenario: A sysctl is changed in the module

- **WHEN** `net.ipv4.ip_forward` is set to `0` in `k3s-server-kernel` and the regulator is rebuilt
- **THEN** the regulator fails at the forwarding assertion with the observed value `0`

#### Scenario: A port is removed from the firewall

- **WHEN** `6443` is removed from `allowedTCPPorts` in `k3s-server-networking` and the regulator is rebuilt
- **THEN** the regulator fails at the assertion that TCP 6443 is accepted

### Requirement: The nix snapshotter is active in k3s's embedded containerd and NRI state is recorded

The single-node regulator SHALL assert that the containerd configuration k3s generates under `/var/lib/rancher/k3s/agent/etc/containerd/` contains `[plugins."io.containerd.snapshotter.v1.nix"]`, that `k3s ctr plugins ls` reports the `nix` snapshotter with status `ok`, and that the `snapshotter` value in the CRI plugin section is `nix`; it SHALL record whether the NRI plugin section is present and enabled as an observation in the test log, and SHALL NOT assume NRI state from the template.
There SHALL be a second regulator, `vm-k3s-nix-workload`, that runs one pod whose image is a `nix-snapshotter.buildImage` output referenced as `nix:0<store path>` and asserts the container reaches `Running` and its process is the store-path binary; it MAY use a test-only flannel override as CNI glue because the production module ships none.
Coverage bin: T2 adequacy for ADR-007 D7.1–D7.2 and F6; non-vacuity: the snapshotter assertion fails when the flag is removed, the workload assertion fails when `pkgs.nix` is removed from the unit path.

#### Scenario: The snapshotter plugin is loaded

- **WHEN** `k3s.service` becomes active on a node with `k3s-server.snapshotter = "nix"`
- **THEN** `k3s ctr plugins ls` lists `io.containerd.snapshotter.v1 nix ok` and the generated containerd config names `nix` as the CRI snapshotter

#### Scenario: nix-store is absent from the unit path

- **WHEN** `pkgs.nix` is removed from the k3s unit's `path` and `vm-k3s-nix-workload` is rebuilt
- **THEN** the pod does not reach `Running` and the regulator fails at the workload assertion with the containerd error naming `nix-store`

#### Scenario: NRI is observed disabled

- **WHEN** the test log records the NRI plugin section as disabled on a root k3s node
- **THEN** the finding is recorded against ADR-007 D7.8 and `services.k3s.containerdConfigTemplate` is introduced by a module change; the regulator itself does not fail

### Requirement: A second node joins through the production firewall

There SHALL be a regulator that boots one `role = "server"` machine with `clusterInit = true` and one `role = "agent"` machine with `serverAddr` pointing at the server, both importing the production module and sharing one token file, on one test-driver VLAN, and asserts both nodes are registered, the agent's `ExecStart` contains `--server=` and neither `--cluster-cidr` nor `--service-cidr`, and the agent reaches the server's TCP 6443 and 10250.
Coverage bin: T2 adequacy for the join path; non-vacuity: the firewall mutation below.

#### Scenario: The agent registers

- **WHEN** both guests reach `multi-user.target`
- **THEN** within the test timeout `kubectl get node agent` on the server succeeds and shows the agent's role label

#### Scenario: The join port is removed from the firewall

- **WHEN** `6443` is removed from the production firewall list and the regulator is rebuilt
- **THEN** the agent never registers and the regulator fails at the registration assertion

### Requirement: The token is delivered hermetically

The shared token for the multi-node regulator SHALL be a file in the Nix store or a clanTest-generated shared var, and SHALL NOT be read from the host environment, a GitHub Secret, or any path outside the derivation's inputs.
The production module's `k3s-server.bootstrap` option SHALL name the two production token paths — `clan-vars` and `cloud-init` — and a VM regulator SHALL exercise each with a test fixture rather than a production secret.

#### Scenario: Token delivery follows the production generator

- **WHEN** the fleet declares a `clan.core.vars` generator with `share = true` for the k3s token
- **THEN** the multi-node regulator switches to consuming that generator through clanTest's in-sandbox vars generation and the store-path token is removed

### Requirement: A cloud-init bootstrap node starts k3s from a NoCloud seed through the air-gapped shim

There SHALL be a regulator, `vm-k3s-capi-bootstrap`, that boots one machine importing the production module with `k3s-server.bootstrap = "cloud-init"`, attaches a `cidata` ISO built in the sandbox whose `user-data` contains the `write_files` (including `/etc/rancher/k3s/config.yaml` and any `KThreesConfig.spec.files` entries) and the `runcmd` line `INSTALL_K3S_SKIP_DOWNLOAD=true INSTALL_K3S_EXEC='server' sh /opt/install.sh` that cluster-api-k3s emits in `airGapped` mode, and asserts: `/opt/install.sh` in the image is a store path; `cloud-final.service` completes; `k3s.service` is active with `--config /etc/rancher/k3s/config.yaml` in its command line; the sentinel file the cluster-api-k3s template expects exists; `kubectl get nodes` lists the machine; and no k3s binary was downloaded or written outside the store.
The `user-data` SHALL be rendered by a Nix function that mirrors cluster-api-k3s' control-plane init template at the pinned revision, and the regulator SHALL NOT run the Cluster API controllers.
Coverage bin: T2 adequacy for the bootstrap-identity seam (ADR-009 D9.8, D9.9) and the regulator that discharges open risk R9.d; non-vacuity: the two mutations below.

#### Scenario: The shim starts k3s

- **WHEN** the guest reaches `cloud-final.service` with the rendered `user-data`
- **THEN** within the test timeout `k3s.service` is active, its command line contains `--config /etc/rancher/k3s/config.yaml`, and the sentinel file exists

#### Scenario: The config file is not written

- **WHEN** the `write_files` entry for `/etc/rancher/k3s/config.yaml` is removed from the rendered `user-data` and the regulator is rebuilt
- **THEN** the shim exits non-zero before `systemctl start`, `k3s.service` is not active, and the regulator fails at the activity assertion

#### Scenario: The runcmd template drifts

- **WHEN** the pinned cluster-api-k3s revision changes the `runcmd` text and the Nix renderer is not updated
- **THEN** a T1 assertion comparing the renderer's output against the string in the pinned source's test fixture fails, independent of the VM leaf

### Requirement: Every runtime assertion has mutation evidence

For each substrate regulator, at least two runtime assertions SHALL be accompanied, in the change that introduces the regulator, by a recorded mutation of the production module, the resulting failure output, and the revert.

#### Scenario: A regulator lands without mutation evidence

- **WHEN** a change introduces a `vm-k3s-*` leaf whose description records no mutation and failure output
- **THEN** review rejects the change until the evidence is added
