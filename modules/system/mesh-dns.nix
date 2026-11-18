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
  flake.modules.darwin.base = {
    environment.etc."resolver/${fleet.domain}" = {
      enable = true;
      text = lib.concatMapStrings (address: "nameserver ${address}\n") resolverAddresses;
    };
  };

  # systemd-resolved routes names under a link's route-only domain to that
  # link's servers. The unit is tincr's own: its NixOS module writes
  # systemd.network.networks."40-tincr-<network>" matching the tinc interface
  # with the interface's Address= (Mic92/tincr nix/module.nix:478-480 at
  # fd92f216), and networkd applies only the first .network file matching an
  # interface, so a separate unit would shadow tincr's address. Defining the
  # same attribute merges DNS= and Domains= into tincr's unit.
  flake.modules.nixos.base = {
    systemd.network.networks."40-tincr-${mesh.instance}" = {
      matchConfig.Name = mesh.interface.nixos;
      dns = resolverAddresses;
      domains = [ "~${fleet.domain}" ];
    };
    # On hosts running NetworkManager (pyrite), networkd owns the mesh link,
    # so NetworkManager must leave it alone.
    networking.networkmanager.unmanaged = [ "interface-name:${mesh.interface.nixos}" ];
  };
}
