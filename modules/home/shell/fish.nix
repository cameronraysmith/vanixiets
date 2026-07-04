# Fish shell - interactive shell option (login shell remains zsh)
# Tool integrations (atuin, zoxide, fzf, starship, direnv) enabled automatically
# via home.shell.enableFishIntegration cascade when programs.fish.enable = true
{ ... }:
{
  flake.modules = {
    homeManager.shell =
      {
        pkgs,
        config,
        lib,
        ...
      }:
      {
        programs.man.generateCaches = false; # (apropos)

        programs.fish = {
          enable = true;
          generateCompletions = false;

          # Interactive-parity plugins. Use `.src` (raw upstream layout): the built
          # package installs to share/fish/vendor_* which home-manager's plugin loader
          # does not read, so it would register zero abbreviations/bindings.
          plugins = [
            {
              name = "plugin-git";
              src = pkgs.fishPlugins.plugin-git.src;
            }
            {
              name = "puffer";
              src = pkgs.fishPlugins.puffer.src;
            }
            {
              name = "sponge";
              src = pkgs.fishPlugins.sponge.src;
            }
            {
              name = "done";
              src = pkgs.fishPlugins.done.src;
            }
            {
              name = "autopair";
              src = pkgs.fishPlugins.autopair.src;
            }
            {
              name = "fzf-fish";
              src = pkgs.fishPlugins.fzf-fish.src;
            }
          ];

          # TTY fallback - fish misbehaves in Linux console (TERM=linux)
          loginShellInit = ''
            if test "$TERM" = linux
              exec zsh; or exec bash
            end
          '';

          interactiveShellInit = ''
            # Vi mode keybindings. Command-line editing in $EDITOR uses fish's native
            # alt-e/alt-v; vi command mode is named `default` (not `normal`), so a
            # `bind -M normal` for edit_command_buffer would be inert.
            fish_vi_key_bindings

            # Keep our shared `gts = check_github_token_scopes` alias over plugin-git's
            # `gts = git tag -s`. plugin-git registers abbrs from conf.d, which fish
            # sources before config.fish, so erasing here (after) wins.
            abbr --erase gts

            # atuin owns Ctrl-R; neutralize the fzf-fish plugin's history widget so it
            # does not shadow atuin. (programs.fzf's own Ctrl-R is disabled separately
            # via historyWidget.command in terminal/fzf.nix, a distinct mechanism.)
            fzf_configure_bindings --history=
          '';

          # nnn cd-on-quit function (no home-manager fish integration exists)
          # Mirrors the zsh function in modules/home/development/zsh.nix
          functions.n = ''
            # Block nesting of nnn
            if set -q NNNLVL; and test "$NNNLVL" -ge 1
              echo "nnn is already running"
              return
            end

            set -x NNN_TMPFILE "$HOME/.config/nnn/.lastd"

            nnn -adeHo $argv

            if test -f "$NNN_TMPFILE"
              source "$NNN_TMPFILE"
              rm -f "$NNN_TMPFILE" > /dev/null
            end
          '';
        };
      };
  };
}
