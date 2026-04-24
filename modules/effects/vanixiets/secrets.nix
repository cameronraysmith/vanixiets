# Pattern C'-refined (mic92 idiom) — per-repo effects-secrets generator.
#
# This file owns every clan-vars and buildbot-nix wire for the
# github:cameronraysmith/vanixiets repo's effects-secrets bundle.
# Consumer-repo effect declarations (preview-docs-deploy,
# production-docs-deploy, etc.) live in each consumer's own flake under
# `herculesCI.effects.*`; vanixiets owns only the secret-material side
# of the contract.
#
# When integrated into the live tree at modules/effects/vanixiets/secrets.nix:
#   - The one-line wire
#       services.buildbot-nix.master.effects.perRepoSecretFiles."github:cameronraysmith/vanixiets" = …;
#     currently in modules/nixos/buildbot.nix MUST be removed; it is
#     authoritative here. NixOS module-system semantics allow additive
#     extension of `services.buildbot-nix.master.effects.perRepoSecretFiles`
#     from this module without duplicating `services.buildbot-nix.master.enable`.
#   - magnetite's host module (modules/machines/nixos/magnetite/default.nix)
#     MUST add `effects-vanixiets-secrets` to its `with flakeModules; [ … ]`
#     list so the flake-parts deferred module is included in magnetite's
#     NixOS configuration.
#
# Operator runbook (routine):
#   clan vars generate --regenerate \
#     --generator vanixiets-effects-secrets magnetite
#   # Walks the four prompts (cloudflare-api-token, cloudflare-account-id,
#   # github-token, sops-age-key); "Enter to keep, Backspace for new" per field.
#   # Composed `secrets` file is re-encrypted and git-committed automatically.
#
# Operator runbook (escape hatch — single-token non-interactive rotation):
#   printf '%s' "$TOK" | clan vars set magnetite \
#     vanixiets-effects-secrets/github-token
#   clan vars generate --regenerate \
#     --generator vanixiets-effects-secrets magnetite
#
# Reference: ADR-002 (Pattern C'-refined) and its amendment-A; reference
# implementation is
# ~/projects/nix-workspace/mic92-clan-dotfiles/machines/eve/modules/buildbot.nix
# (`harmonia-effects-secrets`).
#
# This file contributes a flake-parts deferred NixOS module named
# `effects-vanixiets-secrets`, following the outer-lambda shape of
# modules/nixos/buildbot.nix so that import-tree can auto-discover it and
# magnetite can `imports = with flakeModules; [ … effects-vanixiets-secrets ];`.
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
      # Per-repo effects-secrets generator for github:cameronraysmith/vanixiets.
      #
      # Composes the four operator-sourced tokens
      # (CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, GITHUB_TOKEN,
      # SOPS_AGE_KEY) into a single `secrets` file shaped as
      # hercules-ci-effects-nested JSON:
      #
      #   {
      #     "<KEY>": { "data": { "value": "<value>" } },
      #     …
      #   }
      #
      # consumed by buildbot-nix at dispatch time as
      # HERCULES_CI_SECRETS_JSON inside the bwrap sandbox. The keys below
      # match the secret identifiers referenced by effect scripts in
      # modules/effects/vanixiets/herculesCI/*.nix.
      clan.core.vars.generators.vanixiets-effects-secrets = {
        # The composed JSON file deployed to magnetite and pointed at by
        # services.buildbot-nix.master.effects.perRepoSecretFiles below.
        # `secret = true` is the default (see clan-core/modules/clan/vars/settings-opts.nix:30-37);
        # stated explicitly to mirror mic92's harmonia-effects-secrets idiom.
        files.secrets = {
          secret = true;
          owner = "buildbot";
        };

        # --- Prompts (interactive capture, persisted for rotation UX) ---

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

        # Raw prompt files are auto-materialized by `persist = true` so
        # their encrypted-at-rest copy lives in the repo, enabling
        # per-token rotation via the "Enter to keep" UX. They must NOT be
        # deployed to magnetite: only the composed `secrets` file needs to
        # reach the machine's secret store at activation time.
        # (Reference: clanServices/admin/root-password.nix:17-20 uses the
        # same idiom for `files.password.deploy = false`.)
        files.cloudflare-api-token.deploy = false;
        files.cloudflare-account-id.deploy = false;
        files.github-token.deploy = false;
        files.sops-age-key.deploy = false;

        # --- Composition script (mic92 harmonia-effects-secrets style) ---

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

      # Wire the composed `secrets` file to buildbot-nix's per-repo
      # effects-secret map. The attribute `services.buildbot-nix.master`
      # is declared as an option by
      # inputs.buildbot-nix.nixosModules.buildbot-master (imported by
      # modules/machines/nixos/magnetite/default.nix); the NixOS module
      # system merges this additive attribute with the rest of the master
      # config in modules/nixos/buildbot.nix. In particular we do NOT
      # redeclare master.enable, workersFile, github.*, accessMode.*, or
      # any other authoritative option here — only the perRepoSecretFiles
      # attribute keyed on this repo's forge identifier.
      #
      # This module is the sole authoritative definition of the
      # `github:cameronraysmith/vanixiets` perRepoSecretFiles entry;
      # m4-01c retired the legacy inline wire in modules/nixos/buildbot.nix,
      # so no transitional `lib.mkDefault` priority marker is required.
      services.buildbot-nix.master.effects.perRepoSecretFiles."github:cameronraysmith/vanixiets" =
        config.clan.core.vars.generators.vanixiets-effects-secrets.files.secrets.path;
    };
}
