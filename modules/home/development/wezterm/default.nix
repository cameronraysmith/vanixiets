# WezTerm terminal emulator configuration
# Reference: https://alexplescan.com/posts/2024/08/10/wezterm/
{ ... }:
{
  flake.modules = {
    homeManager.development =
      {
        pkgs,
        config,
        lib,
        flake,
        osConfig ? null,
        ...
      }:
      {
        programs.wezterm = {
          enable = true;
          # On nix-darwin hosts with Homebrew the app is the `wezterm@nightly` cask
          # (modules/darwin/homebrew.nix), signed by its developer so TCC grants survive updates.
          # home-manager's `package` is not nullable and its shell integration sources
          # `${package}/etc/profile.d/wezterm.sh`, so this package exposes only the cask bundle's copy
          # of that script; the CLI comes from /opt/homebrew/bin. Standalone homes keep nixpkgs.
          package =
            if osConfig ? custom && osConfig.custom ? homebrew then
              pkgs.runCommand "wezterm-cask-shell-integration" { } ''
                mkdir -p $out/etc/profile.d
                ln -s /Applications/WezTerm.app/Contents/Resources/wezterm.sh $out/etc/profile.d/wezterm.sh
              ''
            else
              pkgs.wezterm;
          extraConfig = builtins.readFile ./wezterm.lua;
        };
      };
  };
}
