# Mesh names answered on every node from the registry
#
# Every NixOS and darwin peer maps each flake.lib.meshRecords name
# (`<member>.vanixiets.internal` and the service names) to its mesh address
# in /etc/hosts, so peers find each other by name while neither resolver of
# flake.lib.mesh.resolvers is reachable. Until ZeroTier is retired the same
# holds for the `.zt` names cinnabar's dnsmasq serves (flake.lib.ztRecords),
# with both of the addresses it answers for a name, so a `.zt` name keeps
# its A record where it has one.
#
# /etc/hosts answers before DNS on both classes: systemd-resolved, first in
# the NixOS hosts database, reads it before any DNS server and holds itself
# authoritative for a name it lists (systemd resolved-etc-hosts.c,
# etc_hosts_lookup_by_name); mDNSResponder answers from it before deciding
# AAAA suppression (mDNSResponder-2881.120.11 mDNSCore/mDNS.c, AnswerNewQuestion
# calls AnswerQuestionWithLORecord first). The resolvers stay: phones have no
# hosts file and ask them, and every other name still goes there.
#
# NixOS writes `networking.hosts`; darwin writes `vanixiets.hosts`
# (modules/darwin/etc-hosts.nix), which activation splices into /etc/hosts.
# A NixOS host leaves out its own `fqdnOrHostName`, which NixOS already maps
# to 127.0.0.2. Each class's module is exported as
# flake.modules.<class>.mesh-hosts and imported by that class's base;
# vmTests.x86_64-linux.tincr-mesh-partition imports the NixOS one.
#
# flake.lib.meshHostsObligations.failures, asserted by
# modules/checks/machines.nix on every nixos-<host> and darwin-<host> check,
# holds each machine's entries to the records. Its judge reads both sides
# as name -> addresses, independently of hostsOf's address -> names
# grouping: every name under the fleet domain or `.zt` must map to exactly
# the records' addresses, so a missing name, a moved or added address and a
# stray name all fail; a NixOS host's own fqdnOrHostName is not judged.
# checks.x86_64-linux.mesh-hosts-obligations runs the judge over fixtures.
# The machine checks already evaluate each configuration, so the obligation
# adds almost nothing there; a standalone check judging every peer cost
# 454 MB of evaluation for its drvPath and was replaced by it.
{ config, lib, ... }:
let
  inherit (config.flake.lib)
    fleet
    meshRecords
    ztRecords
    ;
  inherit (config.flake) modules;

  records = meshRecords ++ ztRecords;
  hostsOf = records: lib.mapAttrs (_: map (r: r.name)) (lib.groupBy (r: r.address) records);

  isMeshName = name: lib.hasSuffix ".${fleet.domain}" name || lib.hasSuffix ".zt" name;
  addressesByName =
    pairs:
    lib.mapAttrs (_: ps: lib.sort lib.lessThan (lib.unique (map (p: p.address) ps))) (
      lib.groupBy (p: p.name) pairs
    );

  # Every mesh name whose addresses in `hosts` (address -> names) differ from
  # those `records` give it, `own` left out.
  mismatches =
    {
      records,
      hosts,
      own ? null,
    }:
    let
      pairs = lib.concatLists (
        lib.mapAttrsToList (address: names: map (name: { inherit name address; }) names) hosts
      );
      actual = addressesByName (lib.filter (p: isMeshName p.name && p.name != own) pairs);
      expected = removeAttrs (addressesByName records) (lib.optional (own != null) own);
      show = addresses: "[${lib.concatStringsSep " " addresses}]";
    in
    lib.concatMap (
      name:
      lib.optional ((actual.${name} or [ ]) != (expected.${name} or [ ]))
        "${name} maps to ${show (actual.${name} or [ ])}, the registry to ${show (expected.${name} or [ ])}"
    ) (lib.unique (builtins.attrNames actual ++ builtins.attrNames expected));

  meshHostsObligations = {
    inherit mismatches;
    failures =
      name: hostConfig:
      let
        isDarwin = config.flake.lib.hosts.${name}.class == "darwin";
      in
      if isDarwin then
        if hostConfig ? vanixiets.hosts then
          mismatches {
            inherit records;
            inherit (hostConfig.vanixiets) hosts;
          }
        else
          [ "${name} does not import etc-hosts, so vanixiets.hosts is undefined" ]
      else
        mismatches {
          inherit records;
          inherit (hostConfig.networking) hosts;
          own = hostConfig.networking.fqdnOrHostName;
        };
  };
in
{
  flake.lib = {
    inherit meshHostsObligations;
  };

  fleetObligations.meshHostsObligations.failures = meshHostsObligations.failures;

  flake.modules.nixos.mesh-hosts =
    { config, ... }:
    {
      networking.hosts = hostsOf (lib.filter (r: r.name != config.networking.fqdnOrHostName) records);
    };

  flake.modules.darwin.mesh-hosts = {
    vanixiets.hosts = hostsOf records;
  };
  flake.modules.darwin.base.imports = [ modules.darwin.mesh-hosts ];
}
