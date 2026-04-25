# Flake app: re-run the bootstrap flow from an already-nix-ready host.
#
# Chicken-and-egg note: The repo's primary bootstrap entry point is the
# Makefile (`make bootstrap`), which installs nix itself via the NixOS
# community installer and only then installs direnv. This flake app, by
# contrast, can only run once nix is already present (since `nix run`
# requires nix). It exists for reproducibility / scripting on hosts that
# have nix but want to (idempotently) finish the direnv half of bootstrap
# or re-verify that bootstrap has been completed.
#
# Idempotent.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.bootstrap = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "bootstrap";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              # `nix` is in runtimeInputs so `nix profile install` works
              # from within the hermetic PATH. The host must already have
              # a running nix daemon; this app is explicitly not a
              # first-contact installer (the Makefile is).
              pkgs.nix
            ];
            text = builtins.readFile ./bootstrap.sh;
          }
        );
      };
    };
}
