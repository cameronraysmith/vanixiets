{
  # OUTER: Flake-parts module signature
  ...
}:
let
  content =
    {
      # INNER: Home-manager module signature
      config,
      flake, # the home's own module argument (flake.lib.homeFlake)
      ...
    }:
    {
      home.stateVersion = "23.11";

      sops = {
        defaultSopsFile = ../../../../secrets/home-manager/users/ubuntu/secrets.yaml;

        secrets = {
          # `development/radicle.nix` places the login key at ~/.radicle/keys/radicle.
          ssh-signing-key = {
            mode = "0400";
          };
          commit-signing-key = {
            mode = "0400";
          };
          linear-api-key-personal = { };
          linear-api-key-work = { };
          linear-workspace-personal = { };
          linear-workspace-work = { };
        };

        templates."linear-credentials.toml" = flake.lib.mkLinearCredentialsTemplate config;
      };

      # The one profile on no clan machine: it signs with its own sops entry
      # rather than a generated `<person>-commit-signing-key` var.
      vcs.signing.keyFile = config.sops.secrets.commit-signing-key.path;

      # Devin sources $ENVRC under `set -a` at the top of every exec shell, and
      # $ENVRC sources the sandbox aggregate's ~/.config/vanixiets/session-env.sh,
      # so it runs before every tool call. That is the only automatic
      # session-start trigger available: the blueprint's maintenance block is
      # surfaced to the agent rather than executed.
      vanixiets.sandbox.sopsDir = "/dev/shm/ubuntu-sops";
    };
in
{
  flake.users.ubuntu.contentPrivate = content;
}
