# tmux-command-palette - fzf-powered keybinding palette for tmux
#
# Searchable popup palette surfacing all tmux keybindings and custom commands.
# Overrides prefix+? with an fzf interface, prefix+Backspace for root table,
# and prefix+M-m for custom command lists.
#
# Source: https://github.com/lost-melody/tmux-command-palette
{
  lib,
  fetchFromGitHub,
  tmuxPlugins,
  makeWrapper,
  fzf,
  coreutils,
  gnused,
  gnugrep,
  getopt,
  mdcat,
}:

tmuxPlugins.mkTmuxPlugin {
  pluginName = "tmux-command-palette";
  rtpFilePath = "init.tmux";
  version = "unstable-2025-09-29";

  src = fetchFromGitHub {
    owner = "lost-melody";
    repo = "tmux-command-palette";
    rev = "dbcaf7666a05b7af34f3ba38c0a67a751188df7a";
    hash = "sha256-zkQhWRd4AiH9XjfRausvB2MNR3xXirYJA13OtvQ4oGQ=";
  };

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    for f in $target/scripts/show-prompt.sh $target/scripts/show-cmdlist.sh; do
      chmod +x "$f"
      wrapProgram "$f" \
        --prefix PATH : ${
          lib.makeBinPath [
            fzf
            coreutils
            gnused
            gnugrep
            getopt
            mdcat
          ]
        }
    done
  '';

  meta = {
    description = "fzf-powered keybinding palette and command launcher for tmux";
    homepage = "https://github.com/lost-melody/tmux-command-palette";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
