# Datacenter-optimized NVIDIA configuration for headless ML servers
# Target: GCP T4/L4 GPU nodes (scheelite) for JAX/PyTorch training/inference
#
# CRITICAL NOTES:
# - DO NOT enable datacenter.enable (Bug #454772 - GSP firmware missing)
# - nvidiaPersistenced is MANDATORY for headless servers
# - This module is for COMPUTE ONLY, not desktop/display
# - DO NOT set nixpkgs.config.cudaSupport = true (causes mass rebuild of ALL packages)
#
# Reference: docs/notes/development/nvidia-module-analysis.md
{
  flake.modules.nixos.nvidia =
    { config, pkgs, ... }:
    {
      # Allow unfree packages (required for NVIDIA proprietary drivers)
      nixpkgs.config.allowUnfree = true;

      # IMPORTANT: We do NOT set nixpkgs.config.cudaSupport = true globally.
      # That would change derivation hashes for ALL packages, causing mass rebuilds
      # since cache.nixos.org doesn't build with cudaSupport enabled (unfree).
      #
      # Instead, enable CUDA support only for specific ML packages via overlays.
      # This preserves cache hits for system packages (nix, nixd, etc.)
      nixpkgs.overlays = [
        (final: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (python-final: python-prev: {
              # PyTorch with CUDA support
              torch = python-prev.torch.override {
                cudaSupport = true;
                triton = python-prev.triton-cuda;
                rocmSupport = false;
              };

              # JAX with CUDA support
              jax = python-prev.jax.override {
                cudaSupport = true;
              };

              jaxlib = python-prev.jaxlib.override {
                cudaSupport = true;
              };

              # Additional ML packages can be added here as needed:
              # tensorflow = python-prev.tensorflow.override { cudaSupport = true; };
              # numba = python-prev.numba.override { cudaSupport = true; };
            })
          ];
        })
      ];

      # Enable graphics infrastructure (required even for headless compute)
      # Provides OpenGL/Vulkan compute APIs and /run/opengl-driver paths
      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = false; # No 32-bit support needed for server

      # NVIDIA drivers via X11 videoDrivers path
      # NOTE: datacenter.enable has Bug #454772 (GSP firmware missing)
      # Using standard driver path works correctly for L4/T4/A100 compute
      services.xserver.videoDrivers = [ "nvidia" ];

      # Disable X11 display server (headless compute)
      services.xserver.enable = false;

      # NVIDIA hardware configuration - DATACENTER OPTIMIZED
      hardware.nvidia = {
        # Driver package: use production for stability
        # For L4 (Ada Lovelace): production or stable recommended
        # Avoids bleeding-edge issues in training workloads
        package = config.boot.kernelPackages.nvidiaPackages.production;

        # Open-source kernel modules (RECOMMENDED for L4/Ada Lovelace)
        # Mandatory for driver >= 560, recommended for Turing+ (including Ampere)
        # Better performance and support for modern architectures
        open = true;

        # CRITICAL: Enable persistence daemon for headless servers
        # Keeps GPU initialized between compute jobs
        # Without this: ~100ms+ GPU reinitialization latency per CUDA job launch
        # With this: GPU stays initialized, near-instant job startup
        nvidiaPersistenced = true;

        # DISABLE: Desktop-only features not needed for compute servers
        nvidiaSettings = false; # GUI configuration tool
        modesetting.enable = false; # Display/framebuffer (adds overhead)

        # DISABLE: Power management (experimental, laptop-oriented)
        # Cloud VMs are always-on, no suspend/hibernate needed
        powerManagement.enable = false;
        powerManagement.finegrained = false;
      };

      # Enable CUDA sandbox support for nix builds
      # Allows CUDA packages to access GPU during sandboxed nix builds
      programs.nix-required-mounts = {
        enable = true;
        presets.nvidia-gpu.enable = true;
      };

      # GPU monitoring and debugging tools
      environment.systemPackages = with pkgs; [
        nvtopPackages.nvidia # htop-like GPU monitor (better than nvidia-smi for monitoring)
        pciutils # lspci for debugging GPU detection
      ];

      # Environment variables for ML frameworks (JAX/PyTorch)
      # These help CUDA libraries find the correct paths on NixOS
      environment.variables = {
        # CUDA library path (set by videoDrivers, but explicit for clarity)
        LD_LIBRARY_PATH = "/run/opengl-driver/lib";
      };
    };
}
