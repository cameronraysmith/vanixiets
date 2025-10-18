{
  flake,
  pkgs,
  lib,
  ...
}:

let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  nixpkgs = {
    config = {
      allowBroken = true;
      allowUnsupportedSystem = true;
      allowUnfree = true;
    };
    overlays = lib.attrValues self.overlays ++ [ inputs.lazyvim.overlays.nvim-treesitter-main ];
  };

  nix = {
    nixPath = [ "nixpkgs=${flake.inputs.nixpkgs}" ]; # Enables use of `nix-shell -p ...` etc
    registry.nixpkgs.flake = flake.inputs.nixpkgs; # Make `nix shell` etc use pinned nixpkgs

    # Automatic garbage collection
    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
    }
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      # Darwin-specific: use launchd interval
      interval = {
        Weekday = 0; # Sunday
        Hour = 2;
        Minute = 0;
      };
    }
    // lib.optionalAttrs pkgs.stdenv.isLinux {
      # NixOS-specific: use systemd dates
      dates = "weekly";
    };

    # Automatic store optimization via hardlinking
    optimise.automatic = true;

    settings = {
      accept-flake-config = true;
      build-users-group = lib.mkDefault "nixbld";
      experimental-features = "nix-command flakes auto-allocate-uids";
      extra-platforms = lib.mkIf pkgs.stdenv.isDarwin "aarch64-darwin x86_64-darwin";
      flake-registry = builtins.toFile "empty-flake-registry.json" ''{"flakes":[],"version":2}'';
      max-jobs = "auto";
      trusted-users = [
        "root"
        (if pkgs.stdenv.isDarwin then flake.config.me.username else "@wheel")
      ];

      # Space-based automatic GC (emergency backstop)
      min-free = lib.mkDefault (5 * 1024 * 1024 * 1024); # 5 GB
      max-free = lib.mkDefault (10 * 1024 * 1024 * 1024); # 10 GB

      # download-buffer-size = 1024 * 1024 * 500;
    };
  };
}
