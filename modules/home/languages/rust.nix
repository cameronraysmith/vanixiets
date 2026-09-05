{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        dioxus-cli
        rustup
      ];
    };
}
