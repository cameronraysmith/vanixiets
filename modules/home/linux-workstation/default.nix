# GUI applications for a graphical Linux home. Only hosts with a graphical
# session import this module; headless homes never do, so it may assume a
# display server, a desktop-entry consumer and Linux-only packages.
{ ... }:
{
  flake.modules.homeManager.linux-workstation =
    { pkgs, flake, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      antigravity-hub = flake.inputs.llm-agents.packages.${system}.antigravity-hub;
    in
    {
      # The development aggregate leaves the package null for headless homes
      # and for the Macs, which take Zed from the zed Homebrew cask in the
      # darwin base cask list.
      programs.zed-editor.package = pkgs.zed-editor;
      programs.calibre.enable = true;
      # Zathura, themed by catppuccin.zathura, is the LaTeX preview and
      # presentation viewer; Papers stays the default for PDFs.
      programs.zathura.enable = true;
      home.packages = [
        pkgs.gdu
        pkgs.zed-delta
        antigravity-hub
      ];
    };
}
