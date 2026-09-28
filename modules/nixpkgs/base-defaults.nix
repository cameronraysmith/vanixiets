# Shared nixpkgs defaults applied to every NixOS and nix-darwin machine
#
# Contributes to both flake.modules.darwin.base and flake.modules.nixos.base,
# which every machine imports via the `base` flakeModule in its
# modules/machines/<class>/<host>/default.nix.
#
# Settings:
#   - nixpkgs.config.allowUnfree: required for proprietary packages
#     (copilot-language-server, NVIDIA drivers, casks, etc.)
#   - nixpkgs.overlays: wires the composed flake.overlays.default into nixpkgs
#     construction so machines see the overlay-provided attributes (e.g.
#     openclaw-gateway, mactop, channels).
#   - nixpkgs.config.permittedInsecurePackages: the exact name-version pairs the
#     fleet accepts despite nixpkgs knownVulnerabilities, exported as
#     flake.lib.permittedInsecurePackages so the standalone home-manager pkgs
#     in modules/home/mk-home.nix admit the same set.
#
# Out of scope: allowUnfree writes in modules/nixpkgs/per-system.nix,
# modules/nixpkgs/overlays/channels.nix, modules/home/configurations.nix,
# modules/darwin/nix-settings.nix, and modules/nixos/nvidia.nix live in
# different evaluation contexts (perSystem pkgs, child-channel imports,
# home-manager pkgs, darwin-specific nix.settings, NVIDIA-only override).
{ inputs, ... }:
let
  # radicle-node (and radicle-tui, which propagates it) is marked insecure for
  # every release to date: the node transport sends data in cleartext after the
  # handshake, and the handshake lets a peer present a Node ID it does not own
  # (https://radicle.dev/2026/09/23/disclosure-of-vulnerability-in-network-protocol,
  # NixOS/nixpkgs#566450). Both flaws cost confidentiality, not integrity:
  # signed references still reject objects tampered with in transit. The fleet
  # accepts this because it publishes and replicates only public Radicle
  # repositories, so nothing the transport carries is secret. Traffic from
  # fleet clients to the cinnabar seed also stays on ZeroTier, since cinnabar
  # opens 8776 only on the zt+ interfaces (cinnabar/zt-dns.nix). That narrows
  # the network path but does not fix impersonation, so no private repository
  # may be added until a Radicle 2.x transport replaces this one. Pinned to the
  # exact version so any radicle-node bump drops the permission and forces this
  # to be re-examined; remove it once a release no longer carries the advisory.
  permittedInsecurePackages = [ "radicle-node-1.10.3" ];

  defaults = {
    nixpkgs.config.allowUnfree = true;
    nixpkgs.config.permittedInsecurePackages = permittedInsecurePackages;
    nixpkgs.overlays = [ inputs.self.overlays.default ];
  };
in
{
  flake.lib.permittedInsecurePackages = permittedInsecurePackages;
  flake.modules.darwin.base = defaults;
  flake.modules.nixos.base = defaults;
}
