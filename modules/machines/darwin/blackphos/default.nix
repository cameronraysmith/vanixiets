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
  flake.modules.darwin."machines/darwin/blackphos" =
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
      ]
      ++ (with flakeModules; [
        base
        ssh-known-hosts
        # Note: Not importing users module (defines testuser at UID 550)
        # blackphos defines its own users (crs58 + raquel)
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

      networking.hostName = "blackphos";
      networking.computerName = "blackphos";

      # Remote deployment target (enables `clan machines update` from stibnite)
      clan.core.networking.targetHost = "crs58@blackphos.zt";

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
      # Note: crs58 is the admin user on blackphos
      system.primaryUser = "crs58";

      custom.profile.isDesktop = true;

      # Base casks from modules/darwin/homebrew.nix; machine-specific additions below
      custom.homebrew = {
        enable = true;

        # Machine-specific casks (blackphos-only)
        additionalCasks = [
          "codelayer-nightly"
          "dbeaver-community"
          "docker-desktop"
          "gpg-suite"
          "inkscape"
          "keycastr"
          "meld"
          "postgres-unofficial"
          "zerotier-one"
        ];

        # Machine-specific Mac App Store apps
        additionalMasApps = {
          "save-to-raindrop-io" = 1549370672;
        };

        # Fonts managed via base homebrew module (manageFonts defaults to true)
      };

      security.pam.services.sudo_local.touchIdAuth = true;

      # SSH daemon configuration
      # Increase MaxAuthTries to accommodate agent forwarding with many keys
      # Default is 6, but Bitwarden SSH agent may have 10+ keys loaded
      # nix-darwin writes this to /etc/ssh/sshd_config.d/100-nix-darwin.conf
      services.openssh.extraConfig = ''
        MaxAuthTries 20
      '';

      # crs58: admin (UID 502), raquel: primary (UID 506) - matches existing system
      users.users.crs58 = {
        uid = 502;
        home = "/Users/crs58";
        shell = pkgs.zsh;
        description = "crs58";
        openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.crs58.sshKeys;
      };

      users.users.raquel = {
        uid = 506;
        home = "/Users/raquel";
        shell = pkgs.zsh;
        description = "raquel";
        openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.raquel.sshKeys;
      };

      # Darwin requires explicit knownUsers
      # Note: Not managing root user (no users.users.root definition)
      users.knownUsers = [
        "crs58"
        "raquel"
      ];

      environment.systemPackages = with pkgs; [
        vim
        git
      ];

      programs.zsh.enable = true;

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

        # crs58 (admin): Import portable home modules + base-sops
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

        # raquel (primary user): Import portable home modules + base-sops
        users.raquel.imports = [
          flakeModulesHome."users/raquel"
          flakeModulesHome.base-sops
          # Import aggregate modules for raquel
          # All aggregates except ai
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
