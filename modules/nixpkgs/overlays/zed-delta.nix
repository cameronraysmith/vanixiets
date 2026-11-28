# Zed Industries' Delta agent workspace, from the Linux-only delta-nix flake.
# It is exposed as zed-delta because `delta` names the git diff pager that git,
# jujutsu and lazygit invoke (modules/home/development/git.nix). The desktop
# entry execs Delta's own store path, so the package does not need bin/delta.
{ inputs, ... }:
{
  nixpkgsOverlaysByName.zed-delta = [
    (
      _final: prev:
      prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
        zed-delta =
          let
            delta = inputs.delta.packages.${prev.stdenv.hostPlatform.system}.delta;
          in
          prev.runCommand "zed-delta-${delta.version}"
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
      }
    )
  ];
}
