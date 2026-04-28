# bitwarden-cli wrap to silence punycode deprecation warning on Node 22+
#
# Upstream: https://github.com/bitwarden/clients/issues/18741
# TODO: Remove when upstream resolves punycode dependency
# Date added: 2026-03-31
#
# Skipped on aarch64-darwin because stable-fallbacks.nix routes
# pkgs.bitwarden-cli to the cached stable derivation on that platform
# to avoid local rebuild from channel lag. overrideAttrs would force
# a full rebuild even though the underlying stable output is cached;
# accept the punycode warning there as a tradeoff for cache hit.
{ ... }:
{
  nixpkgsOverlays = [
    (
      final: prev:
      prev.lib.optionalAttrs (prev.stdenv.hostPlatform.system != "aarch64-darwin") {
        bitwarden-cli = prev.bitwarden-cli.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
          postInstall = (old.postInstall or "") + ''
            wrapProgram $out/bin/bw \
              --set NODE_OPTIONS "--no-deprecation"
          '';
        });
      }
    )
  ];
}
