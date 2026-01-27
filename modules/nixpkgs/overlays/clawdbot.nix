# Clawdbot gateway with bundled extensions environment
#
# Flake-parts module exporting clawdbot overlay via list concatenation
#
# The llm-agents flake provides a clawdbot package that bundles all extensions
# (including matrix) at $out/lib/clawdbot/extensions/, but the upstream
# makeWrapper does not set CLAWDBOT_BUNDLED_PLUGINS_DIR to point there.
# This overlay wraps the existing binary to add the required env vars.
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      clawdbot-gateway =
        let
          basePkg = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.clawdbot;
        in
        basePkg.overrideAttrs (old: {
          postFixup = (old.postFixup or "") + ''
            wrapProgram $out/bin/clawdbot \
              --set CLAWDBOT_BUNDLED_PLUGINS_DIR "$out/lib/clawdbot/extensions" \
              --set CLAWDBOT_NIX_MODE 1
          '';

          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
        });
    })
  ];
}
