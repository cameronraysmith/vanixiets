# niks3 binary cache service for magnetite
#
# Provides clan vars generators for niks3 credentials and will configure
# the niks3 service once the flake input is added.
# Generators define the credential slots; values are populated via:
#   - niks3-s3: manual `clan vars set` (R2 S3 credentials from Cloudflare dashboard)
#   - niks3-api-token: auto-generated
#   - niks3-signing-key: auto-generated
{
  config,
  inputs,
  ...
}:
let
  flakeLib = config.flake.lib;
in
{
  # niks3-claim-without-exception.patch, carried locally (F65), not filed
  # upstream (operator decision 2026-11-19).
  #
  # Mic92/niks3 f91108b1 ("keep a publish claim only until its push
  # commits") claims narinfos outside a transaction first: claim_narinfos
  # RAISEs SQLSTATE NK301 whenever a key is not won outright, and
  # claimNarinfos (server/uploads.go) catches it and retries in a
  # transaction. Our nixbot uploader pushes overlapping closures, so a key
  # another push committed meanwhile is routine, and PostgreSQL logged each
  # fallback as an ERROR with its statement: about 400 an hour on magnetite,
  # nothing lost. Still so on upstream main 38c867bd.
  #
  # The patch catches NK301 inside the function, in a block whose
  # subtransaction undoes the claim insert, and returns
  # {"needs_transaction": true}; claimNarinfos retries on that flag. The
  # fast path is upstream's. The alternative, claiming in a transaction
  # every time, removes the fast path f91108b1 added. The patch replaces only
  # a function body, which niks3 re-applies on every start
  # (server/pg/pg.go), so it needs no migration and dropping it needs none.
  # checks.x86_64-linux.niks3-claim runs upstream's claim tests with it, plus
  # modules/checks/niks3-claim/claim-test.patch, which fails without it.
  #
  # Trial from its first magnetite deploy (built 2026-11-19). Offer it
  # upstream after four weeks if: postgresql.service's journal has no
  # `claim needs a transaction`; niks3_http_requests_total for route
  # "POST /api/pushes/{id}/sign" shows no 5xx; that route's
  # niks3_http_request_duration_seconds is no worse than before; GC runs
  # succeed; no publish_claims rows are left behind and no live narinfo's NAR
  # is missing; and upstream main still raises NK301.
  flake.lib.niks3Patches = [ ./niks3-claim-without-exception.patch ];

  flake.modules.nixos.niks3 =
    {
      config,
      options,
      pkgs,
      lib,
      ...
    }:
    {
      # The module builds niks3-server from its own source with this host's
      # pkgs (serverPackage's default), so the patch goes on that package.
      services.niks3.serverPackage = options.services.niks3.serverPackage.default.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ flakeLib.niks3Patches;
      });

      # Clan vars for niks3 R2 S3 credentials (populated manually via clan vars set)
      vanixiets.secrets.niks3-s3 = {
        files."access-key" = {
          owner = "niks3";
        };
        files."secret-key" = {
          owner = "niks3";
        };
        script = ''
          echo "niks3-s3 credentials are populated manually from Cloudflare R2 dashboard" >&2
          exit 1
        '';
      };

      # API authentication token (auto-generated, minimum 36 characters)
      vanixiets.secrets.niks3-api-token = {
        files."token" = {
          owner = "niks3";
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 24 > $out/token
        '';
      };

      # Ed25519 cache signing key (auto-generated)
      vanixiets.secrets.niks3-signing-key = {
        files."key" = {
          owner = "niks3";
        };
        files."key.pub".secret = false;
        runtimeInputs = [ pkgs.nix ];
        script = ''
          nix --extra-experimental-features "nix-command flakes" \
            key generate-secret --key-name cache.scientistexperience.net-1 > $out/key
          nix --extra-experimental-features "nix-command flakes" \
            key convert-secret-to-public < $out/key > $out/key.pub
        '';
      };

      # niks3 service configuration with Cloudflare R2 backend
      services.niks3 = {
        enable = true;
        httpAddr = "127.0.0.1:5752";

        cacheUrl = "https://cache.scientistexperience.net";

        # Cloudflare R2 configuration (S3-compatible)
        s3 = {
          endpoint = "1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";
          bucket = "sciexp-nix-cache";
          region = "auto";
          useSSL = true;
          accessKeyFile = config.vanixiets.secrets.niks3-s3.files."access-key".path;
          secretKeyFile = config.vanixiets.secrets.niks3-s3.files."secret-key".path;
        };

        # PostgreSQL for closure tracking and GC state
        database.createLocally = true;

        # API authentication token
        apiTokenFile = config.vanixiets.secrets.niks3-api-token.files."token".path;

        # Cache signing key
        signKeyFiles = [ config.vanixiets.secrets.niks3-signing-key.files."key".path ];

        # nginx reverse proxy with ACME TLS
        nginx.enable = true;
        nginx.domain = "niks3.scientistexperience.net";
      };

      # Prometheus endpoint: loopback and ZeroTier mesh only
      services.nginx.virtualHosts.${config.services.niks3.nginx.domain}.locations =
        flakeLib.nginxMetricsLocation
          config.services.nginx.virtualHosts.${config.services.niks3.nginx.domain};
    };
}
