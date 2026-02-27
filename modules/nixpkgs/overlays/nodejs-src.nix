# Workaround for nixpkgs PR #481461 which restructured nodejs_* from
# mkDerivation to symlinkJoin over nodejs-slim_*, removing the src attribute.
# playwright-web-flake node-env.nix:211 accesses nodejs.src for native bindings.
{ ... }:
{
  flake.nixpkgsOverlays = [
    (
      final: prev:
      let
        restoreSrc =
          nodejs: slim: if slim ? src && !(nodejs ? src) then nodejs // { inherit (slim) src; } else nodejs;
      in
      {
        nodejs_22 = restoreSrc prev.nodejs_22 prev.nodejs-slim_22;
        nodejs_24 = restoreSrc prev.nodejs_24 prev.nodejs-slim_24;
      }
    )
  ];
}
