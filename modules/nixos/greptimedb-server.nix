# How this fleet deploys the telemetry store (flake.modules.nixos.greptimedb,
# which stays free of clan vars so the runtime tests can import it with their
# own credentials): the store accounts' and the R2 credentials' generators,
# the store's object storage, the credentials greptimedb, greptimedb-schema,
# greptimedb-envelope and devloop-reconcile load, and the dataset facts
# greptimedb-envelope checks, read from the host's ZFS boot invariants
# (flake.lib.zfsBootInvariants, modules/lib/zfs-boot-invariants.nix). Which
# units may load each store secret is asserted by the host
# (machines/nixos/magnetite/default.nix), which sees every unit.
{ config, ... }:
let
  collectorSchema = config.flake.lib.otelCollectorSchema;
  inherit (config.flake.lib) zfsBootInvariants;
in
{
  flake.modules.nixos.greptimedb-server =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      inherit (config.networking) hostName;
      # The account's R2 endpoint.
      r2Endpoint = "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";

      # The store dataset's boot-enforced quota and reservation (ADR-007
      # E7.3): the entries of the units that apply them, so R7.3 compares the
      # dataset against the values this host enforces.
      invariant =
        unit:
        lib.findFirst (entry: entry.unit == unit)
          (throw "greptimedb-server: flake.lib.zfsBootInvariants.${hostName} has no ${unit} entry")
          (zfsBootInvariants.${hostName} or [ ]);
      quota = invariant "zfs-set-root-greptimedb-quota";
      reservation = invariant "zfs-set-root-greptimedb-reservation";
    in
    {
      # Store accounts for GreptimeDB (ADR-007, ADR-008; design D6). Hex
      # passwords, because a users line needs exactly one `=` and the store
      # silently skips a malformed line (design F2); written with printf '%s'
      # so no file carries a trailing newline into an HTTP basic-auth header.
      # perses-password is loaded by perses.service, which restarts on its
      # rotation. users-sha256 is public: the sha256 of 256-bit hex passwords
      # is not reversible, and R7.4 compares it with
      # /run/greptimedb/loaded-users.sha256.
      clan.core.vars.generators.greptimedb-users = {
        files.users = {
          owner = "greptimedb";
          mode = "0400";
          restartUnits = [ "greptimedb.service" ];
        };
        files.admin-password.mode = "0400";
        files.collector-password = {
          mode = "0400";
          restartUnits = [ "opentelemetry-collector.service" ];
        };
        files.perses-password = {
          mode = "0400";
          restartUnits = [ "perses.service" ];
        };
        files.regulator-password.mode = "0400";
        files.users-sha256.secret = false;
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          admin="$(openssl rand -hex 32)"
          collector="$(openssl rand -hex 32)"
          perses="$(openssl rand -hex 32)"
          regulator="$(openssl rand -hex 32)"
          printf '%s' "$admin" > "$out/admin-password"
          printf '%s' "$collector" > "$out/collector-password"
          printf '%s' "$perses" > "$out/perses-password"
          printf '%s' "$regulator" > "$out/regulator-password"
          printf 'admin:rw=%s\ncollector:wo=%s\nperses:ro=%s\nregulator:ro=%s\n' \
            "$admin" "$collector" "$perses" "$regulator" > "$out/users"
          sha256sum "$out/users" | cut -d ' ' -f 1 > "$out/users-sha256"
        '';
      };

      # Cloudflare R2 credentials for the store's object data, an Object Read
      # & Write token on bucket sciexp, delivered as an EnvironmentFile in
      # GreptimeDB's GREPTIMEDB_STANDALONE__ layered-config form.
      clan.core.vars.generators.greptimedb-r2 = {
        prompts.access-key = {
          description = ''
            Cloudflare R2 S3 access key ID with Object Read & Write scope on
            bucket sciexp, for GreptimeDB. Minted in the Cloudflare dashboard;
            distinct from the omnigraph-r2 and niks3-s3 tokens.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "greptimedb";
            label = "GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID";
          };
        };

        prompts.secret-key = {
          description = "Cloudflare R2 S3 secret access key paired with the access key ID above.";
          type = "hidden";
          persist = true;
          display = {
            group = "greptimedb";
            label = "GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY";
          };
        };

        files.access-key.deploy = false;
        files.secret-key.deploy = false;

        files."env" = {
          restartUnits = [ "greptimedb.service" ];
        };

        script = ''
          {
            printf 'GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID=%s\n' "$(cat "$prompts/access-key")"
            printf 'GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY=%s\n' "$(cat "$prompts/secret-key")"
          } > "$out/env"
        '';
      };

      # Telemetry store (design D3 to D7). WAL and caches live on
      # zroot/root/greptimedb; SSTs go to R2 under one prefix of sciexp, at the
      # endpoint omnigraph already uses. Credentials arrive by path only.
      services.greptimedb = {
        # One source with the collector's routing (review F4).
        inherit (collectorSchema) databases;
        settings.storage = {
          type = "S3";
          bucket = "sciexp";
          root = "projects/vanixiets/observability/store/";
          endpoint = r2Endpoint;
          region = "auto";
          enable_virtual_host_style = false;
          disable_ec2_metadata = true;
          # ADR-007: the object-store read cache is capped at 4 GiB.
          cache_capacity = "4GiB";
        };
      };

      systemd.services.greptimedb.serviceConfig = {
        LoadCredential = [
          "users:${config.clan.core.vars.generators.greptimedb-users.files.users.path}"
        ];
        EnvironmentFile = config.clan.core.vars.generators.greptimedb-r2.files."env".path;
      };

      systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
        "admin-password:${config.clan.core.vars.generators.greptimedb-users.files.admin-password.path}"
      ];

      # The regulator credential and the host facts greptimedb-envelope checks.
      # Quota and reservation are the values the
      # zfs-set-root-greptimedb-{quota,reservation} oneshots apply, so R7.3
      # compares the dataset against the value this host enforces.
      systemd.services.greptimedb-envelope = {
        serviceConfig.LoadCredential = [
          "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
        ];
        environment =
          let
            gibibytes =
              size:
              let
                m = builtins.match "([0-9]+)G" size;
              in
              assert lib.assertMsg (
                m != null
              ) "the store dataset's quota and reservation must be whole gibibytes (\"<n>G\"), got ${size}";
              toString (lib.toInt (builtins.head m) * 1024 * 1024 * 1024);
          in
          {
            GREPTIMEDB_ENVELOPE_DATASET = quota.dataset;
            GREPTIMEDB_ENVELOPE_QUOTA_BYTES = gibibytes quota.value;
            GREPTIMEDB_ENVELOPE_RESERVATION_BYTES = gibibytes reservation.value;
            GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE = "${config.clan.core.vars.generators.greptimedb-users.files.users-sha256.path
            }";
          };
      };

      # devloop-reconcile's store credential, the third regulator-password
      # holder (S2 design D11); devloop-collection.nix stays free of clan vars.
      systemd.services.devloop-reconcile.serviceConfig.LoadCredential = [
        "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
      ];
    };
}
