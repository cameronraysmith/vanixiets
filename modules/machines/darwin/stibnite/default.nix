{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.darwin;
  flakeModulesHome = config.flake.modules.homeManager;
  # sops-nix requires flake in extraSpecialArgs
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
      _module.args.flake = inputs.self;

      imports = [
        inputs.home-manager.darwinModules.home-manager
        inputs.srvos.darwinModules.server
        inputs.nix-rosetta-builder.darwinModules.default
      ]
      ++ (with flakeModules; [
        base
        ssh-ca-trust
        ssh-known-hosts
        beads-ui
        colima
        dnscrypt-proxy
        zt-dns
        zt-services-trust
        dolt-sql-server
        # Not importing users module (defines testuser at UID 550)
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

      networking.hostName = "stibnite";
      networking.computerName = "stibnite";

      # Remote deployment target (enables `clan machines update` from other machines)
      clan.core.networking.targetHost = "crs58@stibnite.zt";

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
      # crs58 is both admin and primary user on stibnite
      system.primaryUser = "crs58";

      custom.profile.isDesktop = true;

      # Base casks from modules/darwin/homebrew.nix; machine-specific additions below
      custom.homebrew = {
        enable = true;

        additionalCasks = [
          "codelayer-nightly"
          "dbeaver-community"
          # "docker-desktop" # defer to orbstack and colima/incus
          "gitbutler"
          "gpg-suite"
          "inkscape"
          "keycastr"
          "meld"
          "postgres-unofficial"
          "steipete/tap/codexbar"
          "zerotier-one"
        ];

        additionalBrews = [
          "incus" # Incus client for Colima incus runtime (not available in nixpkgs)
        ];

        # Machine-specific Mac App Store apps
        additionalMasApps = {
          "save-to-raindrop-io" = 1549370672;
        };

        # Fonts managed via base homebrew module (manageFonts defaults to true)
      };

      security.pam.services.sudo_local.touchIdAuth = true;

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
        openssh.authorizedKeys.keys = inputs.self.lib.userIdentities.crs58.sshKeys;
      };

      # Darwin requires explicit knownUsers
      # Not managing root user (no users.users.root definition)
      users.knownUsers = [
        "crs58"
      ];

      environment.systemPackages = with pkgs; [
        vim
        git
      ];

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
        nestedVirtualization = true; # Required for incus VMs (KVM), needs M3/M4 + macOS 15+
        mountType = "virtiofs"; # High-performance mount driver
        extraPackages = [ ];

        # Port forwards for k3s clusters (see ADR-004)
        portForwards = {
          k3s-dev = {
            ip = "192.100.0.10";
            apiPort = 6443;
            httpPort = 8080;
            httpsPort = 8443;
            sshPort = 2210;
          };
        };
      };

      # Encrypted DNS via DNS-over-HTTPS (DoH)
      # Routes all DNS through Quad9+Cloudflare DoH, bypassing enterprise DNS interception
      # DoH uses HTTPS (port 443), invisible to Cisco/enterprise DNS proxies
      # Rollback: sudo /nix/var/nix/profiles/system-N-link/activate (N = previous gen)
      services.localDnscryptProxy = {
        enable = true;
        providers = [
          "quad9"
          # "cloudflare"
        ];
        userHome = "/private/var/lib/dnscrypt-proxy";
      };

      # Trust local k8s development CA for curl/git/OpenSSL tools
      # Certificate is public (committed to git), private key is sops-encrypted
      security.pki.certificateFiles = [
        ../../../../kubernetes/clusters/local/pki/root_ca.crt
      ];

      # Trust local k8s development CA in macOS Keychain (for browsers)
      # Uses security add-trusted-cert which requires the cert to already be in keychain
      # or adds it with trust settings
      system.activationScripts.postActivation.text = ''
        echo "Adding local k8s development CA to macOS Keychain..."
        CERT_PATH="${../../../../kubernetes/clusters/local/pki/root_ca.crt}"
        CERT_NAME="Local Development Root CA"

        # Check if cert already exists in System keychain
        if ! /usr/bin/security find-certificate -c "$CERT_NAME" /Library/Keychains/System.keychain >/dev/null 2>&1; then
          echo "Installing $CERT_NAME to System keychain..."
          /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_PATH"
        else
          echo "$CERT_NAME already installed in System keychain"
        fi
      '';

      # Dolt SQL server for beads issue tracking
      services.dolt-sql-server.enable = true;

      # Beads UI web interface (localhost-only)
      services.beads-ui.enable = true;

      services.zt-services-trust.enable = true;

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;

        backupFileExtension = "before-home-manager";

        # Pass flake as extraSpecialArgs for sops-nix access
        extraSpecialArgs = {
          flake = flakeForHomeManager;
        };

        # crs58 (admin + primary): Import portable home modules + base-sops
        users.crs58 = {
          imports = [
            flakeModulesHome."users/crs58"
            flakeModulesHome.base-sops
            flakeModulesHome.ai
            flakeModulesHome.core
            flakeModulesHome.development
            flakeModulesHome.packages
            flakeModulesHome.shell
            flakeModulesHome.terminal
            flakeModulesHome.tools
            inputs.lazyvim-nix.homeManagerModules.default
            # nix-index-database for comma command-not-found
            inputs.nix-index-database.homeModules.nix-index
            # agents-md option module (requires flake arg from extraSpecialArgs)
            ../../../home/modules/_agents-md.nix
            # Mac app integration (Spotlight, Launchpad)
            # Disabled: mac-app-util requires SBCL which has nixpkgs cache compatibility issues
            # inputs.mac-app-util.homeManagerModules.default
          ];

          # Incus k3s profiles (see ADR-004)
          # Provides instance profiles for k3s clusters in Colima
          incus.k3sProfiles = {
            k3s-dev = {
              ip = "192.100.0.10";
            };
          };
        };
      };
    };
}
