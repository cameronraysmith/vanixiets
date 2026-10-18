# Evaluation-time regulator for ntfy's declarative provisioning on cinnabar
# (design D6). A rejected environmentFile stops ntfy for every publisher, not
# only alerts, so the generators' rendered strings are judged before deploy.
#
# The check runs cinnabar's ntfy-alerter and ntfy-alerter-env generators in
# the build sandbox exactly as clan does (finalScript: PATH from runtimeInputs
# plus coreutils, then the script) and judges what they write against the
# parse rules of the pinned ntfy 2.28.0, read at binwiederhier/ntfy@v2.28.0:
#   - token: ^tk_[-_A-Za-z0-9]{29}$ (user/util.go:24, ValidToken);
#   - NTFY_AUTH_USERS: name:hash:role, three fields (cmd/serve.go:620-645),
#     hash accepted by ValidPasswordHash(hash, 10) (user/util.go:52-65): a
#     $2a$/$2b$/$2y$ prefix, a two-digit cost from 10 to 31, and the 53
#     bcrypt characters GenerateFromPassword emits (golang.org/x/crypto
#     v0.55.0 bcrypt/bcrypt.go:57-63,168-190,282-300);
#   - NTFY_AUTH_TOKENS: user:token, user provisioned (cmd/serve.go:690-720),
#     carrying the same token the publishers read from the token file;
#   - auth-access: every user is * or everyone or provisioned
#     (cmd/serve.go:647-668, cmd/access.go:18).
# The patterns admit no backslash, quote or whitespace, so systemd reads each
# unquoted EnvironmentFile value byte for byte (systemd.exec(5) at v261.3).
# The access clause relates cinnabar's evaluated settings to the users the
# generator provisions, two independently written values.
#
# Mutants edit the subjects, never the validator (S1 review.md F11): a token
# generator emitting tk_ plus 28 characters, an env generator writing the
# unhashed password, an env generator provisioning a freshly generated token
# instead of the shared one, and an auth-access entry naming alertr. Each
# must be rejected, or the build fails.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      cinnabar = self.nixosConfigurations.cinnabar.config;
      tokenGenerator = cinnabar.clan.core.vars.generators.ntfy-alerter;
      envGenerator = cinnabar.clan.core.vars.generators.ntfy-alerter-env;
      accessEntries = cinnabar.services.ntfy-sh.settings.auth-access or [ ];

      # A mutant generator: the generator's own script with one line replaced,
      # wrapped the way clan's finalScript wraps it. A replacement that
      # matches nothing is an evaluation error, not a silently equal mutant.
      mutantGenerator =
        name: generator: from: to:
        let
          script = builtins.replaceStrings [ from ] [ to ] generator.script;
        in
        assert lib.assertMsg (
          script != generator.script
        ) "ntfy-provisioning: mutant ${name} matched nothing in its generator's script";
        pkgs.writeScript "ntfy-provisioning-${name}" ''
          set -euo pipefail
          PATH=${lib.makeBinPath (generator.runtimeInputs ++ [ pkgs.coreutils ])}
          ${script}
        '';

      shortTokenGenerator =
        mutantGenerator "short-token" tokenGenerator ''token="$(ntfy token generate)"''
          ''token="$(ntfy token generate | cut -c 1-31)"'';
      unhashedEnvGenerator =
        mutantGenerator "unhashed-password" envGenerator
          ''hash="$(printf '%s\n%s\n' "$password" "$password" | ntfy user hash)"''
          ''hash="$password"'';
      # A well-formed token that is not the shared one, so only the token
      # equality clause can reject it.
      foreignTokenEnvGenerator =
        mutantGenerator "foreign-token" envGenerator ''token="$(cat "$in/ntfy-alerter/token")"''
          ''token="$(ntfy token generate)"'';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        ntfy-provisioning = pkgs.runCommand "ntfy-provisioning" { } ''
          token_re='^tk_[-_A-Za-z0-9]{29}$'
          users_re='^NTFY_AUTH_USERS=alerter:\$2[aby]\$([0-9]{2})\$[./A-Za-z0-9]{53}:user$'

          # $1: token file, $2: ntfy-env file.
          valid_provisioning() {
            local token users cost
            token="$(cat "$1")"
            if ! [[ $token =~ $token_re ]]; then
              echo "ntfy-provisioning: the token does not match ^tk_[-_A-Za-z0-9]{29}\$ (user/util.go:24)" >&2
              return 1
            fi
            if [ "$(wc -l < "$2")" -ne 2 ]; then
              echo "ntfy-provisioning: ntfy-env must hold exactly the NTFY_AUTH_USERS and NTFY_AUTH_TOKENS lines" >&2
              return 1
            fi
            users="$(sed -n 1p "$2")"
            if ! [[ $users =~ $users_re ]]; then
              echo "ntfy-provisioning: line 1 is not NTFY_AUTH_USERS=alerter:<bcrypt hash>:user (cmd/serve.go:620-645, user/util.go:52-65)" >&2
              return 1
            fi
            cost=$((10#''${BASH_REMATCH[1]}))
            if [ "$cost" -lt 10 ] || [ "$cost" -gt 31 ]; then
              echo "ntfy-provisioning: bcrypt cost $cost is outside 10..31 (user/util.go:58-63)" >&2
              return 1
            fi
            if [ "$(sed -n 2p "$2")" != "NTFY_AUTH_TOKENS=alerter:$token" ]; then
              echo "ntfy-provisioning: line 2 is not NTFY_AUTH_TOKENS=alerter:<the token file's token> (cmd/serve.go:690-720)" >&2
              return 1
            fi
          }

          # $1: ntfy-env file; the rest: auth-access entries.
          valid_access() {
            local env="$1" entry user provisioned
            shift
            provisioned="$(sed -n 's/^NTFY_AUTH_USERS=//p' "$env" | tr ',' '\n' | cut -d ':' -f 1)"
            for entry in "$@"; do
              user="''${entry%%:*}"
              case "$user" in
                '*' | everyone) continue ;;
              esac
              if ! grep -qxF -- "$user" <<< "$provisioned"; then
                echo "ntfy-provisioning: auth-access entry $entry names $user, who is not provisioned (cmd/serve.go:647-668)" >&2
                return 1
              fi
            done
          }

          expect_rejected() {
            local name="$1"
            shift
            if "$@"; then
              echo "ntfy-provisioning: mutant $name was accepted" >&2
              exit 1
            fi
            echo "ntfy-provisioning: mutant $name rejected"
          }

          # The real generators, run as clan runs them.
          real="$TMPDIR/real"
          mkdir -p "$real/ntfy-alerter" "$real/ntfy-alerter-env"
          out="$real/ntfy-alerter" bash ${tokenGenerator.finalScript}
          in="$real" out="$real/ntfy-alerter-env" bash ${envGenerator.finalScript}
          valid_provisioning "$real/ntfy-alerter/token" "$real/ntfy-alerter-env/ntfy-env" || exit 1
          valid_access "$real/ntfy-alerter-env/ntfy-env" ${lib.escapeShellArgs accessEntries} || exit 1
          echo "ntfy-provisioning: generators and cinnabar's ${toString (builtins.length accessEntries)} auth-access entries accepted"

          # Mutant: tk_ plus 28 characters.
          short="$TMPDIR/short-token"
          mkdir -p "$short/ntfy-alerter" "$short/ntfy-alerter-env"
          out="$short/ntfy-alerter" bash ${shortTokenGenerator}
          in="$short" out="$short/ntfy-alerter-env" bash ${envGenerator.finalScript}
          expect_rejected short-token valid_provisioning "$short/ntfy-alerter/token" "$short/ntfy-alerter-env/ntfy-env"

          # Mutant: the password written where its hash belongs.
          unhashed="$TMPDIR/unhashed-password"
          mkdir -p "$unhashed/ntfy-alerter-env"
          cp -r "$real/ntfy-alerter" "$unhashed/ntfy-alerter"
          in="$unhashed" out="$unhashed/ntfy-alerter-env" bash ${unhashedEnvGenerator}
          expect_rejected unhashed-password valid_provisioning "$unhashed/ntfy-alerter/token" "$unhashed/ntfy-alerter-env/ntfy-env"

          # Mutant: ntfy-env provisions a token other than the shared one.
          foreign="$TMPDIR/foreign-token"
          mkdir -p "$foreign/ntfy-alerter-env"
          cp -r "$real/ntfy-alerter" "$foreign/ntfy-alerter"
          in="$foreign" out="$foreign/ntfy-alerter-env" bash ${foreignTokenEnvGenerator}
          expect_rejected foreign-token valid_provisioning "$foreign/ntfy-alerter/token" "$foreign/ntfy-alerter-env/ntfy-env"

          # Mutant: an access entry naming a user nobody provisions.
          expect_rejected access-user-alertr valid_access "$real/ntfy-alerter-env/ntfy-env" ${
            lib.escapeShellArgs (accessEntries ++ [ "alertr:fleet-*:rw" ])
          }

          touch "$out"
        '';
      };
    };
}
