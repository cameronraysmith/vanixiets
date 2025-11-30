# Epic 7: GCP Multi-Node Infrastructure (Post-MVP Phase 6)

**Status:** Backlog
**Dependencies:** Epic 6 complete
**Strategy:** Replicate hetzner.nix patterns for GCP provider with togglable CPU and GPU nodes

---

## Epic Goal

Deploy togglable CPU-only and GPU-capable compute nodes on GCP using terranix, integrating with existing clan infrastructure and zerotier mesh network.

**Key Outcomes:**
- Terranix GCP module following established hetzner.nix patterns
- CPU-only nodes with cost-effective machine types (e2-standard, n2-standard)
- GPU-capable nodes with NVIDIA accelerators (T4, A100)
- Full clan inventory integration with zerotier mesh connectivity
- Toggle mechanism for cost control (disabled nodes incur zero ongoing cost)

**Business Objective:** GCP contract obligations, GPU availability for ML workloads, multi-cloud infrastructure redundancy.

---

## FR Coverage Map

| Story | Functional Requirements |
|-------|-------------------------|
| Story 7.1 | FR-7.1 (Terranix GCP provider) |
| Story 7.2 | FR-7.2 (CPU-only nodes) |
| Story 7.3 | FR-7.4 (Clan + zerotier integration) |
| Story 7.4 | FR-7.3 (GPU-capable nodes) |

*Note: Stories 7.3/7.4 reordered 2025-11-30 - zerotier before GPU per Party Mode decision.*

---

## Story 7.1: Terranix GCP provider and base configuration

As a system administrator,
I want to create a terranix GCP module following the patterns established in hetzner.nix,
So that I can provision GCP compute instances with the same declarative approach used for Hetzner Cloud.

**Acceptance Criteria:**

**Given** the existing terranix pattern in `modules/terranix/hetzner.nix`
**When** I create `modules/terranix/gcp.nix`
**Then** the module should:
- Define `flake.modules.terranix.gcp` following dendritic flake-parts namespace
- Use `hashicorp/google` terraform provider
- Generate ED25519 SSH key for deployment (matching hetzner pattern)
- Store private key locally for `clan machines install`
- Evaluate successfully with `nix eval .#terranixConfigurations.gcp`

**And** the configuration should include:
- GCP project ID variable
- Region and zone configuration
- Service account credentials path
- Network/firewall configuration for SSH and zerotier

**Prerequisites:** Epic 6 complete (dendritic+clan architecture stable)

**Technical Notes:**
- Pattern template: `modules/terranix/hetzner.nix`
- Terraform provider: `hashicorp/google`
- SSH key pattern: Same ED25519 key generation as Hetzner
- State management: Consistent with existing Hetzner terraform state

**NFR Coverage:** NFR-7.1 (Pattern consistency), NFR-7.3 (Deployment consistency)

---

## Story 7.2: CPU-only togglable node definition and deployment

As a system administrator,
I want to define CPU-only GCP compute instances with an enabled/disabled toggle,
So that I can control costs by disabling nodes when not in use while maintaining infrastructure-as-code definitions.

**Acceptance Criteria:**

**Given** the GCP terranix module from Story 7.1
**When** I define CPU-only machine configurations
**Then** the module should:
- Define machine entries with `enabled = true/false` toggle
- Support e2-standard and n2-standard machine families
- Allow configurable zone/region selection
- Use debian-12 base image for NixOS installation consistency

**And** deployment should:
- Only provision machines where `enabled = true`
- Deploy via `clan machines install` with `--target-host` pattern
- Register SSH keys with GCP project

**And** cost management should:
- Disabled machines not provisioned (zero ongoing cost)
- Clear documentation of hourly costs per machine type

Example machine definition:
```nix
machines = {
  gcp-cpu-1 = {
    enabled = false;  # Toggle for cost control
    machineType = "e2-standard-4";  # 4 vCPU, 16GB RAM
    zone = "us-central1-a";
    image = "debian-12";
    comment = "General purpose CPU node";
  };
};
```

**Prerequisites:** Story 7.1 (GCP terranix provider)

**Technical Notes:**
- Machine types: e2-standard-2/4/8 or n2-standard-2/4/8
- Zones: us-central1-a/b/c for lowest latency to existing infrastructure
- Filter pattern: `enabledMachines = lib.filterAttrs (_name: cfg: cfg.enabled) machines;`
- Provisioner: `null_resource.install-<name>` with `clan machines install`

**NFR Coverage:** NFR-7.2 (Cost management)

---

## Story 7.3: Clan integration and zerotier mesh for GCP nodes

*Reordered from Story 7.4 on 2025-11-30 - zerotier integration before GPU to test on cheap CPU node first.*

As a system administrator,
I want GCP nodes to join the clan inventory and zerotier mesh network,
So that GCP nodes are managed consistently with Hetzner VPS and darwin workstations.

**Acceptance Criteria:**

