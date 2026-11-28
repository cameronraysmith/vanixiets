# Split DNS for the mesh zone
#
# The name services on flake.lib.mesh.resolvers (modules/nixos/mesh-dns.nix)
# answer for the fleet domain on their mesh addresses. Every member sends only
# names under that domain there; every other name keeps its usual path.
{ config, lib, ... }:
let
  inherit (config.flake.lib) fleet hosts mesh;
  resolverAddresses = map (name: hosts.${name}.address) mesh.resolvers;
in
{
  # macOS consults /etc/resolver/<domain> for names under that domain, asking
  # the listed name servers in order.
  #
  # A `flags` line replaces the query flags the resolver would inherit from
  # the Mac's own connectivity (configd-1405.100.8
  # dnsinfo/dnsinfo_flatfile.c:74,380-394,520-522, present since configd-596,
  # OS X 10.10; resolver(5) does not document it).
  #
  # `aaaa` makes configd mark this resolver "Request AAAA records". Without
  # it the resolver inherits the global flags, which on a Mac without an IPv6
  # default route are A only, and getaddrinfo with AI_ADDRCONFIG (what
  # flags=0 defaults to on macOS, and what Chrome, Firefox and curl pass)
  # never asks for the AAAA records that are the only records of this
  # IPv6-only zone (finding F34, design D7).
  #
  # No `a`: the zone has no A records (D7), and asking for them costs a
  # stall when the resolvers are unreachable. On stibnite (2026-11-18), in
  # its steady configuration with `flags a aaaa` and both resolvers blocked,
  # getaddrinfo(AF_UNSPEC) for names /etc/hosts lists took 30.004-30.005 s:
  # mDNSResponder answered the AAAA question from the hosts file at once and
  # sent the A question to the two resolvers 8 times until it timed out at
  # 30 s (logs/cam109-15.6-steady-before-20261118-130026.log and its
  # -mdnsresponder.log). /etc/resolver/zt keeps `a aaaa`
  # (modules/system/zt-dns.nix).
  # checks.x86_64-linux.darwin-mesh-resolver-flags holds every Mac to it.
  flake.modules.darwin.base-mesh-dns = {
    environment.etc."resolver/${fleet.domain}" = {
      enable = true;
      text = lib.concatMapStrings (address: "nameserver ${address}\n") resolverAddresses + "flags aaaa\n";
    };
  };

  # systemd-resolved routes names under a link's route-only domain to that
  # link's servers. The unit is tincr's own: its NixOS module writes
  # systemd.network.networks."40-tincr-<network>" matching the tinc interface
  # with the interface's Address= (Mic92/tincr nix/module.nix:478-480 at
  # fd92f216), and networkd applies only the first .network file matching an
  # interface, so a separate unit would shadow tincr's address. Defining the
  # same attribute merges DNS= and Domains= into tincr's unit.
  #
  # On every peer of the instance, the assertion holds that coupling: the
  # merged unit carries tincr's address and these DNS= and Domains=, and no
  # other enabled unit matches the mesh interface. Name= patterns are matched as
  # networkd globs; a pattern with a bracket class, or a [Match] without Name=
  # but with other keys, counts as matching, because the evaluation cannot
  # tell. NetworkManager's unmanaged entry for the link is the tincr service's
  # (modules/clan/services/tincr/flake-module.nix).
  flake.modules.nixos.base-mesh-dns =
    { config, lib, ... }:
    let
      unitName = "40-tincr-${mesh.instance}";
      interface = mesh.interface.nixos;
      tincrNetwork = (config.services.tincr.networks or { }).${mesh.instance} or null;
      networks = lib.filterAttrs (_: network: network.enable) config.systemd.network.networks;
      unit = networks.${unitName} or null;
      globMatches =
        pattern:
        lib.hasInfix "[" pattern
        ||
          builtins.match (lib.concatMapStrings (
            c:
            if c == "*" then
              ".*"
            else if c == "?" then
              "."
            else
              lib.escapeRegex c
          ) (lib.stringToCharacters pattern)) interface != null;
      matchesInterface =
        network:
        let
          patterns = lib.filter (p: p != "") (
            lib.concatMap (lib.splitString " ") (lib.toList (network.matchConfig.Name or [ ]))
          );
          negated = map (lib.removePrefix "!") (lib.filter (lib.hasPrefix "!") patterns);
          positive = lib.filter (p: !lib.hasPrefix "!" p) patterns;
        in
        if network.matchConfig == { } then
          false
        else if patterns == [ ] then
          true
        else
          (positive == [ ] || lib.any globMatches positive) && !(lib.any globMatches negated);
      others = lib.attrNames (
        lib.filterAttrs (name: network: name != unitName && matchesInterface network) networks
      );
      address = hosts.${tincrNetwork.nodeName}.address or null;
    in
    {
      systemd.network.networks.${unitName} = {
        matchConfig.Name = interface;
        dns = resolverAddresses;
        domains = [ "~${fleet.domain}" ];
      };
      assertions = lib.optionals (tincrNetwork != null) [
        {
          assertion =
            unit != null
            && address != null
            && lib.any (lib.hasPrefix "${address}/") unit.address
            && lib.all (server: lib.elem server unit.dns) resolverAddresses
            && lib.elem "~${fleet.domain}" unit.domains;
          message = "mesh-dns: systemd.network.networks.${unitName} must carry tincr's Address= (${toString address}/…) and DNS= ${toString resolverAddresses} with Domains= ~${fleet.domain}";
        }
        {
          assertion = others == [ ];
          message = "mesh-dns: only systemd.network.networks.${unitName} may match ${interface}; also matching: ${toString others}";
        }
      ];
    };
}
