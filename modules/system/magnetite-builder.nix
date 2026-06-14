# Cross-platform opt-in remote builder registering magnetite as a nix build machine
# Shared options/closure; machines import it explicitly and set enable = true.
#   darwin: ssh Host alias via environment.etc."ssh/ssh_config.d/120-magnetite.conf"
#   nixos:  ssh Host alias via programs.ssh.extraConfig
# Consumers splice config.services.magnetite-builder.buildMachines into their own
# nix.buildMachines; this module never assigns nix.buildMachines directly.
{ lib, ... }:
let
  mkOptions =
    config:
    let
      cfg = config.services.magnetite-builder;
    in
    {
      options.services.magnetite-builder = {
        enable = lib.mkEnableOption "register magnetite as a remote nix build machine";
        maxJobs = lib.mkOption {
          type = lib.types.int;
          default = 8;
          description = "Maximum simultaneous build jobs dispatched to magnetite.";
        };
        speedFactor = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = "Scheduler weight; higher than the rosetta builder (1) so the scheduler prefers native magnetite for x86_64-linux.";
        };
        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "x86_64-linux" ];
          description = "Systems magnetite can build for.";
        };
        supportedFeatures = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          # "kvm" is deliberately omitted pending confirmation magnetite exposes /dev/kvm:
          # without kvm advertised, QEMU VM tests won't mis-route to a possibly-kvm-less host,
          # while nspawn container tests (needing only uid-range) still route correctly.
          default = [
            "big-parallel"
            "nixos-test"
            "uid-range"
            "recursive-nix"
          ];
          description = "Build features magnetite advertises to the scheduler.";
        };
        sshUser = lib.mkOption {
          type = lib.types.str;
          default = "builder";
          description = "SSH user the nix-daemon connects as.";
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = "fddb:4344:343b:14b9:399:930f:39db:40d2";
          description = "magnetite's deterministic ZeroTier IPv6, matching modules/system/ssh-known-hosts.nix.";
        };
        hostAlias = lib.mkOption {
          type = lib.types.str;
          default = "magnetite";
          description = "ssh Host alias the nix-daemon resolves to the literal address.";
        };
        buildMachines = lib.mkOption {
          type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
          default =
            if cfg.enable then
              [
                {
                  hostName = cfg.hostAlias;
                  sshUser = cfg.sshUser;
                  protocol = "ssh-ng";
                  sshKey = config.clan.core.vars.generators.nix-remote-build.files.key.path;
                  systems = cfg.systems;
                  maxJobs = cfg.maxJobs;
                  speedFactor = cfg.speedFactor;
                  supportedFeatures = cfg.supportedFeatures;
                  mandatoryFeatures = [ ];
                }
              ]
            else
              [ ];
          defaultText = lib.literalExpression "single-element magnetite buildMachines entry when enabled, else []";
          description = "Computed nix.buildMachines entry for magnetite. Consumers splice this into their own nix.buildMachines; this module never sets nix.buildMachines itself.";
        };
      };
    };

  mkGenerator = pkgs: {
    clan.core.vars.generators.nix-remote-build = {
      files.key = { };
      files."key.pub".secret = false;
      runtimeInputs = [ pkgs.openssh ];
      script = ''
        ssh-keygen -t ed25519 -N "" -C "nix-remote-build" -f "$out"/key
      '';
    };
  };

  mkSshBlock =
    cfg: ''
      Host ${cfg.hostAlias}
        HostName ${cfg.address}
        User ${cfg.sshUser}
        IdentityFile ${cfg.sshKeyPath}
        IdentitiesOnly yes
        HostKeyAlias magnetite.zt
    '';
in
{
  flake.modules.darwin.magnetite-builder =
    { config, pkgs, ... }:
    let
      cfg = config.services.magnetite-builder;
      sshKeyPath = config.clan.core.vars.generators.nix-remote-build.files.key.path;
    in
    (mkOptions config)
    // {
      config = lib.mkIf cfg.enable (
        (mkGenerator pkgs)
        // {
          nix.distributedBuilds = true;
          environment.etc."ssh/ssh_config.d/120-magnetite.conf".text = mkSshBlock (cfg // { inherit sshKeyPath; });
        }
      );
    };

  flake.modules.nixos.magnetite-builder =
    { config, pkgs, ... }:
    let
      cfg = config.services.magnetite-builder;
      sshKeyPath = config.clan.core.vars.generators.nix-remote-build.files.key.path;
    in
    (mkOptions config)
    // {
      config = lib.mkIf cfg.enable (
        (mkGenerator pkgs)
        // {
          nix.distributedBuilds = true;
          programs.ssh.extraConfig = mkSshBlock (cfg // { inherit sshKeyPath; });
        }
      );
    };
}
