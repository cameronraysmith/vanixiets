# Global cognee-cli wrapper (deliverable E): a writeShellApplication named
# exactly cognee-cli that the cognee-memory plugin's skills and agent hardcode
# on PATH. It execs ${pkgs.python313Packages.cognee}/bin/cognee-cli directly:
# the cognee-nix overlay surfaces the package in pythonPackagesExtensions (so it
# is python313Packages.cognee, not a top-level pkgs.cognee, matching the NixOS
# module's services.cognee.package default), and the package carries no
# meta.mainProgram (lib.getExe would throw). It also bakes the canonical
# mesh --api-url (the CLI has no env fallback for it, so HTTP-delegate mode
# requires the flag), and supplies --api-key (sent as X-Api-Key, never the
# --api-token Bearer) by reading the sops-nix secret at runtime so no plaintext
# key enters the nix store. Baked optionals precede "$@" because the CLI
# declares --api-url/--api-key on the top-level argparse parser, before its
# subparsers, so they must appear ahead of the subcommand token.
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
      inherit (flake.lib.cognee) meshApiUrl;
      keyPath = config.sops.secrets."cognee-api-key".path;
    in
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "cognee-cli";
          runtimeInputs = [ pkgs.coreutils ];
          text = ''
            api_key=""
            if [ -r "${keyPath}" ]; then
              api_key="$(cat "${keyPath}")"
            fi
            exec ${pkgs.python313Packages.cognee}/bin/cognee-cli \
              --api-url "${meshApiUrl}" \
              --api-key "$api_key" \
              "$@"
          '';
          meta.description = "cognee CLI wrapper baking the mesh --api-url and the per-host sops --api-key";
        })
      ];
    };
}
