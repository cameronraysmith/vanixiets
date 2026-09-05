# gh-dash, a GitHub dashboard TUI. Enabling the home-manager module rather than
# listing the package in modules/home/development/tools.nix
# nix-manages $XDG_CONFIG_HOME/gh-dash/config.yml — until now gh-dash's own
# default dump, written by createConfigFileIfMissing on first run — and registers
# gh-dash as a `gh` extension. Keys left unset stay at gh-dash's compiled-in
# defaults.
#
# Split across two aggregates because the tuicr review binding calls `tuicr` and
# `htab`, which only the ai aggregate delivers: every user gets gh-dash itself,
# and the ai user alone gets the binding.
{ ... }:
{
  flake.modules.homeManager = {
    development =
      { lib, ... }:
      {
        programs.gh-dash.enable = lib.mkDefault true;
      };

    # Review the selected PR in tuicr, in a new herdr tab.
    #
    # A `prs:` binding is templated with RepoName, PrNumber, HeadRefName,
    # BaseRefName, and Author. RepoPath is resolved only through the `repoPaths`
    # mapping, falling back to the repo gh-dash was launched from
    # (resolveTemplateInput, internal/tui/modelUtils.go); with `repoPaths` unset a
    # dashboard row from any other repo leaves it missing, and the template runs
    # under missingkey=error. So the target is the checkout-independent
    # `owner/repo#N` form tuicr accepts (src/app/init.rs).
    #
    # `htab` (modules/home/herdr) is the herdr analogue of `tmux new-window`:
    # it creates the tab, runs the command in it over the socket, and exits, so
    # gh-dash's tea.ExecProcess resumes immediately. The command runs under
    # `$SHELL -c` (internal/shell/shell.go), so it stays free of substitutions
    # fish would read differently.
    #
    # Custom keybindings are matched before built-ins (internal/tui/ui.go), so `C`
    # shadows gh-dash's own checkout binding; Space still checks out.
    ai =
      { lib, config, ... }:
      {
        programs.gh-dash.settings.keybindings.prs = lib.mkIf config.programs.tuicr.enable (
          lib.mkDefault [
            {
              key = "C";
              name = "code review";
              command = "htab --label PR-{{.PrNumber}} tuicr pr {{.RepoName}}#{{.PrNumber}}";
            }
          ]
        );
      };
  };
}
