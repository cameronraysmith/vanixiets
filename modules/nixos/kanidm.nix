# kanidm IdP for magnetite — server scaffold + nginx-fronted TLS + OAuth2 synapse client.
#
# Shape (per ADR-0022): nginx terminates public TLS via ACME and reverse-proxies to
# kanidm bound on 127.0.0.1:8443. A single security.acme.certs."accounts..." entry
# serves both legs — nginx via useACMEHost, kanidm via LoadCredential into
# /run/credentials/kanidm.service/. Hostname is a literal FQDN per ADR-0023; package
# is pinned to kanidmWithSecretProvisioning_1_10 per ADR-0027.
#
# Clan-vars secret generators land in nix-4qr.2 (admin-password, idm-admin-password,
# kanidm-oauth2-synapse). This scaffold references those generator paths so the .2
# dispatch can drop in generators and password/secret file wiring without editing
# this module's structure. basicSecretFile on the synapse OAuth2 client is omitted
# here (null default → kanidm generates a random secret per provision) and will be
# bound to the clan-vars path in .2.
#
# Cameron's kanidm account is intentionally not declared via provision.persons
# (gotcha 4 — destructive on re-provision); creation is operational per ADR-0025.
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.kanidm =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      domain = "accounts.scientistexperience.net";
    in
    {
      services.kanidm = {
        package = pkgs.kanidmWithSecretProvisioning_1_10;

        server.enable = true;

        server.settings = {
          inherit domain;
          origin = "https://${domain}";

          # Loopback bind; nginx fronts public TLS per ADR-0022 sub-decision.
          bindaddress = "127.0.0.1:8443";

          # See real client IPs through the nginx reverse-proxy hop.
          trust_x_forward_for = true;

          # Cert material delivered via systemd LoadCredential (defelo-nixos pattern,
          # preferred over filesystem-ACL sharing per ADR-0022 alternatives).
          tls_chain = "/run/credentials/kanidm.service/tls_chain";
          tls_key = "/run/credentials/kanidm.service/tls_key";
        };

        provision = {
          enable = true;

          # Destructive removal of state-only entities is disabled until cameron's
          # account is migrated. See gotcha 4 + ADR-0025.
          autoRemove = false;

          groups = {
            # No-op declaration required before scopeMaps.matrix_users references.
            matrix_users = { };
          };

          systems.oauth2.synapse = {
            displayName = "Matrix";
            originUrl = "https://matrix.scientistexperience.net/_synapse/client/oidc/callback";
            originLanding = "https://matrix.scientistexperience.net/";
            preferShortUsername = true;
            scopeMaps.matrix_users = [
              "openid"
              "profile"
              "email"
            ];
            # basicSecretFile bound to clan-vars path in nix-4qr.2:
            #   = config.clan.core.vars.generators.kanidm-oauth2-synapse.files.secret.path;
          };
        };
      };

      # Single ACME cert serves both nginx (public leg) and kanidm (loopback leg).
      # postRun restarts kanidm so cert rotation is picked up by the in-process TLS
      # loop (LoadCredential snapshots cert material at unit-start).
      security.acme.certs.${domain} = {
        postRun = "systemctl restart kanidm.service";
      };

      # Block kanidm startup on ACME cert availability; deliver cert via
      # LoadCredential into /run/credentials/kanidm.service/.
      systemd.services.kanidm = {
        requires = [ "acme-${domain}.service" ];
        after = [ "acme-${domain}.service" ];
        serviceConfig.LoadCredential = [
          "tls_chain:/var/lib/acme/${domain}/fullchain.pem"
          "tls_key:/var/lib/acme/${domain}/key.pem"
        ];
      };

      services.nginx.virtualHosts.${domain} = {
        useACMEHost = domain;
        forceSSL = true;
        locations."/" = {
          proxyPass = "https://127.0.0.1:8443";
          proxyWebsockets = true;
          extraConfig = ''
            # kanidm's loopback TLS uses an ACME cert valid only for the public
            # name; proxy_ssl_verify off avoids upstream-cert hostname checks
            # against 127.0.0.1.
            proxy_ssl_verify off;
          '';
        };
      };
    };
}
