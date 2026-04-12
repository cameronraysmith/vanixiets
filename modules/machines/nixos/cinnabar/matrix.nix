{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      matrixPort = 8008;
    in
    {
      services.matrix-tuwunel = {
        enable = true;
        settings.global = {
          server_name = "matrix.zt";
          address = [
            "::1"
            "127.0.0.1"
          ];
          port = [ matrixPort ];
          allow_registration = true;
          registration_token_file = "/run/credentials/tuwunel.service/registration-token";
          grant_admin_to_first_user = true;
          allow_federation = false;
          trusted_servers = [ ];
        };
      };

      # DynamicUser cannot read clan-vars paths; relay via systemd credentials
      systemd.services.tuwunel.serviceConfig.LoadCredential = [
        "registration-token:${
          config.clan.core.vars.generators.tuwunel-registration-token.files."token".path
        }"
      ];

      clan.core.vars.generators.tuwunel-registration-token = {
        files."token".neededFor = "services";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.pwgen
        ];
        script = ''
          pwgen -s 48 1 > "$out"/token
        '';
      };

      clan.core.vars.generators.matrix-password-cameron = {
        files."password".neededFor = "services";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.xkcdpass
        ];
        script = ''
          xkcdpass -n 4 -d - > "$out"/password
        '';
      };

      clan.core.vars.generators.matrix-password-clawd = {
        files."password" = {
          neededFor = "services";
          owner = config.users.users.cameron.name;
        };
        runtimeInputs = [
          pkgs.coreutils
          pkgs.xkcdpass
        ];
        script = ''
          xkcdpass -n 4 -d - > "$out"/password
        '';
      };

      # First registered user gets server admin via grant_admin_to_first_user
      systemd.services.tuwunel-register-users = {
        description = "Provision Matrix users on tuwunel";
        after = [ "tuwunel.service" ];
        requires = [ "tuwunel.service" ];
        before = [ "openclaw-gateway.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        path = [
          pkgs.curl
          pkgs.jq
          pkgs.coreutils
        ];
        script =
          let
            adminUser = config.users.users.cameron.name;
            tokenFile = config.clan.core.vars.generators.tuwunel-registration-token.files."token".path;
            cameronPasswordFile =
              config.clan.core.vars.generators.matrix-password-cameron.files."password".path;
            clawdPasswordFile = config.clan.core.vars.generators.matrix-password-clawd.files."password".path;
          in
          ''
            set -euo pipefail

            TOKEN=$(cat ${tokenFile})

            for i in $(seq 1 30); do
              if curl -fsS http://localhost:${toString matrixPort}/_matrix/client/versions >/dev/null 2>&1; then
                break
              fi
              if [ "$i" -eq 30 ]; then
                echo "tuwunel did not become ready within 30s" >&2
                exit 1
              fi
              sleep 1
            done

            register() {
              local user="$1"
              local pw_file="$2"
              local body tmpfile http_code
              tmpfile=$(mktemp)
              body=$(jq -n \
                --arg u "$user" \
                --arg p "$(cat "$pw_file")" \
                --arg t "$TOKEN" \
                '{auth:{type:"m.login.registration_token",token:$t}, username:$u, password:$p, inhibit_login:true}')
              http_code=$(curl -sS -o "$tmpfile" -w '%{http_code}' \
                -X POST http://localhost:${toString matrixPort}/_matrix/client/v3/register \
                -H 'Content-Type: application/json' \
                -d "$body")
              case "$http_code" in
                200)
                  echo "registered $user"
                  ;;
                400)
                  if jq -e '.errcode == "M_USER_IN_USE"' "$tmpfile" >/dev/null 2>&1; then
                    echo "$user already exists, skipping"
                  else
                    echo "registration failed for $user: HTTP 400: $(cat "$tmpfile")" >&2
                    rm -f "$tmpfile"
                    exit 1
                  fi
                  ;;
                *)
                  echo "registration failed for $user: HTTP $http_code: $(cat "$tmpfile")" >&2
                  rm -f "$tmpfile"
                  exit 1
                  ;;
              esac
              rm -f "$tmpfile"
            }

            register "${adminUser}" "${cameronPasswordFile}"
            register clawd "${clawdPasswordFile}"
          '';
      };
    };
}
