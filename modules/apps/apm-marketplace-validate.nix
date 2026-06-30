# Consumer-path validation flake-app for the vanixiets apm skills marketplace.
#
# Manually runnable proof that an apm-native CONSUMER can register the
# marketplace this repo publishes and install every package into a throwaway,
# fully isolated environment that never touches the real $HOME / ~/.claude.
#
#   nix run .#apm-marketplace-validate -- --local    # offline, validates the worktree
#   nix run .#apm-marketplace-validate -- --remote    # github fetch (needs branch pushed)
#
# Mirrors the openspec-refresh-vendored-artifacts flake-app + co-located .sh
# sidecar convention. Read-only with respect to the repo; all writes land in a
# scratch tmpdir cleaned up on exit.
#
# Promotable to a herculesCI effect later via config.apps.apm-marketplace-validate.program
# (mirroring modules/effects/vanixiets/herculesCI/release-packages.nix, which
# consumes config.apps.<name>.program inside an effectScript). Not built as an
# effect here.
{ ... }:
{
  perSystem =
    {
      inputs',
      pkgs,
      lib,
      ...
    }:
    {
      apps.apm-marketplace-validate = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "apm-marketplace-validate";
            runtimeInputs = [
              inputs'.llm-agents.packages.apm
              pkgs.git # repo root + local git-backed marketplace `git show <ref>:<file>`
              pkgs.jq
              pkgs.yq-go
              pkgs.coreutils
              pkgs.cacert # TLS roots for the superpowers transitive dep + --remote fetch
              pkgs.gnugrep
            ];
            runtimeEnv = {
              SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
              GIT_SSL_CAINFO = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            };
            text = builtins.readFile ./apm-marketplace-validate.sh;
          }
        );
      };
    };
}
