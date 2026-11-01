{ ... }:
{
  # home-manager ships modules/programs/worktrunk.nix as of 17903129, so the
  # third-party module this aspect used to import
  # (flake.inputs.worktrunk.homeModules.default) became a second declaration of
  # programs.worktrunk.enable, which the module system rejects outright.
  #
  # The upstreamed module is a strict superset of the one it replaces: the same
  # enable/package/enable*Integration options with the same `wt config shell
  # init` semantics, plus a settings option and an all-default-off
  # claudeCodeIntegration tree. package is mkPackageOption with nullable, so
  # the worktrunk-bin override below still applies. Nothing this aspect used
  # was dropped, so the import goes and the settings stay.
  flake.modules.homeManager.ai =
    { pkgs, ... }:
    {
      programs.worktrunk = {
        enable = true;
        package = pkgs.worktrunk-bin;
        # Every list shows each branch's open PR with its check status, and
        # branches without a worktree, such as bookmarks pushed from the jj join.
        settings.list = {
          full = true;
          branches = true;
        };
      };
    };
}
