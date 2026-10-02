# Per-repo effects-secrets generator for github:cameronraysmith/vanixiets.
#
# flake.lib.vanixietsEffectSecrets is the one declaration of the secrets the
# vanixiets effects may read: the clan prompts, the composed secrets file and
# the effects registry's `secrets` enum are all derived from it, so a secret
# cannot be prompted for without being deliverable, or referenced by an effect
# without being prompted for. Prompt names are the persisted var file names,
# so renaming one orphans its stored value.
{ config, lib, ... }:
let
  effectSecrets = config.flake.lib.vanixietsEffectSecrets;
in
{
  flake.lib.vanixietsEffectSecrets = {
    CLOUDFLARE_API_TOKEN = {
      prompt = "cloudflare-api-token";
      type = "hidden";
      description = ''
        Cloudflare account API token for the docs preview and production deploy:
        the "Edit Cloudflare Workers" template plus the cameronraysmith.net zone,
        which serves the docs custom domain infra.cameronraysmith.net.
      '';
      helperText = ''
        Pasted once at first generate; Enter to keep existing on subsequent
        `clan vars generate --regenerate` invocations.
      '';
    };

    CLOUDFLARE_ACCOUNT_ID = {
      prompt = "cloudflare-account-id";
      type = "line";
      description = ''
        Cloudflare account ID paired with CLOUDFLARE_API_TOKEN above.
        Required by wrangler for Pages/Workers deploys. Not secret in
        the cryptographic sense, but captured via the same generator
        to keep the 3-env-var contract homogeneous and avoid a
        parallel non-secret distribution channel.
      '';
      helperText = ''
        Single-line account id (32 hex chars). Enter to keep existing
        on subsequent `clan vars generate --regenerate` invocations.
      '';
    };

    GITHUB_TOKEN = {
      prompt = "github-token";
      type = "hidden";
      description = ''
        GitHub fine-grained Personal Access Token for effect scripts that
        interact with the forge API (release creation, label edits, etc.).
        Scope to the minimum repositories required by the effect bundle.
      '';
      helperText = ''
        Fine-grained PAT, not a classic PAT. Expires per your GitHub
        account default (rotate before expiry).
      '';
    };
    R2_EVIDENCE_ACCESS_KEY_ID = {
      prompt = "r2-evidence-access-key-id";
      type = "line";
      description = ''
        Access Key ID of the R2 account token limited to Object Read & Write on
        the sciexp bucket, used to publish browser evidence.
      '';
      helperText = ''
        The "Access Key ID" shown when the R2 token is created. Enter to keep
        existing on subsequent `clan vars generate --regenerate` invocations.
      '';
    };
    R2_EVIDENCE_SECRET_ACCESS_KEY = {
      prompt = "r2-evidence-secret-access-key";
      type = "hidden";
      description = ''
        Secret Access Key of the same R2 token. The effect signs per-run
        temporary credentials with it, limited to the evidence prefix.
      '';
      helperText = ''
        The "Secret Access Key" shown once when the R2 token is created. Enter
        to keep existing on subsequent `clan vars generate --regenerate`
        invocations.
      '';
    };
  };

  flake.modules.nixos.effects-vanixiets-secrets =
    {
      config,
      pkgs,
      ...
    }:
    let
      jqVar = secret: lib.replaceStrings [ "-" ] [ "_" ] secret.prompt;
    in
    {
      clan.core.vars.generators.vanixiets-effects-secrets = {
        files = {
          secrets = {
            secret = true;

            # nixbot's unit runs as "nixbot" and never opens the file itself:
            # systemd loads it as a credential, which PID 1 reads as root before
            # re-exposing a copy to the service user, so the default root owner
            # suffices.

            # clan-vars plumbs restartUnits through to sops-nix's restartUnits,
            # which keys the unit's restartTriggers on the encrypted blob hash
            # so the next deploy refreshes the credential snapshot the service
            # took at unit start.
            restartUnits = [ "nixbot.service" ];
          };
        }
        # component secrets kept in repo for rotation management, but only the
        # composed secrets file deploys to the nixbot host.
        // lib.mapAttrs' (_: secret: lib.nameValuePair secret.prompt { deploy = false; }) effectSecrets;

        prompts = lib.mapAttrs' (
          name: secret:
          lib.nameValuePair secret.prompt {
            inherit (secret) description type;
            persist = true;
            display = {
              group = "vanixiets effects";
              label = name;
              inherit (secret) helperText;
            };
          }
        ) effectSecrets;

        runtimeInputs = [ pkgs.jq ];

        # The composed file is hercules-ci's secrets.json shape, one
        # `{ NAME: { data: { value } } }` entry per declared secret.
        script = ''
          jq -n \
            ${
              lib.concatStrings (
                lib.mapAttrsToList (
                  _: secret: ''--arg ${jqVar secret} "$(cat "$prompts/${secret.prompt}")" \'' + "\n  "
                ) effectSecrets
              )
            }${
              lib.escapeShellArg (
                "{ "
                + lib.concatStringsSep ", " (
                  lib.mapAttrsToList (name: secret: "${name}: { data: { value: \$${jqVar secret} } }") effectSecrets
                )
                + " }"
              )
            } > "$out/secrets"
        '';
      };

      # nixbot is the only consumer: buildbot serves only Gitea repositories
      # and never this one, so it is given no copy of these secrets.
      #
      # The key is forge-prefixed, unlike the allowlist entry in
      # modules/nixos/nixbot.nix. nixbot substitutes ":" and "/" to derive the
      # systemd credential name it looks the file up under, so a mismatch here
      # delivers no secrets at all and every effect stops at its own
      # missing-secret guard — indistinguishable from not wiring it.
      services.nixbot.effects.perRepoSecretFiles."github:cameronraysmith/vanixiets" =
        config.clan.core.vars.generators.vanixiets-effects-secrets.files.secrets.path;
    };
}
