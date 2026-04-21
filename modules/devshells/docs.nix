{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.docs = pkgs.mkShell {
        name = "vanixiets-docs-dev";
        inputsFrom = [ config.packages.vanixiets-docs ];
        packages = [
          pkgs.sops
          pkgs.age
          pkgs.jq
        ];
        passthru.meta.description = "Narrow environment for docs authoring and local experimentation";
      };
    };
}
