# How this fleet deploys the Perses dashboard service
# (flake.modules.nixos.perses, which stays free of `vanixiets.secrets` so the runtime
# tests can import it with their own credentials): the session-token
# encryption key's secret and the three credentials perses.service loads.
# The store password comes from greptimedb-users and the OIDC client secret
# from kanidm-oauth2-perses, read through config.vanixiets.secrets
# without importing the aspects that declare them, so a host that imports this
# one without them fails evaluation naming the missing secret.
{
  flake.modules.nixos.perses-server =
    { config, pkgs, ... }:
    {
      # Perses signs its session tokens with this key (design D8); 32 bytes,
      # as Perses requires, and replaced only by regeneration, which restarts
      # perses.service.
      vanixiets.secrets.perses-encryption-key = {
        files.key = {
          mode = "0400";
          restartUnits = [ "perses.service" ];
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          printf '%s' "$(openssl rand -hex 16)" > "$out/key"
        '';
      };

      # The three files flake.modules.nixos.perses reads, each under
      # /run/credentials/perses.service/.
      systemd.services.perses.serviceConfig.LoadCredential = [
        "kanidm-client-secret:${config.vanixiets.secrets.kanidm-oauth2-perses.files.secret.path}"
        "encryption-key:${config.vanixiets.secrets.perses-encryption-key.files.key.path}"
        "perses-password:${config.vanixiets.secrets.greptimedb-users.files.perses-password.path}"
      ];
    };
}
