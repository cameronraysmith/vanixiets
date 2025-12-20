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

          # TTY fallback - fish misbehaves in Linux console (TERM=linux)
          loginShellInit = ''
            if test "$TERM" = linux
              exec zsh; or exec bash
            end
          '';

          interactiveShellInit = ''
            # Vi mode keybindings
            fish_vi_key_bindings

            # Edit command in $EDITOR (like zsh's `vv`)
            # Alt+e in vi mode, or bind to `vv` in normal mode:
            bind -M normal v edit_command_buffer
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
