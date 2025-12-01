# NixOS NVIDIA Module Deep Analysis for Datacenter ML Training

**Analysis Date**: 2025-12-01
**Source**: `/Users/crs58/projects/nix-workspace/nixpkgs/nixos/modules/hardware/video/nvidia.nix` (nixpkgs commit: Wed Nov 26 10:35:26 2025)
**Target Use Case**: Headless GCP ML training server (scheelite)
**Reference Pattern**: gaetanlepage desktop configuration

## Executive Summary

The NixOS NVIDIA module provides 28 distinct configuration options divided into 5 major categories.
For datacenter ML training, **8 options are directly relevant**, with 3 being **datacenter-critical**.
The module has two mutually exclusive modes: X11 mode (desktop/display) and datacenter mode (NVLink/multi-GPU).
Our target configuration should use datacenter mode where available but can safely use X11 mode for single-GPU scenarios.

## Complete Option Reference

### Category 1: Core Driver Configuration

#### hardware.nvidia.enabled
- **Type**: `bool` (read-only)
- **Default**: `true` if NVIDIA support is enabled
- **Datacenter Relevance**: NEUTRAL
- **Scheelite Recommendation**: Read-only, set automatically
- **Rationale**: Automatically determined by other options

#### hardware.nvidia.package
- **Type**: `package`
- **Default**: `config.boot.kernelPackages.nvidiaPackages."${if cfg.datacenter.enable then "dc" else "stable"}"`
- **Available Packages**:
  - `stable` (currently production 580.105.08)
  - `production` (same as stable)
  - `latest` (575.64.05)
  - `beta` (580.65.06)
  - `vulkan_beta` (580.94.11 - Vulkan developer beta)
  - `dc` / `dc_570` (570.172.08 - Data Center driver with fabricmanager)
  - `dc_565` (565.57.01 - Data Center driver)
  - `dc_535` (535.154.05 - Data Center driver)
  - `legacy_535` (535.274.02)
  - `legacy_470` (470.256.02 - Last Kepler support)
  - `legacy_390` (390.157 - Last x86 support)
  - `legacy_340` (340.108 - ancient, broken on kernel 6.7+)
- **Datacenter Relevance**: DATACENTER_CRITICAL
- **Scheelite Recommendation**: For single A100: `production` or `stable`. For multi-GPU NVLink: use `dc` (datacenter driver)
- **Rationale**: Production branch is well-tested. DC drivers required only for NVLink topologies. GCP A100 is single-GPU, so production driver is optimal.

#### hardware.nvidia.open
- **Type**: `bool | null`
- **Default**: `null` for driver >= 560, `false` for < 560
- **Datacenter Relevance**: DATACENTER_RECOMMENDED
- **Scheelite Recommendation**: `true` (A100 is Ampere architecture)
- **Rationale**: Open kernel modules mandatory for driver 560+. Recommended for Turing (RTX series, GTX 16xx) and newer (including Ampere A100). Better performance and support for modern GPUs.

#### hardware.nvidia.gsp.enable
- **Type**: `bool`
- **Default**: `true` if open modules OR driver >= 555
- **Datacenter Relevance**: DATACENTER_RECOMMENDED
- **Scheelite Recommendation**: `true` (default, auto-enabled with open modules)
- **Rationale**: GPU System Processor offloads driver tasks to GPU firmware. Mandatory with open modules. Improves performance and reduces CPU overhead.

### Category 2: Datacenter-Specific Options

#### hardware.nvidia.datacenter.enable
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DATACENTER_CRITICAL (for multi-GPU NVLink only)
- **Scheelite Recommendation**: `false` (single A100, no NVLink)
- **Rationale**: Enables fabricmanager for NVLink coordination across multi-GPU systems. Required for NVSwitch topologies. Not needed for single GPU. **Mutually exclusive with X11 mode** (services.xserver.videoDrivers containing "nvidia").

#### hardware.nvidia.datacenter.settings
- **Type**: `attrsOf str` (key-value settings)
- **Default**: Comprehensive fabricmanager defaults (see source lines 39-58)
- **Key Settings**:
  - `LOG_LEVEL` (default: 4)
  - `LOG_FILE_NAME` (default: "/var/log/fabricmanager.log")
  - `TOPOLOGY_FILE_PATH` (default: from fabricmanager package)
  - `FABRIC_MODE` (default: 0)
  - `ABORT_CUDA_JOBS_ON_FM_EXIT` (default: 1)
