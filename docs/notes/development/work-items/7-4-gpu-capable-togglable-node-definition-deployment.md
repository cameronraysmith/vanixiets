# Story 7.4: GPU-Capable Togglable Node Definition and Deployment (scheelite)

Status: drafted

## Story

As a system administrator,
I want to define and deploy a GPU-capable GCP compute instance (scheelite) with NVIDIA accelerator support,
so that I can run ML inference and training workloads on the zerotier-connected infrastructure.

## Context

Story 7.4 builds on the foundation established in Stories 7.1-7.3.
The terranix GCP module exists with GPU scaffolding (lines 163-175 in gcp.nix), and zerotier integration is validated on the galena CPU node.
This story activates GPU support by defining and deploying the first GPU-capable node (scheelite).

**Story Order History (2025-11-30):** Per Party Mode decision, zerotier integration (Story 7.3) was executed before GPU deployment (this story).
Rationale: Test zerotier on cheaper CPU node (galena, ~$0.27/hr) before expensive GPU node (scheelite, ~$2-3/hr).

**Current State:**
- GPU resource blocks in `modules/terranix/gcp.nix`: EXISTS (lines 163-175)
- Example scheelite definition: COMMENTED (lines 29-38)
- GPU configuration pattern: `guest_accelerator` + `on_host_maintenance = "TERMINATE"`
- NixOS NVIDIA modules: NOT CONFIGURED

**Cost Warning:**
- L4 GPU: ~$0.24/hour per GPU (~$175/month if left running)
- T4 GPU: ~$0.35/hour per GPU (~$250/month if left running)
- A100 GPU: ~$2.95/hour per GPU (~$2,124/month if left running)
- Default `enabled = false` is CRITICAL for cost control

## Acceptance Criteria

1. Terranix module supports g2-standard and n1-standard machine types with GPU attachment
2. Support L4 (cost-effective inference), T4 (legacy inference), and A100 (high-performance training) accelerator options
3. Configurable accelerator count (1, 2, 4 GPUs)
4. GPU-specific machine metadata included in terraform output
5. NixOS configuration includes `hardware.nvidia.package` module
6. NixOS includes CUDA toolkit modules
7. GPU-specific kernel parameters configured
8. Proper device permissions for GPU access
9. Hourly costs documented prominently (GPUs expensive when idle)
10. GPU nodes default to `enabled = false`
11. Cost comparison table in documentation/comments

## Tasks / Subtasks

