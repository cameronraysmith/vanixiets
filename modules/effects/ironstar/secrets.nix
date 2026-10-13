# Per-repo effects-secrets generator for github:sciexp/ironstar.
{
  config,
  inputs,
  ...
}:
{
  flake.modules.nixos.effects-ironstar-secrets =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      buildbot = config.vanixiets.buildbot.enable or false;
    in
    {
      clan.core.vars.generators.ironstar-effects-secrets = {
        files.secrets = {
          secret = true;

          # buildbot-master runs as this user and opens the path directly.
          # nixbot's unit runs as "nixbot" and never opens it: systemd loads
          # the file as a credential, which PID 1 reads as root before
          # re-exposing a copy to the service user, so root suffices without
          # buildbot.
          owner = if buildbot then "buildbot" else "root";

          # clan-vars plumbs restartUnits through to sops-nix's restartUnits,
          # which keys the unit's restartTriggers on the encrypted blob hash
          # so the next deploy refreshes the credential snapshot. Each service
          # snapshots the file at unit start, so a rotation that restarts only
          # one of them leaves the other serving the superseded value.
          restartUnits = [ "nixbot.service" ] ++ lib.optional buildbot "buildbot-master.service";
        };

        prompts.cloudflare-api-token = {
          description = ''
            Cloudflare API token (scope: Workers/Pages:Edit + relevant zone/R2 scopes).
            Single token shared across preview and production effects.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "ironstar effects";
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
            to keep the env-var contract homogeneous and avoid a
            parallel non-secret distribution channel.
          '';
          type = "line";
          persist = true;
          display = {
            group = "ironstar effects";
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
            group = "ironstar effects";
            label = "GITHUB_TOKEN";
            helperText = ''
              Fine-grained PAT, not a classic PAT. Expires per your GitHub
              account default (rotate before expiry).
            '';
          };
        };

        # component secrets kept in repo for rotation management, but only the
        # composed secrets file deploys to the buildbot-nix host.
        files.cloudflare-api-token.deploy = false;
        files.cloudflare-account-id.deploy = false;
        files.github-token.deploy = false;

        runtimeInputs = [ pkgs.jq ];

        script = ''
          jq -n \
            --arg cloudflare_api_token  "$(cat "$prompts/cloudflare-api-token")" \
            --arg cloudflare_account_id "$(cat "$prompts/cloudflare-account-id")" \
            --arg github_token           "$(cat "$prompts/github-token")" \
            '{
              CLOUDFLARE_API_TOKEN:  { data: { value: $cloudflare_api_token } },
              CLOUDFLARE_ACCOUNT_ID: { data: { value: $cloudflare_account_id } },
              GITHUB_TOKEN:          { data: { value: $github_token } }
            }' > "$out/secrets"
        '';
      };

      # One composed file, two consumers. Both services accept the same
      # hercules-ci secrets.json shape at a path they load as a systemd
      # credential, so the generator above remains the single source of truth
      # and the two services' copies cannot drift apart.
      #
      # The key is forge-prefixed, unlike the allowlist entry in
      # modules/nixos/nixbot.nix. nixbot substitutes ":" and "/" to derive the
      # systemd credential name it looks the file up under, so a mismatch here
      # delivers no secrets at all and every effect stops at its own
      # missing-secret guard — indistinguishable from not wiring it.
      services.buildbot-nix.master.effects.perRepoSecretFiles."github:sciexp/ironstar" =
        config.clan.core.vars.generators.ironstar-effects-secrets.files.secrets.path;

      services.nixbot.effects.perRepoSecretFiles."github:sciexp/ironstar" =
        config.clan.core.vars.generators.ironstar-effects-secrets.files.secrets.path;
    };
}
