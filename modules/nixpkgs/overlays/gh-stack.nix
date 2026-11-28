# nixpkgs fetches gh-stack by tag only; record the commit the tag names so the
# structure-release-alignment-gh-stack check can compare the skill's apm.yml ref
# with it. structure-release-alignment-gh-stack-tag refetches github/gh-stack at
# this commit with nixpkgs' source hash, so a nixpkgs bump fails there until this
# and the apm.yml ref move together.
{ ... }:
{
  nixpkgsOverlaysByName.gh-stack = [
    (_final: prev: {
      gh-stack = prev.gh-stack.overrideAttrs (old: {
        passthru = (old.passthru or { }) // {
          sourceRev = "2a49e6751238633db504655d8a8eba3e433e827d";
        };
      });
    })
  ];
}
