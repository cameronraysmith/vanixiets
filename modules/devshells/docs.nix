{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.docs = pkgs.mkShell {
        name = "vanixiets-docs-dev";
        inputsFrom = [ config.packages.vanixiets-docs ];
        packages = [
          # vanixiets-docs no longer pulls in bun2nix.hook, which used to
          # propagate bun into this shell; `bun run dev` still needs it.
          pkgs.bun
          pkgs.sops
          pkgs.age
          pkgs.jq
        ];
        passthru.meta.description = "Narrow environment for docs authoring and local experimentation";
      };
    };
}
