# The fleet's tincr mesh, beside ZeroTier until the cutover: every NixOS and
# darwin member of the registry that is enrolled with clan (its machine key is
# committed under sops/machines) is a peer, so a reserved name with no machine,
# such as blackphos, is left out until a machine takes it; members with public
# endpoints are dialled at them. The instance name is
# flake.lib.mesh.instance, which names the network, the key generator and the
# interfaces.
#
# flake.lib.meshHostFiles is every peer's and device's host file as each peer
# renders it (flake.lib.tincrHostFile over the same registry values and the
# public vars), for members outside clan, such as phones, that carry them by
# hand.
{
  config,
  lib,
  ...
}:
let
  inherit (config.flake.lib)
    hosts
    mesh
    tincrHostFile
    vars
    ;

  peers = lib.filterAttrs (_: host: host.class != "android" && host.enrolled) hosts;

  # Phones, keyed by registry name, each with the Ed25519 public key tincapp
  # generated when it joined by invitation.
  devices = {
    # Joined by invitation through cinnabar on 2026-11-18 (tincapp 0.48).
    pixel11.publicKey = "qmeYsFrBPTxrP0EbvjuIHNI9E7cqtU6Bppq1BuaVHAP";
  };

  peerKey =
    name:
    vars.public {
      machine = name;
      generator = "tincr-${mesh.instance}";
      file = "ed25519_key.pub";
    };
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
