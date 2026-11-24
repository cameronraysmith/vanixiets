{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
  flake.modules.homeManager.development.imports = [
    config.flake.modules.homeManager.nix-classic
  ];
  flake.modules.homeManager.nix-classic =
    {
      config,
      lib,
      pkgs,
      osConfig ? null,
      ...
    }:
    let
      host = if osConfig == null then { } else flakeLib.hosts.${osConfig.networking.hostName} or { };
    in
    {
      key = "vanixiets/nix-classic-home-module";

      options.nixClassic.enable = lib.mkOption {
        type = lib.types.bool;
        default = host.nixClassic or false && host.primaryUser == config.home.username;
        defaultText = lib.literalExpression "the host's flake.lib.hosts.<name>.nixClassic, for its primaryUser";
        description = ''
          iets' classic mode as `nix` for this user (flake.lib.nixClassic): on the
          user's PATH and in this repository's default devShell, which carries the
          same wrapper inert. Writes the marker file the wrapper checks;
          `nix-stock` is the real Nix, and deleting the marker turns classic off at
          once for every shell and agent.
        '';
      };

      config = lib.mkIf config.nixClassic.enable {
        home.packages = [ (flakeLib.nixClassic pkgs) ];
        xdg.configFile."nix-classic/enabled".text = "";
      };
    };
}
