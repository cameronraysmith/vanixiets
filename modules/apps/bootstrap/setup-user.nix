# Flake app: generate the user's age key for sops-nix secrets (first-time
# user setup only; idempotent on re-run).
#
# Usage:
#   nix run .#setup-user        # generate key if absent; print public key
#   nix run .#setup-user -- --help
#
# Chicken-and-egg note: Mirrors `make setup-user` from the repo-root
# Makefile. Requires nix to be already installed (this flake app cannot
# run before nix). For a clean-host first-contact, use `make setup-user`
# instead; both targets share the same idempotence guarantee.
#
# Idempotent: if ~/.config/sops/age/keys.txt already exists, the script
# re-prints the public key and exits 0 WITHOUT regenerating. Only the
# first invocation writes keys.txt (mode 0600).
#
# Template bifurcation (writeShellApplication): PURE READFILE FORM.
# The sidecar needs no nix-eval-time path injection.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.setup-user = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "setup-user";
            runtimeInputs = [
              pkgs.coreutils
              # `age` provides age-keygen directly, avoiding a nested
              # `nix shell nixpkgs#age` invocation (cleaner dependency
              # closure than the Makefile's approach).
              pkgs.age
            ];
            text = builtins.readFile ./setup-user.sh;
          }
        );
      };
    };
}