**Given** deployed GCP node galena from Story 7.2
**When** galena is configured for zerotier via clan inventory
**Then** clan integration should:
- Add galena entry in `modules/clan/inventory/machines.nix`
- Assign appropriate tags: `["nixos", "cloud", "gcp", "peer"]`
- Inherit zerotier peer role via `roles.peer.tags."peer"` pattern
- Deploy clan vars to `/run/secrets/` with proper permissions

**And** zerotier mesh should:
- Configure peer role connecting to cinnabar controller (network ID db4344343b14b903)
- Establish mesh connectivity with all existing nodes (darwin + Hetzner)
- Validate bidirectional SSH access via zerotier IPs

**And** operational validation should:
- `clan machines list` includes galena
- `zerotier-cli status` shows network membership on galena
- SSH access via zerotier IP (galena.zt) functional from all other hosts
- galena.zt added to home-manager SSH config

**Prerequisites:** Story 7.2 (galena CPU node validated)

**Technical Notes:**
- Zerotier role: Peer (like electrum), not controller (cinnabar is controller)
- Tags: `["nixos", "cloud", "gcp", "peer"]` - peer tag triggers zerotier service
- Pattern reference: `modules/clan/inventory/machines.nix` electrum entry
- Service inheritance: zerotier peer role via tag-based selection
- Cost control: Re-enable galena only for testing, disable after validation

**NFR Coverage:** NFR-7.3 (Deployment consistency with Hetzner pattern)

---

## Story 7.4: GPU-capable togglable node definition and deployment

*Reordered from Story 7.3 on 2025-11-30 - GPU after zerotier integration validated.*

As a system administrator,
I want to define GPU-capable GCP compute instances with NVIDIA accelerators,
So that I can run ML workloads requiring GPU acceleration with cost-conscious toggle control.

**Acceptance Criteria:**

**Given** the GCP terranix module from Story 7.1 and zerotier integration from Story 7.3
**When** I define GPU-capable machine configurations
**Then** the module should:
- Support n1-standard machine types with GPU attachment
- Allow T4 and A100 accelerator options
- Configure accelerator count (1, 2, 4 GPUs)
- Include GPU-specific machine metadata

**And** NixOS configuration should:
- Include NVIDIA driver module (`hardware.nvidia.package`)
- Include CUDA toolkit modules where needed
- Configure GPU-specific kernel parameters
- Set up proper device permissions

**And** cost considerations should:
- Document hourly costs prominently (GPUs expensive when idle)
- Default to `enabled = false` for GPU nodes
- Include cost comparison table in documentation

Example GPU machine definition (scheelite):
```nix
machines = {
  scheelite = {
    enabled = false;  # Default disabled for cost control
    machineType = "n1-standard-4";
    zone = "us-central1-a";
    image = "debian-12";
    gpu = {
      type = "nvidia-tesla-t4";
      count = 1;
    };
    comment = "T4 GPU node for ML inference (~$0.35/hr + base)";
  };
};
```

**Prerequisites:** Story 7.3 (zerotier integration validated on galena)

**Technical Notes:**
- GPU machine types: n1-standard-4/8/16 with attached GPUs
- T4: Cost-effective inference, ~$0.35/hour per GPU
- A100: High-performance training, ~$2.95/hour per GPU
- NVIDIA driver: `hardware.nvidia.modesetting.enable = true`
- CUDA modules: `environment.systemPackages = [ pkgs.cudaPackages.cudatoolkit ]`
- Zone constraints: Not all zones have GPU availability
- Naming: scheelite (tungsten ore mineral, continuing metallurgical theme)

**NFR Coverage:** NFR-7.2 (Cost management - especially critical for GPUs)

---

## Dependencies

**Depends on:**
- Epic 6: Legacy cleanup complete (clean dendritic+clan architecture)

**Enables:**
- Epic 8: Documentation alignment (can document GCP infrastructure after deployment)

---

## Success Criteria

- [ ] Terranix GCP module builds (`nix eval .#terranixConfigurations.gcp`)
- [ ] CPU-only node deploys successfully with toggle enabled
- [ ] GPU-capable node deploys successfully with toggle enabled
- [ ] Both node types join zerotier mesh and clan inventory
- [ ] Disabled nodes incur zero ongoing cost
- [ ] SSH access functional from all mesh nodes
- [ ] Clan vars deployed correctly to GCP nodes

---

## Risk Notes

**Cost risks:**
- GPU nodes are expensive (~$0.35-$2.95/hour per GPU)
- Toggle discipline critical for cost control
- Consider GCP budget alerts

**Technical risks:**
- GPU driver compatibility with NixOS
- Zone availability for GPU instances
- Network latency between GCP and Hetzner

**Mitigation:**
- Default all nodes to `enabled = false`
- Validate GPU driver stack on CPU node first
- Document cost expectations prominently

---

**References:**
- Pattern template: `modules/terranix/hetzner.nix`
- PRD: `docs/notes/development/PRD/functional-requirements.md` (FR-7)
- NFRs: `docs/notes/development/PRD/non-functional-requirements.md` (NFR-7)
