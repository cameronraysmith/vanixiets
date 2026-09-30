# Deploy the vanixiets-docs derivation to Cloudflare Workers.
#
#   nix run .#deploy-docs -- production --rev <sha>
#   nix run .#deploy-docs -- preview --rev <sha> --alias <name> [--payload <dir>]
#
# Why: the program deploys the nix-built CF Worker payload from
# config.packages.vanixiets-docs, interpolated into the script as the
# non-exported shell variable `builtin_payload` so no environment variable can
# replace what production deploys. Only preview accepts another build, through
# --payload.
{ ... }:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      apps.deploy-docs = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "deploy-docs";
            # Secrets flow via inherited env (never via `sops exec-env`
            # inside the script), so pkgs.sops / pkgs.age are not required
            # runtime inputs.
            #
            # The hercules-ci-effects bwrap sandbox PATH is runtimeInputs
            # only; curl resolves main's head for the production supersede
            # check.
            runtimeInputs = [
              pkgs.nodejs_24
              pkgs.curl
              pkgs.jq
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.gawk
              pkgs.findutils
            ];
            runtimeEnv = {
              DOCS_NODE_MODULES = "${config.packages.vanixiets-docs-deps}/packages/docs/node_modules";
            };
            text = ''
              builtin_payload=${lib.escapeShellArg config.packages.vanixiets-docs}
              ${builtins.readFile ./deploy.sh}
            '';
          }
        );
      };
    };
}
