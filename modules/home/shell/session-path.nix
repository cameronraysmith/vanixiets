# Interactive-shell PATH tail (zsh, bash, fish).
# APPENDS Homebrew, krew, and user-local bins at LOWEST priority so the
# nix-managed entries nix-darwin's set-environment exports earlier always win
# over Homebrew. Appended (not prepended, not via home.sessionPath which
# prepends) so Homebrew/krew/user-local never shadow nix. Each append attaches
# to the same home-manager class that defines its shell: zsh -> development,
# bash and fish -> shell.
{ lib, ... }:
let
  extraPaths = [
    "/opt/homebrew/bin"
    "$HOME/.krew/bin"
    "$HOME/.local/bin"
  ];
  pathLine = ''export PATH="$PATH:${lib.concatStringsSep ":" extraPaths}"'';
  fishPathLine = "fish_add_path --append --global /opt/homebrew/bin $HOME/.krew/bin $HOME/.local/bin";
in
{
  flake.modules = {
    homeManager.development =
      { ... }:
      {
        programs.zsh.envExtra = lib.mkAfter pathLine;
      };
    homeManager.shell =
      { ... }:
      {
        programs.bash.initExtra = lib.mkAfter pathLine;
        programs.fish.interactiveShellInit = lib.mkAfter fishPathLine;
      };
  };
}
