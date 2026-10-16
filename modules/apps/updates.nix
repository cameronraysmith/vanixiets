# Package update apps for packages with custom update scripts.
#
# Packages using nix-update-script do not need flake apps;
# invoke nix-update directly, e.g.:
#   nix-update --flake <package> --version=branch=main
#
# nix run .#update-claude-code
{ ... }:
{
  perSystem =
    { config, ... }:
    {
      apps.update-atomic = {
        type = "app";
        program = "${config.packages.atomic.updateScript}";
      };

      apps.update-claude-code = {
        type = "app";
        program = "${config.packages.claude-code.updateScript}";
      };

      apps.update-devin-cli = {
        type = "app";
        program = "${config.packages.devin-cli.updateScript}";
      };

      apps.update-xsra = {
        type = "app";
        program = "${config.packages.xsra.updateScript}";
      };

      apps.update-git-xet = {
        type = "app";
        program = "${config.packages.git-xet.updateScript}";
      };

      apps.update-hindsight = {
        type = "app";
        program = "${config.packages.hindsight.updateScript}";
      };

      apps.update-golem-binary = {
        type = "app";
        program = "${config.packages.golem-binary.updateScript}";
      };

      # greptimedb-bin exists only on x86_64-linux (its package.nix yields null
      # elsewhere); the updater is host-agnostic, so the app runs the script
      # itself and is available on every system, stibnite included.
      apps.update-greptimedb-bin = {
        type = "app";
        program = "${../../pkgs/by-name/greptimedb-bin/update.sh}";
      };

      apps.update-linear-cli = {
        type = "app";
        program = "${config.packages.linear-cli.updateScript}";
      };

      apps.update-quarto = {
        type = "app";
        program = "${config.packages.quarto-bin.updateScript}";
      };

      apps.update-worktrunk-bin = {
        type = "app";
        program = "${config.packages.worktrunk-bin.updateScript}";
      };

      apps.update-mergify-cli-bin = {
        type = "app";
        program = "${config.packages.mergify-cli-bin.updateScript}";
      };

      apps.update-buzz-source = {
        type = "app";
        program = "${config.packages.buzz-source.updateScript}";
      };

      apps.update-omnigraph = {
        type = "app";
        program = "${config.packages.omnigraph.updateScript}";
      };

      apps.update-moshi-hook = {
        type = "app";
        program = "${config.packages.moshi-hook.updateScript}";
      };
    };
}
