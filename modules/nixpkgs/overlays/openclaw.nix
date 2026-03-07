# flake-parts module exporting openclaw overlay
#
# The llm-agents flake provides an openclaw package that bundles all extensions
# (including matrix) at $out/lib/openclaw/extensions/, but the upstream
# build is missing several things this overlay patches:
#   1. OPENCLAW_BUNDLED_PLUGINS_DIR env var pointing to extensions/
#   2. The @matrix-org/matrix-sdk-crypto-nodejs native .node addon,
#      which is normally downloaded at npm install time via download-lib.js
#      but unavailable in the nix sandbox
#   3. v2026.3.2 build gap: tsdown.config.ts at this tag does not build all
#      plugin-sdk subpath entry points declared in package.json exports. The
#      matrix extension's send-queue.ts imports from the subpath
#      openclaw/plugin-sdk/keyed-async-queue, but the dist file is never
#      produced and Jiti's CJS resolver bypasses the exports map entirely
#      (resolving index.js as a directory). Patch the extension source to
#      import from the barrel openclaw/plugin-sdk which does export the symbol.
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
            # Patch subpath import that Jiti cannot resolve (v2026.3.2 build gap)
            # keyed-async-queue is re-exported from the barrel index.js
            ${prev.gnused}/bin/sed -i \
              's|from "openclaw/plugin-sdk/keyed-async-queue"|from "openclaw/plugin-sdk"|' \
              $out/lib/openclaw/extensions/matrix/src/matrix/send-queue.ts

            # Inject native Matrix crypto addon where the SDK expects it
            cp ${matrixCryptoNode} $out/lib/openclaw/node_modules/.pnpm/@matrix-org+matrix-sdk-crypto-nodejs@0.4.0/node_modules/@matrix-org/matrix-sdk-crypto-nodejs/matrix-sdk-crypto.linux-x64-gnu.node

            wrapProgram $out/bin/openclaw \
              --set OPENCLAW_BUNDLED_PLUGINS_DIR "$out/lib/openclaw/extensions" \
              --set OPENCLAW_NIX_MODE 1
          '';

          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
        });
    })
  ];
}