- **Datacenter Relevance**: DATACENTER_CRITICAL (only with datacenter.enable)
- **Scheelite Recommendation**: N/A (datacenter.enable is false)
- **Rationale**: Configures fabricmanager daemon for NVLink management. Only relevant for multi-GPU NVLink topologies.

#### hardware.nvidia.nvidiaPersistenced
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DATACENTER_CRITICAL
- **Scheelite Recommendation**: `true`
- **Rationale**: **Critical for headless servers**. Ensures GPU state persists without X11 running. Prevents GPU reinitialization overhead. Keeps GPU accessible for compute even when no processes are actively using it. Essential for ML training where jobs may start/stop frequently.

### Category 3: Power Management

#### hardware.nvidia.powerManagement.enable
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DATACENTER_AVOID
- **Scheelite Recommendation**: `false`
- **Rationale**: Experimental laptop-oriented power management via systemd (suspend/hibernate/resume hooks). Not relevant for always-on cloud VMs. May cause issues. Requires driver >= 430.09. Adds kernel parameter `nvidia.NVreg_PreserveVideoMemoryAllocations=1`.

#### hardware.nvidia.powerManagement.finegrained
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DATACENTER_AVOID
- **Scheelite Recommendation**: `false`
- **Rationale**: PCI-Express Runtime D3 power management for PRIME offload laptops. Turns off GPU when not in use. Incompatible with PRIME sync. Requires offload.enable. **Not applicable to datacenter**. Adds modprobe option `NVreg_DynamicPowerManagement=0x02`.

