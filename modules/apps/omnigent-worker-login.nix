{ ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      packages.omnigent-worker-login = pkgs.writeShellApplication {
        name = "omnigent-worker-login";
        runtimeInputs = [ pkgs.openssh ];
        text = builtins.readFile ./omnigent-worker-login.sh;
      };
      apps.omnigent-worker-login = {
        type = "app";
        program = lib.getExe config.packages.omnigent-worker-login;
      };
    };
}
