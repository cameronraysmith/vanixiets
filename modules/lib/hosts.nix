# Fleet host registry: flake.fleet.hosts holds one typed record per fleet
# member, the only place a member's name, system or overlay address is
# written. `class`, `fqdn`, `address`, `targetHost`, `memoryGiB`, `enrolled`
# and `cloud` are read-only fields the submodule derives from the name, the
# declared fields, the committed flake source and flake.lib.cloudMachines;
# `zerotier` carries today's ZeroTier address and member id until ZeroTier is
# retired. Whether a host is checked, enrolled or has its cloud server up are
# three independent facts. A field that contradicts the host's class throws
# when it is read, so flake.lib.nixEvalJobsBoundProblems' tryEval still
# catches it. flake.lib.hosts is the read-only alias every reader uses.
{
  config,
  lib,
  self,
  ...
}:
let
  inherit (config.flake.lib)
    fleet
    mesh
    cloudMachines
    cloudMachineMemoryGiB
    ;
  inherit (lib) types;
  flakeConfig = config;

  # Each cloud machine's provider, machine type and whether its server
  # exists, read from the terraform table, which stays their only writer.
  cloudRecords = lib.concatMapAttrs (
    provider: machines:
    lib.mapAttrs (_: m: {
      inherit provider;
      type = m.serverType or m.machineType;
      inherit (m) enabled;
    }) machines
  ) cloudMachines;

  hostModule =
    { name, config, ... }:
    let
      where = "flake.fleet.hosts.${name}";
    in
    {
      options = {
        system = lib.mkOption {
          type = types.nullOr (
            types.enum [
              "x86_64-linux"
              "aarch64-linux"
              "aarch64-darwin"
            ]
          );
          description = "The host's Nix system; null for a member that runs no Nix configuration (a phone).";
        };
        endpoints = lib.mkOption {
          type = types.listOf types.str;
          description = "Public names the host is dialled at.";
        };
        deployUser = lib.mkOption {
          type = types.nullOr types.str;
          description = "The account clan deploys the host as; null for a member that is never deployed.";
        };
        services = lib.mkOption {
          type = types.listOf types.str;
          description = "Service labels published under the fleet domain at the host's address.";
        };
        zerotier = {
          address = lib.mkOption {
            type = types.str;
            description = "The host's ZeroTier address.";
          };
          memberId = lib.mkOption {
            type = types.str;
            description = "The host's ZeroTier member id.";
          };
        };
        # The person a machine belongs to, if it is anyone's: a name under
        # flake.users (modules/home/users, aliases included) or null for a
        # shared server or a phone. flake.lib.fleetDeployer derives who may
        # deploy a machine from it, and its obligation requires the user to
        # have an account on that machine.
        primaryUser = lib.mkOption {
          type = types.nullOr (types.enum (lib.attrNames flakeConfig.flake.users));
          description = "The person the host belongs to, a name under flake.users, or null.";
        };
        memory = lib.mkOption {
          type = types.nullOr (types.either types.ints.positive (types.enum [ "unknown" ]));
          description = "Memory in GiB read on the machine (MemTotal, hw.memsize), \"unknown\", or null for a phone or a cloud host, whose memory follows from its machine type.";
        };
        # Machines whose primary user's `nix` is iets' classic mode
        # (home/development/nix-classic.nix): a trial, stibnite first.
        nixClassic = lib.mkOption {
          type = types.bool;
          apply =
            v:
            assert lib.assertMsg (
              !v || config.primaryUser != null
            ) "${where}.nixClassic: true on a host without a primaryUser";
            v;
          description = "Whether the primary user's `nix` is iets' classic mode.";
        };
        checked = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Whether the host's configuration has a machine check.";
        };
        stateVersion = lib.mkOption {
          type = types.nullOr (types.either types.ints.positive types.str);
          apply =
            v:
            assert lib.assertMsg
              (
                {
                  darwin = builtins.isInt v;
                  nixos = builtins.isString v;
                  android = v == null;
                }
                .${config.class}
              )
              "${where}.stateVersion: ${builtins.toJSON v} does not fit a ${config.class} host (darwin an integer, nixos a release string, android null)";
            v;
          description = "The host module's state version; not yet read by the host modules.";
        };

        class = lib.mkOption {
          readOnly = true;
          type = types.enum [
            "nixos"
            "darwin"
            "android"
          ];
          description = "The host's kind, derived from `system`.";
        };
        fqdn = lib.mkOption {
          readOnly = true;
          type = types.str;
          description = "The host's name under the fleet domain.";
        };
        address = lib.mkOption {
          readOnly = true;
          type = types.str;
          description = "The host's overlay address, derived from its name.";
        };
        # The one address every deploy path names for this machine: clan's
        # own targetHost (darwin machine modules), the inventory's
        # deploy.targetHost where a NixOS machine sets one, and the fleet
        # deployer's reachability probe. The ZeroTier name until the tincr
        # cutover (CAM-109) changes it here.
        targetHost = lib.mkOption {
          readOnly = true;
          type = types.nullOr types.str;
          description = "`<deployUser>@<name>.zt`, or null without a deployUser.";
        };
        # It alone decides the machine's nix-eval-jobs: iets or stock, and
        # iets' bound, by flake.lib.nixEvalJobsBoundRules
        # (modules/lib/nix-eval-jobs-host.nix).
        memoryGiB = lib.mkOption {
          readOnly = true;
          type = types.nullOr (types.either types.ints.positive (types.enum [ "unknown" ]));
          description = "Memory in GiB of a host that runs Nix (a cloud host's from its machine type), \"unknown\", or null for a phone.";
        };
        # Whether clan holds the host's machine key: the committed flake
        # source, never the working tree, is read.
        enrolled = lib.mkOption {
          readOnly = true;
          type = types.bool;
          description = "Whether sops/machines/<name> exists in the committed flake source.";
        };
        cloud = lib.mkOption {
          readOnly = true;
          type = types.nullOr (
            types.submodule {
              options = {
                provider = lib.mkOption { type = types.str; };
                type = lib.mkOption { type = types.str; };
                enabled = lib.mkOption { type = types.bool; };
              };
            }
          );
          description = "The host's cloud provider, machine type and whether its server exists, or null.";
        };
      };

      config = {
        class =
          if config.system == null then
            "android"
          else if lib.hasSuffix "-darwin" config.system then
            "darwin"
          else
            "nixos";
        fqdn = "${name}.${fleet.domain}";
        address = mesh.addressOf mesh.instance name;
        targetHost = if config.deployUser == null then null else "${config.deployUser}@${name}.zt";
        memoryGiB =
          let
            runsNix = config.class != "android";
          in
          if config.cloud != null then
            assert lib.assertMsg (
              config.memory == null
            ) "${where}.memory: set on a cloud host, whose memory follows from its machine type";
            cloudMachineMemoryGiB.${config.cloud.type}
              or (throw "${where}.memoryGiB: cloud machine type ${config.cloud.type} has no memory in flake.lib.cloudMachineMemoryGiB")
          else
            assert lib.assertMsg (runsNix == (config.memory != null))
              "${where}.memoryGiB: ${builtins.toJSON config.memory} is not ${
                if runsNix then "a positive number of GiB or \"unknown\"" else "unset for an android member"
              }";
            config.memory;
        enrolled = builtins.pathExists (self + "/sops/machines/${name}");
        cloud = cloudRecords.${name} or null;
      };
    };
