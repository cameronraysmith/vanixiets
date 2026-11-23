# Command-line reads of the agent traces in the Langfuse Cloud project (EU),
# through the official Langfuse CLI behind a read-only allow-list.
#
# The key is a Viewer key, read-only on Langfuse's server, kept as the clan
# secrets langfuse-viewer-{public,secret}-key: workstation-only operator
# credentials, like hetzner-api-token, encrypted to users and no machine. The
# collectors' Application key (shared clan var langfuse) is never read here.
# Only the sops ciphertext, already public in this repository, reaches the
# store; sops decrypts it at run time with the caller's own age identity, and
# the key reaches the CLI through its environment alone. Another user gains it
# with `clan secrets users add-secret <user> langfuse-viewer-public-key` and
# the same for langfuse-viewer-secret-key.
#
# checks.x86_64-linux.langfuse-query builds the same script with stub sops and
# langfuse executables, and reads the key files from this app's program.
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
      apps.langfuse-query = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "langfuse-query";
            runtimeInputs = [
              # Reached through config.packages: the perSystem pkgs does not
              # carry the pkgs/by-name overlay (see modules/checks/apps.nix).
              config.packages.langfuse-cli
              pkgs.sops
              pkgs.jq
              pkgs.gawk
              pkgs.gnugrep
              pkgs.gnused
              pkgs.coreutils
            ];
            runtimeEnv = {
              LANGFUSE_QUERY_PUBLIC_KEY_FILE = ../../sops/secrets/langfuse-viewer-public-key/secret;
              LANGFUSE_QUERY_SECRET_KEY_FILE = ../../sops/secrets/langfuse-viewer-secret-key/secret;
            };
            text = builtins.readFile ./langfuse-query.sh;
          }
        );
        meta.description = "Read agent traces from Langfuse Cloud, read-only";
      };
    };
}
