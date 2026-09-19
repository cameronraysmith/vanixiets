{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.darwin;
  flakeUsers = config.flake.users;
  # sops-nix requires flake in extraSpecialArgs
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
      _module.args.flake = inputs.self;

      imports = [
        inputs.home-manager.darwinModules.home-manager
        inputs.srvos.darwinModules.server
      ]
      ++ (with flakeModules; [
        base
        ssh-ca-trust
        ssh-known-hosts
        dnscrypt-proxy
        zt-dns
        zt-services-trust
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

      # System state version (matching vanixiets configuration)
      # Override base.nix which sets stateVersion = 5
      system.stateVersion = lib.mkForce 4;

      # Known gap: no environment.etc."nix/nix.conf".knownSha256Hashes.
      # stibnite, argentum and rosegold each carry the sha256 of the
      # /etc/nix/nix.conf that the nix installer left on that specific Mac.
      # The value is a property of the machine, not of this repository: it
      # cannot be computed here, and another host's hash is simply the wrong
      # file. blackphos is semi-permanently offline, so it cannot be read now,
      # and no placeholder is supplied because a wrong hash never matches and
      # would only look like the gap was closed.
      #
      # It matters only if /etc/nix/nix.conf there is still an unmanaged
      # regular file. nix-darwin's /etc check (modules/system/etc.nix) skips
      # any /etc entry already symlinked into /etc/static, so an already
      # activated blackphos needs nothing; otherwise activation aborts with
      # "Unexpected files in /etc" naming /etc/nix/nix.conf and refuses to
      # overwrite it.
      #
      # To close it when the machine next boots:
      #   readlink /etc/nix/nix.conf        # /etc/static/... means no hash needed
      #   shasum -a 256 /etc/nix/nix.conf   # otherwise add the digest here

      # Primary user for homebrew and system-level user operations
      # crs58 is the admin user on blackphos
      system.primaryUser = "crs58";

      custom.profile.isDesktop = true;

      # Base casks from modules/darwin/homebrew.nix; machine-specific additions below
      custom.homebrew = {
        enable = true;

        additionalCasks = [
          "dbeaver-community"
          "docker-desktop"
          "gitbutler"
          "gpg-suite"
          "inkscape"
          "keycastr"
          "meld"
          "postgres-app"
          "steipete/tap/codexbar"
          "zerotier-one"
        ];

        # Machine-specific Mac App Store apps
        additionalMasApps = {
          "save-to-raindrop-io" = 1549370672;
        };

        # Fonts managed via base homebrew module (manageFonts defaults to true)
      };

      # Operator claim (modules/darwin/sshd-declaration.nix): blackphos accepts
      # inbound SSH so it can be deployed to from stibnite over zerotier.
      declaredSshd.serving = true;

      # Encrypted DNS via DoH (DNS-over-HTTPS)
      # Routes all DNS through Quad9 DoH, bypassing enterprise DNS interception
      # DoH uses HTTPS (port 443)
      services.localDnscryptProxy = {
        enable = true;
        providers = [
          "quad9"
        ];
        userHome = "/private/var/lib/dnscrypt-proxy";
      };

      services.zt-services-trust.enable = true;

      # crs58: admin (UID 502), raquel: primary (UID 506) - matches existing system
      users.users.crs58 = {
        uid = 502;
        home = "/Users/crs58";
        shell = pkgs.zsh;
        description = "crs58";
        openssh.authorizedKeys.keys = inputs.self.users.crs58.meta.sshKeys;
      };

      users.users.raquel = {
        uid = 506;
        home = "/Users/raquel";
        shell = pkgs.zsh;
        description = "raquel";
        openssh.authorizedKeys.keys = inputs.self.users.raquel.meta.sshKeys;
      };

      # Darwin requires explicit knownUsers
      # Not managing root user (no users.users.root definition)
      users.knownUsers = [
        "crs58"
        "raquel"
      ];

      home-manager = {
        useGlobalPkgs = true;
        useUserPackages = true;

        backupFileExtension = "before-home-manager";

        # Pass flake as extraSpecialArgs for sops-nix access
        extraSpecialArgs = {
          flake = flakeForHomeManager;
        };

        users.crs58.imports = flakeUsers.crs58.modules;

        users.raquel.imports = flakeUsers.raquel.modules;
      };
    };
}
