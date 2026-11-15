# GUI applications for a graphical Linux home. Only hosts with a graphical
# session import this module; headless homes never do, so it may assume a
# display server, a desktop-entry consumer and Linux-only packages.
{ ... }:
{
  flake.modules.homeManager.linux-workstation =
    { pkgs, flake, ... }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      delta = flake.inputs.delta.packages.${system}.delta;
      # Expose Delta as zed-delta because `delta` names the git pager that git,
      # lazygit and jujutsu invoke (development/git.nix). The desktop entry
      # execs Delta's own store path, so it does not need bin/delta.
      zed-delta =
        pkgs.runCommand "zed-delta-${delta.version}"
          {
            meta = delta.meta // {
              mainProgram = "zed-delta";
            };
          }
          ''
            mkdir -p $out/bin
            ln -s ${delta}/bin/delta $out/bin/zed-delta
            ln -s ${delta}/share $out/share
          '';
      antigravity-hub = flake.inputs.llm-agents.packages.${system}.antigravity-hub;
    in
    {
      # The development aggregate leaves the package null for headless homes
      # and stibnite's Homebrew cask.
      programs.zed-editor.package = pkgs.zed-editor;
      programs.calibre.enable = true;
      # Zathura, themed by catppuccin.zathura, is the LaTeX preview and
      # presentation viewer; Papers stays the default for PDFs.
      programs.zathura.enable = true;
      home.packages = [
        pkgs.gdu
        zed-delta
        antigravity-hub
      ];
    };
}