- [ ] Task 1: Define scheelite machine in terranix GCP module (AC: #1, #2, #3, #4, #10)
  - [ ] Uncomment/update scheelite definition in `modules/terranix/gcp.nix`
  - [ ] Set `enabled = false` as default
  - [ ] Configure `machineType = "g2-standard-4"` (4 vCPU, 16GB RAM, optimized for L4)
  - [ ] Configure `zone = "us-central1-a"` (verify GPU quota available)
  - [ ] Configure `gpuType = "nvidia-l4"` and `gpuCount = 1`
  - [ ] Add cost comment: "L4 GPU node for ML inference (~$0.24/hr GPU + ~$0.13/hr base)"
  - [ ] Verify guest_accelerator block activates for GPU machines

- [ ] Task 2: Create dendritic nvidia module (AC: #5, #6, #7, #8)

  **CRITICAL - HEADLESS SERVER CONTEXT:**
  scheelite is a headless GPU compute node for ML inference/training (JAX, PyTorch), NOT a desktop workstation.
  The gaetanlepage reference is a DESKTOP configuration. You MUST filter appropriately.

  **DO NOT COPY from gaetanlepage nvidia.nix:**
  - `services.xserver.videoDrivers = [ "nvidia" ]` (display server - scheelite is headless)
  - `programs.sway.package = pkgs.sway.override { ... }` (Wayland compositor - no display)
  - `hardware.nvidia.nvidiaSettings = true` (GUI configuration tool - no GUI)
  - `hardware.graphics.enable32Bit = true` (32-bit graphics for gaming - server doesn't need)

  **ADD for headless compute (not in gaetanlepage):**
  - `hardware.nvidia.nvidiaPersistenced = true` (headless daemon for GPU persistence)
  - `hardware.nvidia.nvidiaSettings = false` (explicitly disable GUI tool)
  - `hardware.graphics.enable32Bit = false` (no 32-bit support needed)

  **KEEP from gaetanlepage (compute-relevant):**
  - `nixpkgs.config.cudaSupport = true`
  - `programs.nix-required-mounts.presets.nvidia-gpu.enable = true`
  - `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.latest`
  - `hardware.nvidia.modesetting.enable = true`
  - `hardware.nvidia.open = true` (open kernel module)
  - `hardware.nvidia.powerManagement.enable = false` (no suspend on servers)
  - `hardware.graphics.enable = true`
  - `environment.systemPackages = [ pkgs.nvtopPackages.nvidia ]`

  - [ ] Create `modules/nixos/nvidia.nix` following gaetanlepage pattern
  - [ ] Export as `flake.modules.nixos.nvidia` (dendritic namespace)
  - [ ] Configure `nixpkgs.config.cudaSupport = true`
  - [ ] Configure `services.xserver.videoDrivers = [ "nvidia" ]`
  - [ ] Configure `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.latest`
  - [ ] Configure `hardware.nvidia.modesetting.enable = true`
  - [ ] Configure `hardware.nvidia.open = true` (L4 Ada Lovelace supports open drivers)
  - [ ] Add `pkgs.nvtopPackages.nvidia` for GPU monitoring
  - [ ] Configure `hardware.graphics.enable = true`
  - [ ] Add `programs.nix-required-mounts.presets.nvidia-gpu.enable = true` for CUDA sandbox

- [ ] Task 2b: Add CUDA cache substituter (AC: related to build speed)
  - [ ] Update `lib/caches.nix` with CUDA cache entry (follows infra DRY pattern):
    ```nix
    {
      url = "https://cache.nixos-cuda.org";
      publicKey = "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=";
      priority = 5;
    }
    ```
  - [ ] Verify `modules/system/caches.nix` imports from `lib/caches.nix`
  - [ ] **DO NOT** create separate `modules/nixos/substituters.nix` (would duplicate existing pattern)

  **Rationale:** infra uses `lib/caches.nix` as single source of truth for binary caches. Adding CUDA cache here maintains consistency with existing DRY cache management pattern.

- [ ] Task 3: Create scheelite NixOS machine configuration (AC: #5, #6, #7, #8)
  - [ ] Create `modules/machines/nixos/scheelite/default.nix` (copy galena pattern)
  - [ ] Create `modules/machines/nixos/scheelite/disko.nix` (copy galena pattern)
  - [ ] Import nvidia module: `++ (with flakeModules; [ base ssh-known-hosts nvidia ])`
  - [ ] Configure hostname: `networking.hostName = "scheelite"`

- [ ] Task 4: Configure clan inventory for scheelite (AC: related to deployment)
  - [ ] Add scheelite entry to `modules/clan/machines.nix`
  - [ ] Add scheelite entry to `modules/clan/inventory/machines.nix` with tags `["nixos", "cloud", "gcp", "gpu", "peer"]`
  - [ ] Add scheelite to `user-cameron` service for SSH access
  - [ ] Verify configuration builds: `nix build .#nixosConfigurations.scheelite.config.system.build.toplevel`

- [ ] Task 5: Deploy and validate scheelite (AC: #1-#8)
  - [ ] Enable scheelite: Set `enabled = true` in `modules/terranix/gcp.nix`
  - [ ] Deploy infrastructure: `nix run .#terraform` (apply)
  - [ ] Note new GCP external IP, update `modules/clan/inventory/services/internet.nix`
  - [ ] Deploy NixOS: `clan machines install scheelite --target-host root@<IP>`
  - [ ] Validate NVIDIA driver loaded:
    ```bash
    ssh cameron@<IP> "nvidia-smi"
    # Expect: GPU listed (L4 or T4), driver version shown
    ```
  - [ ] Validate CUDA toolkit available:
    ```bash
    ssh cameron@<IP> "nvcc --version"
    # Expect: CUDA 12.x version
    ```
  - [ ] Validate CUDA compilation works:
    ```bash
    ssh cameron@<IP> "echo '__global__ void k(){}' | nvcc -x cu - -o /tmp/test.cubin && echo 'CUDA compilation: PASS'"
    # Expect: "CUDA compilation: PASS"
    ```
  - [ ] Validate nix CUDA sandbox (nix-required-mounts):
    ```bash
    ssh cameron@<IP> "nix-shell -p cudaPackages.cudatoolkit --run 'nvcc --version'"
    # Expect: CUDA version (proves nix-required-mounts works)
    ```
  - [ ] Validate zerotier connectivity:
    ```bash
    ssh cameron@<IP> "sudo zerotier-cli status"
    # Expect: ONLINE, network joined
    ```
  - [ ] Validate zerotier mesh access from darwin:
    ```bash
    ssh scheelite.zt "nvidia-smi"
    # Expect: GPU info via zerotier IPv6
    ```
  - [ ] Validate nvidiaPersistenced running:
    ```bash
    ssh cameron@<IP> "systemctl status nvidia-persistenced"
    # Expect: active (running)
    ```

- [ ] Task 6: Configure SSH and zerotier mesh access (AC: related to integration)
  - [ ] Get scheelite zerotier IP from `zerotier-cli listnetworks`
  - [ ] Add scheelite.zt hostname entry to `modules/home/core/ssh.nix`
  - [ ] Add scheelite.zt to declarative known_hosts in `modules/system/ssh-known-hosts.nix`
  - [ ] Validate SSH from darwin workstations via zerotier

- [ ] Task 7: Document costs and disable for cost control (AC: #9, #10, #11)
  - [ ] Add cost comparison table to gcp.nix or documentation
  - [ ] Document scheelite zerotier IP for future reference
  - [ ] Disable scheelite: Set `enabled = false` in `modules/terranix/gcp.nix`
  - [ ] Apply terraform to destroy instance: `nix run .#terraform.apply`
  - [ ] Commit all changes with atomic commits

## Dev Notes

### Story 7.3 Foundation (zerotier integration validated)

Story 7.3 successfully validated zerotier mesh integration on galena:
- Inventory pattern: `["nixos", "cloud", "gcp", "peer"]` tags enable zerotier peer role
- Deployment sequence: terraform apply → clan machines install → clan machines update [controller]
- SSH config pattern: `modules/home/core/ssh.nix` + `modules/system/ssh-known-hosts.nix`

**Key Learning from Story 7.3:**
- Zerotier authorization flow requires `clan machines update cinnabar` after adding new inventory entry
- `backupFileExtension` prevents home-manager race condition on new GCP instances

### Existing GPU Scaffolding

The gcp.nix module already contains GPU support infrastructure (lines 163-175):
```nix
// lib.optionalAttrs (cfg ? gpuType && cfg ? gpuCount) {
  guest_accelerator = [
    {
      type = cfg.gpuType;
      count = cfg.gpuCount;
    }
  ];
  scheduling = {
    on_host_maintenance = "TERMINATE";
  };
}
```

This pattern automatically activates when a machine definition includes `gpuType` and `gpuCount`.

### NixOS NVIDIA Configuration Pattern

**Reference: gaetanlepage-dendritic-nix-config `modules/nixos/nvidia.nix`**

The gaetanlepage repo uses a dendritic module pattern for NVIDIA configuration that we should adapt:

```nix
# gaetanlepage pattern: modules/nixos/nvidia.nix
{
  flake.modules.nixos.nvidia =
    { pkgs, config, ... }:
    {
      # Enable CUDA support globally
      nixpkgs.config.cudaSupport = true;

      # NVIDIA driver
      services.xserver.videoDrivers = [ "nvidia" ];
      environment.systemPackages = [ pkgs.nvtopPackages.nvidia ];

      # Enable CUDA sandbox support for nix builds
      programs.nix-required-mounts = {
        enable = true;
        presets.nvidia-gpu.enable = true;
      };

      hardware = {
        graphics = {
          enable = true;
          enable32Bit = true;
        };

        nvidia = {
          # Use latest drivers (L4 is Ada Lovelace - needs recent drivers)
          package = config.boot.kernelPackages.nvidiaPackages.latest;
          modesetting.enable = true;

          # Power management (disable for cloud VMs)
          powerManagement.enable = false;
          powerManagement.finegrained = false;

          # Open source kernel module
          # L4 (Ada Lovelace) supports open drivers, but proprietary may be more stable
          open = true;  # or false for proprietary

          nvidiaSettings = true;
        };
      };
    };
}
```

**Key differences for our scheelite (GCP L4 GPU):**
1. No desktop/sway configuration needed (headless compute node)
2. L4 is Ada Lovelace architecture (newer than T4 Turing) - `nvidiaPackages.latest` preferred
3. Consider `open = true` for L4 (Ada Lovelace supports open drivers better than older GPUs)
4. Add CUDA cache substituter for faster builds

### Dendritic Module Auto-Discovery Pattern

**CRITICAL UNDERSTANDING for Task 2 → Task 3 workflow:**

1. **Creating the nvidia module** (Task 2):
   - File: `modules/nixos/nvidia.nix`
   - Exports: `flake.modules.nixos.nvidia`
   - Discovery: import-tree automatically finds this file during flake evaluation
   - NO manual imports needed in flake.nix

2. **Importing the nvidia module** (Task 3):
   - scheelite's default.nix uses outer config capture pattern (see galena lines 1-8):
   ```nix
   { config, ... }:
   let
     flakeModules = config.flake.modules.nixos;  # Capture ALL auto-discovered modules
   in
   {
     flake.modules.nixos."machines/nixos/scheelite" = { ... }: {
       imports = [ ... ]
       ++ (with flakeModules; [ base ssh-known-hosts nvidia ]);  # nvidia available here
     };
   }
   ```

3. **How it works**:
   - import-tree evaluates `modules/nixos/nvidia.nix` → creates `config.flake.modules.nixos.nvidia`
   - scheelite captures `config.flake.modules.nixos` as `flakeModules` variable
   - `flakeModules.nvidia` references the auto-discovered module
   - This is the dendritic pattern - ZERO manual flake.nix imports required

**Reference:** `modules/machines/nixos/galena/default.nix` lines 1-27 demonstrates this exact pattern.

### Mandatory Reference Files

The dev agent MUST read these files before implementation:

**NVIDIA Module Source Code (AUTHORITATIVE REFERENCE):**
0. `~/projects/nix-workspace/nixpkgs/nixos/modules/hardware/video/nvidia.nix` - The authoritative source for ALL `hardware.nvidia.*` options. When in doubt about any NVIDIA configuration option, consult this file directly. It contains 28 options with full type definitions, defaults, and descriptions.

**Local Analysis Document:**
0a. `docs/notes/development/nvidia-module-analysis.md` - Comprehensive analysis of nvidia.nix options with datacenter relevance assessment, created during Story 7.4 research.

**Infra Architecture Patterns (MUST READ):**
1. `flake.nix` - Dendritic import-tree integration with clan
2. `modules/machines/nixos/galena/default.nix` - EXACT pattern for scheelite (outer config capture, flakeModules)
3. `modules/machines/nixos/galena/disko.nix` - Disko namespace merging pattern
4. `modules/terranix/gcp.nix` - GPU scaffolding (lines 163-175), machine pattern (lines 20-39)
5. `modules/clan/machines.nix` - Machine registration pattern
6. `modules/clan/inventory/machines.nix` - Inventory tags pattern
7. `modules/clan/inventory/services/zerotier.nix` - Peer tag role pattern
8. `lib/caches.nix` - DRY cache configuration (add CUDA cache here)
9. `modules/system/caches.nix` - Cache import pattern
10. `modules/home/core/ssh.nix` - SSH config for .zt hostnames
11. `modules/system/ssh-known-hosts.nix` - Known hosts pattern with clan vars

**gaetanlepage Reference (READ WITH SERVER CONTEXT FILTER):**
12. `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/nixos/nvidia.nix` - Base pattern, REMOVE desktop-specific lines
13. `~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/nixos/dev/substituters.nix` - CUDA cache pattern

**Architecture Documentation:**
14. `docs/notes/development/architecture/index.md` - Implementation patterns
15. `docs/notes/development/work-items/7-3-clan-integration-zerotier-mesh-gcp-nodes.md` - Zerotier pattern reference

### CUDA Cache Substituter (from gaetanlepage)

**Reference: gaetanlepage-dendritic-nix-config `modules/nixos/dev/substituters.nix`**

Add the nixos-cuda.org cache for faster CUDA package builds:

```nix
# Add to nix.settings (or create modules/nixos/substituters.nix)
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://cache.nixos-cuda.org?priority=5"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
  ];
};
```

### Dendritic Module Pattern for scheelite

Following the gaetanlepage `modules/hosts/cuda/default.nix` pattern, our scheelite should import the nvidia module:

```nix
# modules/machines/nixos/scheelite/default.nix (proposed)
{
  flake.modules.nixos."machines/nixos/scheelite" =
    { config, lib, ... }:
    {
      imports = [
        # ... base imports from galena
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
        nvidia  # NEW: import nvidia module
      ]);

      # scheelite-specific configuration
      networking.hostName = "scheelite";
      # ...
    };
}
```

This requires creating a separate `modules/nixos/nvidia.nix` dendritic module (or inline in scheelite).

### GCP GPU Zone Availability

Not all GCP zones have GPU quota. Verify availability before deployment.

**L4 availability:** us-central1-a, us-central1-b, us-east1-b, us-west1-b, europe-west4-a
**T4 availability:** us-central1-a, us-central1-b, us-west1-b, europe-west4-a
**A100 availability:** us-central1-a, us-east1-c, europe-west4-a

**Recommendation:** Start with `us-central1-a` (same region as existing infrastructure, L4 available)

### Cost Reference Table

| Machine Type | GPU | Config | Hourly Cost | Monthly (730h) |
|--------------|-----|--------|-------------|----------------|
| g2-standard-4 | 1x L4 | 4 vCPU, 16GB + L4 | ~$0.37/hr | ~$270/mo |
| g2-standard-8 | 1x L4 | 8 vCPU, 32GB + L4 | ~$0.50/hr | ~$365/mo |
| n1-standard-4 | 1x T4 | 4 vCPU, 15GB + T4 | ~$0.54/hr | ~$394/mo |
| n1-standard-8 | 1x A100 | 8 vCPU, 30GB + A100 | ~$3.14/hr | ~$2,292/mo |

**L4 vs T4:** L4 (Ada Lovelace) is ~30% faster than T4 (Turing) at lower cost. Recommended for inference.

**CRITICAL:** GPU nodes should remain `enabled = false` by default.
Only enable for active use, disable immediately after workload completion.

### Naming Convention

scheelite: A tungsten ore mineral (CaWO4), continuing the metallurgical theme:
- galena: lead ore (CPU node)
- scheelite: tungsten ore (GPU node)
- cinnabar: mercury ore (zerotier controller)
- electrum: gold-silver alloy (Hetzner peer)

### Project Structure Notes

Files to create:
- `modules/nixos/nvidia.nix` - Dendritic nvidia module (following gaetanlepage pattern)
- `modules/machines/nixos/scheelite/default.nix` - NixOS configuration importing nvidia module
- `modules/machines/nixos/scheelite/disko.nix` - Disk layout (copy from galena)
- `modules/nixos/substituters.nix` - CUDA cache substituter (optional, for faster builds)

Files to modify:
- `modules/terranix/gcp.nix` - Update scheelite definition (uncomment/enhance)
- `modules/clan/machines.nix` - Add scheelite entry
- `modules/clan/inventory/machines.nix` - Add scheelite with gpu+peer tags
- `modules/clan/inventory/services/user-cameron.nix` - Add scheelite
- `modules/home/core/ssh.nix` - Add scheelite.zt
- `modules/system/ssh-known-hosts.nix` - Add scheelite.zt

### Learnings from Previous Story

**From Story 7.3 (Status: done - APPROVED)**

- **Zerotier Authorization Flow**: Adding a new peer to inventory requires `clan machines update [controller]` to authorize the new node
- **Home-manager Race Condition**: GCP instances may run zsh-newuser-install before home-manager activation; `backupFileExtension` prevents file conflicts
- **Deployment Sequence**: terraform apply → clan machines install → clan machines update cinnabar
- **SSH Config Pattern**: galena.zt added to `modules/home/core/ssh.nix:75-78` and `modules/system/ssh-known-hosts.nix`
- **Network Details**: Network ID db4344343b14b903, IPv6 prefix fddb:4344:343b:14b9:*

**Files Created in Story 7.3 (pattern to follow):**
- `modules/clan/inventory/machines.nix:25-34` - galena inventory entry
- `modules/home/core/ssh.nix:75-78` - galena.zt SSH config

**Story 7.3 Advisory Notes (apply to this story):**
- Consider adding nix-unit tests for scheelite configuration
- Pattern documentation for GPU deployments recommended for architecture docs

[Source: docs/notes/development/work-items/7-3-clan-integration-zerotier-mesh-gcp-nodes.md#Dev-Agent-Record]

### References

**infra repo patterns:**
- [Epic 7: docs/notes/development/epics/epic-7-gcp-multi-node-infrastructure.md#Story-7.4 (lines 164-222)]
- [Pattern: modules/terranix/gcp.nix (GPU scaffolding lines 163-175)]
- [Pattern: modules/machines/nixos/galena/ (NixOS machine structure)]
- [Pattern: modules/clan/inventory/machines.nix (inventory entry structure)]
- [Story 7.3: docs/notes/development/work-items/7-3-clan-integration-zerotier-mesh-gcp-nodes.md (zerotier pattern)]

**gaetanlepage-dendritic-nix-config reference (NVIDIA/CUDA patterns):**
- [~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/nixos/nvidia.nix - Dendritic nvidia module]
- [~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/hosts/cuda/default.nix - Host composition pattern]
- [~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/hosts/cuda/_nixos/default.nix - Machine config]
- [~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/hosts/cuda/_nixos/hardware.nix - Hardware scan]
- [~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/hosts/cuda/_nixos/disko.nix - Disk layout]
- [~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/nixos/dev/substituters.nix - CUDA cache config]
- [~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/hosts/cuda/_nixos/nix-remote-builder.nix - Remote builder (optional)]

**External documentation:**
- [NixOS NVIDIA Wiki: https://nixos.wiki/wiki/Nvidia]
- [CUDA cache: https://cache.nixos-cuda.org]
- [GCP GPU pricing: https://cloud.google.com/compute/gpus-pricing]

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-7.2 (Cost management) | GPU default disabled, cost table, prominent warnings |
| NFR-7.3 (Deployment consistency) | Follows galena pattern with NVIDIA additions |

### Estimated Effort

**4-6 hours** (configuration, deployment, validation)

- Terranix scheelite definition: 0.5 hour
- NixOS NVIDIA configuration: 1-1.5 hours
- Clan inventory setup: 0.5 hour
- GCP deployment + NixOS install: 1-1.5 hours
- GPU validation (nvidia-smi, CUDA): 0.5-1 hour
- SSH config + documentation: 0.5-1 hour

Note: GPU driver compatibility may require additional debugging time.

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

## Change Log

**2025-11-30 (Story Updated - gaetanlepage reference patterns)**:
- Added gaetanlepage-dendritic-nix-config reference patterns for NVIDIA/CUDA configuration
- Updated GPU type from T4 to L4 (nvidia-l4, Ada Lovelace architecture) per user direction
- Updated machine type from n1-standard-4 to g2-standard-4 (optimized for L4)
- Added Task 2: Create dendritic nvidia module (flake.modules.nixos.nvidia)
- Added Task 2b: CUDA cache substituter (cache.nixos-cuda.org)
- Updated cost reference table with L4 pricing (~$0.37/hr total)
- Added 7 gaetanlepage file references to References section
- Updated Files to create: modules/nixos/nvidia.nix, modules/nixos/substituters.nix
- Renumbered tasks (now 7 tasks instead of 6)
- Estimated effort: 4-6 hours (unchanged)

**2025-11-30 (Story Drafted)**:
- Story file created adapting Epic 7 Story 7.4 specification
- All 11 acceptance criteria mapped to task groups
- GPU scaffolding context from gcp.nix documented
- NixOS NVIDIA configuration pattern researched and documented
- Cost reference table added with prominent warnings
- Learnings from Story 7.3 incorporated (zerotier patterns, deployment sequence)
- Naming theme documented (scheelite = tungsten ore)
- Estimated effort: 4-6 hours
