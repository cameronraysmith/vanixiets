# Command-line reads of the agent traces in the Langfuse Cloud project (EU),
# through the official Langfuse CLI behind a read-only allow-list.
#
# The project key is the shared clan var langfuse/{public,secret}-key; only
# its sops ciphertext, already public in this repository, reaches the store.
# sops decrypts it at run time with the caller's own age identity, and the key
# reaches the CLI through its environment alone.
#
# checks.x86_64-linux.langfuse-query builds the same script with stub sops and
# langfuse executables.
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
              LANGFUSE_QUERY_PUBLIC_KEY_FILE = ../../vars/shared/langfuse/public-key/secret;
              LANGFUSE_QUERY_SECRET_KEY_FILE = ../../vars/shared/langfuse/secret-key/secret;
            };
            text = builtins.readFile ./langfuse-query.sh;
          }
        );
        meta.description = "Read agent traces from Langfuse Cloud, read-only";
      };
    };
}
