# flake-parts module exporting openclaw overlay
#
# The llm-agents flake provides an openclaw package that bundles all extensions
# (including matrix) at $out/lib/openclaw/extensions/, but the upstream
# build is missing two things this overlay patches:
#   1. OPENCLAW_NIX_MODE env var so openclaw skips runtime downloads
#   2. The @matrix-org/matrix-sdk-crypto-nodejs native .node addon,
#      which is normally downloaded at npm install time via download-lib.js
#      but unavailable in the nix sandbox
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      openclaw-gateway =
        let
          basePkg = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.openclaw;

          # Native addon for Matrix E2EE crypto, downloaded from upstream GitHub release
          matrixCryptoNode = prev.fetchurl {
            url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v0.4.0/matrix-sdk-crypto.linux-x64-gnu.node";
            sha256 = "06779l1ry2hxdxssiwj3gviyrbb43xi4yb0rzndgfa3ik3fx8y3h";
          };
        in
        basePkg.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            # Inject native Matrix crypto addon where the SDK expects it.
            # Search entire node_modules tree to handle both pnpm flat-store and hoisted layouts.
            cryptoDir=$(find $out/lib/openclaw/node_modules -type d -name "matrix-sdk-crypto-nodejs" -path "*/@matrix-org/*" | head -1)
            if [ -n "$cryptoDir" ]; then
              cp ${matrixCryptoNode} "$cryptoDir/matrix-sdk-crypto.linux-x64-gnu.node"
            else
              echo "error: matrix-sdk-crypto-nodejs directory not found in node_modules — native addon injection failed" >&2
              exit 1
            fi

            wrapProgram $out/bin/openclaw \
              --set OPENCLAW_NIX_MODE 1
          '';

          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
        });
    })
  ];
}