#### hardware.nvidia.dynamicBoost.enable
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`
- **Rationale**: Laptop feature for balancing CPU/GPU power via nvidia-powerd. Requires driver >= 510.39.01. Not applicable to datacenter.

### Category 4: Display/Graphics (Desktop-Only)

#### hardware.nvidia.modesetting.enable
- **Type**: `bool`
- **Default**: `true` for driver >= 535
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false` or default (doesn't matter, no X11)
- **Rationale**: Kernel modesetting for framebuffer device. Fixes screen tearing in Optimus. Enables Wayland compositors on driver >= 545. **Not needed for headless compute**. Adds kernel parameter `nvidia-drm.modeset=1` and `nvidia-drm.fbdev=1` (driver >= 545).

#### hardware.nvidia.forceFullCompositionPipeline
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`
- **Rationale**: Fixes screen tearing but reduces OpenGL performance and increases clock-down time. Display-only setting. Not applicable to headless.

#### hardware.nvidia.nvidiaSettings
- **Type**: `bool`
- **Default**: `true`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`
- **Rationale**: nvidia-settings GUI configuration tool. No value on headless server.

#### hardware.nvidia.videoAcceleration
- **Type**: `bool`
- **Default**: `true`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`
- **Rationale**: VA-API video decoding/encoding. For video playback/streaming, not compute. Adds nvidia-vaapi-driver package.

### Category 5: PRIME (Laptop Multi-GPU)

All PRIME options are **DESKTOP_ONLY** and not applicable to datacenter single-GPU scenarios:

#### hardware.nvidia.prime.nvidiaBusId
- **Type**: `str` (bus ID format)
- **Default**: `""`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: Not used
- **Rationale**: For laptop hybrid graphics (Intel/AMD iGPU + NVIDIA dGPU). Not applicable to datacenter.

#### hardware.nvidia.prime.intelBusId
- **Type**: `str` (bus ID format)
- **Default**: `""`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: Not used

#### hardware.nvidia.prime.amdgpuBusId
- **Type**: `str` (bus ID format)
- **Default**: `""`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: Not used

#### hardware.nvidia.prime.sync.enable
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`
- **Rationale**: PRIME sync for always-on dGPU rendering with iGPU displays. Requires X11.

#### hardware.nvidia.prime.offload.enable
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`
- **Rationale**: PRIME offload for selective dGPU use. Requires X11.

#### hardware.nvidia.prime.offload.enableOffloadCmd
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`

#### hardware.nvidia.prime.offload.offloadCmdMainProgram
- **Type**: `str`
- **Default**: `"nvidia-offload"`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: Not used

#### hardware.nvidia.prime.reverseSync.enable
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`

#### hardware.nvidia.prime.reverseSync.setupCommands.enable
- **Type**: `bool`
- **Default**: `true`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: Not used

#### hardware.nvidia.prime.allowExternalGpu
- **Type**: `bool`
- **Default**: `false`
- **Datacenter Relevance**: DESKTOP_ONLY
- **Scheelite Recommendation**: `false`

## Options Comparison: gaetanlepage vs Scheelite

| Option | gaetanlepage Value | Scheelite Recommended | Rationale for Difference |
|--------|-------------------|----------------------|--------------------------|
| `package` | `latest` | `stable`/`production` | Desktop can use bleeding edge; datacenter needs stability |
| `modesetting.enable` | `true` (default) | `false` or N/A | gaetanlepage uses Sway (Wayland); scheelite is headless |
| `powerManagement.enable` | `false` | `false` | Correct for both (no suspend/hibernate) |
| `powerManagement.finegrained` | `false` | `false` | Correct for both (not PRIME offload) |
| `open` | `true` | `true` | Both use modern GPUs (Turing+/Ampere) |
| `nvidiaSettings` | `true` | `false` | GUI useful for desktop; wasteful for headless |
| `nvidiaPersistenced` | Not set (false) | **`true`** | **Critical gap**: gaetanlepage has X11 keeping GPU alive; scheelite needs daemon |
| `videoAcceleration` | `true` (default) | `false` | Video decode useful for desktop; not for compute |
| `datacenter.enable` | Not set (false) | `false` | Correct for both (single GPU, no NVLink) |

### Critical Finding: nvidiaPersistenced

**gaetanlepage omits `nvidiaPersistenced` because X11 keeps GPU initialized.**
Without X11, headless servers **must** enable `nvidiaPersistenced` to:
- Prevent GPU state loss between compute jobs
- Reduce reinitialization latency (significant for large GPUs)
- Ensure CUDA applications can always access GPU
- Avoid race conditions in job scheduling

## Datacenter-Optimal Configuration for Scheelite

```nix
hardware.nvidia = {
  # Core driver - production stability for ML training
  package = config.boot.kernelPackages.nvidiaPackages.production;

  # Open kernel modules - recommended for Ampere A100
  open = true;

  # GPU System Processor - auto-enabled with open modules, improves performance
  gsp.enable = true;

  # CRITICAL: Persistence daemon for headless operation
  # Keeps GPU initialized without X11, essential for compute workloads
  nvidiaPersistenced = true;

  # Disable all desktop/display features
  nvidiaSettings = false;          # No GUI needed
  videoAcceleration = false;       # No video decode/encode needed
  modesetting.enable = false;      # No display output needed

  # Disable power management (cloud VM, always-on)
  powerManagement.enable = false;
  powerManagement.finegrained = false;
  dynamicBoost.enable = false;

  # No PRIME (single GPU, no hybrid graphics)
  prime = {};  # All defaults (empty)

  # No datacenter mode (single GPU, no NVLink)
  datacenter.enable = false;

  # No composition pipeline forcing (display-only)
  forceFullCompositionPipeline = false;
};

# Enable CUDA support in nixpkgs
nixpkgs.config.cudaSupport = true;

# Not needed (only required when datacenter.enable = false AND NOT using xserver videoDrivers)
# services.xserver.videoDrivers = [ "nvidia" ];
```

## Additional System Configuration

### Kernel Parameters (Set Automatically)

The module automatically adds kernel parameters based on configuration:

```nix
boot.kernelParams = [
  # Added when open = true
  "nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"

  # Added when modesetting.enable OR offload.enable (not applicable to scheelite)
  # "nvidia-drm.modeset=1"
  # "nvidia-drm.fbdev=1"  # driver >= 545

  # Added when powerManagement.enable (not applicable to scheelite)
  # "nvidia.NVreg_PreserveVideoMemoryAllocations=1"

  # Added when kernel >= 6.2 AND NOT ibtSupport
  # "ibt=off"
];
```

### Kernel Modules (Loaded Automatically)

```nix
boot = {
  # Blacklisted automatically
  blacklistedKernelModules = [ "nouveau" "nvidiafb" ];

  # Loaded automatically for open modules (to fix CUDA softdep issue)
  kernelModules = [ "nvidia_uvm" ];  # when open = true

  # Loaded automatically when xserver enabled (not our case)
  # kernelModules = [ "nvidia" "nvidia_modeset" "nvidia_drm" ];

  # Extramodprobeconfig set automatically
  extraModprobeConfig = ''
    softdep nvidia post: nvidia-uvm  # Lazy load nvidia-uvm after nvidia
  '';
};
```

### Systemd Services (Created Automatically)

When `nvidiaPersistenced = true`:

```nix
systemd.services.nvidia-persistenced = {
  description = "NVIDIA Persistence Daemon";
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "forking";
    Restart = "always";
    PIDFile = "/var/run/nvidia-persistenced/nvidia-persistenced.pid";
    ExecStart = "${nvidia_x11.persistenced}/bin/nvidia-persistenced --verbose";
    ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-persistenced";
  };
};
```

### Environment Packages (Added Automatically)

```nix
environment.systemPackages = [
  nvidia_x11.bin  # nvidia-smi, nvidia-debugdump, etc.
  # nvidia_x11.persistenced  # added when nvidiaPersistenced = true
];

