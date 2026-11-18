# Name service for the mesh zone on each flake.lib.mesh.resolvers member.
#
# dnsmasq answers every flake.lib.meshRecords name with its mesh address,
# listens on the resolver's own mesh address and forwards every other name to
# quad9, since a phone's tincapp makes the resolver its only one while the VPN
# is up. Port 53 is opened on flake.lib.meshInterfaces only.
#
# services.dnsmasq runs one instance per host, so on a resolver that already
# runs dnsmasq (cinnabar's .zt zone, machines/nixos/cinnabar/zt-dns.nix) this
# module adds its listen address and records to that instance's lists; the
# shared settings are defaults that such a host's own definitions override.
# bind-dynamic lets dnsmasq bind the mesh address once the tincr interface
# carries it.
{ config, lib, ... }:
let
  inherit (config.flake.lib)
    hosts
    mesh
    meshInterfaces
    meshRecords
    ;

  resolverModule =
    name:
    { config, lib, ... }:
    {
      services.dnsmasq = {
        enable = true;
        resolveLocalQueries = lib.mkDefault false;
        settings = {
          "listen-address" = [ hosts.${name}.address ];
          "bind-dynamic" = lib.mkDefault true;
          "no-resolv" = lib.mkDefault true;
          "no-hosts" = lib.mkDefault true;
          server = lib.mkDefault [
            "9.9.9.9"
            "149.112.112.112"
          ];
          address = map (record: "/${record.name}/${record.address}") meshRecords;
        };
      };

      networking.firewall.interfaces = lib.genAttrs (meshInterfaces config) (_: {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      });
    };
in
{
  flake.modules.nixos = lib.listToAttrs (
    map (name: lib.nameValuePair "machines/nixos/${name}" (resolverModule name)) mesh.resolvers
  );
}
