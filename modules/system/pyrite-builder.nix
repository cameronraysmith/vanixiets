# Cross-platform opt-in remote builder registering pyrite as a nix build machine.
# Shared options/closure; machines import it explicitly and set enable = true.
#   darwin: ssh Host alias via environment.etc."ssh/ssh_config.d/121-pyrite.conf"
#   nixos:  ssh Host alias via programs.ssh.extraConfig
# Consumers splice config.services.pyrite-builder.buildMachines into their own
# nix.buildMachines; this module never assigns nix.buildMachines directly.
#
# pyrite is the only machine in the fleet with /dev/kvm (see the kvm-declaration
# module), so it is the only host that builds a kvm-requiring derivation, such
# as a vmTests output, with hardware acceleration. It is not the only host that
# can build one at all: stibnite's rosetta-builder entry also advertises kvm,
# on the evidence that qemu there falls back to TCG and completes the build
# emulated, so on stibnite the two are alternatives and pyrite is the fast one.
#
# It is also a laptop that is often but not always reachable, and nix 2.35
# handles that as follows (src/nix/build-remote/build-remote.cc:250-259 and
# src/libstore/build/derivation-building-goal.cc:261-335 at tag 2.35.2):
#   - The build hook tries to connect; on failure it logs
#     `cannot build on '<store uri>': <error>`, sets that machine's `enabled` to
#     false for the rest of the hook's lifetime, and reconsiders the remaining
#     machines. Work another builder can take routes there, and work the caller
#     can do itself falls back to a local build.
#   - A derivation requiring kvm with pyrite offline and no other kvm machine
#     leaves no candidate: the hook logs `Failed to find a machine for remote
#     build!` and declines, and the local goal then fails the build with
#     `Cannot build '<drv>' ... missing system features / Required features:
#     {kvm}`. There is no silent degradation to a TCG-emulated or unaccelerated
#     local build.
# The second case is the intended outcome on a consumer with no other kvm
# machine. vmTests are opt-in and outside pull-request gating, so an offline
# pyrite costs a manual re-run and never a red pull request; on stibnite it
# costs an emulated run on the rosetta builder instead.
{ lib, ... }:
let
  mkOptions =
    config:
    let
      cfg = config.services.pyrite-builder;
    in
    {
      options.services.pyrite-builder = {
        enable = lib.mkEnableOption "register pyrite as a remote nix build machine";
        maxJobs = lib.mkOption {
          type = lib.types.int;
          # MacBookPro14,1: two cores, four threads, and a machine in interactive
          # use. One job at a time, free to use every thread through the daemon's
          # own `cores` setting.
          default = 1;
          description = "Maximum simultaneous build jobs dispatched to pyrite.";
        };
        speedFactor = lib.mkOption {
          type = lib.types.int;
          # Below magnetite's 2, so ordinary x86_64-linux work prefers the cloud
          # build host and pyrite is picked for it only when magnetite is busy.
          # kvm-requiring work reaches pyrite because magnetite does not
          # advertise the feature; on stibnite the rosetta builder does, at the
          # same speedFactor, so the two tie and either may take it.
          default = 1;
          description = "Scheduler weight, compared against other x86_64-linux builders.";
        };
        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "x86_64-linux" ];
          description = "Systems pyrite can build for.";
        };
        supportedFeatures = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          # Both are genuine here: /dev/kvm exists at mode 0666 and the host is a
          # Linux machine whose daemon can run the nixos-test sandbox. Features
          # pyrite cannot honour are deliberately absent, "big-parallel" in
          # particular, because two cores do not serve a parallel-heavy build.
          default = [
            "kvm"
            "nixos-test"
          ];
          description = "Build features pyrite advertises to the scheduler.";
        };
        sshUser = lib.mkOption {
          type = lib.types.str;
          default = "builder";
          description = "SSH user the nix-daemon connects as; the account pyrite restricts to nix-daemon --stdio.";
        };
        sshKey = lib.mkOption {
          type = lib.types.path;
          default = config.clan.core.vars.generators.nix-remote-build.files.key.path;
          defaultText = lib.literalExpression "config.clan.core.vars.generators.nix-remote-build.files.key.path";
          description = ''
            Private key the nix-daemon authenticates with. Defaults to this
            machine's `nix-remote-build` key, the same identity it presents to
            magnetite's builder account; that generator is declared by the
            magnetite-builder module, so a consumer enabling this builder without
            that one has to set this option.
          '';
        };
        address = lib.mkOption {
          type = lib.types.str;
          default = "fddb:4344:343b:14b9:399:937e:8067:8028";
          description = "pyrite's deterministic ZeroTier IPv6, matching modules/system/ssh-known-hosts.nix.";
        };
        hostAlias = lib.mkOption {
          type = lib.types.str;
          default = "pyrite-builder";
          description = "ssh Host alias the nix-daemon resolves to the literal address, distinct from the interactive `pyrite.zt` name.";
        };
        connectTimeout = lib.mkOption {
          type = lib.types.int;
          default = 5;
          description = ''
            ssh ConnectTimeout in seconds. Without it an asleep or off-network
            laptop absorbs the kernel's full SYN retry schedule before the hook
            gives up, stalling every dispatch behind it; five seconds is ample
            for a ZeroTier round trip on this mesh.
          '';
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
                  sshKey = cfg.sshKey;
                  systems = cfg.systems;
                  maxJobs = cfg.maxJobs;
                  speedFactor = cfg.speedFactor;
                  supportedFeatures = cfg.supportedFeatures;
                  mandatoryFeatures = [ ];
                }
              ]
            else
              [ ];
          defaultText = lib.literalExpression "single-element pyrite buildMachines entry when enabled, else []";
          description = "Computed nix.buildMachines entry for pyrite. Consumers splice this into their own nix.buildMachines; this module never sets nix.buildMachines itself.";
        };
      };
    };

  # BatchMode keeps an unreachable host from parking the daemon on a password or
  # host-key prompt it cannot answer, and the keepalive pair tears down a
  # connection to a laptop that suspends mid-transfer after ~30 s rather than
  # leaving the build waiting on a half-open session.
  mkSshBlock = cfg: ''
    Host ${cfg.hostAlias}
      HostName ${cfg.address}
      User ${cfg.sshUser}
      IdentityFile ${cfg.sshKey}
      IdentitiesOnly yes
      HostKeyAlias pyrite.zt
      BatchMode yes
      ConnectTimeout ${toString cfg.connectTimeout}
      ServerAliveInterval 15
      ServerAliveCountMax 2
  '';
in
{
  flake.modules.darwin.pyrite-builder =
    { config, ... }:
    let
      cfg = config.services.pyrite-builder;
    in
    (mkOptions config)
    // {
      config = lib.mkIf cfg.enable {
        nix.distributedBuilds = true;
        environment.etc."ssh/ssh_config.d/121-pyrite.conf".text = mkSshBlock cfg;
      };
    };

  flake.modules.nixos.pyrite-builder =
    { config, ... }:
    let
      cfg = config.services.pyrite-builder;
    in
    (mkOptions config)
    // {
      config = lib.mkIf cfg.enable {
        nix.distributedBuilds = true;
        programs.ssh.extraConfig = mkSshBlock cfg;
      };
    };
}