hardware.graphics = {
  extraPackages = [ nvidia_x11.out ];
  extraPackages32 = [ nvidia_x11.lib32 ];  # if not disable32Bit
};
```

## Options to Explicitly AVOID

| Option | Reason |
|--------|--------|
| `powerManagement.enable` | Experimental, laptop-oriented, causes suspend/resume hooks on cloud VM |
| `powerManagement.finegrained` | PRIME offload specific, not applicable to datacenter |
| `dynamicBoost.enable` | Laptop CPU/GPU power balancing, not applicable |
| `modesetting.enable` | Display/framebuffer feature, overhead for headless |
| `nvidiaSettings` | GUI tool, wasteful package for headless |
| `videoAcceleration` | VA-API for video, not compute |
| `forceFullCompositionPipeline` | Display tearing fix, reduces performance |
| `datacenter.enable` | Only for multi-GPU NVLink topologies |
| All `prime.*` options | Laptop hybrid graphics, not single GPU datacenter |

## Datacenter-Specific Deep Dive

### nvidia-persistenced

**What It Does**:
- Keeps NVIDIA kernel modules loaded and GPU initialized
- Maintains device nodes in `/dev/nvidia*`
- Prevents reinitialization overhead when compute jobs start/stop
- Essential for headless operation without X11

**Configuration**:
- Enabled via `hardware.nvidia.nvidiaPersistenced = true`
- No tuning options exposed in NixOS (runs with `--verbose`)
- Creates `/var/run/nvidia-persistenced/nvidia-persistenced.pid`
- Systemd service with `Type=forking`, `Restart=always`

**Headless Implications**:
- **Without persistenced + without X11**: GPU state is lost when no CUDA processes run
- **With persistenced**: GPU always available, ~100ms saved per job launch
- **Critical for ML training**: Jobs may pause between batches or epochs

### Datacenter Driver vs Production Driver

**Datacenter Drivers** (`dc`, `dc_570`, `dc_565`, `dc_535`):
- Include fabricmanager for NVLink coordination
- Required for multi-GPU NVSwitch topologies (DGX systems)
- No nvidia-settings included (`useSettings = false`)
- Optimized for compute workloads
- Downloaded from `https://us.download.nvidia.com/tesla/`

**Production/Stable Drivers**:
- Standard GeForce/Quadro/Tesla unified driver
- Include nvidia-settings
- Support single GPU compute
- More frequent updates and broader hardware support

**For Single A100**: Production driver is **equivalent** for compute. Datacenter driver only adds value for NVLink.

### Open vs Proprietary Kernel Modules

**Open Modules** (`open = true`):
- Mandatory for driver >= 560
- Recommended for Turing (GTX 16xx, RTX series) and newer
- Better performance on modern architectures
- Requires GSP (GPU System Processor) firmware
- MIT licensed (open source)
- Better upstream kernel integration
- Requires `nvidia_uvm` module loaded eagerly (NixOS handles this)

**Proprietary Modules** (`open = false`):
- Required for pre-Turing (Maxwell, Pascal, Kepler)
- Proprietary license
- Less performant on Turing+
- No source code available

**For A100 (Ampere)**: Open modules are strongly recommended.

### Compute Mode Configuration

**Not Exposed in NixOS Module**. Must be configured via `nvidia-smi`:

```bash
# Set compute-only mode (no display)
nvidia-smi -c 3  # EXCLUSIVE_PROCESS mode

# Set application clocks (fix frequency for consistent training)
nvidia-smi -ac <memory_clock>,<graphics_clock>

# Enable persistence mode (alternative to persistenced daemon)
nvidia-smi -pm 1

# Enable ECC memory (if supported by hardware)
nvidia-smi -e 1
```

These settings can be applied via systemd service or startup script.

