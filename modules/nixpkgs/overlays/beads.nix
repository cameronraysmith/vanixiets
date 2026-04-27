# beads sourced via overlay because pkgs.beads has multiple consumers
# including a callPackage cross-coupling in pkgs/by-name/beads-ui —
# per-site inline would either require threading inputs through that
# derivation or parallel edits at every consumer.
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      beads = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.beads;
    })
  ];
}
