# bitwarden-cli wrap to silence punycode deprecation warning on Node 22+
#
# Upstream: https://github.com/bitwarden/clients/issues/18741
# TODO: Remove when upstream resolves punycode dependency
# Date added: 2026-03-31
#
# Skipped on aarch64-darwin so that platform keeps substituting the
# cache.nixos.org build: overrideAttrs forces a full local rebuild, so the
# punycode warning is accepted there as the price of the cache hit.
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
