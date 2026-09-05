{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        bun
        nodejs_22
        pnpm
        tailwindcss_4
        yarn-berry
      ];
    };
}
