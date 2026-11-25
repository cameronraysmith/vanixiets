# tmux-command-palette - fzf-powered keybinding palette for tmux
#
# Searchable popup palette surfacing all tmux keybindings and custom commands.
# Overrides prefix+? with an fzf interface, prefix+Backspace for root table,
# and prefix+M-m for custom command lists.
#
# Source: https://github.com/lost-melody/tmux-command-palette
#
# The commit and the source hash are in pin.json: Renovate proposes the head of
# the branch it names, and realize-pin rewrites both. The version shows the
# commit's first seven characters.
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
let
  inherit
    ((import ../../../lib/pins.nix { inherit lib; }).load ./pin.json { name = "tmux-command-palette"; })
    pin
    pinPlan
    ;

  plugin = tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-command-palette";
    rtpFilePath = "init.tmux";
    version = "unstable-${builtins.substring 0 7 pin.version}";

    src = fetchFromGitHub (
      (pinPlan pin.version).artifacts.src.sourceBuild.fetchFromGitHub
      // {
        inherit (pin.artifacts.src.sourceBuild) hash;
      }
    );

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
  };
in
# mkTmuxPlugin replaces any passthru it is given with its own updateScript, so
# the pin is added to its result.
plugin
// {
  passthru = plugin.passthru // {
    inherit pin pinPlan;
  };
}
