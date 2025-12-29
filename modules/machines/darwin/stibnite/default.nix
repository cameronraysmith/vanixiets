{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  # Capture outer config for use in imports
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
  # Capture flake for extraSpecialArgs (needed by sops-nix)
  flakeForHomeManager = config.flake // {
    inherit inputs;
  };
in
{
  flake.modules.darwin."machines/darwin/stibnite" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # Make flake available to all darwin modules
      _module.args.flake = inputs.self;

      imports = [
        inputs.home-manager.darwinModules.home-manager
        inputs.srvos.darwinModules.server
        inputs.nix-rosetta-builder.darwinModules.default
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
        colima
        # Note: Not importing users module (defines testuser at UID 550)
        # stibnite defines its own user (crs58)
      ]);

      # Re-enable documentation for laptop use
      # Override both srvos and clan-core defaults
      srvos.server.docs.enable = lib.mkForce true;
      documentation.enable = lib.mkForce true;
      documentation.doc.enable = lib.mkForce true;
      documentation.info.enable = lib.mkForce true;
      documentation.man.enable = lib.mkForce true;
      programs.info.enable = lib.mkForce true;
      programs.man.enable = lib.mkForce true;

      # Host identification
      networking.hostName = "stibnite";
      networking.computerName = "stibnite";

      # Remote deployment target (enables `clan machines update` from other machines)
      clan.core.networking.targetHost = "crs58@stibnite.zt";

      # Platform
      nixpkgs.hostPlatform = "aarch64-darwin";

      # Allow unfree packages (required for copilot-language-server, etc.)
      nixpkgs.config.allowUnfree = true;

      # Use flake.overlays.default (drupol pattern)
      # All 5 overlay layers + pkgs-by-name packages exported from modules/nixpkgs.nix
      nixpkgs.overlays = [ inputs.self.overlays.default ];

      # System state version (matching vanixiets configuration)
      # Override base.nix which sets stateVersion = 5
      system.stateVersion = lib.mkForce 4;

      # Primary user for homebrew and system-level user operations
      # Note: crs58 is both admin and primary user on stibnite
      system.primaryUser = "crs58";

      # Enable desktop profile for GUI applications
      custom.profile.isDesktop = true;

      # Homebrew configuration
      # Base casks (40 apps) from modules/darwin/homebrew.nix
      # Machine-specific additions below
      custom.homebrew = {
        enable = true;

        # Machine-specific casks (stibnite-only)
        additionalCasks = [
          "codelayer-nightly"
          "dbeaver-community"
          # "docker-desktop" # defer to orbstack and colima/incus
          "gpg-suite"
          "inkscape"
          "keycastr"
          "meld"
          "postgres-unofficial"
          "zerotier-one"
        ];

        # Machine-specific brews (stibnite-only)
        additionalBrews = [
          "incus" # Incus client for Colima incus runtime (not available in nixpkgs)
        ];

        # Machine-specific Mac App Store apps
        additionalMasApps = {
          "save-to-raindrop-io" = 1549370672;
        };

        # Fonts managed via base homebrew module (manageFonts defaults to true)
      };

      # TouchID authentication for sudo
      security.pam.services.sudo_local.touchIdAuth = true;

      # SSH daemon configuration
      # Increase MaxAuthTries to accommodate agent forwarding with many keys
      # Default is 6, but Bitwarden SSH agent may have 10+ keys loaded
      # nix-darwin writes this to /etc/ssh/sshd_config.d/100-nix-darwin.conf
      services.openssh.extraConfig = ''
        MaxAuthTries 20
      '';

      # SSH client fix for nix-rosetta-builder
      # The nix-rosetta-builder module generates 100-rosetta-builder.conf without IdentitiesOnly
      # When Bitwarden SSH agent has many keys loaded, SSH tries all agent keys first and
      # hits "too many authentication failures" before trying the rosetta-builder identity file.
      # This config comes BEFORE (050 < 100) and adds IdentitiesOnly to fix the issue.
      environment.etc."ssh/ssh_config.d/050-rosetta-builder-identities.conf".text = ''
        Host "rosetta-builder"
          IdentitiesOnly yes
      '';

      # Single-user configuration
      # crs58: admin AND primary user (UID 501 - matches existing stibnite system)
      users.users.crs58 = {
        uid = 501;
        home = "/Users/crs58";
        shell = pkgs.zsh;
        description = "crs58";
        # SSH keys from shared identity module
        openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.crs58.sshKeys;
      };

      # Darwin requires explicit knownUsers
      # Note: Not managing root user (no users.users.root definition)
      users.knownUsers = [
        "crs58"
      ];

      # System packages
      environment.systemPackages = with pkgs; [
        vim
        git
      ];

      # Enable zsh system-wide
      programs.zsh.enable = true;

      # Disable native linux-builder (replaced by nix-rosetta-builder)
      # Bootstrap step 1 complete - see docs/notes/containers/multi-arch-container-builds.md
      nix.linux-builder.enable = false;

      # nix-rosetta-builder for cross-platform Linux builds on Apple Silicon
      # Provides x86_64-linux builder via Rosetta 2 translation
      nix-rosetta-builder = {
        enable = true;
        onDemand = true; # VM powers off when idle to save resources
        permitNonRootSshAccess = true; # Allow nix-daemon to read SSH key (safe for localhost-only VM)
        cores = 12;
        memory = "48GiB";
        diskSize = "500GiB";
      };

      # Colima for OCI container management (complementary to nix-rosetta-builder)
      services.colima = {
        enable = true;
        runtime = "incus";
        profile = "default";
        autoStart = false; # Manual control preferred
        cpu = 12;
        memory = 48;
        disk = 500;
        arch = "aarch64";
        vmType = "vz"; # macOS Virtualization.framework
        rosetta = true; # Rosetta 2 for x86_64 emulation
        mountType = "virtiofs"; # High-performance mount driver
        extraPackages = [ ];
      };

      # Home-Manager configuration
      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;

        # Backup existing files with this extension when home-manager needs to replace them
        backupFileExtension = "before-home-manager";

        # Pass flake as extraSpecialArgs for sops-nix access
        # Bridge from flake-parts layer to home-manager layer
        extraSpecialArgs = {
          flake = flakeForHomeManager;
        };

        # crs58 (admin + primary): Import portable home modules + base-sops
        users.crs58.imports = [
          flakeModulesHome."users/crs58"
          flakeModulesHome.base-sops
          # Import aggregate modules for crs58
          # All aggregates via auto-merge
          flakeModulesHome.ai
          flakeModulesHome.core
          flakeModulesHome.development
          flakeModulesHome.packages
          flakeModulesHome.shell
          flakeModulesHome.terminal
          flakeModulesHome.tools
          # LazyVim home-manager module
          inputs.lazyvim-nix.homeManagerModules.default
          # nix-index-database for comma command-not-found
          inputs.nix-index-database.homeModules.nix-index
          # agents-md option module (requires flake arg from extraSpecialArgs)
          ../../../home/modules/_agents-md.nix
          # Mac app integration (Spotlight, Launchpad)
          # Disabled: mac-app-util requires SBCL which has nixpkgs cache compatibility issues
          # inputs.mac-app-util.homeManagerModules.default
        ];
      };
    };
}
