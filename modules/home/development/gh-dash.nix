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
    # Landing in this repository is queue-mediated, and gh-dash's built-in `m`
    # cannot express that: MergePR (internal/tui/components/tasks/pr.go) hardcodes
    # `gh pr merge <N> -R <repo>` with no flags. Our default-branch rulesets
    # require nixbot/nix-eval, nixbot/nix-build, nixbot/effects, and the App's
    # gitea-mq, so a fresh PR is BLOCKED and gh's canMerge (pkg/cmd/pr/merge in
    # cli/cli) refuses with "add the `--auto` flag" — gh-dash then reports the
    # failure. gitea-mq is also not GitHub's native merge queue, so gh's
    # isMergeQueueEnabled path never fires and `--auto` stays the enqueue signal.
    #
    # Custom bindings are matched before built-ins (internal/tui/ui.go), so `m`
    # shadows the built-in merge with the enqueue that actually works, and `M`
    # covers the registered-stack case, where auto-merge on any member is
    # forbidden and the merge-queue label on the topmost PR is the authorization.
    # Both are non-interactive: one keystroke is a merge authorization.
    #
    # mkDefault on both this list and the tuicr list below keeps them at equal
    # priority so the module system concatenates them; a plain list here would
    # outrank the mkDefault one and silently drop the review binding.
    development =
      { lib, ... }:
      {
        programs.gh-dash.enable = lib.mkDefault true;

        programs.gh-dash.settings.keybindings.prs = lib.mkDefault [
          {
            key = "m";
            name = "enqueue";
            command = "gh pr merge --auto --rebase --repo {{.RepoName}} {{.PrNumber}}";
          }
          {
            key = "M";
            name = "enqueue stack";
            command = "gh pr edit --repo {{.RepoName}} {{.PrNumber}} --add-label merge-queue";
          }
        ];
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