### Multi-GPU / NVLink

**For NVLink topologies**:
- Enable `hardware.nvidia.datacenter.enable = true`
- Automatically enables fabricmanager service
- Configures NVSwitch communication
- Requires datacenter driver (`dc` package)

**For multi-GPU without NVLink** (PCIe topology like GCP):
- No special configuration needed
- Use standard driver
- CUDA/NCCL handle PCIe communication
- nvidia-persistenced still recommended

**Scheelite (single A100)**: No multi-GPU configuration needed.

### Container/Kubernetes Integration

**nvidia-container-toolkit** (separate module):
- Path: `/Users/crs58/projects/nix-workspace/nixpkgs/nixos/modules/services/hardware/nvidia-container-toolkit/default.nix`
- Enable via `hardware.nvidia-container-toolkit.enable = true`
- Provides CDI (Container Device Interface) configuration
- Auto-generates CDI specs for Docker/Podman
- Mounts GPU devices and libraries into containers
- Requires `hardware.nvidia.datacenter.enable` OR `services.xserver.videoDrivers = ["nvidia"]`

**For future container workloads**:
```nix
hardware.nvidia-container-toolkit = {
  enable = true;
  device-name-strategy = "index";  # or "uuid", "type-index"
  discovery-mode = "auto";         # or "nvml", "csv", "wsl"
  mount-nvidia-executables = true; # nvidia-smi in containers
};
```

## Missing Capabilities (Not Exposed via NixOS)

### 1. GPU Application Clocks

**Need**: Fix GPU frequency for consistent ML training performance.

**Solution**: Manual nvidia-smi configuration or systemd service:

```nix
systemd.services.nvidia-application-clocks = {
  description = "Set NVIDIA Application Clocks";
  after = [ "nvidia-persistenced.service" ];
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "${pkgs.linuxPackages.nvidia_x11}/bin/nvidia-smi -ac 1215,1410";  # A100 clocks
  };
};
```

### 2. ECC Memory

**Need**: Error-correcting code memory for reliability in long training runs.

**Solution**: Enable via nvidia-smi (if hardware supports):

```bash
nvidia-smi -e 1
```

A100 supports ECC, should be enabled by default.

### 3. Compute Mode (Exclusive Process)

**Need**: Prevent multiple processes from competing for GPU.

**Solution**: nvidia-smi configuration:

```bash
nvidia-smi -c 3  # EXCLUSIVE_PROCESS
```

### 4. MIG (Multi-Instance GPU)

**Need**: Partition A100 into smaller GPU instances.

**Solution**: Not commonly used for ML training (reduces memory bandwidth). Configure via nvidia-smi if needed:

```bash
nvidia-smi mig -cgi <GPU instance profile>
```

### 5. GPU Power Limits

**Need**: Reduce power consumption or prevent thermal throttling.

**Solution**: nvidia-smi power limit:

```bash
nvidia-smi -pl <watts>  # e.g., 300W for A100 (default 400W)
```

## Source Code Insights

### 1. X11 vs Datacenter Mode Mutual Exclusion

Lines 338-341 show assertion:
```nix
assertion = !(nvidiaEnabled && cfg.datacenter.enable);
message = "You cannot configure both X11 and Data Center drivers at the same time.";
```

**Implication**: Must choose between display support and datacenter features. For headless ML, stay in X11 mode (default) unless you need NVLink.

### 2. Open Module nvidia_uvm Loading Strategy

Lines 367-373 show critical fix:
```nix
# Exception is the open-source kernel module failing to load nvidia-uvm using softdep
# for unknown reasons.
# It affects CUDA: https://github.com/NixOS/nixpkgs/issues/334180
# We are now loading the module eagerly for all users of the open driver (including headless).
kernelModules = lib.optionals useOpenModules [ "nvidia_uvm" ];
```

**Implication**: Open modules require `nvidia_uvm` loaded eagerly. NixOS handles this automatically. Don't use `boot.kernelModules` manually.

### 3. Package Selection Logic

Lines 286-290:
```nix
default = config.boot.kernelPackages.nvidiaPackages."${if cfg.datacenter.enable then "dc" else "stable"}";
```

**Implication**: datacenter.enable automatically switches to DC driver. For single GPU, use stable/production driver explicitly.

### 4. Persistence Daemon Implementation

