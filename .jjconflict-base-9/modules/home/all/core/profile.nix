# Cross-platform profile detection
# Inspired by: /Users/crs58/projects/nix-workspace/mirkolenz-nixos/common/profile.nix
args@{
  lib,
  config,
  ...
}:
let
  cfg = config.custom.profile;
  osConfig = args.osConfig or { };
in
{
  options.custom.profile = {
    isDesktop = lib.mkEnableOption "desktop (non-headless system with GUI)" // {
      description = "Whether this is a desktop system with GUI capabilities";
    };

    isServer = lib.mkEnableOption "server" // {
      description = "Whether this is a server system";
    };

    isWorkstation = lib.mkEnableOption "workstation" // {
      default = cfg.isDesktop;
      description = "Whether this is a workstation (typically same as isDesktop)";
    };

    isHeadless = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      description = "Computed: true if server or not desktop";
    };
  };

  config.custom.profile = {
    isHeadless = !cfg.isDesktop || cfg.isServer;
  }
  // (osConfig.custom.profile or { });
}
