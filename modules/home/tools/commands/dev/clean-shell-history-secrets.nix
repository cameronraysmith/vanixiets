{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "clean-shell-history-secrets";
          runtimeInputs = with pkgs; [
            atuin
            gitleaks
            jq
          ];
          text = builtins.readFile ./clean-shell-history-secrets.sh;
          meta.description = "Clean secrets from shell history using atuin and gitleaks";
        })
      ];
    };
}
