# Global cognee wrapper: a writeShellApplication named cognee that execs
# ${pkgs.python313Packages.cognee}/bin/cognee-cli directly. The cognee-nix
# overlay surfaces the package in pythonPackagesExtensions (so it is
# python313Packages.cognee, not a top-level pkgs.cognee, matching the NixOS
# module's services.cognee.package default), and the package carries no
# meta.mainProgram (lib.getExe would throw). The wrapper bakes the hosted SaaS
# --api-url (the CLI has no env fallback for it, so HTTP-delegate mode requires
# the flag) and supplies --api-key (sent as X-Api-Key, never the --api-token
# Bearer) by reading the sops-nix secret at runtime so no plaintext key enters
# the nix store, then forwards "$@". It defaults LOG_LEVEL to ERROR and
# COGNEE_LOG_FILE to false to keep output quiet, both overridable per-invocation
# (e.g. `LOG_LEVEL=INFO cognee datasets list`). It no longer passes --user-id: the
# SaaS scopes by api-key alone. Baked optionals precede "$@" because the CLI
# declares --api-url/--api-key on the top-level argparse parser, before its
# subparsers, so they must appear ahead of the subcommand token. The raw
# upstream cognee-cli is also placed on PATH unwrapped for testing/experiments.
{ ... }:
{
  flake.modules.homeManager.ai =
    {
      pkgs,
      config,
      flake, # extraSpecialArgs: config.flake // { inherit inputs; }; exposes flake.lib.cognee
      ...
    }:
    let
      inherit (flake.lib.cognee) saasApiUrl;
      keyPath = config.sops.secrets."cognee-api-key".path;
    in
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "cognee";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            api_key=""
            if [ -r "${keyPath}" ]; then
              api_key="$(cat "${keyPath}")"
            fi
            export LOG_LEVEL="''${LOG_LEVEL:-ERROR}"
            export COGNEE_LOG_FILE="''${COGNEE_LOG_FILE:-false}"
            exec ${pkgs.python313Packages.cognee}/bin/cognee-cli \
              --api-url "${saasApiUrl}" \
              --api-key "$api_key" \
              "$@"
          '';
          meta.description = "cognee CLI wrapper baking the hosted SaaS --api-url and the per-host sops --api-key";
        })
        # raw, unwrapped cognee-cli on PATH (no baked SaaS flags/env) for ad-hoc/testing
        pkgs.python313Packages.cognee
      ];
    };
}
