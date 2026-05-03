# Per-repo effects-secrets generator for github:cameronraysmith/vanixiets.
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.effects-vanixiets-secrets =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      clan.core.vars.generators.vanixiets-effects-secrets = {
        files.secrets = {
          secret = true;
          owner = "buildbot";
          # systemd LoadCredential= snapshots /run/secrets/vars/<gen>/secrets
          # at unit-start time and never re-reads.
          # Without this, regenerating the secret leaves
          # /run/credentials/buildbot-master.service/effects-secret__... stale
          # until manual `systemctl restart buildbot-master.service`.
          # clan-vars plumbs restartUnits through to sops-nix's restartUnits,
          # which keys the unit's restartTriggers on the encrypted blob hash
          # so the next deploy refreshes the credential snapshot.
          restartUnits = [ "buildbot-master.service" ];
        };

        prompts.cloudflare-api-token = {
          description = ''
            Cloudflare API token (scope: Workers/Pages:Edit + relevant zone/R2 scopes).
            Single token shared across preview and production effects.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "vanixiets effects";
            label = "CLOUDFLARE_API_TOKEN";
            helperText = ''
              Pasted once at first generate; Enter to keep existing on subsequent
              `clan vars generate --regenerate` invocations.
            '';
          };
        };

        prompts.cloudflare-account-id = {
          description = ''
            Cloudflare account ID paired with CLOUDFLARE_API_TOKEN above.
            Required by wrangler for Pages/Workers deploys. Not secret in
            the cryptographic sense, but captured via the same generator
            to keep the 4-env-var contract homogeneous and avoid a
            parallel non-secret distribution channel.
          '';
          type = "line";
          persist = true;
          display = {
            group = "vanixiets effects";
            label = "CLOUDFLARE_ACCOUNT_ID";
            helperText = ''
              Single-line account id (32 hex chars). Enter to keep existing
              on subsequent `clan vars generate --regenerate` invocations.
            '';
          };
        };

        prompts.github-token = {
          description = ''
            GitHub fine-grained Personal Access Token for effect scripts that
            interact with the forge API (release creation, label edits, etc.).
            Scope to the minimum repositories required by the effect bundle.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "vanixiets effects";
            label = "GITHUB_TOKEN";
            helperText = ''
              Fine-grained PAT, not a classic PAT. Expires per your GitHub
              account default (rotate before expiry).
            '';
          };
        };

        prompts.sops-age-key = {
          description = ''
            Age private key used by sops-secrets-operator bootstrap effects
            running inside the ephemeral test-cluster spawned during CI.
            Corresponds to the age recipient recorded in .sops.yaml.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "vanixiets effects";
            label = "SOPS_AGE_KEY";
            helperText = ''
              AGE-SECRET-KEY-… literal (single line). Not the path to a key
              file; paste the key body itself.
            '';
          };
        };

        # component secrets kept in repo for rotation management, but only the
        # composed secrets file deploys to the buildbot-nix host.
        files.cloudflare-api-token.deploy = false;
        files.cloudflare-account-id.deploy = false;
        files.github-token.deploy = false;
        files.sops-age-key.deploy = false;

        runtimeInputs = [ pkgs.jq ];

        script = ''
          jq -n \
            --arg cloudflare_api_token  "$(cat "$prompts/cloudflare-api-token")" \
            --arg cloudflare_account_id "$(cat "$prompts/cloudflare-account-id")" \
            --arg github_token           "$(cat "$prompts/github-token")" \
            --arg sops_age_key           "$(cat "$prompts/sops-age-key")" \
            '{
              CLOUDFLARE_API_TOKEN:  { data: { value: $cloudflare_api_token } },
              CLOUDFLARE_ACCOUNT_ID: { data: { value: $cloudflare_account_id } },
              GITHUB_TOKEN:          { data: { value: $github_token } },
              SOPS_AGE_KEY:          { data: { value: $sops_age_key } }
            }' > "$out/secrets"
        '';
      };

      services.buildbot-nix.master.effects.perRepoSecretFiles."github:cameronraysmith/vanixiets" =
        config.clan.core.vars.generators.vanixiets-effects-secrets.files.secrets.path;
    };
}
