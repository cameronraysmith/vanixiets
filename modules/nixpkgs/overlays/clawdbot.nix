# flake-parts module exporting clawdbot overlay
#
# The llm-agents flake provides a clawdbot package that bundles all extensions
# (including matrix) at $out/lib/clawdbot/extensions/, but the upstream
# build is missing two things:
#   1. CLAWDBOT_BUNDLED_PLUGINS_DIR env var pointing to extensions/
#   2. The @matrix-org/matrix-sdk-crypto-nodejs native .node addon,
#      which is normally downloaded at npm install time via download-lib.js
#      but unavailable in the nix sandbox
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      clawdbot-gateway =
        let
          basePkg = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.clawdbot;

          # Native addon for Matrix E2EE crypto, downloaded from upstream GitHub release
          matrixCryptoNode = prev.fetchurl {
            url = "https://github.com/matrix-org/matrix-rust-sdk-crypto-nodejs/releases/download/v0.4.0/matrix-sdk-crypto.linux-x64-gnu.node";
            sha256 = "06779l1ry2hxdxssiwj3gviyrbb43xi4yb0rzndgfa3ik3fx8y3h";
          };
        in
        basePkg.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            # Inject native Matrix crypto addon where the SDK expects it
            cp ${matrixCryptoNode} $out/lib/clawdbot/node_modules/.pnpm/@matrix-org+matrix-sdk-crypto-nodejs@0.4.0/node_modules/@matrix-org/matrix-sdk-crypto-nodejs/matrix-sdk-crypto.linux-x64-gnu.node

            wrapProgram $out/bin/clawdbot \
              --set CLAWDBOT_BUNDLED_PLUGINS_DIR "$out/lib/clawdbot/extensions" \
              --set CLAWDBOT_NIX_MODE 1
          '';

          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
        });
    })
  ];
}
