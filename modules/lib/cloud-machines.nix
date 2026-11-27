# Cloud machine definitions, read by the terranix modules that provision them
# (modules/terranix/hetzner.nix, modules/terranix/gcp.nix) and, through
# flake.fleet.hosts.<name>.cloud (modules/lib/hosts.nix), by
# flake.lib.fleetDeployer, which deploys only machines whose `enabled` is true.
# flake.lib.cloudMachineMemoryGiB gives each machine type's memory, from which
# a cloud host's memoryGiB follows.
#
# Set enabled = true to deploy, false to destroy.
# Run: nix run .#terraform (regenerates config and applies)
{
  flake.lib.cloudMachineMemoryGiB = {
    cx43 = 16;
    ccx23 = 16;
    cx53 = 32;
    "e2-standard-8" = 32;
    "n1-standard-8" = 30;
  };

  flake.lib.cloudMachines = {
    hetzner = {
      cinnabar = {
        enabled = true; # Primary VPS, zerotier controller (CX43: BIOS + GRUB)
        serverType = "cx43";
        location = "fsn1";
        image = "debian-12";
        comment = "8 vCPU, 16GB RAM, 160GB SSD, legacy BIOS";
      };
      electrum = {
        enabled = false; # Secondary test VM, zerotier peer (CCX23: UEFI + systemd-boot)
        serverType = "ccx23";
        location = "fsn1";
        image = "debian-12";
        comment = "4 vCPU, 16GB RAM, 160GB SSD, native UEFI";
      };
      magnetite = {
        enabled = true; # Build infrastructure server (CX53: BIOS + GRUB)
        serverType = "cx53";
        location = "fsn1";
        image = "debian-12";
        comment = "16 vCPU, 32GB RAM, 320GB SSD, legacy BIOS";
      };
    };

    # COST REFERENCE TABLE:
    # =========================================
    # | Machine     | Type          | GPU       | Hourly  | Monthly (730h) |
    # |-------------|---------------|-----------|---------|----------------|
    # | galena      | e2-standard-8 | None      | ~$0.27  | ~$197          |
    # | scheelite   | n1-standard-8 | 1x T4     | ~$0.54  | ~$394          |
    # | scheelite-l4| g2-standard-4 | 1x L4     | ~$0.37  | ~$270          |
    # | (new)       | a2-highgpu-1g | 1x A100   | ~$3.14  | ~$2,292        |
    # =========================================
    gcp = {
      galena = {
        enabled = false;
        machineType = "e2-standard-8"; # 8 vCPU, 32GB RAM
        zone = "us-central1-b";
        image = "debian-12";
        comment = "CPU-only GCP node (~$0.27/hr) - named for lead ore mineral";
      };

      scheelite = {
        enabled = false;
        machineType = "n1-standard-8"; # 8 vCPU, 30GB RAM
        zone = "us-central1-f"; # Try: a -> b -> c -> f if RESOURCE_EXHAUSTED
        image = "debian-12";
        gpuType = "nvidia-tesla-t4"; # Turing architecture, 16GB VRAM
        gpuCount = 1;
        comment = "T4 GPU node for ML training/inference (~$0.35/hr GPU + ~$0.19/hr base)";
      };

      # scheelite-l4 = {
      #   enabled = false;
      #   machineType = "g2-standard-4"; # 4 vCPU, 16GB RAM, optimized for L4
      #   zone = "us-central1-a";
      #   image = "debian-12";
      #   gpuType = "nvidia-l4"; # Ada Lovelace, 24GB VRAM, ~30% faster than T4
      #   gpuCount = 1;
      #   comment = "L4 GPU node (~$0.24/hr GPU + ~$0.13/hr base)";
      # };
    };
  };
}
