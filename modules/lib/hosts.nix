# Fleet member registry, the only place a member's name or overlay address is
# written. `fqdn` and `address` are derived from the name; `zerotier` carries
# today's ZeroTier address and member id until ZeroTier is retired.
# Consolidated into this single file because flake.lib is lazyAttrsOf raw,
# which forbids multi-file writes at the same nested path.
{ config, lib, ... }:
let
  inherit (config.flake.lib) fleet mesh;

  members = {
    cinnabar = {
      class = "nixos";
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
    };
    electrum = {
      class = "nixos";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:93d1:7e6d:27cc";
        memberId = "d17e6d27cc";
      };
    };
    galena = {
      class = "nixos";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9315:c67a:dec9";
        memberId = "15c67adec9";
      };
    };
    scheelite = {
      class = "nixos";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9380:46d5:3400";
        memberId = "8046d53400";
      };
    };
    magnetite = {
      class = "nixos";
      endpoints = [ "magnetite.scientistexperience.net" ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:930f:39db:40d2";
        memberId = "0f39db40d2";
      };
    };
    pyrite = {
      class = "nixos";
      endpoints = [ ];
      deployUser = "root";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:937e:8067:8028";
        memberId = "7e80678028";
      };
    };
    stibnite = {
      class = "darwin";
      endpoints = [ ];
      deployUser = "crs58";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9324:19d9:3451";
        memberId = "2419d93451";
      };
    };
    blackphos = {
      class = "darwin";
      endpoints = [ ];
      deployUser = "crs58";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:930e:e971:d9e0";
        memberId = "0ee971d9e0";
      };
    };
    argentum = {
      class = "darwin";
      endpoints = [ ];
      deployUser = "cameron";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:93f7:54d5:ad7e";
        memberId = "f754d5ad7e";
      };
    };
    rosegold = {
      class = "darwin";
      endpoints = [ ];
      deployUser = "cameron";
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:9315:3431:ee8";
        memberId = "1534310ee8";
      };
    };
    pixel7 = {
      class = "android";
      endpoints = [ ];
      deployUser = null;
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:939f:c45d:577c";
        memberId = "9fc45d577c";
      };
    };
    pixel11 = {
      class = "android";
      endpoints = [ ];
      deployUser = null;
      services = [ ];
      zerotier = {
        address = "fddb:4344:343b:14b9:399:933c:8999:9bb8";
        memberId = "3c89999bb8";
      };
    };
  };

  # The person a machine belongs to, if it is anyone's: a name under
  # flake.users (modules/home/users, aliases included) or null for a shared
  # server or a phone. flake.lib.fleetDeployer derives who may deploy a
  # machine from it, and its obligation requires the user to have an account
  # on that machine.
  primaryUsers = {
    pyrite = "cameron";
    stibnite = "crs58";
    blackphos = "raquel";
    argentum = "christophersmith";
    rosegold = "janettesmith";
  };
  primaryUserType = lib.types.nullOr (lib.types.enum (lib.attrNames config.flake.users));
  primaryUserOf =
    name:
    let
      user = primaryUsers.${name} or null;
    in
    assert lib.assertMsg (primaryUserType.check user)
      "flake.lib.hosts.${name}.primaryUser: ${builtins.toJSON user} is not null or a name under flake.users";
    user;

  # Memory in GiB of every machine that runs Nix (class nixos or darwin), or
  # "unknown". It alone decides the machine's nix-eval-jobs: iets or stock,
  # and iets' bound, by flake.lib.nixEvalJobsBoundRules
  # (modules/lib/nix-eval-jobs-host.nix). Cloud machines carry their declared
  # server type's memory (flake.lib.cloudMachines); the others were read on
  # the machine (MemTotal, hw.memsize).
  memoryGiB = {
    cinnabar = 16; # cx43
    electrum = 16; # ccx23
    galena = 32; # e2-standard-8
    scheelite = 30; # n1-standard-8
    magnetite = 32; # cx53
    pyrite = 16;
    stibnite = 64;
    blackphos = "unknown";
    argentum = 8;
    rosegold = 8;
  };
  memoryOf =
    name: member:
    let
      memory = memoryGiB.${name} or null;
      runsNix = member.class == "nixos" || member.class == "darwin";
    in
    assert lib.assertMsg
      (if runsNix then builtins.isInt memory && memory > 0 || memory == "unknown" else memory == null)
      "flake.lib.hosts.${name}.memoryGiB: ${builtins.toJSON memory} is not ${
        if runsNix then "a positive number of GiB or \"unknown\"" else "unset for a ${member.class} member"
      }";
    memory;

  # Machines whose primary user's `nix` is iets' classic mode
  # (home/development/nix-classic.nix): a trial, stibnite first.
  nixClassic = [ "stibnite" ];

  hosts =
    assert lib.assertMsg (lib.all (name: members ? ${name}) (
      lib.attrNames primaryUsers
    )) "flake.lib.hosts: primaryUsers names a machine that is not a member";
    assert lib.assertMsg (lib.all (name: members ? ${name}) (
      lib.attrNames memoryGiB
    )) "flake.lib.hosts: memoryGiB names a machine that is not a member";
    assert lib.assertMsg (lib.all (
      name: primaryUsers ? ${name}
    ) nixClassic) "flake.lib.hosts: nixClassic names a machine without a primaryUser";
    lib.mapAttrs (
      name: member:
      member
      // {
        fqdn = "${name}.${fleet.domain}";
        address = mesh.addressOf mesh.instance name;
        primaryUser = primaryUserOf name;
        memoryGiB = memoryOf name member;
        nixClassic = lib.elem name nixClassic;
        # The one address every deploy path names for this machine: clan's
        # own targetHost (darwin machine modules), the inventory's
        # deploy.targetHost where a NixOS machine sets one, and the fleet
        # deployer's reachability probe. The ZeroTier name until the tincr
        # cutover (CAM-109) changes it here.
        targetHost = if member.deployUser == null then null else "${member.deployUser}@${name}.zt";
      }
    ) members;
in
{
  flake.lib.hosts = hosts;

  flake.lib.meshRecords = lib.concatLists (
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
    ) hosts
  );
}