in
{
  options.flake.fleet.hosts = lib.mkOption {
    type = types.attrsOf (types.submodule hostModule);
    description = "The fleet's host registry: one record per member.";
  };

  config.flake.fleet.hosts = {
    cinnabar = {
      system = "x86_64-linux";
      endpoints = [ "cinnabar.scientistexperience.net" ];
      deployUser = "root";
      services = [
        "matrix"
        "hermes"
        "ntfy"
        "omnigraph"
        "radicle"
      ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:93db:4344:343b";
        memberId = "db4344343b";
      };
      primaryUser = null;
      memory = null; # cloud
      nixClassic = false;
      stateVersion = "25.05";
    };
    electrum = {
      system = "x86_64-linux";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:93d1:7e6d:27cc";
        memberId = "d17e6d27cc";
      };
      primaryUser = null;
      memory = null; # cloud
      nixClassic = false;
      stateVersion = "25.05";
    };
    galena = {
      system = "x86_64-linux";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9315:c67a:dec9";
        memberId = "15c67adec9";
      };
      primaryUser = null;
      memory = null; # cloud
      nixClassic = false;
      stateVersion = "25.05";
    };
    scheelite = {
      system = "x86_64-linux";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9380:46d5:3400";
        memberId = "8046d53400";
      };
      primaryUser = null;
      memory = null; # cloud
      nixClassic = false;
      checked = false;
      stateVersion = "25.05";
    };
    magnetite = {
      system = "x86_64-linux";
      endpoints = [ "magnetite.scientistexperience.net" ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:930f:39db:40d2";
        memberId = "0f39db40d2";
      };
      primaryUser = null;
      memory = null; # cloud
      nixClassic = false;
      stateVersion = "25.05";
    };
    pyrite = {
      system = "x86_64-linux";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:937e:8067:8028";
        memberId = "7e80678028";
      };
      primaryUser = "cameron";
      memory = 16;
      nixClassic = false;
      stateVersion = "26.05";
    };
    stibnite = {
      system = "aarch64-darwin";
      endpoints = [ ];
      deployUser = "crs58";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9324:19d9:3451";
        memberId = "2419d93451";
      };
      primaryUser = "crs58";
      memory = 64;
      nixClassic = true;
      stateVersion = 4;
    };
    blackphos = {
      system = "aarch64-darwin";
      endpoints = [ ];
      deployUser = "crs58";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:930e:e971:d9e0";
        memberId = "0ee971d9e0";
      };
      primaryUser = "raquel";
      memory = "unknown";
      nixClassic = false;
      stateVersion = 4;
    };
    argentum = {
      system = "aarch64-darwin";
      endpoints = [ ];
      deployUser = "cameron";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:93f7:54d5:ad7e";
        memberId = "f754d5ad7e";
      };
      primaryUser = "christophersmith";
      memory = 8;
      nixClassic = false;
      stateVersion = 4;
    };
    rosegold = {
      system = "aarch64-darwin";
      endpoints = [ ];
      deployUser = "cameron";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9315:3431:ee8";
        memberId = "1534310ee8";
      };
      primaryUser = "janettesmith";
      memory = 8;
      nixClassic = false;
      stateVersion = 4;
    };
    pixel7 = {
      system = null;
      endpoints = [ ];
      deployUser = null;
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:939f:c45d:577c";
        memberId = "9fc45d577c";
      };
      primaryUser = null;
      memory = null;
      nixClassic = false;
      stateVersion = null;
    };
    pixel11 = {
      system = null;
      endpoints = [ ];
      deployUser = null;
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:933c:8999:9bb8";
        memberId = "3c89999bb8";
      };
      primaryUser = null;
      memory = null;
      nixClassic = false;
      stateVersion = null;
    };
  };

  config.flake.lib.hosts = config.flake.fleet.hosts;

  # Every host that builds a Nix configuration, and its system: the phones
  # carry none.
  config.flake.lib.machineSystems = lib.mapAttrs (_: h: h.system) (
    lib.filterAttrs (_: h: h.system != null) config.flake.fleet.hosts
  );

  config.flake.lib.meshRecords = lib.concatLists (
    lib.mapAttrsToList (
      _: host:
      [
        {
          name = host.fqdn;
          inherit (host) address;
        }
      ]
      ++ map (label: {
        name = "${label}.${fleet.domain}";
        inherit (host) address;
      }) host.services
    ) config.flake.fleet.hosts
  );
}
