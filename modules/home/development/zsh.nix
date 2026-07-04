# Enhanced zsh configuration with oh-my-zsh, syntax highlighting, completions
{ ... }:
{
  flake.modules = {
    homeManager.development =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.zsh = {
          enable = true;
          dotDir = "${config.xdg.configHome}/zsh";
          autosuggestion.enable = true;
          enableCompletion = true;

          initContent = ''
            # Special handling for nnn's cd-on-quit functionality
            # This needs to be a shell function to change the current shell's directory
            n() {
              # Block nesting of nnn
              if [ -n "$NNNLVL" ] && [ "$NNNLVL" -ge 1 ]; then
                echo "nnn is already running"
                return
              fi

              export NNN_TMPFILE="$HOME/.config/nnn/.lastd"

              nnn -adeHo "$@"

              if [ -f "$NNN_TMPFILE" ]; then
                . "$NNN_TMPFILE"
                rm -f "$NNN_TMPFILE" > /dev/null
              fi
            }
          '';

          oh-my-zsh = {
            enable = true;
            plugins = [
              "git"
              "rust"
              "vi-mode"
              "zoxide"
            ];
            theme = "robbyrussell";
          };

          syntaxHighlighting = {
            enable = true;
          };
        };
      };
  };
}
