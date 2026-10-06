# One nixpkgs instance per system for every NixOS machine, nix-darwin machine
# and standalone home-manager configuration
#
# perSystem `_module.args.fleetPkgs` instantiates nixpkgs once per system with
# the fleet configuration; consumers fetch it through flake-parts `withSystem`:
#   - flake.modules.{nixos,darwin}.base set `nixpkgs.pkgs` to it, so the NixOS
#     and nix-darwin nixpkgs modules forward it instead of re-importing nixpkgs
#     per machine. A machine that still sets `nixpkgs.overlays` gets
#     `fleetPkgs.appendOverlays overlays`, i.e. its own instance
#     (modules/nixos/nvidia.nix on scheelite). Setting `nixpkgs.config` next to
#     `nixpkgs.pkgs` fails a nixpkgs-module assertion, so per-machine config
#     belongs in this instance or in an overlay.
#   - modules/home/mk-home.nix passes it as homeManagerConfiguration's `pkgs`.
# Each machine's home-manager users inherit it through `useGlobalPkgs`.
#
# This is deliberately not the perSystem `pkgs` (modules/nixpkgs/per-system.nix):
# that instance builds the pkgs-by-name packages which flake.overlays.default
# re-exports, so it cannot itself carry flake.overlays.default.
#
# Configuration:
#   - config.allowUnfree: required for proprietary packages
#     (copilot-language-server, NVIDIA drivers, casks, etc.)
#   - config.permittedInsecurePackages: the exact name-version pairs the
#     fleet accepts despite nixpkgs knownVulnerabilities.
#   - overlays: the composed flake.overlays.default, so machines and homes see
#     the overlay-provided attributes (e.g. openclaw-gateway, mactop, channels).
{
  config,
  inputs,
  withSystem,
  ...
}:
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

  defaults =
    { config, ... }:
    {
      nixpkgs.pkgs = withSystem config.nixpkgs.hostPlatform.system ({ fleetPkgs, ... }: fleetPkgs);
    };
in
{
  perSystem =
    { system, ... }:
    {
      _module.args.fleetPkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          inherit permittedInsecurePackages;
        };
        overlays = [ config.flake.overlays.default ];
      };
    };
  flake.modules.darwin.base = defaults;
  flake.modules.nixos.base = defaults;
}
