# Deploy the vanixiets-docs derivation to Cloudflare Workers.
#
#   nix run .#deploy-docs -- preview <branch>   preview version of <branch>
#   nix run .#deploy-docs -- production         production deploy; exits 0
#                                               without deploying when main
#                                               has moved past this commit
#
# Why: consumes the nix-built CF Worker payload from
# config.packages.vanixiets-docs (DOCS_PAYLOAD). A caller may set DOCS_PAYLOAD
# to another build of the docs: the preview effect passes a pull request's.
#
# Template bifurcation (writeShellApplication): INTERPOLATION FORM.
# `text` is a nix string that injects one eval-time-computed path
# (DOCS_PAYLOAD via config.packages.vanixiets-docs) into the script preamble
# before the readFile'd sidecar body. Contrast with `release.nix` and
# `preview-version.nix`, which use the pure
# `text = builtins.readFile ./<name>.sh` form because they have no
# nix-eval-time path injection requirement (they rely on runtimeEnv only).
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
            # sed/awk/grep/find/curl are explicitly declared because the
            # hercules-ci-effects bwrap sandbox PATH does not include them
            # by default; curl resolves main's head for the production
            # supersede check. Required for the writeShellApplication
            # invariant that PATH equals runtimeInputs at runtime.
            runtimeInputs = [
              pkgs.nodejs_24
              pkgs.curl
              pkgs.jq
              pkgs.coreutils
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
              pkgs.gawk
              pkgs.findutils
            ];
            runtimeEnv = {
              DOCS_NODE_MODULES = "${config.packages.vanixiets-docs-deps}/packages/docs/node_modules";
            };
            text = ''
              export DOCS_PAYLOAD="''${DOCS_PAYLOAD:-${config.packages.vanixiets-docs}}"
              ${builtins.readFile ./deploy.sh}
            '';
          }
        );
      };
    };
}
