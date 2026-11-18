# The fleet's tincr mesh, beside ZeroTier until the cutover: every NixOS and
# darwin member of the registry is a peer, except blackphos (below), and
# members with public endpoints are dialled at them. The instance name is
# flake.lib.mesh.instance, which names the network, the key generator and the
# interfaces.
#
# flake.lib.meshHostFiles is every peer's and device's host file as each peer
# renders it (flake.lib.tincrHostFile over the same registry values and the
# public vars), for members outside clan, such as phones, that carry them by
# hand.
{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib) hosts mesh tincrHostFile;

  peers = lib.filterAttrs (
    name: host:
    host.class != "android"
    # blackphos: reserved name with no machine; enrolled when a machine takes the name.
    && name != "blackphos"
  ) hosts;

  # Phones, keyed by registry name, each with the Ed25519 public key tincapp
  # generated when it joined by invitation.
  devices = { };

  peerKey =
    name:
    builtins.readFile "${inputs.self}/vars/per-machine/${name}/tincr-${mesh.instance}/ed25519_key.pub/value";
in
{
  flake.lib.meshHostFiles =
    lib.mapAttrs (
      name: host:
      tincrHostFile {
        inherit (host) address endpoints;
        publicKey = peerKey name;
        pq = mesh.crypto == "pq";
      }
    ) peers
    // lib.mapAttrs (
      name: device:
      tincrHostFile {
        inherit (hosts.${name}) address;
        inherit (device) publicKey;
      }
    ) devices;

  flake.clan.inventory.instances.${mesh.instance} = {
    module = {
      name = "tincr";
      input = "self";
    };
    roles.peer.settings.devices = devices;
    roles.peer.machines = lib.mapAttrs (_: host: { settings.endpoints = host.endpoints; }) peers;
  };
}
