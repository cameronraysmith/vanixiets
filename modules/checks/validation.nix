{
  self,
  lib,
  config,
  ...
}:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
      terraformPkg = self.packages.${system}.terraform;
      terraformConfig = terraformPkg.passthru.config;
      tofuWithProviders = terraformPkg.passthru.tofuBundle;
      mkCheck = self.lib.mkStructuralCheck pkgs;

      # Resolve a deferred module to its post-merge config attrset.
      # `_module.check = false` and a permissive freeform type let the
      # eval succeed without re-declaring every option the slot might
      # set; we only care whether the slot produced any config keys.
      evalSlot =
        slot:
        (lib.evalModules {
          modules = [
            slot
            {
              _module.check = false;
              freeformType = lib.types.lazyAttrsOf lib.types.raw;
            }
          ];
        }).config;
      hasContent =
        user:
        let
          resolved = removeAttrs (evalSlot user.contentPrivate) [ "_module" ];
        in
        resolved != { };

      # Reports why a parsed secret file is not sops-encrypted; prints
      # nothing when it is. A file passes when it is a mapping with a
      # top-level `sops` object whose `mac` is ENC[...], at least one value
      # outside `sops` is ENC[...], and, unless the metadata declares partial
      # encryption (encrypted_suffix, encrypted_regex, unencrypted_regex),
      # every non-empty scalar outside `sops` is ENC[...] except under keys
      # ending in `sops.unencrypted_suffix`.
      sopsEncryptedFilter = pkgs.writeText "sops-encrypted.jq" ''
        def isenc: type == "string" and startswith("ENC[");

        if type != "object" then
          "not a mapping"
        elif (.sops | type) != "object" then
          "missing top-level sops metadata"
        elif (.sops.mac | isenc | not) then
          "sops.mac is not an ENC[...] value"
        else
          .sops as $s
          | ($s.unencrypted_suffix // "_unencrypted") as $us
          | del(.sops) as $d
          | [
              $d
              | paths(scalars) as $p
              | select([$p[] | select(type == "string" and endswith($us))] == [])
              | {p: $p, v: ($d | getpath($p))}
              | select(.v != "" and .v != null)
            ] as $leaves
          | [$leaves[] | select(.v | isenc)] as $enc
          | if $enc == [] then
              "no ENC[...] value outside sops metadata"
            elif ($s.encrypted_suffix // $s.encrypted_regex // $s.unencrypted_regex) != null then
              empty
            elif ($leaves | length) != ($enc | length) then
              "plaintext value at: " + ([$leaves[] | select(.v | isenc | not) | .p | map(tostring) | join(".")] | join(", "))
            else
              empty
            end
        end
      '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        # TC-020: every primary user's `contentPrivate` slot resolves to a
        # non-empty config. The slot is a `deferredModule` defaulting to
        # `{ }`, so deleting a user's writer leaves home-manager builds green
        # with the content silently gone; resolving the slot makes that fail.
        # The `_phantom*` keys pin the `hasContent` predicate itself on the
        # empty/authored boundary, so a predicate that always answers `true`
        # (e.g. freeformType injecting keys) also fails the diff.
        home-module-exports =
          let
            # Primary users only — aliases inherit their target's typed
            # content slot via aliases-fold; they don't author their own
            # `contentPrivate`.
            primaryUsers = builtins.removeAttrs config.flake.users (
              builtins.attrNames config.flake.userAliases
            );
            controls = {
              _phantomEmpty = hasContent { contentPrivate = { }; };
              _phantomAuthored = hasContent { contentPrivate.home.stateVersion = "23.11"; };
            };
          in
          mkCheck {
            name = "home-module-exports";
            actual = lib.mapAttrs (_: u: hasContent u) primaryUsers // controls;
            expected = lib.mapAttrs (_: _: true) primaryUsers // {
              _phantomEmpty = false;
              _phantomAuthored = true;
            };
          };

        # TC-023: the terranix-generated config passes `tofu validate`
        # against the bundled provider schemas (offline via -plugin-dir).
        terraform-validate =
          pkgs.runCommand "terraform-validate"
            {
              nativeBuildInputs = [ tofuWithProviders ];
              passthru.meta.description = "Validate generated terraform is syntactically correct";
            }
            ''
              mkdir -p terraform
              cd terraform
              ln -s ${terraformConfig} config.tf.json
              tofu init -backend=false -plugin-dir=${tofuWithProviders}/libexec/terraform-providers
              tofu validate
              touch $out
            '';

        # TC-028: no plaintext secret is committed.
        #
        # Selection: every regular file under secrets/ except dotfiles
        # (.keep), and every regular file named `secret` under vars/. Clan
        # `value` files are public by design; `.validation-hash` and the
        # machines/ and users/ recipient symlinks next to each secret are
        # not secrets. Format follows sops' extension rule: *.yaml and *.yml
        # are YAML; every other file (clan vars `secret`, *.enc) is a sops
        # json or binary store, which is JSON on disk. The source is
        # restricted to the selected files, so the check rebuilds only when
        # a secret changes.
        secrets-encryption-integrity =
          pkgs.runCommand "secrets-encryption-integrity"
            {
              src = lib.fileset.toSource {
                root = ../..;
                fileset = lib.fileset.unions [
                  (lib.fileset.fileFilter (f: f.type == "regular" && !lib.hasPrefix "." f.name) ../../secrets)
                  (lib.fileset.fileFilter (f: f.type == "regular" && f.name == "secret") ../../vars)
                ];
              };
              nativeBuildInputs = [
                pkgs.jq
                pkgs.yq-go
              ];
              passthru.meta.description = "Validate all secrets are SOPS-encrypted";
            }
            ''
              set -euo pipefail
              cd "$src"
              failed=0
              checked=0

              while IFS= read -r -d "" f; do
                checked=$((checked + 1))
                case "$f" in
                  *.yaml | *.yml) doc=$(yq -o=json '.' "$f" 2>/dev/null) || doc="" ;;
                  *) doc=$(cat "$f") ;;
                esac
                if ! reasons=$(jq -r -f ${sopsEncryptedFilter} <<<"$doc" 2>/dev/null) || [ -z "$doc" ]; then
                  reasons="not parseable in its sops format"
                fi
                if [ -n "$reasons" ]; then
                  printf 'NOT ENCRYPTED: %s: %s\n' "$f" "$reasons" >&2
                  failed=$((failed + 1))
                fi
              done < <(
                {
                  find secrets -type f ! -name '.*' -print0
                  find vars -type f -name secret -print0
                } | sort -z
              )

              if [ "$checked" -eq 0 ]; then
                echo "no secret files found" >&2
                exit 1
              fi
              if [ "$failed" -ne 0 ]; then
                echo "$failed of $checked secret files are not sops-encrypted" >&2
                exit 1
              fi
              echo "OK: $checked secret files are sops-encrypted"
              touch $out
            '';
      };
    };
}
