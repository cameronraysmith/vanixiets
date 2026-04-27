# mactop test-disable
#
# TestHeadlessIntegration tries to mkdir /homeless-shelter (sandbox $HOME)
# Symptom: mkdir /homeless-shelter: read-only file system
# Reference: https://github.com/metaspartan/mactop/issues
# TODO: Remove when upstream fixes test to use temp directory
# Date added: 2026-01-10
{ ... }:
{
  nixpkgsOverlays = [
    (final: prev: {
      mactop = prev.mactop.overrideAttrs (old: {
        doCheck = false;
      });
    })
  ];
}
