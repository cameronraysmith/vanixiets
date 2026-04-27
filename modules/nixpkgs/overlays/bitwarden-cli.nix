# bitwarden-cli wrap to silence punycode deprecation warning on Node 22+
#
# Upstream: https://github.com/bitwarden/clients/issues/18741
# TODO: Remove when upstream resolves punycode dependency
# Date added: 2026-03-31
{ ... }:
{
  nixpkgsOverlays = [
    (final: prev: {
      bitwarden-cli = prev.bitwarden-cli.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
        postInstall = (old.postInstall or "") + ''
          wrapProgram $out/bin/bw \
            --set NODE_OPTIONS "--no-deprecation"
        '';
      });
    })
  ];
}