Lines 609-621 (X11 mode) and 740-751 (datacenter mode) show identical service definitions:
```nix
"nvidia-persistenced" = {
  description = "NVIDIA Persistence Daemon";
  wantedBy = [ "multi-user.target" ];
  serviceConfig = {
    Type = "forking";
    Restart = "always";
    PIDFile = "/var/run/nvidia-persistenced/nvidia-persistenced.pid";
    ExecStart = "${lib.getExe nvidia_x11.persistenced} --verbose";
    ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/nvidia-persistenced";
  };
};
```

**Implication**: persistenced works identically in both modes. Always restart on failure. Use verbose logging.

### 5. GSP Firmware Requirement

Lines 307-316:
```nix
gsp.enable = lib.mkEnableOption ''
  the GPU System Processor (GSP) on the video card
'' // {
  default = useOpenModules || lib.versionAtLeast nvidia_x11.version "555";
};
```

**Implication**: GSP auto-enabled for open modules or driver >= 555. Modern feature, improves performance by offloading to GPU firmware.

## Uncertainties and Recommendations

### 1. What Couldn't Be Determined from Source

- **Optimal driver version for A100 ML training**: Source shows stable/production/latest but not performance characteristics
- **ECC memory default state**: Whether A100 boots with ECC enabled
- **Application clock defaults**: What frequencies A100 runs at without manual configuration
- **MIG configuration**: Whether MIG should be disabled for full-GPU ML training
- **PCIe link speed**: Whether GCP A100 negotiates Gen4 x16 or needs tuning

### 2. What Needs Runtime Testing

- **Open module performance on A100**: Verify open modules provide equal/better performance vs proprietary
- **Persistence daemon impact**: Measure job launch latency with/without persistenced
- **Driver stability**: Test production vs latest driver for multi-day training runs
- **Memory bandwidth**: Verify ECC doesn't significantly reduce training throughput
- **NCCL communication**: If adding second GPU later, test PCIe NCCL performance

### 3. Recommendations for Further Investigation

1. **Web research**: NVIDIA A100 recommended driver versions for ML frameworks (PyTorch/JAX)
2. **GCP documentation**: A100 VM GPU configuration, PCIe topology, MIG support
3. **Benchmark**: Open vs proprietary kernel modules on A100 compute workloads
4. **Monitor**: nvidia-smi dmon during training for clock frequencies, power, temperature
5. **Test**: persistenced impact on CUDA job launch latency

### 4. Open Questions

- **Should we enable hardware.graphics on headless server?** (Required for OpenGL compute, not pure CUDA)
- **Does scheelite need 32-bit NVIDIA libraries?** (likely not, but module enables by default)
- **Should we pin driver version for reproducibility?** (vs tracking stable branch)
- **Do we need nvidia-smi in systemPackages explicitly?** (added automatically via nvidia_x11.bin)

## Integration with Parallel Web Research

This source code analysis should be merged with web research covering:

1. **NVIDIA official recommendations**: A100 driver versions for datacenter ML
2. **ML framework requirements**: PyTorch/JAX CUDA version compatibility
3. **GCP-specific tuning**: A100 VM optimization guides
4. **Community best practices**: Reddit/GitHub discussions on A100 NixOS configurations
5. **Performance benchmarks**: Open vs proprietary modules on Ampere

Combined analysis will inform final Story 7.4 guidance document.

## Validation Against test-clan

The test-clan repository (`~/projects/nix-workspace/test-clan/`) should be consulted for:

- Validated dendritic + clan patterns for GPU servers
- Real-world systemd service configurations
- Terraform integration for GCP GPU VMs
- Secrets management for cloud API keys

Any patterns validated in test-clan take precedence over theoretical source analysis.

## References

- **Primary Source**: `/Users/crs58/projects/nix-workspace/nixpkgs/nixos/modules/hardware/video/nvidia.nix`
- **Driver Packages**: `/Users/crs58/projects/nix-workspace/nixpkgs/pkgs/os-specific/linux/nvidia-x11/default.nix`
- **Container Toolkit**: `/Users/crs58/projects/nix-workspace/nixpkgs/nixos/modules/services/hardware/nvidia-container-toolkit/default.nix`
- **Reference Desktop Config**: `/Users/crs58/projects/nix-workspace/gaetanlepage-dendritic-nix-config/modules/nixos/nvidia.nix`
- **NVIDIA Docs**: Chapter 21 (Power Management), Chapter 22 (RTD3), Chapter 23 (Dynamic Boost)
- **NixPkgs Issues**: #334180 (nvidia-uvm loading), #267335 (Azure GPU instances)
