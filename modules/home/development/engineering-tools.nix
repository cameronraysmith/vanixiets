{ ... }:
{
  flake.modules.homeManager.engineering-tools =
    { pkgs, ... }:
    {
      key = "vanixiets/engineering-tools-home-module";
      home.packages = [
        pkgs.jc
        pkgs.just
        pkgs.uncomment-bin
        pkgs.ratchet
        pkgs.shellcheck
        pkgs.jaq
        pkgs.yq
      ];
    };
}
