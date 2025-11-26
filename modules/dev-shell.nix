{
  perSystem =
    {
      pkgs,
      inputs',
      config,
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.pre-commit.devShell ];

        packages = [
          inputs'.clan-core.packages.default
          pkgs.just
          pkgs.nh
          pkgs.nix-output-monitor
          # Tools required by Makefile verify target
          pkgs.age
          pkgs.ssh-to-age
          pkgs.sops
        ];

        passthru.meta.description = "Development environment with clan CLI and build tools";
      };
    };
}
