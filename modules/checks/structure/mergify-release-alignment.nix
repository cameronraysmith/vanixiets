# agent-plugins-mergify-cli and mergify-cli-bin are bumped by separate
# updaters (modules/apps/updates.nix) and must track the same release.
# The versions do not depend on the build system, so the check exists only
# on x86_64-linux.
{ self, lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-mergify-release-alignment = self.lib.mkStructuralCheck pkgs {
          name = "mergify-release-alignment";
          actual = self'.packages.agent-plugins-mergify-cli.version;
          expected = self'.packages.mergify-cli-bin.version;
        };
      };
    };
}
